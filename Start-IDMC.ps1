[CmdletBinding()]
param(
    [string]$ProjectPath = $PSScriptRoot,
    [switch]$NoBrowser
)

$ErrorActionPreference = "Stop"
$ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
$BackendPath = Join-Path $ProjectPath "apps\backend"
$FrontendPath = Join-Path $ProjectPath "apps\frontend"
$EnvironmentFile = Join-Path $BackendPath ".env"
$LogPath = Join-Path $ProjectPath "runtime-logs"

function Stop-IdmcPort {
    param([int]$Port)
    $connections = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    foreach ($connection in $connections) {
        if ($connection.OwningProcess -and $connection.OwningProcess -ne $PID) {
            Stop-Process -Id $connection.OwningProcess -Force -ErrorAction SilentlyContinue
        }
    }
}

function Test-EnvironmentKey {
    param([string]$Name)
    $pattern = "^\s*" + [regex]::Escape($Name) + "\s*=\s*(.+?)\s*$"
    $line = Get-Content -LiteralPath $EnvironmentFile | Where-Object { $_ -match $pattern } | Select-Object -Last 1
    if (-not $line) { return $false }
    $value = ($line -replace ("^\s*" + [regex]::Escape($Name) + "\s*=\s*"), "").Trim().Trim('"').Trim("'")
    return -not [string]::IsNullOrWhiteSpace($value)
}

if (-not (Test-Path -LiteralPath (Join-Path $BackendPath "package.json"))) { throw "Backend package.json was not found under $BackendPath" }
if (-not (Test-Path -LiteralPath (Join-Path $FrontendPath "server.mjs"))) { throw "Frontend server.mjs was not found under $FrontendPath" }
if (-not (Test-Path -LiteralPath $EnvironmentFile)) { throw "Backend .env was not found. Restore the existing apps\backend\.env file before startup." }
if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw "Node.js is not installed or is not available in PATH." }
if (-not (Get-Command npm.cmd -ErrorAction SilentlyContinue)) { throw "npm is not installed or is not available in PATH." }

$requiredKeys = @("SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY", "JWT_SECRET", "SMTP_HOST", "SMTP_USER", "SMTP_PASSWORD", "SMTP_FROM_EMAIL")
$missingKeys = @($requiredKeys | Where-Object { -not (Test-EnvironmentKey -Name $_) })
if ($missingKeys.Count -gt 0) { throw "Backend .env is missing required values: $($missingKeys -join ', ')" }

New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$BackendLog = Join-Path $LogPath "backend-$stamp.log"
$FrontendLog = Join-Path $LogPath "frontend-$stamp.log"

Write-Host "Stopping old IDMC listeners on ports 4000 and 5500..." -ForegroundColor Yellow
Stop-IdmcPort -Port 4000
Stop-IdmcPort -Port 5500
Start-Sleep -Seconds 1

Push-Location $BackendPath
try {
    if (-not (Test-Path -LiteralPath (Join-Path $BackendPath "node_modules"))) {
        Write-Host "Installing backend dependencies..." -ForegroundColor Yellow
        & npm.cmd install --no-audit --no-fund
        if ($LASTEXITCODE -ne 0) { throw "npm install failed." }
    }
    Write-Host "Checking backend build before startup..." -ForegroundColor Cyan
    & npm.cmd run build
    if ($LASTEXITCODE -ne 0) { throw "Backend build failed. Startup was stopped." }
}
finally { Pop-Location }

$backendEscaped = $BackendPath.Replace("'", "''")
$backendLogEscaped = $BackendLog.Replace("'", "''")
$backendCommand = "Set-Location -LiteralPath '$backendEscaped'; npm.cmd start 2>&1 | Tee-Object -FilePath '$backendLogEscaped'"
Write-Host "Starting backend and waiting for health check..." -ForegroundColor Cyan
Start-Process powershell.exe -ArgumentList @("-NoExit", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $backendCommand) | Out-Null

$backendReady = $false
for ($attempt = 1; $attempt -le 45; $attempt++) {
    Start-Sleep -Seconds 1
    try {
        $health = Invoke-RestMethod -Uri "http://127.0.0.1:4000/api/v1/health" -TimeoutSec 2
        if ($health.success -eq $true) { $backendReady = $true; break }
    }
    catch { }
}
if (-not $backendReady) {
    Write-Host "Backend startup log: $BackendLog" -ForegroundColor Red
    if (Test-Path -LiteralPath $BackendLog) { Get-Content -LiteralPath $BackendLog -Tail 30 }
    throw "Backend did not become healthy on port 4000. Frontend startup was stopped. Fix the error shown above, then run this script again."
}

$frontendEscaped = $FrontendPath.Replace("'", "''")
$frontendLogEscaped = $FrontendLog.Replace("'", "''")
$frontendCommand = "Set-Location -LiteralPath '$frontendEscaped'; node server.mjs --root . --host 127.0.0.1 --port 5500 2>&1 | Tee-Object -FilePath '$frontendLogEscaped'"
Write-Host "Backend is healthy. Starting frontend..." -ForegroundColor Green
Start-Process powershell.exe -ArgumentList @("-NoExit", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $frontendCommand) | Out-Null

$frontendReady = $false
for ($attempt = 1; $attempt -le 30; $attempt++) {
    Start-Sleep -Seconds 1
    try {
        $page = Invoke-WebRequest -Uri "http://127.0.0.1:5500/login/" -UseBasicParsing -TimeoutSec 2
        if ($page.StatusCode -eq 200 -and $page.Content -match 'loginForm') { $frontendReady = $true; break }
    }
    catch { }
}
if (-not $frontendReady) {
    Write-Host "Frontend startup log: $FrontendLog" -ForegroundColor Red
    if (Test-Path -LiteralPath $FrontendLog) { Get-Content -LiteralPath $FrontendLog -Tail 30 }
    throw "Frontend did not become healthy on port 5500."
}

Write-Host ""; Write-Host "IDMC iMIS is ready." -ForegroundColor Green
Write-Host "Backend : http://127.0.0.1:4000/api/v1/health"
Write-Host "Login   : http://127.0.0.1:5500/login/"
Write-Host "Applicant: http://127.0.0.1:5500/applicant-portal.html"
Write-Host "Admissions: http://127.0.0.1:5500/admissions.html"
if (-not $NoBrowser) { Start-Process "http://127.0.0.1:5500/login/" }
