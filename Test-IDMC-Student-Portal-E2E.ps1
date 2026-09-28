[CmdletBinding()]
param(
    [string]$ProjectPath = $PSScriptRoot,
    [string]$ApiBaseUrl = "http://127.0.0.1:4000/api/v1",
    [string]$FrontendBaseUrl = "http://127.0.0.1:5500",
    [string]$AccessToken = ""
)
$ErrorActionPreference = "Stop"
$ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
$failures = [System.Collections.Generic.List[string]]::new()
function Check([string]$Name,[scriptblock]$Action) {
    try { & $Action; Write-Host "[PASS] $Name" -ForegroundColor Green }
    catch { $failures.Add("$Name`: $($_.Exception.Message)"); Write-Host "[FAIL] $Name - $($_.Exception.Message)" -ForegroundColor Red }
}
function Require-Text([string]$Path,[string]$Pattern) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "Missing file: $Path" }
    if (-not (Select-String -LiteralPath $Path -Pattern $Pattern -Quiet)) { throw "Expected contract not found: $Pattern" }
}

Check "Backend health" { $r=Invoke-RestMethod "$ApiBaseUrl/health" -TimeoutSec 5; if($r.success -ne $true){throw "Health response was not successful."} }
foreach($page in @("/login/","/student-portal.html","/student-registration.html","/student-results.html","/student-fees.html","/student-documents.html","/student-notifications.html","/student-transcript.html")) {
    Check "Frontend $page" { $r=Invoke-WebRequest ($FrontendBaseUrl+$page) -UseBasicParsing -TimeoutSec 5; if($r.StatusCode -ne 200){throw "HTTP $($r.StatusCode)"} }
}

$backend=Join-Path $ProjectPath "apps\backend"
Check "Backend typecheck" { Push-Location $backend; try { npm run typecheck; if($LASTEXITCODE -ne 0){throw "Typecheck failed."} } finally { Pop-Location } }
Check "Focused student routes" { Require-Text (Join-Path $backend "src\modules\student-management\students\student-self-service.routes.ts") 'router.get\("/summary"' }
Check "Registration actions mounted" { Require-Text (Join-Path $backend "src\routes\index.ts") 'router.use\("/self-service"' }
Check "Payment callback is fail-closed" { Require-Text (Join-Path $backend "src\modules\self-service-actions\payment-provider.routes.ts") 'PAYMENT_PROVIDER_CALLBACK_SECRET' }
Check "Payment event migration" { Require-Text (Join-Path $ProjectPath "supabase\migrations\20260926151503_student_portal_completion.sql") 'process_student_payment_provider_event' }

if($AccessToken) {
    $headers=@{Authorization="Bearer $AccessToken"}
    foreach($route in @("/students/me","/students/me/summary","/students/me/registration","/students/me/results","/students/me/finance","/students/me/documents","/students/me/notifications","/students/me/transcript","/self-service/student/registration","/self-service/student/payments")) {
        Check "Authenticated API $route" { $r=Invoke-RestMethod ($ApiBaseUrl+$route) -Headers $headers -TimeoutSec 20; if($r.success -ne $true){throw "API response was not successful."} }
    }
} else {
    Write-Host "[SKIP] Authenticated API checks: pass -AccessToken to test a real student session." -ForegroundColor Yellow
}

if($failures.Count) { throw ("E2E audit failed:`n - "+($failures -join "`n - ")) }
Write-Host "IDMC student portal E2E audit passed." -ForegroundColor Green
