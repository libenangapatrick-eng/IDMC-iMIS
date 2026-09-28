param(
    [string]$BaseUrl = "http://127.0.0.1:4000/api/v1"
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host " IDMC iMIS - A4 AUTHENTICATED CONTRACT TEST" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

# -----------------------------------------------------
# TOKEN
# -----------------------------------------------------

$Token = $env:IDMC_ACCESS_TOKEN

if ([string]::IsNullOrWhiteSpace($Token)) {
    throw "IDMC_ACCESS_TOKEN is not set."
}

$Token = $Token.Trim()

if ($Token -match "\s") {
    throw "IDMC_ACCESS_TOKEN contains whitespace."
}

$Headers = @{
    Authorization = "Bearer $Token"
    Accept        = "application/json"
}

# -----------------------------------------------------
# TEST CONTRACTS
# -----------------------------------------------------
#
# IMPORTANT:
# Test a REAL GET endpoint where a module has no GET "/".
#
# 200 = accessible
# 403 = route exists but RBAC denied
# 404 = route contract missing
# 5xx = backend failure
#
# -----------------------------------------------------

$Tests = @(
    @{ Module = "Health";          Route = "/health" },

    @{ Module = "Institutions";    Route = "/institutions" },
    @{ Module = "Campuses";        Route = "/campuses" },
    @{ Module = "Departments";     Route = "/departments" },
    @{ Module = "Schools";         Route = "/schools" },

    @{ Module = "Users";           Route = "/users" },
    @{ Module = "Roles";           Route = "/roles" },

    @{ Module = "Applications";    Route = "/applications/applications" },
    @{ Module = "Admissions";      Route = "/admissions/admission-decisions" },

    @{ Module = "Students";        Route = "/students" },
    @{ Module = "Registration";    Route = "/registrations" },

    @{ Module = "Academic Core";   Route = "/academic-core/years" },

    @{ Module = "Timetables";      Route = "/timetables" },
    @{ Module = "Attendance";      Route = "/attendance" },

    # Backend mounts BOTH /assessment and /assessments.
    @{ Module = "Assessments";     Route = "/assessment/assessments" },

    @{ Module = "Examinations";    Route = "/examinations/periods" },
    @{ Module = "Results";         Route = "/results/course-results" },

    @{ Module = "Transcripts";     Route = "/transcripts" },

    @{ Module = "Graduation";      Route = "/graduation/periods" },
    @{ Module = "Alumni";          Route = "/alumni/records" },

    # Finance has no GET "/".
    # Use an actual finance GET endpoint.
    @{ Module = "Finance";         Route = "/finance/fee-structures" },

    @{ Module = "Human Resources"; Route = "/hr/staff" },

    @{ Module = "Operations";      Route = "/operations/inventory/items" },

    @{ Module = "Assets";          Route = "/assets/assets" },

    @{ Module = "Procurement";     Route = "/operations/procurement/requests" },

    @{ Module = "Research";        Route = "/research/projects" },

    @{ Module = "Communications";  Route = "/communications/announcements" },

    @{ Module = "Documents";       Route = "/documents/documents" },

    @{ Module = "Helpdesk";        Route = "/communications/helpdesk/tickets" },

    @{ Module = "Reports";         Route = "/reports/definitions" },

    @{ Module = "System";          Route = "/system/settings" },

    @{ Module = "Hostel";          Route = "/hostel/hostels" },

    @{ Module = "Library";         Route = "/library/items" }
)

$Results = @()

# -----------------------------------------------------
# HTTP TEST FUNCTION
# -----------------------------------------------------

function Invoke-ApiContractTest {

    param(
        [string]$Module,
        [string]$Route
    )

    $Url = "$BaseUrl$Route"

    Write-Host ""
    Write-Host "TEST: $Module" -ForegroundColor Yellow
    Write-Host "URL : $Url"

    $Status = 0
    $Result = "FAIL"
    $Body = $null

    try {

        $Response = Invoke-WebRequest `
            -Uri $Url `
            -Method Get `
            -Headers $Headers `
            -UseBasicParsing

        $Status = [int]$Response.StatusCode
        $Body = $Response.Content

    }
    catch {

        if ($_.Exception.Response) {

            try {
                $Status = [int]$_.Exception.Response.StatusCode
            }
            catch {
                $Status = 0
            }

            try {
                $Stream = $_.Exception.Response.GetResponseStream()

                if ($Stream) {
                    $Reader = New-Object System.IO.StreamReader($Stream)
                    $Body = $Reader.ReadToEnd()
                    $Reader.Close()
                }
            }
            catch {
                $Body = $_.Exception.Message
            }

        }
        else {
            $Status = 0
            $Body = $_.Exception.Message
        }
    }

    switch ($Status) {

        200 {
            $Result = "PASS"
            Write-Host "PASS [200]" -ForegroundColor Green
        }

        201 {
            $Result = "PASS"
            Write-Host "PASS [201]" -ForegroundColor Green
        }

        204 {
            $Result = "PASS"
            Write-Host "PASS [204]" -ForegroundColor Green
        }

        400 {
            # Route exists. Request simply requires parameters.
            $Result = "CONTRACT"
            Write-Host "ROUTE EXISTS [400]" -ForegroundColor DarkYellow
        }

        401 {
            $Result = "AUTH"
            Write-Host "AUTH FAILURE [401]" -ForegroundColor Red
        }

        403 {
            # This is NOT a missing route.
            # It proves router + auth + RBAC were reached.
            $Result = "RBAC"
            Write-Host "RBAC PROTECTED [403]" -ForegroundColor Yellow
        }

        404 {
            $Result = "MISSING"
            Write-Host "ROUTE MISSING [404]" -ForegroundColor Red
        }

        default {

            if ($Status -ge 500) {
                $Result = "SERVER"
                Write-Host "SERVER ERROR [$Status]" -ForegroundColor Red
            }
            elseif ($Status -ge 200 -and $Status -lt 300) {
                $Result = "PASS"
                Write-Host "PASS [$Status]" -ForegroundColor Green
            }
            elseif ($Status -gt 0) {
                $Result = "OTHER"
                Write-Host "HTTP [$Status]" -ForegroundColor DarkYellow
            }
            else {
                $Result = "NETWORK"
                Write-Host "REQUEST FAILED [0]" -ForegroundColor Red
            }
        }

    }

    if (
        $Result -eq "MISSING" -or
        $Result -eq "SERVER" -or
        $Result -eq "AUTH" -or
        $Result -eq "NETWORK"
    ) {
        if ($Body) {
            Write-Host "Response: $Body" -ForegroundColor DarkGray
        }
    }

    return [PSCustomObject]@{
        Module = $Module
        Route  = $Route
        Status = $Status
        Result = $Result
    }
}

# -----------------------------------------------------
# HEALTH FIRST
# -----------------------------------------------------

try {

    $Health = Invoke-WebRequest `
        -Uri "$BaseUrl/health" `
        -Method Get `
        -UseBasicParsing

    if ($Health.StatusCode -ne 200) {
        throw "Health endpoint returned $($Health.StatusCode)"
    }

    Write-Host ""
    Write-Host "Backend health: PASS [200]" -ForegroundColor Green

}
catch {

    Write-Host ""
    Write-Host "Backend is not healthy." -ForegroundColor Red
    Write-Host $_.Exception.Message
    exit 1
}

# -----------------------------------------------------
# RUN TESTS
# -----------------------------------------------------

foreach ($Test in $Tests) {

    $Results += Invoke-ApiContractTest `
        -Module $Test.Module `
        -Route $Test.Route
}

# -----------------------------------------------------
# RESULTS
# -----------------------------------------------------

Write-Host ""
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host " AUTHENTICATED CONTRACT RESULTS" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host ""

$Results | Format-Table -AutoSize

$Passed = @(
    $Results |
        Where-Object {
            $_.Result -eq "PASS" -or
            $_.Result -eq "CONTRACT"
        }
).Count

$Rbac = @(
    $Results |
        Where-Object Result -eq "RBAC"
).Count

$Missing = @(
    $Results |
        Where-Object Result -eq "MISSING"
).Count

$AuthFailed = @(
    $Results |
        Where-Object Result -eq "AUTH"
).Count

$Server = @(
    $Results |
        Where-Object Result -eq "SERVER"
).Count

$Network = @(
    $Results |
        Where-Object Result -eq "NETWORK"
).Count

$Other = @(
    $Results |
        Where-Object Result -eq "OTHER"
).Count

Write-Host ""
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host " SUMMARY" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

Write-Host "Passed/Contract : $Passed"
Write-Host "RBAC 403        : $Rbac"
Write-Host "Missing 404     : $Missing"
Write-Host "Auth 401        : $AuthFailed"
Write-Host "Server 5xx      : $Server"
Write-Host "Network         : $Network"
Write-Host "Other           : $Other"
Write-Host "Total           : $($Results.Count)"

$CriticalFailures =
    $Missing +
    $AuthFailed +
    $Server +
    $Network

Write-Host ""

if ($CriticalFailures -eq 0) {

    Write-Host "====================================================" -ForegroundColor Green
    Write-Host " A4 ROUTE/AUTH FOUNDATION PASSED" -ForegroundColor Green
    Write-Host "====================================================" -ForegroundColor Green

    if ($Rbac -gt 0) {
        Write-Host ""
        Write-Host "NOTE: $Rbac endpoint(s) returned 403." -ForegroundColor Yellow
        Write-Host "Routes exist; remaining work is role/permission coverage." -ForegroundColor Yellow
    }

    exit 0
}

Write-Host "====================================================" -ForegroundColor Red
Write-Host " A4 STILL HAS CRITICAL FAILURES" -ForegroundColor Red
Write-Host "====================================================" -ForegroundColor Red

exit 1


