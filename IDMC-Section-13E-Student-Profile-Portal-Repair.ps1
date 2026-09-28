[CmdletBinding()]
param(
    [string]$StudentNumber = "IDMC/2026/00001",
    [int]$ExpectedCourseCount = 6,
    [decimal]$ExpectedCredits = 60,
    [switch]$SkipSourceInstall,
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

function Step([string]$Text) { Write-Host "`n===== $Text =====" -ForegroundColor Cyan }

function EnvValue([string]$Path, [string[]]$Names) {
    foreach ($name in $Names) {
        $line = Get-Content -LiteralPath $Path | Where-Object { $_ -match "^\s*$([regex]::Escape($name))\s*=" } | Select-Object -Last 1
        if ($line) {
            $value = ($line -split "=", 2)[1].Trim()
            if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
                $value = $value.Substring(1, $value.Length - 2)
            }
            if ($value) { return $value }
        }
    }
    return $null
}

function HttpDetail($Record) {
    try {
        $response = $Record.Exception.Response
        if (-not $response) { return $Record.Exception.Message }
        $body = ""
        if ($response.PSObject.Methods.Name -contains "GetResponseStream") {
            $reader = New-Object IO.StreamReader($response.GetResponseStream())
            $body = $reader.ReadToEnd()
        } elseif ($response.Content) {
            $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        }
        return "HTTP $([int]$response.StatusCode). $body".Trim()
    } catch { return $Record.Exception.Message }
}

function Api([string]$Method, [string]$Path, $Body = $null, [string]$Prefer = "") {
    $headers = @{ apikey = $script:ServiceKey; Authorization = "Bearer $($script:ServiceKey)"; Accept = "application/json" }
    if ($Prefer) { $headers.Prefer = $Prefer }
    $args = @{ Method=$Method; Uri="$($script:Url)$Path"; Headers=$headers; UserAgent="IDMC-iMIS-Repair/13E"; ErrorAction="Stop" }
    if ($null -ne $Body) { $args.ContentType="application/json"; $args.Body=$Body | ConvertTo-Json -Depth 20 -Compress }
    try { return Invoke-RestMethod @args } catch { throw "Supabase $Method $Path failed. $(HttpDetail $_)" }
}

function Rows([string]$Table, [string]$Query) { return @(Api "GET" "/rest/v1/$Table`?$Query") }
function One([string]$Table, [string]$Query, [string]$Label) {
    $items = @(Rows $Table $Query)
    if ($items.Count -gt 1) { throw "$Label is not unique ($($items.Count) rows)." }
    if ($items.Count -eq 0) { return $null }
    return $items[0]
}
function Prop($Object, [string]$Name, $Default = $null) {
    if ($null -eq $Object) { return $Default }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p -or $null -eq $p.Value) { return $Default }
    return $p.Value
}
function Expand-Rows($Value) {
    $expanded = @()
    foreach ($item in @($Value)) {
        if ($null -eq $item) { continue }
        if ($item -is [System.Array]) {
            foreach ($nested in $item) { if ($null -ne $nested) { $expanded += $nested } }
        } else {
            $expanded += $item
        }
    }
    return $expanded
}
function Q([string]$Value) { return [uri]::EscapeDataString($Value) }

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$EnvFile = Join-Path $Root "apps\backend\.env"
if (-not (Test-Path -LiteralPath $EnvFile)) { throw "Backend .env not found: $EnvFile" }

$script:Url = EnvValue $EnvFile @("SUPABASE_URL")
$script:ServiceKey = EnvValue $EnvFile @("SUPABASE_SERVICE_ROLE_KEY", "SUPABASE_SECRET_KEY", "SB_SECRET")
if (-not $script:Url -or -not $script:ServiceKey) { throw "SUPABASE_URL or service-role/secret key is missing from apps\backend\.env." }

Write-Host "====================================================" -ForegroundColor DarkRed
Write-Host " SECTION 13E - STUDENT PROFILE / PORTAL REPAIR" -ForegroundColor White
Write-Host "====================================================" -ForegroundColor DarkRed

if (-not $SkipSourceInstall) {
    Step "1. SAFE SOURCE INSTALL"
    $sourceRoot = Join-Path $Root "section-13e-source"
    if (-not (Test-Path -LiteralPath $sourceRoot)) { throw "Installer payload is missing: $sourceRoot" }
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backup = Join-Path $Root "repair-backups\student-portal-$stamp"
    $files = @(
        "apps\backend\src\modules\student-management\students\students.service.ts",
        "apps\backend\src\modules\student-management\students\students.controller.ts",
        "apps\backend\src\modules\student-management\students\students.routes.ts",
        "apps\frontend\assets\js\student-portal-home.js",
        "apps\frontend\assets\js\student-portal-pages.js",
        "apps\frontend\assets\js\applicant-live-forms.js",
        "apps\frontend\assets\css\student-portal-home.css",
        "apps\frontend\assets\css\student-portal-pages.css",
        "apps\frontend\assets\css\applicant-live-forms.css",
        "apps\frontend\student-portal.html",
        "apps\frontend\student-profile.html",
        "apps\frontend\student-registration.html",
        "apps\frontend\student-attendance.html",
        "apps\frontend\student-results.html",
        "apps\frontend\student-timetable.html",
        "apps\frontend\student-fees.html",
        "apps\frontend\student-documents.html",
        "apps\frontend\student-notifications.html",
        "apps\frontend\admissions.html",
        "apps\frontend\applications.html"
    )
    foreach ($relative in $files) {
        $target = Join-Path $Root $relative
        $source = Join-Path $sourceRoot $relative
        if (-not (Test-Path -LiteralPath $source)) { throw "Payload file missing: $relative" }
        if (Test-Path -LiteralPath $target) {
            $backupFile = Join-Path $backup $relative
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backupFile) | Out-Null
            Copy-Item -LiteralPath $target -Destination $backupFile -Force
        }
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
        Copy-Item -LiteralPath $source -Destination $target -Force
    }
    Write-Host "Portal source installed; previous files backed up at $backup" -ForegroundColor Green
}

Step "2. STUDENT / APPLICANT / PROGRAMME DIAGNOSIS"
$encodedNumber = Q $StudentNumber
$student = One "students" "select=*&student_number=eq.$encodedNumber" "Student $StudentNumber"
if (-not $student) { throw "Student $StudentNumber was not found." }
$applicant = One "applicants" "select=*&id=eq.$($student.applicant_id)" "Linked applicant"
if (-not $applicant) { throw "Student has no valid linked applicant." }
$programme = One "programmes" "select=id,programme_code,programme_name,status&id=eq.$($student.programme_id)" "Linked programme"
if (-not $programme) { throw "Student has no valid linked programme." }
$registrations = @(Expand-Rows (Rows "student_registrations" "select=*&student_id=eq.$($student.id)&order=created_at.desc"))
$courses = @(Expand-Rows (Rows "course_registrations" "select=*&student_id=eq.$($student.id)&order=created_at.desc"))

Write-Host "Student    : $StudentNumber" -ForegroundColor White
Write-Host "Applicant  : $($applicant.first_name) $($applicant.middle_name) $($applicant.last_name)" -ForegroundColor White
Write-Host "Programme  : $($programme.programme_code) - $($programme.programme_name)" -ForegroundColor White
Write-Host "Status     : $($student.student_status)" -ForegroundColor White
Write-Host "Registrations / Courses: $($registrations.Count) / $($courses.Count)" -ForegroundColor White

Step "3. RECONCILE STUDENT MASTER AND PROFILE"
$address = @($applicant.address_line_1, $applicant.address_line_2, $applicant.city, $applicant.district, $applicant.region, $applicant.country) | Where-Object { $_ }
$studentPatch = [ordered]@{
    first_name = $applicant.first_name; middle_name = $applicant.middle_name; last_name = $applicant.last_name
    gender = $applicant.gender; date_of_birth = $applicant.date_of_birth; nationality = $applicant.nationality
    national_id = $applicant.national_id_number; passport_number = $applicant.passport_number
    phone = $applicant.phone; email = $applicant.email; physical_address = ($address -join ", ")
}
[void](Api "PATCH" "/rest/v1/students?id=eq.$($student.id)" $studentPatch "return=representation")

$profilePatch = [ordered]@{
    student_id = $student.id; first_name = $applicant.first_name; middle_name = $applicant.middle_name; last_name = $applicant.last_name
    gender = $applicant.gender; date_of_birth = $applicant.date_of_birth; nationality = $applicant.nationality
    national_id_number = $applicant.national_id_number; passport_number = $applicant.passport_number
    phone = $applicant.phone; email = $applicant.email
}
[void](Api "POST" "/rest/v1/student_profiles?on_conflict=student_id" $profilePatch "resolution=merge-duplicates,return=representation")

if ($student.user_id) {
    $userPatch = @{ first_name=$applicant.first_name; middle_name=$applicant.middle_name; last_name=$applicant.last_name; phone=$applicant.phone }
    [void](Api "PATCH" "/rest/v1/users?id=eq.$($student.user_id)" $userPatch "return=representation")
}
Write-Host "Student master and profile reconciled from the authoritative applicant record." -ForegroundColor Green

Step "4. VERIFY REGISTRATION LINK"
if ($registrations.Count -eq 0) { throw "No semester registration is linked to $StudentNumber." }
$current = $registrations[0]
$linkedCourses = @(Expand-Rows ($courses | Where-Object { (Prop $_ "student_registration_id") -eq $current.id }))
if ($linkedCourses.Count -eq 0) { throw "Registration $($current.id) has no linked courses." }
$creditValues = @()
foreach ($courseRow in $linkedCourses) {
    $rawCredit = Prop $courseRow "credits"
    if ($null -ne $rawCredit -and "$rawCredit" -ne "") {
        $parsedCredit = 0D
        if ([decimal]::TryParse("$rawCredit", [ref]$parsedCredit)) { $creditValues += $parsedCredit }
    }
}
$registrationCredits = [decimal](Prop $current "total_registered_credits" 0)
$creditSum = $registrationCredits
$creditsAreRowBased = ($creditValues.Count -eq $linkedCourses.Count)
if ($creditsAreRowBased) {
    $creditSum = [decimal](($creditValues | Measure-Object -Sum).Sum)
}
if ($creditsAreRowBased -and $registrationCredits -ne $creditSum) {
    [void](Api "PATCH" "/rest/v1/student_registrations?id=eq.$($current.id)" @{ total_registered_credits=$creditSum } "return=representation")
    Write-Host "Registration credits corrected to $creditSum." -ForegroundColor Yellow
}
if (-not $creditsAreRowBased) {
    Write-Host "Course rows do not expose a credits column; verified against registration total instead." -ForegroundColor DarkGray
}
Write-Host "Registration $($current.registration_status): $($linkedCourses.Count) courses / $creditSum credits." -ForegroundColor Green
if ($ExpectedCourseCount -gt 0 -and $linkedCourses.Count -ne $ExpectedCourseCount) {
    throw "Registration has $($linkedCourses.Count) linked course rows; expected $ExpectedCourseCount. No course data was changed."
}
if ($ExpectedCredits -ge 0 -and $creditSum -ne $ExpectedCredits) {
    throw "Registration has $creditSum credits; expected $ExpectedCredits. No course data was changed."
}

if (-not $SkipBuild) {
    Step "5. BACKEND BUILD CHECK"
    Push-Location (Join-Path $Root "apps\backend")
    try {
        & npm.cmd run build
        if ($LASTEXITCODE -ne 0) { throw "Backend build failed with exit code $LASTEXITCODE." }
    } finally { Pop-Location }
}

Step "6. FINAL READ-BACK"
$studentAfter = One "students" "select=student_number,first_name,middle_name,last_name,email,phone,student_status,programme_id,profile_photo_url&id=eq.$($student.id)" "Updated student"
$summary = [ordered]@{
    student_number = $studentAfter.student_number
    full_name = @($studentAfter.first_name, $studentAfter.middle_name, $studentAfter.last_name) -join " "
    email = $studentAfter.email
    programme = "$($programme.programme_code) - $($programme.programme_name)"
    student_status = $studentAfter.student_status
    registration_status = $current.registration_status
    registered_courses = $linkedCourses.Count
    registered_credits = $creditSum
    profile_photo = [bool]$studentAfter.profile_photo_url
}
$auditPath = Join-Path $Root "IDMC_SECTION_13E_STUDENT_PORTAL_AUDIT.json"
$summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $auditPath -Encoding UTF8
$summary | Format-List

Write-Host "====================================================" -ForegroundColor DarkRed
Write-Host " SECTION 13E COMPLETE - STUDENT PORTAL CONNECTED" -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor DarkRed
Write-Host "Restart backend and frontend, then sign in as $StudentNumber." -ForegroundColor White
