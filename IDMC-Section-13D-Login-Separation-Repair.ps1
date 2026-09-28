[CmdletBinding()]
param(
    [string]$OwnerEmail = "libenangapatrick@gmail.com",
    [string]$StudentNumber = "IDMC/2026/00001",
    [switch]$SkipSourceInstall,
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

function Write-Step([string]$Text) {
    Write-Host "`n===== $Text =====" -ForegroundColor Cyan
}

function Get-EnvValue([string]$Path, [string]$Name) {
    $line = Get-Content -LiteralPath $Path | Where-Object {
        $_ -match "^\s*$([regex]::Escape($Name))\s*="
    } | Select-Object -Last 1

    if (-not $line) { return $null }
    $value = ($line -split "=", 2)[1].Trim()
    if (($value.StartsWith('"') -and $value.EndsWith('"')) -or
        ($value.StartsWith("'") -and $value.EndsWith("'"))) {
        $value = $value.Substring(1, $value.Length - 2)
    }
    return $value
}

function Get-HttpErrorBody($ErrorRecord) {
    try {
        $response = $ErrorRecord.Exception.Response
        if (-not $response) { return $ErrorRecord.Exception.Message }
        $statusCode = ""
        $statusText = ""
        try { $statusCode = [int]$response.StatusCode } catch { }
        try { $statusText = [string]$response.StatusDescription } catch { }
        $body = ""
        if ($response.PSObject.Methods.Name -contains "GetResponseStream") {
            $stream = $response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($stream)
            $body = $reader.ReadToEnd()
        } elseif ($response.Content) {
            $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        }
        return "HTTP $statusCode $statusText. $body".Trim()
    } catch {
        return $ErrorRecord.Exception.Message
    }
}

function Invoke-SupabaseApi {
    param(
        [Parameter(Mandatory = $true)][ValidateSet("GET", "POST", "PATCH", "PUT", "DELETE")][string]$Method,
        [Parameter(Mandatory = $true)][string]$Path,
        $Body = $null,
        [string]$Prefer = ""
    )

    $headers = @{
        apikey        = $script:ServiceRoleKey
        Accept         = "application/json"
    }
    if ($Prefer) { $headers.Prefer = $Prefer }

    $parameters = @{
        Method      = $Method
        Uri         = "$($script:SupabaseUrl)$Path"
        Headers     = $headers
        UserAgent   = "IDMC-iMIS-Server-Repair/13D"
        ErrorAction = "Stop"
    }

    if ($null -ne $Body) {
        $parameters.ContentType = "application/json"
        $parameters.Body = $Body | ConvertTo-Json -Depth 20 -Compress
    }

    try {
        return Invoke-RestMethod @parameters
    } catch {
        $detail = Get-HttpErrorBody $_
        throw "Supabase $Method $Path failed. $detail"
    }
}

function Escape-QueryValue([string]$Value) {
    return [uri]::EscapeDataString($Value)
}

function Get-ObjectProperty($Object, [string]$Name, $Default = $null) {
    if ($null -eq $Object) { return $Default }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) { return $Default }
    return $property.Value
}

function Get-Rows([string]$Table, [string]$Query) {
    $result = Invoke-SupabaseApi -Method GET -Path "/rest/v1/$Table`?$Query"
    return @($result)
}

function Get-One([string]$Table, [string]$Query, [string]$Description) {
    $rows = @(Get-Rows $Table $Query)
    if ($rows.Count -gt 1) {
        throw "$Description is not unique ($($rows.Count) rows). Repair stopped safely."
    }
    if ($rows.Count -eq 0) { return $null }
    return $rows[0]
}

function Add-Row([string]$Table, $Body) {
    $result = Invoke-SupabaseApi -Method POST -Path "/rest/v1/$Table" -Body $Body -Prefer "return=representation"
    $rows = @($result)
    if ($rows.Count -ne 1) { throw "Insert into $Table did not return exactly one row." }
    return $rows[0]
}

function Set-Row([string]$Table, [string]$Filter, $Body) {
    $result = Invoke-SupabaseApi -Method PATCH -Path "/rest/v1/$Table`?$Filter" -Body $Body -Prefer "return=representation"
    return @($result)
}

function Get-AllAuthUsers {
    $all = @()
    for ($page = 1; $page -le 100; $page++) {
        $response = Invoke-SupabaseApi -Method GET -Path "/auth/v1/admin/users?page=$page&per_page=1000"
        $batch = @($response.users)
        foreach ($item in $batch) { $all += $item }
        if ($batch.Count -lt 1000) { break }
    }
    return $all
}

function Find-AuthByEmail([object[]]$AuthUsers, [string]$Email) {
    $matches = @($AuthUsers | Where-Object { [string]$_.email -ieq $Email })
    if ($matches.Count -gt 1) { throw "Auth email $Email exists more than once." }
    if ($matches.Count -eq 0) { return $null }
    return $matches[0]
}

function Get-AuthById([string]$Id) {
    if (-not $Id) { return $null }
    try {
        return Invoke-SupabaseApi -Method GET -Path "/auth/v1/admin/users/$Id"
    } catch {
        if ($_.Exception.Message -match "404|user_not_found") { return $null }
        throw
    }
}

function Get-OrCreateRole([string]$Code, [string]$Name, [string]$Description) {
    $encoded = Escape-QueryValue $Code
    $role = Get-One "roles" "select=*&role_code=eq.$encoded" "Role $Code"
    if (-not $role) {
        $role = Add-Row "roles" @{
            role_code = $Code; role_name = $Name; description = $Description
            is_system_role = $true; status = "ACTIVE"
        }
        Write-Host "Role created: $Code" -ForegroundColor Yellow
    } elseif ($role.status -ne "ACTIVE") {
        $updated = @(Set-Row "roles" "id=eq.$($role.id)" @{ status = "ACTIVE" })
        $role = $updated[0]
        Write-Host "Role activated: $Code" -ForegroundColor Yellow
    }
    return $role
}

function Ensure-UserRole([string]$UserId, [string]$RoleId, [string]$RoleCode) {
    $assignment = Get-One "user_roles" "select=*&user_id=eq.$UserId&role_id=eq.$RoleId" "User-role $RoleCode"
    if (-not $assignment) {
        [void](Add-Row "user_roles" @{ user_id = $UserId; role_id = $RoleId; status = "ACTIVE" })
        Write-Host "Role assigned: $RoleCode" -ForegroundColor Yellow
    } elseif ($assignment.status -ne "ACTIVE" -or $assignment.expires_at) {
        [void](Set-Row "user_roles" "id=eq.$($assignment.id)" @{ status = "ACTIVE"; expires_at = $null })
        Write-Host "Role reactivated: $RoleCode" -ForegroundColor Yellow
    } else {
        Write-Host "Role reused: $RoleCode" -ForegroundColor DarkGray
    }
}

function Remove-UserRole([string]$UserId, [string]$RoleId, [string]$RoleCode) {
    $assignment = Get-One "user_roles" "select=*&user_id=eq.$UserId&role_id=eq.$RoleId" "User-role $RoleCode"
    if (-not $assignment) {
        Write-Host "Role absent as required: $RoleCode" -ForegroundColor DarkGray
        return
    }
    [void](Invoke-SupabaseApi -Method DELETE -Path "/rest/v1/user_roles?id=eq.$($assignment.id)" -Prefer "return=representation")
    Write-Host "Role removed: $RoleCode" -ForegroundColor Yellow
}

function Get-OrCreatePermission([string]$Code, [string]$Name, [string]$Module, [string]$Action) {
    $encoded = Escape-QueryValue $Code
    $permission = Get-One "permissions" "select=*&permission_code=eq.$encoded" "Permission $Code"
    if (-not $permission) {
        $permission = Add-Row "permissions" @{
            permission_code = $Code; permission_name = $Name
            module_code = $Module; action_code = $Action; status = "ACTIVE"
        }
        Write-Host "Permission created: $Code" -ForegroundColor Yellow
    } elseif ($permission.status -ne "ACTIVE") {
        $updated = @(Set-Row "permissions" "id=eq.$($permission.id)" @{ status = "ACTIVE" })
        $permission = $updated[0]
    }
    return $permission
}

function Ensure-RolePermission([string]$RoleId, [string]$PermissionId, [string]$Code) {
    $link = Get-One "role_permissions" "select=id&role_id=eq.$RoleId&permission_id=eq.$PermissionId" "Role-permission $Code"
    if (-not $link) {
        [void](Add-Row "role_permissions" @{ role_id = $RoleId; permission_id = $PermissionId })
        Write-Host "Permission assigned: $Code" -ForegroundColor Yellow
    }
}

function Get-SafeAuthSnapshot($User) {
    if (-not $User) { return $null }
    return [ordered]@{
        id = (Get-ObjectProperty $User "id")
        email = (Get-ObjectProperty $User "email")
        created_at = (Get-ObjectProperty $User "created_at")
        last_sign_in_at = (Get-ObjectProperty $User "last_sign_in_at")
        user_metadata = (Get-ObjectProperty $User "user_metadata")
    }
}

function Save-Json([string]$Path, $Value) {
    $Value | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function ConvertFrom-SecureValue([Security.SecureString]$SecureValue) {
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureValue)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
}

function Read-ConfirmedOwnerPassword {
    Write-Host "Enter the NEW password for $OwnerEmail." -ForegroundColor Yellow
    Write-Host "Input is hidden. Type @ normally; do not type a backslash before it." -ForegroundColor Yellow
    $first = ConvertFrom-SecureValue (Read-Host "New owner password" -AsSecureString)
    $second = ConvertFrom-SecureValue (Read-Host "Confirm owner password" -AsSecureString)
    if ($first.Length -lt 8) { throw "Owner password must contain at least 8 characters." }
    if ($first -cne $second) { throw "Owner password confirmation does not match." }
    $second = $null
    return $first
}

function Set-DotEnvValue([string]$Path, [string]$Name, [string]$Value) {
    $content = [IO.File]::ReadAllText($Path)
    $line = "$Name=$Value"
    $pattern = "(?m)^\s*$([regex]::Escape($Name))\s*=.*$"
    if ([regex]::IsMatch($content, $pattern)) {
        $content = [regex]::Replace($content, $pattern, $line)
    } else {
        $newLine = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }
        $content = $content.TrimEnd("`r", "`n") + $newLine + $line + $newLine
    }
    [IO.File]::WriteAllText($Path, $content, (New-Object Text.UTF8Encoding($true)))
}

function Invoke-PasswordGrant([string]$Email, [string]$Password) {
    $headers = @{ apikey = $script:PublishableKey; Accept = "application/json" }
    try {
        return Invoke-RestMethod -Method POST `
            -Uri "$($script:SupabaseUrl)/auth/v1/token?grant_type=password" `
            -Headers $headers `
            -UserAgent "IDMC-iMIS-Login-Verification/13D" `
            -ContentType "application/json" `
            -Body (@{ email = $Email; password = $Password } | ConvertTo-Json -Compress) `
            -ErrorAction Stop
    } catch {
        throw "Password verification failed for $Email. $(Get-HttpErrorBody $_)"
    }
}

function Install-PatchedSource {
    $assetRoot = Join-Path $PSScriptRoot "section13d"
    $targets = @(
        @{
            Source = Join-Path $assetRoot "student-login.service.ts"
            Target = Join-Path $PSScriptRoot "apps\backend\src\modules\auth\services\student-login.service.ts"
        },
        @{
            Source = Join-Path $assetRoot "auth.controller.ts"
            Target = Join-Path $PSScriptRoot "apps\backend\src\modules\auth\controllers\auth.controller.ts"
        },
        @{
            Source = Join-Path $assetRoot "auth.service.ts"
            Target = Join-Path $PSScriptRoot "apps\backend\src\modules\auth\services\auth.service.ts"
        },
        @{
            Source = Join-Path $assetRoot "database.ts"
            Target = Join-Path $PSScriptRoot "apps\backend\src\config\database.ts"
        },
        @{
            Source = Join-Path $assetRoot "env.ts"
            Target = Join-Path $PSScriptRoot "apps\backend\src\config\env.ts"
        },
        @{
            Source = Join-Path $assetRoot "login.html"
            Target = Join-Path $PSScriptRoot "apps\frontend\login.html"
        },
        @{
            Source = Join-Path $assetRoot "auth.js"
            Target = Join-Path $PSScriptRoot "apps\frontend\assets\js\auth.js"
        }
    )

    foreach ($item in $targets) {
        if (-not (Test-Path -LiteralPath $item.Source)) {
            throw "Repair asset is missing: $($item.Source). Extract the complete Section 13D ZIP first."
        }
        if (-not (Test-Path -LiteralPath $item.Target)) {
            throw "Backend source is missing: $($item.Target)"
        }
        Copy-Item -LiteralPath $item.Target -Destination $script:BackupDir -Force
        Copy-Item -LiteralPath $item.Source -Destination $item.Target -Force
    }
    Write-Host "Backend/frontend login source installed; originals backed up." -ForegroundColor Green
}

Write-Host "====================================================" -ForegroundColor Green
Write-Host " SECTION 13D - LOGIN SEPARATION / PASSWORD / RBAC REPAIR" -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Green

$projectRoot = $PSScriptRoot
$envPath = Join-Path $projectRoot "apps\backend\.env"
if (-not (Test-Path -LiteralPath $envPath)) { throw "Backend .env not found: $envPath" }

$script:SupabaseUrl = (Get-EnvValue $envPath "SUPABASE_URL").TrimEnd('/')
$script:ServiceRoleKey = Get-EnvValue $envPath "SUPABASE_SERVICE_ROLE_KEY"
if (-not $script:SupabaseUrl -or -not $script:ServiceRoleKey) {
    throw "SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY is missing from apps/backend/.env"
}

$OwnerEmail = $OwnerEmail.Trim().ToLowerInvariant()
$StudentNumber = $StudentNumber.Trim()
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$script:BackupDir = Join-Path $projectRoot "repair-backups\login-separation-$stamp"
New-Item -ItemType Directory -Path $script:BackupDir -Force | Out-Null

Write-Step "1. SAFE SOURCE INSTALL"
if ($SkipSourceInstall) {
    Write-Host "Source install skipped by parameter." -ForegroundColor Yellow
} else {
    Install-PatchedSource
}

$frontendConfigPath = Join-Path $projectRoot "apps\frontend\assets\js\config.js"
$frontendConfig = [IO.File]::ReadAllText($frontendConfigPath)
$publishableMatch = [regex]::Match($frontendConfig, 'SUPABASE_ANON_KEY\s*:\s*["'']([^"'']+)["'']')
if (-not $publishableMatch.Success) {
    throw "SUPABASE_ANON_KEY was not found in frontend config.js"
}
$script:PublishableKey = $publishableMatch.Groups[1].Value
Copy-Item -LiteralPath $envPath -Destination $script:BackupDir -Force
Set-DotEnvValue $envPath "SUPABASE_PUBLISHABLE_KEY" $script:PublishableKey
Write-Host "Backend publishable Auth key configured from frontend public config." -ForegroundColor Green

Write-Step "2. READ-ONLY IDENTITY DIAGNOSIS"
$authUsers = @(Get-AllAuthUsers)
$ownerAuth = Find-AuthByEmail $authUsers $OwnerEmail
if (-not $ownerAuth) {
    throw "No Supabase Auth account exists for $OwnerEmail. No owner password was changed or created."
}

$ownerByAuth = Get-One "users" "select=*&auth_user_id=eq.$($ownerAuth.id)" "Owner public user by auth_user_id"
$encodedOwnerEmail = Escape-QueryValue $OwnerEmail
$ownerByEmail = Get-One "users" "select=*&email=ilike.$encodedOwnerEmail" "Owner public user by email"
if ($ownerByAuth -and $ownerByEmail -and $ownerByAuth.id -ne $ownerByEmail.id) {
    throw "Two different public.users rows match the owner Auth ID and email. Repair stopped safely."
}

$encodedStudent = Escape-QueryValue $StudentNumber
$student = Get-One "students" "select=*&student_number=ilike.$encodedStudent" "Student $StudentNumber"
if (-not $student) { throw "Student $StudentNumber was not found." }

$before = [ordered]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    owner_auth = (Get-SafeAuthSnapshot $ownerAuth)
    owner_public_by_auth = $ownerByAuth
    owner_public_by_email = $ownerByEmail
    student = $student
    student_public_user = $(if ($student.user_id) { Get-One "users" "select=*&id=eq.$($student.user_id)" "Linked student user" } else { $null })
    student_number_users = @(Get-Rows "users" "select=*&user_number=eq.$encodedStudent")
    roles = @(Get-Rows "roles" "select=*&role_code=in.(SUPER_ADMIN,ADMIN,STUDENT)")
}
Save-Json (Join-Path $script:BackupDir "before.json") $before
Write-Host "Safe snapshot: $($script:BackupDir)\before.json" -ForegroundColor DarkGray

Write-Step "3. REPAIR OWNER AUTH -> PUBLIC USER"
$ownerPublic = if ($ownerByAuth) { $ownerByAuth } else { $ownerByEmail }
if ($ownerPublic) {
    $ownerChanges = @{}
    if ([string]$ownerPublic.auth_user_id -ne [string]$ownerAuth.id) { $ownerChanges.auth_user_id = $ownerAuth.id }
    if ([string]$ownerPublic.email -ine $OwnerEmail) { $ownerChanges.email = $OwnerEmail }
    if ([string]$ownerPublic.status -ne "ACTIVE") { $ownerChanges.status = "ACTIVE" }
    if ($ownerChanges.Count -gt 0) {
        $updated = @(Set-Row "users" "id=eq.$($ownerPublic.id)" $ownerChanges)
        if ($updated.Count -ne 1) { throw "Owner public user update affected $($updated.Count) rows." }
        $ownerPublic = $updated[0]
        Write-Host "Owner public.users link repaired." -ForegroundColor Green
    } else {
        Write-Host "Owner Auth link already correct." -ForegroundColor DarkGray
    }
} else {
    $baseUsername = ($OwnerEmail -split '@')[0].ToLowerInvariant()
    $username = $baseUsername
    if ((Get-Rows "users" "select=id&username=eq.$(Escape-QueryValue $username)").Count -gt 0) {
        $username = "$baseUsername-$(([string]$ownerAuth.id).Substring(0, 8))"
    }
    $userNumber = "IDMC-ADMIN-00001"
    if ((Get-Rows "users" "select=id&user_number=eq.$(Escape-QueryValue $userNumber)").Count -gt 0) {
        $userNumber = "IDMC-ADMIN-$(([string]$ownerAuth.id).Substring(0, 8).ToUpperInvariant())"
    }
    $metadata = Get-ObjectProperty $ownerAuth "user_metadata"
    $metadataFirstName = Get-ObjectProperty $metadata "first_name"
    $metadataLastName = Get-ObjectProperty $metadata "last_name"
    $firstName = if ($metadataFirstName) { [string]$metadataFirstName } else { "Patrick" }
    $lastName = if ($metadataLastName) { [string]$metadataLastName } else { "Libenanga" }
    $ownerPublic = Add-Row "users" @{
        auth_user_id = $ownerAuth.id; user_number = $userNumber; username = $username
        first_name = $firstName; last_name = $lastName; display_name = "$firstName $lastName"
        email = $OwnerEmail; status = "ACTIVE"; email_verified_at = (Get-Date).ToUniversalTime().ToString("o")
    }
    Write-Host "Owner public.users profile created." -ForegroundColor Green
}

$superAdminRole = Get-OrCreateRole "SUPER_ADMIN" "Super Administrator" "Full system administration"
$adminRole = Get-OrCreateRole "ADMIN" "Administrator" "System administration"
$studentRole = Get-OrCreateRole "STUDENT" "Student" "Student self-service account"
Ensure-UserRole ([string]$ownerPublic.id) ([string]$adminRole.id) "ADMIN"
Ensure-UserRole ([string]$ownerPublic.id) ([string]$superAdminRole.id) "SUPER_ADMIN"
Remove-UserRole ([string]$ownerPublic.id) ([string]$studentRole.id) "STUDENT"

$ownerPassword = Read-ConfirmedOwnerPassword
[void](Invoke-SupabaseApi -Method PUT -Path "/auth/v1/admin/users/$($ownerAuth.id)" -Body @{
    password = $ownerPassword; email_confirm = $true
})
$ownerPasswordCheck = Invoke-PasswordGrant $OwnerEmail $ownerPassword
if (-not (Get-ObjectProperty $ownerPasswordCheck "access_token")) {
    throw "Owner password authentication verification failed."
}
$ownerPasswordCheck = $null
$ownerPassword = $null
Write-Host "Owner password reset and authentication: PASS" -ForegroundColor Green

Write-Step "4. REPAIR STUDENT IDENTITY"
$studentPublic = $null
if ($student.user_id) {
    $linked = Get-One "users" "select=*&id=eq.$($student.user_id)" "Linked student public user"
    if ($linked -and $linked.id -ne $ownerPublic.id -and [string]$linked.user_number -ieq $StudentNumber) {
        $studentPublic = $linked
    } elseif ($linked -and $linked.id -eq $ownerPublic.id) {
        Write-Host "Student was linked to owner identity; a separate student identity will be used." -ForegroundColor Yellow
    }
}
if (-not $studentPublic) {
    $studentPublic = Get-One "users" "select=*&user_number=eq.$encodedStudent" "Student public user by number"
    if ($studentPublic -and $studentPublic.id -eq $ownerPublic.id) { $studentPublic = $null }
}
if (-not $studentPublic) {
    $encodedStudentUsername = Escape-QueryValue ($StudentNumber.ToLowerInvariant())
    $usernameCandidate = Get-One "users" "select=*&username=ilike.$encodedStudentUsername" "Student public user by username"
    if ($usernameCandidate -and $usernameCandidate.id -ne $ownerPublic.id -and
        [string]$usernameCandidate.user_number -ieq $StudentNumber) {
        $studentPublic = $usernameCandidate
    } elseif ($usernameCandidate) {
        throw "Username $StudentNumber is owned by a different public user. Repair stopped safely."
    }
}

$safeStudentNumber = ($StudentNumber -replace '[^a-zA-Z0-9._-]', '').ToLowerInvariant()
$internalEmail = "$safeStudentNumber@students.idmc.local"
$studentAuth = $null
if ($studentPublic -and $studentPublic.auth_user_id) {
    $studentAuth = Get-AuthById ([string]$studentPublic.auth_user_id)
}
if (-not $studentAuth) {
    $studentAuth = Find-AuthByEmail $authUsers $internalEmail
}

$firstName = if ($student.first_name) { [string]$student.first_name } else { "Student" }
$middleName = if ($student.middle_name) { [string]$student.middle_name } else { $null }
$lastName = if ($student.last_name) { [string]$student.last_name } else { $StudentNumber }
$displayName = (@($firstName, $middleName, $lastName) | Where-Object { $_ }) -join ' '

if (-not $studentAuth) {
    $studentAuth = Invoke-SupabaseApi -Method POST -Path "/auth/v1/admin/users" -Body @{
        email = $internalEmail; password = $StudentNumber; email_confirm = $true
        user_metadata = @{
            account_type = "STUDENT"; student_number = $StudentNumber
            first_name = $firstName; middle_name = $middleName; last_name = $lastName
            contact_email = $student.email
        }
    }
    Write-Host "Student Auth identity created." -ForegroundColor Green
} else {
    $isVerifiedStudentIdentity =
        ([string]$studentAuth.email -ieq $internalEmail) -or
        ($studentPublic -and [string]$studentPublic.user_number -ieq $StudentNumber) -or
        ([string](Get-ObjectProperty (Get-ObjectProperty $studentAuth "user_metadata") "account_type") -eq "STUDENT")
    if (-not $isVerifiedStudentIdentity -or [string]$studentAuth.id -eq [string]$ownerAuth.id) {
        throw "Refusing to reset password: candidate Auth identity is not safely verified as the student."
    }
    $studentAuth = Invoke-SupabaseApi -Method PUT -Path "/auth/v1/admin/users/$($studentAuth.id)" -Body @{
        password = $StudentNumber; email_confirm = $true
    }
    Write-Host "Student initial password reset to the exact registration number." -ForegroundColor Green
}

if ($studentPublic) {
    $changes = @{
        auth_user_id = $studentAuth.id; email = ([string]$studentAuth.email).ToLowerInvariant()
        user_number = $StudentNumber; username = $StudentNumber.ToLowerInvariant(); status = "ACTIVE"
    }
    $updated = @(Set-Row "users" "id=eq.$($studentPublic.id)" $changes)
    if ($updated.Count -ne 1) { throw "Student public user update affected $($updated.Count) rows." }
    $studentPublic = $updated[0]
} else {
    $studentPublic = Add-Row "users" @{
        auth_user_id = $studentAuth.id; user_number = $StudentNumber
        username = $StudentNumber.ToLowerInvariant(); first_name = $firstName
        middle_name = $middleName; last_name = $lastName; display_name = $displayName
        email = ([string]$studentAuth.email).ToLowerInvariant(); phone = $student.phone
        status = "ACTIVE"; email_verified_at = (Get-Date).ToUniversalTime().ToString("o")
    }
    Write-Host "Student public.users profile created." -ForegroundColor Green
}

$linkedRows = @(Set-Row "students" "id=eq.$($student.id)" @{ user_id = $studentPublic.id })
if ($linkedRows.Count -ne 1) { throw "Student link update affected $($linkedRows.Count) rows." }
Ensure-UserRole ([string]$studentPublic.id) ([string]$studentRole.id) "STUDENT"
Remove-UserRole ([string]$studentPublic.id) ([string]$adminRole.id) "ADMIN"
Remove-UserRole ([string]$studentPublic.id) ([string]$superAdminRole.id) "SUPER_ADMIN"

$ownerStudentLinks = @(Get-Rows "students" "select=id,student_number&user_id=eq.$($ownerPublic.id)")
if ($ownerStudentLinks.Count -gt 0) {
    throw "Owner identity is still linked to $($ownerStudentLinks.Count) student row(s). Repair stopped for manual review."
}

Write-Step "5. RECONCILE RBAC"
$portalPermission = Get-OrCreatePermission "portal.student" "Access student portal" "portal" "student"
$selfPermission = Get-OrCreatePermission "students.self.view" "View own student profile" "students" "self_view"
Ensure-RolePermission ([string]$studentRole.id) ([string]$portalPermission.id) "portal.student"
Ensure-RolePermission ([string]$studentRole.id) ([string]$selfPermission.id) "students.self.view"

$activePermissions = @(Get-Rows "permissions" "select=id&status=eq.ACTIVE")
$existingSuperLinks = @(Get-Rows "role_permissions" "select=permission_id&role_id=eq.$($superAdminRole.id)")
$existingIds = @{}
foreach ($link in $existingSuperLinks) { $existingIds[[string]$link.permission_id] = $true }
$missingLinks = @()
foreach ($permission in $activePermissions) {
    if (-not $existingIds.ContainsKey([string]$permission.id)) {
        $missingLinks += @{ role_id = $superAdminRole.id; permission_id = $permission.id }
    }
}
if ($missingLinks.Count -gt 0) {
    [void](Invoke-SupabaseApi -Method POST -Path "/rest/v1/role_permissions" -Body $missingLinks -Prefer "return=minimal")
}
Write-Host "SUPER_ADMIN permission coverage: $($activePermissions.Count) active permissions; $($missingLinks.Count) links added." -ForegroundColor Green

Write-Step "6. FINAL READ-BACK"
$finalOwner = Get-One "users" "select=*&id=eq.$($ownerPublic.id)" "Final owner"
$finalStudent = Get-One "students" "select=*&id=eq.$($student.id)" "Final student"
$finalStudentUser = Get-One "users" "select=*&id=eq.$($studentPublic.id)" "Final student user"
$ownerRoles = @(Get-Rows "user_roles" "select=status,expires_at,roles(role_code,status)&user_id=eq.$($ownerPublic.id)&status=eq.ACTIVE")
$studentRoles = @(Get-Rows "user_roles" "select=status,expires_at,roles(role_code,status)&user_id=eq.$($studentPublic.id)&status=eq.ACTIVE")
$studentPermissions = @(Get-Rows "role_permissions" "select=permissions(permission_code,status)&role_id=eq.$($studentRole.id)")
$ownerStudentRole = Get-One "user_roles" "select=id&user_id=eq.$($ownerPublic.id)&role_id=eq.$($studentRole.id)&status=eq.ACTIVE" "Owner STUDENT role"
$studentAdminRole = Get-One "user_roles" "select=id&user_id=eq.$($studentPublic.id)&role_id=eq.$($adminRole.id)&status=eq.ACTIVE" "Student ADMIN role"
$studentSuperRole = Get-One "user_roles" "select=id&user_id=eq.$($studentPublic.id)&role_id=eq.$($superAdminRole.id)&status=eq.ACTIVE" "Student SUPER_ADMIN role"

if ([string]$finalOwner.auth_user_id -ne [string]$ownerAuth.id -or $finalOwner.status -ne "ACTIVE") {
    throw "Owner final verification failed."
}
if ([string]$finalStudent.user_id -ne [string]$finalStudentUser.id -or
    [string]$finalStudentUser.auth_user_id -ne [string]$studentAuth.id -or
    $finalStudentUser.status -ne "ACTIVE") {
    throw "Student final verification failed."
}
if ($ownerStudentRole -or $studentAdminRole -or $studentSuperRole) {
    throw "Final role-separation verification failed."
}

$studentPasswordCheck = Invoke-PasswordGrant (([string]$studentAuth.email).ToLowerInvariant()) $StudentNumber
if (-not (Get-ObjectProperty $studentPasswordCheck "access_token")) {
    throw "Student password verification failed."
}
$studentPasswordCheck = $null
Write-Host "Student password authentication: PASS" -ForegroundColor Green

$after = [ordered]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    owner_auth = (Get-SafeAuthSnapshot $ownerAuth)
    owner_public = $finalOwner; owner_roles = $ownerRoles
    student = $finalStudent; student_auth = (Get-SafeAuthSnapshot $studentAuth)
    student_public = $finalStudentUser; student_roles = $studentRoles
    student_permissions = $studentPermissions
    super_admin_active_permission_count = $activePermissions.Count
}
Save-Json (Join-Path $script:BackupDir "after.json") $after

if (-not $SkipBuild) {
    Write-Step "7. BACKEND BUILD"
    Push-Location (Join-Path $projectRoot "apps\backend")
    try {
        & npm.cmd run build
        if ($LASTEXITCODE -ne 0) { throw "Backend build failed with exit code $LASTEXITCODE" }
    } finally {
        Pop-Location
    }
}

Write-Host "`n====================================================" -ForegroundColor Green
Write-Host " SECTION 13D COMPLETE - LOGIN IDENTITIES SEPARATED" -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Green
Write-Host "Owner email          : $OwnerEmail"
Write-Host "Owner Auth mapping   : OK"
Write-Host "Owner roles          : ADMIN, SUPER_ADMIN (STUDENT removed)"
Write-Host "Student              : $StudentNumber"
Write-Host "Student Auth mapping : OK (separate identity)"
Write-Host "Student role         : STUDENT"
Write-Host "Student password     : reset to registration number"
Write-Host "Admin password       : RESET AND VERIFIED (not printed)"
Write-Host "Backup / audit       : $script:BackupDir"
Write-Host "`nNEXT: restart backend, then test both logins." -ForegroundColor Cyan
