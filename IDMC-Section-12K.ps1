#Requires -Version 5.1

[CmdletBinding()]
param(
    [string]$BaseUrl = "http://127.0.0.1:4000/api/v1",
    [string]$ProjectPath = (Get-Location).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# Verified identifiers from Sections 12D-12J.
$StudentId          = "dc03917a-5cc7-4ad6-abdd-03fc38cee8f9"
$StudentNumber      = "IDMC/2026/00001"
$RegistrationId     = "07435cec-e3c6-4cdc-b5a2-b2e9a4206f1e"
$AcademicYearId     = "92e0b66f-6462-4b03-9abe-6f589a637753"
$SemesterId         = "ede56fec-3bfc-4f5e-a518-d061315aff67"
$ProgrammeId        = "4a05c8d7-eb10-4d86-97e9-715cfbcec53b"
$ProgrammeVersionId = "04596b32-00d5-408e-8ce3-67ef6400d328"
$CurriculumId       = "25284c69-38e4-467f-80a6-e153c3ea1bc1"

$ExpectedCourses = @(
    [pscustomobject]@{ Code="GST 04101"; Name="Communication Skills"; Credits=9;  Category="CORE" }
    [pscustomobject]@{ Code="GST 04102"; Name="Basic Computer Applications"; Credits=9; Category="CORE" }
    [pscustomobject]@{ Code="PPA 04101"; Name="Principles of Project Planning"; Credits=12; Category="CORE" }
    [pscustomobject]@{ Code="BAD 04101"; Name="Principles of Business Administration"; Credits=12; Category="CORE" }
    [pscustomobject]@{ Code="ACC 04101"; Name="Elements of Financial Accounting"; Credits=10; Category="CORE" }
    [pscustomobject]@{ Code="GST 04103"; Name="Development Perspectives & Ethics"; Credits=8; Category="GENERAL" }
)

function Get-PropertyValue {
    param([object]$Object, [string[]]$Names)

    if ($null -eq $Object) { return $null }
    foreach ($Name in $Names) {
        $Property = $Object.PSObject.Properties[$Name]
        if ($null -ne $Property) { return $Property.Value }
    }
    return $null
}

function ConvertTo-RecordArray {
    param([object]$Response)

    if ($null -eq $Response) { return @() }

    $DataProperty = $Response.PSObject.Properties["data"]
    if ($null -ne $DataProperty) {
        $Data = $DataProperty.Value
        if ($null -eq $Data) { return @() }

        if ($Data -isnot [System.Array]) {
            foreach ($ContainerName in @("data", "records", "items")) {
                $Container = $Data.PSObject.Properties[$ContainerName]
                if ($null -ne $Container) { return @($Container.Value) }
            }
        }

        return @($Data)
    }

    foreach ($ContainerName in @("records", "items")) {
        $Container = $Response.PSObject.Properties[$ContainerName]
        if ($null -ne $Container) { return @($Container.Value) }
    }

    return @($Response)
}

function Invoke-IDMCGet {
    param([Parameter(Mandatory = $true)][string]$Path)

    return Invoke-RestMethod `
        -Method GET `
        -Uri "$BaseUrl$Path" `
        -Headers $script:Headers `
        -TimeoutSec 60 `
        -ErrorAction Stop
}

function Get-AllPages {
    param([Parameter(Mandatory = $true)][string]$Path)

    $All = New-Object System.Collections.Generic.List[object]
    $Page = 1
    $PageSize = 100
    $Joiner = if ($Path.Contains("?")) { "&" } else { "?" }

    while ($true) {
        $Response = Invoke-IDMCGet -Path "$Path${Joiner}page=$Page&limit=$PageSize"
        $Rows = @(ConvertTo-RecordArray $Response)
        foreach ($Row in $Rows) { $All.Add($Row) }

        $Total = $null
        $MetaProperty = $Response.PSObject.Properties["meta"]
        if ($null -ne $MetaProperty -and $null -ne $MetaProperty.Value) {
            $Total = Get-PropertyValue $MetaProperty.Value @("total")
        }

        if ($Rows.Count -eq 0) { break }
        if ($null -ne $Total -and $All.Count -ge [int]$Total) { break }
        if ($null -eq $Total -and $Rows.Count -lt $PageSize) { break }

        $Page++
        if ($Page -gt 1000) { throw "Pagination exceeded 1000 pages for $Path." }
    }

    return @($All.ToArray())
}

function Get-SingleRecordById {
    param([Parameter(Mandatory = $true)][string]$Path)

    $Response = Invoke-IDMCGet -Path $Path
    $Rows = @(ConvertTo-RecordArray $Response)
    if ($Rows.Count -ne 1) {
        throw "Expected one record from $Path; found $($Rows.Count)."
    }
    return $Rows[0]
}

function Assert-Equal {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [AllowNull()][object]$Actual,
        [AllowNull()][object]$Expected
    )

    if ([string]$Actual -cne [string]$Expected) {
        throw "$Label is '$Actual'; expected '$Expected'."
    }
}

function Assert-OneOf {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [AllowNull()][object]$Actual,
        [Parameter(Mandatory = $true)][object[]]$Allowed
    )

    if ([string]$Actual -notin @($Allowed | ForEach-Object { [string]$_ })) {
        throw "$Label is '$Actual'; allowed: $($Allowed -join ', ')."
    }
}

function Assert-NotBlank {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [AllowNull()][object]$Value
    )

    if ([string]::IsNullOrWhiteSpace([string]$Value)) {
        throw "$Label is missing."
    }
}

function Test-TrueValue {
    param([AllowNull()][object]$Value)

    if ($Value -is [bool]) { return $Value }
    return ([string]$Value).Trim().ToLowerInvariant() -eq "true"
}

function Write-Utf8File {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $Utf8NoBom)
}

# This script is deliberately read-only. The only HTTP method implemented is GET.
$Token = $null
foreach ($TokenName in @("IDMC_ACCESS_TOKEN", "SUPABASE_ACCESS_TOKEN", "ACCESS_TOKEN")) {
    $Candidate = [Environment]::GetEnvironmentVariable($TokenName, "Process")
    if (-not [string]::IsNullOrWhiteSpace($Candidate)) {
        $Token = $Candidate.Trim()
        break
    }
}

if ([string]::IsNullOrWhiteSpace($Token)) {
    throw "Token haipo. Load IDMC_ACCESS_TOKEN kwenye PowerShell session hii kisha rerun."
}
if (-not (Test-Path -LiteralPath $ProjectPath -PathType Container)) {
    throw "ProjectPath haipo au si folder: $ProjectPath"
}

$script:Headers = @{
    Authorization = "Bearer $Token"
    Accept        = "application/json"
}

Write-Host ""
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host " IDMC - SECTION 12K FINAL END-TO-END AUDIT" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "MODE: READ-ONLY (GET requests only)" -ForegroundColor Yellow

$null = Invoke-IDMCGet -Path "/auth/me"
Write-Host "AUTH: PASS" -ForegroundColor Green

$Report = New-Object System.Collections.Generic.List[string]
$Report.Add("IDMC SECTION 12K - FINAL END-TO-END AUDIT REPORT")
$Report.Add("=================================================")
$Report.Add("Generated UTC       : $((Get-Date).ToUniversalTime().ToString('o'))")
$Report.Add("Audit mode          : READ-ONLY (GET requests only)")
$Report.Add("Base URL            : $BaseUrl")
$Report.Add("")

# ============================================================
# 1. STUDENT
# ============================================================
Write-Host ""
Write-Host "===== 1. STUDENT =====" -ForegroundColor Cyan

$Student = Get-SingleRecordById -Path "/students/$StudentId"
$ActualStudentId = [string](Get-PropertyValue $Student @("id"))
$ActualStudentNumber = [string](Get-PropertyValue $Student @("student_number", "studentNumber"))
$StudentStatus = [string](Get-PropertyValue $Student @("student_status", "studentStatus"))

Assert-Equal -Label "Student ID" -Actual $ActualStudentId -Expected $StudentId
Assert-Equal -Label "Student number" -Actual $ActualStudentNumber -Expected $StudentNumber
Assert-Equal -Label "Student status" -Actual $StudentStatus -Expected "ACTIVE"

$Report.Add("1. STUDENT: PASS")
$Report.Add("   Student ID        : $StudentId")
$Report.Add("   Student number    : $StudentNumber")
$Report.Add("   Student status    : ACTIVE")
Write-Host "STUDENT : $StudentNumber / ACTIVE" -ForegroundColor Green

# ============================================================
# 2. PARENT REGISTRATION
# ============================================================
Write-Host ""
Write-Host "===== 2. PARENT REGISTRATION =====" -ForegroundColor Cyan

$Registration = Get-SingleRecordById -Path "/academic-core/registrations/$RegistrationId"
$RegistrationStudentId = [string](Get-PropertyValue $Registration @("student_id", "studentId"))
$RegistrationYearId = [string](Get-PropertyValue $Registration @("academic_year_id", "academicYearId"))
$RegistrationSemesterId = [string](Get-PropertyValue $Registration @("semester_id", "semesterId"))
$RegistrationProgrammeId = [string](Get-PropertyValue $Registration @("programme_id", "programmeId"))
$RegistrationVersionId = [string](Get-PropertyValue $Registration @("programme_version_id", "programmeVersionId"))
$RegistrationStatus = [string](Get-PropertyValue $Registration @("registration_status", "registrationStatus"))
$TotalCredits = [decimal](Get-PropertyValue $Registration @("total_registered_credits", "totalRegisteredCredits"))
$MinimumCredits = [decimal](Get-PropertyValue $Registration @("minimum_credits", "minimumCredits"))
$MaximumCredits = [decimal](Get-PropertyValue $Registration @("maximum_credits", "maximumCredits"))
$AcademicEligibility = [string](Get-PropertyValue $Registration @("academic_eligibility_status", "academicEligibilityStatus"))
$FinanceEligibility = [string](Get-PropertyValue $Registration @("finance_eligibility_status", "financeEligibilityStatus"))
$DocumentEligibility = [string](Get-PropertyValue $Registration @("document_eligibility_status", "documentEligibilityStatus"))
$SubmittedAt = [string](Get-PropertyValue $Registration @("submitted_at", "submittedAt"))
$ApprovedBy = [string](Get-PropertyValue $Registration @("approved_by", "approvedBy"))
$ApprovedAt = [string](Get-PropertyValue $Registration @("approved_at", "approvedAt"))
$LockedAt = [string](Get-PropertyValue $Registration @("locked_at", "lockedAt"))

Assert-Equal -Label "Registration student ID" -Actual $RegistrationStudentId -Expected $StudentId
Assert-Equal -Label "Registration academic year ID" -Actual $RegistrationYearId -Expected $AcademicYearId
Assert-Equal -Label "Registration semester ID" -Actual $RegistrationSemesterId -Expected $SemesterId
Assert-Equal -Label "Registration programme ID" -Actual $RegistrationProgrammeId -Expected $ProgrammeId
Assert-Equal -Label "Registration programme version ID" -Actual $RegistrationVersionId -Expected $ProgrammeVersionId
Assert-Equal -Label "Registration status" -Actual $RegistrationStatus -Expected "REGISTERED"
Assert-Equal -Label "Total registered credits" -Actual $TotalCredits -Expected 60
Assert-Equal -Label "Minimum credits" -Actual $MinimumCredits -Expected 60
Assert-Equal -Label "Maximum credits" -Actual $MaximumCredits -Expected 60
Assert-OneOf -Label "Academic eligibility" -Actual $AcademicEligibility -Allowed @("ELIGIBLE", "OVERRIDE")
Assert-OneOf -Label "Finance eligibility" -Actual $FinanceEligibility -Allowed @("CLEARED", "OVERRIDE")
Assert-OneOf -Label "Document eligibility" -Actual $DocumentEligibility -Allowed @("CLEARED", "OVERRIDE")
Assert-NotBlank -Label "submitted_at" -Value $SubmittedAt
Assert-NotBlank -Label "approved_by" -Value $ApprovedBy
Assert-NotBlank -Label "approved_at" -Value $ApprovedAt
if (-not [string]::IsNullOrWhiteSpace($LockedAt)) {
    throw "Registration was unexpectedly locked at '$LockedAt'."
}

$Report.Add("")
$Report.Add("2. PARENT REGISTRATION: PASS")
$Report.Add("   Registration ID   : $RegistrationId")
$Report.Add("   Status            : REGISTERED")
$Report.Add("   Credits           : $TotalCredits (minimum $MinimumCredits / maximum $MaximumCredits)")
$Report.Add("   Eligibility       : $AcademicEligibility / $FinanceEligibility / $DocumentEligibility")
$Report.Add("   Submitted at      : $SubmittedAt")
$Report.Add("   Approved by       : $ApprovedBy")
$Report.Add("   Approved at       : $ApprovedAt")
$Report.Add("   Locked            : NO")
Write-Host "REGISTRATION : REGISTERED / 60 CREDITS / NOT LOCKED" -ForegroundColor Green

# ============================================================
# 3. APPROVAL
# ============================================================
Write-Host ""
Write-Host "===== 3. APPROVAL WORKFLOW =====" -ForegroundColor Cyan

$AllApprovals = @(Get-AllPages -Path "/academic-core/registration-approvals")
$ApprovalMatches = @(
    $AllApprovals | Where-Object {
        [string](Get-PropertyValue $_ @("student_registration_id", "studentRegistrationId")) -eq $RegistrationId -and
        [int](Get-PropertyValue $_ @("approval_level", "approvalLevel")) -eq 1
    }
)
if ($ApprovalMatches.Count -ne 1) {
    throw "Expected exactly one level-1 approval; found $($ApprovalMatches.Count)."
}

$Approval = $ApprovalMatches[0]
$ApprovalRole = [string](Get-PropertyValue $Approval @("approval_role", "approvalRole"))
$ApprovalStatus = [string](Get-PropertyValue $Approval @("approval_status", "approvalStatus"))
$ApprovalRecordBy = [string](Get-PropertyValue $Approval @("approved_by", "approvedBy"))
$ApprovalRecordAt = [string](Get-PropertyValue $Approval @("approved_at", "approvedAt"))

Assert-Equal -Label "Approval role" -Actual $ApprovalRole -Expected "ACADEMIC"
Assert-Equal -Label "Approval status" -Actual $ApprovalStatus -Expected "APPROVED"
Assert-NotBlank -Label "Approval record approved_by" -Value $ApprovalRecordBy
Assert-NotBlank -Label "Approval record approved_at" -Value $ApprovalRecordAt

$Report.Add("")
$Report.Add("3. APPROVAL WORKFLOW: PASS")
$Report.Add("   Level / role      : 1 / ACADEMIC")
$Report.Add("   Status            : APPROVED")
$Report.Add("   Approved by       : $ApprovalRecordBy")
$Report.Add("   Approved at       : $ApprovalRecordAt")
Write-Host "APPROVAL : LEVEL 1 / ACADEMIC / APPROVED" -ForegroundColor Green

# ============================================================
# 4. COURSE MASTER AND COURSE REGISTRATIONS
# ============================================================
Write-Host ""
Write-Host "===== 4. COURSES / OFFERINGS / REGISTRATIONS =====" -ForegroundColor Cyan

$AllCourses = @(Get-AllPages -Path "/academic-core/courses")
if ($AllCourses.Count -lt 6) {
    throw "Course Master has only $($AllCourses.Count) rows; cannot contain all 6 required courses."
}

$AllCourseRegistrations = @(Get-AllPages -Path "/academic-core/course-registrations")
$CourseRegistrations = @(
    $AllCourseRegistrations | Where-Object {
        [string](Get-PropertyValue $_ @("student_registration_id", "studentRegistrationId")) -eq $RegistrationId -and
        [string](Get-PropertyValue $_ @("registration_status", "registrationStatus")) -notin @("DROPPED", "REJECTED", "CANCELLED")
    }
)
if ($CourseRegistrations.Count -ne 6) {
    throw "Expected 6 active course registrations; found $($CourseRegistrations.Count)."
}

$DuplicateCourseRegistrationIds = @(
    $CourseRegistrations |
        Group-Object { [string](Get-PropertyValue $_ @("course_id", "courseId")) } |
        Where-Object { $_.Count -gt 1 }
)
if ($DuplicateCourseRegistrationIds.Count -gt 0) {
    throw "Duplicate course registrations found for $($DuplicateCourseRegistrationIds.Count) course IDs."
}

$DuplicateOfferingRegistrationIds = @(
    $CourseRegistrations |
        Group-Object { [string](Get-PropertyValue $_ @("course_offering_id", "courseOfferingId")) } |
        Where-Object { $_.Count -gt 1 }
)
if ($DuplicateOfferingRegistrationIds.Count -gt 0) {
    throw "Duplicate offering references found in course registrations."
}

$CourseRegistrationCredits = [decimal](
    ($CourseRegistrations | ForEach-Object {
        [decimal](Get-PropertyValue $_ @("credits"))
    } | Measure-Object -Sum).Sum
)
if ($CourseRegistrationCredits -ne 60) {
    throw "Course registration credits total $CourseRegistrationCredits; expected 60."
}

$AllOfferings = @(Get-AllPages -Path "/academic-core/course-offerings")
$AllMappings = @(Get-AllPages -Path "/academic-core/curriculum-courses")
$AuditedCourses = New-Object System.Collections.Generic.List[object]

foreach ($Expected in $ExpectedCourses) {
    $CourseMatches = @(
        $AllCourses | Where-Object {
            [string](Get-PropertyValue $_ @("course_code", "courseCode")) -ceq $Expected.Code
        }
    )
    if ($CourseMatches.Count -ne 1) {
        throw "$($Expected.Code): expected one Course Master record; found $($CourseMatches.Count)."
    }

    $Course = $CourseMatches[0]
    $CourseId = [string](Get-PropertyValue $Course @("id"))
    $CourseName = [string](Get-PropertyValue $Course @("course_name", "courseName", "name"))
    $CourseCredits = [decimal](Get-PropertyValue $Course @("credit_units", "creditUnits", "credits"))
    $CourseStatus = [string](Get-PropertyValue $Course @("status"))

    Assert-NotBlank -Label "$($Expected.Code) course ID" -Value $CourseId
    Assert-Equal -Label "$($Expected.Code) name" -Actual $CourseName -Expected $Expected.Name
    Assert-Equal -Label "$($Expected.Code) credits" -Actual $CourseCredits -Expected $Expected.Credits
    Assert-Equal -Label "$($Expected.Code) status" -Actual $CourseStatus -Expected "ACTIVE"

    $RegistrationMatches = @(
        $CourseRegistrations | Where-Object {
            [string](Get-PropertyValue $_ @("course_id", "courseId")) -eq $CourseId
        }
    )
    if ($RegistrationMatches.Count -ne 1) {
        throw "$($Expected.Code): expected one course registration; found $($RegistrationMatches.Count)."
    }

    $CourseRegistration = $RegistrationMatches[0]
    $CourseRegistrationId = [string](Get-PropertyValue $CourseRegistration @("id"))
    $CourseRegistrationStatus = [string](Get-PropertyValue $CourseRegistration @("registration_status", "registrationStatus"))
    $RegisteredCredits = [decimal](Get-PropertyValue $CourseRegistration @("credits"))
    $OfferingId = [string](Get-PropertyValue $CourseRegistration @("course_offering_id", "courseOfferingId"))

    Assert-NotBlank -Label "$($Expected.Code) course registration ID" -Value $CourseRegistrationId
    Assert-Equal -Label "$($Expected.Code) registration status" -Actual $CourseRegistrationStatus -Expected "REGISTERED"
    Assert-Equal -Label "$($Expected.Code) registered credits" -Actual $RegisteredCredits -Expected $Expected.Credits
    Assert-NotBlank -Label "$($Expected.Code) offering ID" -Value $OfferingId

    $OfferingMatches = @(
        $AllOfferings | Where-Object {
            [string](Get-PropertyValue $_ @("id")) -eq $OfferingId
        }
    )
    if ($OfferingMatches.Count -ne 1) {
        throw "$($Expected.Code): expected one offering '$OfferingId'; found $($OfferingMatches.Count)."
    }

    $Offering = $OfferingMatches[0]
    $OfferingStatus = [string](Get-PropertyValue $Offering @("status"))
    Assert-Equal -Label "$($Expected.Code) offering course ID" -Actual ([string](Get-PropertyValue $Offering @("course_id", "courseId"))) -Expected $CourseId
    Assert-Equal -Label "$($Expected.Code) offering academic year ID" -Actual ([string](Get-PropertyValue $Offering @("academic_year_id", "academicYearId"))) -Expected $AcademicYearId
    Assert-Equal -Label "$($Expected.Code) offering semester ID" -Actual ([string](Get-PropertyValue $Offering @("semester_id", "semesterId"))) -Expected $SemesterId
    Assert-Equal -Label "$($Expected.Code) offering programme ID" -Actual ([string](Get-PropertyValue $Offering @("programme_id", "programmeId"))) -Expected $ProgrammeId
    Assert-Equal -Label "$($Expected.Code) offering programme version ID" -Actual ([string](Get-PropertyValue $Offering @("programme_version_id", "programmeVersionId"))) -Expected $ProgrammeVersionId
    Assert-OneOf -Label "$($Expected.Code) offering status" -Actual $OfferingStatus -Allowed @("OPEN", "CLOSED")

    $MappingMatches = @(
        $AllMappings | Where-Object {
            [string](Get-PropertyValue $_ @("curriculum_id", "curriculumId")) -eq $CurriculumId -and
            [string](Get-PropertyValue $_ @("course_id", "courseId")) -eq $CourseId
        }
    )
    if ($MappingMatches.Count -ne 1) {
        throw "$($Expected.Code): expected one curriculum mapping; found $($MappingMatches.Count)."
    }

    $Mapping = $MappingMatches[0]
    $YearNumber = [int](Get-PropertyValue $Mapping @("year_number", "yearNumber"))
    $SemesterNumber = [int](Get-PropertyValue $Mapping @("semester_number", "semesterNumber"))
    $CourseCategory = [string](Get-PropertyValue $Mapping @("course_category", "courseCategory"))
    $IsCompulsory = Get-PropertyValue $Mapping @("is_compulsory", "isCompulsory")
    $MappingCredits = [decimal](Get-PropertyValue $Mapping @("credit_units", "creditUnits"))

    Assert-Equal -Label "$($Expected.Code) mapping year" -Actual $YearNumber -Expected 1
    Assert-Equal -Label "$($Expected.Code) mapping semester" -Actual $SemesterNumber -Expected 1
    Assert-Equal -Label "$($Expected.Code) mapping category" -Actual $CourseCategory -Expected $Expected.Category
    Assert-Equal -Label "$($Expected.Code) mapping credits" -Actual $MappingCredits -Expected $Expected.Credits
    if (-not (Test-TrueValue $IsCompulsory)) {
        throw "$($Expected.Code) curriculum mapping is not compulsory."
    }

    $AuditedCourses.Add([pscustomobject]@{
        Code          = $Expected.Code
        Name          = $Expected.Name
        Credits       = [int]$Expected.Credits
        Category      = $Expected.Category
        CourseId      = $CourseId
        OfferingId    = $OfferingId
        RegistrationId = $CourseRegistrationId
        OfferingStatus = $OfferingStatus
    })

    Write-Host "$($Expected.Code): PASS" -ForegroundColor Green
}

if ($AuditedCourses.Count -ne 6) {
    throw "Audited course count is $($AuditedCourses.Count); expected 6."
}

$Report.Add("")
$Report.Add("4. COURSE MASTER: PASS")
$Report.Add("   Total rows found  : $($AllCourses.Count)")
$Report.Add("   Required courses  : 6 / 6 ACTIVE")
$Report.Add("   Required duplicates: 0")
$Report.Add("")
$Report.Add("5. CURRICULUM / OFFERINGS / COURSE REGISTRATIONS: PASS")
$Report.Add("   Curriculum ID     : $CurriculumId")
$Report.Add("   Year / semester   : 1 / 1")
$Report.Add("   Courses           : 6 / 6 REGISTERED")
$Report.Add("   Credits           : $CourseRegistrationCredits")
$Report.Add("   Duplicate courses : 0")
$Report.Add("   Duplicate offers  : 0")
$Report.Add("")
$Report.Add("   COURSE DETAILS")
$Report.Add("   --------------")
foreach ($Item in $AuditedCourses) {
    $Report.Add("   $($Item.Code) | $($Item.Name) | $($Item.Credits) credits | $($Item.Category) | REGISTERED | offering $($Item.OfferingStatus)")
    $Report.Add("      course_id=$($Item.CourseId)")
    $Report.Add("      offering_id=$($Item.OfferingId)")
    $Report.Add("      course_registration_id=$($Item.RegistrationId)")
}

# ============================================================
# 5. FINAL VERDICT AND REPORT
# ============================================================
$Report.Add("")
$Report.Add("FINAL VERDICT: PASS")
$Report.Add("Student              : $StudentNumber / ACTIVE")
$Report.Add("Registration         : $RegistrationId / REGISTERED")
$Report.Add("Course registrations : 6 / 6 REGISTERED")
$Report.Add("Credits              : 60")
$Report.Add("Approval             : Level 1 / ACADEMIC / APPROVED")
$Report.Add("Registration locked  : NO")
$Report.Add("")
$Report.Add("No POST, PATCH, PUT, or DELETE request was performed.")
$Report.Add("SECTION 12 IS COMPLETE.")

$ReportPath = Join-Path $ProjectPath "IDMC_SECTION_12K_FINAL_AUDIT.txt"
$ReportText = [string]::Join([Environment]::NewLine, $Report.ToArray()) + [Environment]::NewLine
Write-Utf8File -Path $ReportPath -Content $ReportText

Write-Host ""
Write-Host "====================================================" -ForegroundColor Green
Write-Host " SECTION 12K COMPLETE - FINAL AUDIT PASS" -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Green
Write-Host "Student              : $StudentNumber / ACTIVE"
Write-Host "Registration ID      : $RegistrationId"
Write-Host "Registration status  : REGISTERED"
Write-Host "Course registrations : 6 / 6 REGISTERED"
Write-Host "Credits              : 60"
Write-Host "Approval             : Level 1 / ACADEMIC / APPROVED"
Write-Host "Registration locked  : NO"
Write-Host "HTTP mutations       : NONE"
Write-Host "Audit report         : $ReportPath"
Write-Host ""
Write-Host "SECTION 12 IS COMPLETE." -ForegroundColor Cyan
