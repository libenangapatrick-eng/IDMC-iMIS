# IDMC iMIS - API Integration Smoke Test
# Tests authenticated API access across all completed modules.

$ErrorActionPreference = "Stop"

$API = "http://127.0.0.1:4000/api/v1"

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host " IDMC iMIS API INTEGRATION TEST" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# ------------------------------------------------------------
# Load existing IDMC session if available
# ------------------------------------------------------------

$sessionFile = "$env:TEMP\idmc-api-session.json"

if (-not (Test-Path $sessionFile)) {
    Write-Warning "API session file not found:"
    Write-Warning $sessionFile
    Write-Host ""
    Write-Host "We will first verify unauthenticated protection." -ForegroundColor Yellow
}

$headers = @{}

if (Test-Path $sessionFile) {
    try {
        $session = Get-Content $sessionFile -Raw | ConvertFrom-Json

        if ($session.access_token) {
            $headers["Authorization"] = "Bearer $($session.access_token)"
            Write-Host "ACCESS TOKEN: FOUND" -ForegroundColor Green
        }
    }
    catch {
        Write-Warning "Session file exists but could not be parsed."
    }
}

# ------------------------------------------------------------
# Endpoint groups
# ------------------------------------------------------------

$tests = @(
    @{ Name="Health";              Path="/health" },

    @{ Name="Institutions";        Path="/institutions" },
    @{ Name="Campuses";            Path="/campuses" },
    @{ Name="Departments";         Path="/departments" },
    @{ Name="Schools";             Path="/schools" },

    @{ Name="Users";               Path="/users" },
    @{ Name="Roles";               Path="/roles" },

    @{ Name="Applications";        Path="/applications" },
    @{ Name="Admissions";          Path="/admissions" },

    @{ Name="Students";            Path="/students" },
    @{ Name="Registration";        Path="/registrations" },

    @{ Name="Academic Core";       Path="/academic-core" },
    @{ Name="Timetables";          Path="/timetables" },
    @{ Name="Attendance";          Path="/attendance" },

    @{ Name="Assessments";         Path="/assessments" },
    @{ Name="Examinations";        Path="/examinations" },
    @{ Name="Results";             Path="/results" },

    @{ Name="Transcripts";         Path="/transcripts" },
    @{ Name="Graduation";          Path="/graduation" },
    @{ Name="Alumni";              Path="/alumni" },

    @{ Name="Finance";             Path="/finance" },
    @{ Name="Human Resources";     Path="/hr" },

    @{ Name="Operations";          Path="/operations" },
    @{ Name="Assets";              Path="/assets" },
    @{ Name="Procurement";         Path="/procurement" },

    @{ Name="Research & QA";       Path="/research" },
    @{ Name="Communications";      Path="/communications" },
    @{ Name="Documents";           Path="/documents" },
    @{ Name="Helpdesk";            Path="/helpdesk" },

    @{ Name="Reports";             Path="/reports" },
    @{ Name="System Configuration";Path="/system" }
)

$passed = 0
$failed = 0
$protected = 0

foreach ($test in $tests) {

    $url = "$API$($test.Path)"

    Write-Host ""
    Write-Host "TEST: $($test.Name)" -ForegroundColor White
    Write-Host "URL : $url" -ForegroundColor DarkGray

    try {

        if ($headers.ContainsKey("Authorization")) {
            $response = Invoke-WebRequest `
                -Uri $url `
                -Method GET `
                -Headers $headers `
                -UseBasicParsing `
                -ErrorAction Stop
        }
        else {
            $response = Invoke-WebRequest `
                -Uri $url `
                -Method GET `
                -UseBasicParsing `
                -ErrorAction Stop
        }

        Write-Host "PASS [$($response.StatusCode)]" -ForegroundColor Green
        $passed++

    }
    catch {

        $status = $_.Exception.Response.StatusCode.value__

        if ($status -eq 401 -or $status -eq 403) {
            Write-Host "PROTECTED [$status]" -ForegroundColor Yellow
            $protected++
        }
        elseif ($status) {
            Write-Host "FAIL [$status]" -ForegroundColor Red
            $failed++
        }
        else {
            Write-Host "FAIL [NO RESPONSE]" -ForegroundColor Red
            $failed++
        }
    }
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host " API TEST SUMMARY" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Passed    : $passed" -ForegroundColor Green
Write-Host "Protected : $protected" -ForegroundColor Yellow
Write-Host "Failed    : $failed" -ForegroundColor Red
Write-Host "Total     : $($tests.Count)"
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

if ($failed -gt 0) {
    exit 1
}

exit 0
