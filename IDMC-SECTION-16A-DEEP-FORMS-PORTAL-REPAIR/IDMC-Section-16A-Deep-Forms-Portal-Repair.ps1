[CmdletBinding()]
param(
    [string]$ProjectRoot = (Get-Location).Path,
    [switch]$SkipDatabase,
    [switch]$RestartServers,
    [switch]$OpenBrowser
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Write-Step([string]$Text) {
    Write-Host "`n===== $Text =====" -ForegroundColor Cyan
}

function Resolve-Executable([string[]]$Names) {
    foreach ($Name in $Names) {
        $Command = Get-Command $Name -ErrorAction SilentlyContinue
        if ($Command) { return $Command.Source }
    }
    throw "Required executable was not found: $($Names -join ', ')"
}

function Stop-ProjectPort([int]$Port, [string]$Root) {
    $Connections = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
    foreach ($Connection in $Connections) {
        $Process = Get-CimInstance Win32_Process -Filter "ProcessId=$($Connection.OwningProcess)" -ErrorAction SilentlyContinue
        if (-not $Process) { continue }
        if ([string]$Process.Name -notmatch '^node(\.exe)?$') {
            throw "Port $Port is used by non-Node PID $($Process.ProcessId) ($($Process.Name)). Stop it manually to avoid terminating an unrelated application."
        }
        Stop-Process -Id $Process.ProcessId -Force
        Write-Host "Stopped previous IDMC process on port $Port (PID $($Process.ProcessId))."
    }
}

function Wait-Url([string]$Url, [int]$Seconds = 30) {
    $Deadline = (Get-Date).AddSeconds($Seconds)
    do {
        try {
            $Response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 3
            if ($Response.StatusCode -ge 200 -and $Response.StatusCode -lt 500) { return }
        } catch { Start-Sleep -Milliseconds 750 }
    } while ((Get-Date) -lt $Deadline)
    throw "Service did not become ready: $Url"
}

$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
$BackendRoot = Join-Path $ProjectRoot "apps\backend"
$FrontendRoot = Join-Path $ProjectRoot "apps\frontend"
$PayloadRoot = Join-Path $PSScriptRoot "payload"

if (-not (Test-Path (Join-Path $BackendRoot "package.json"))) { throw "Invalid ProjectRoot: backend package.json was not found at $BackendRoot" }
if (-not (Test-Path $FrontendRoot)) { throw "Invalid ProjectRoot: frontend directory was not found at $FrontendRoot" }
if (-not (Test-Path $PayloadRoot)) { throw "Repair payload is missing beside this script: $PayloadRoot" }

$Node = Resolve-Executable @("node.exe", "node")
$Npm = Resolve-Executable @("npm.cmd", "npm")
$Npx = Resolve-Executable @("npx.cmd", "npx")
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$BackupRoot = Join-Path $ProjectRoot "repair-backups\section-16A-$Timestamp"
$LogRoot = Join-Path $ProjectRoot "runtime-logs"

Write-Host "====================================================" -ForegroundColor DarkRed
Write-Host " SECTION 16A - DEEP FORMS / PORTAL / API REPAIR" -ForegroundColor DarkRed
Write-Host "====================================================" -ForegroundColor DarkRed

Write-Step "1. PREFLIGHT AND SAFE BACKUP"
$PayloadFiles = @(Get-ChildItem -Path $PayloadRoot -File -Recurse)
if (-not $PayloadFiles.Count) { throw "Repair payload contains no files." }
foreach ($File in $PayloadFiles) {
    $Relative = $File.FullName.Substring($PayloadRoot.Length).TrimStart([char]'\', [char]'/')
    $Target = Join-Path $ProjectRoot $Relative
    if (Test-Path $Target) {
        $Backup = Join-Path $BackupRoot $Relative
        New-Item -ItemType Directory -Path (Split-Path $Backup) -Force | Out-Null
        Copy-Item -LiteralPath $Target -Destination $Backup -Force
    }
}
Write-Host "Backup: $BackupRoot"

Write-Step "2. INSTALL VERIFIED SOURCE FILES"
foreach ($File in $PayloadFiles) {
    $Relative = $File.FullName.Substring($PayloadRoot.Length).TrimStart([char]'\', [char]'/')
    $Target = Join-Path $ProjectRoot $Relative
    New-Item -ItemType Directory -Path (Split-Path $Target) -Force | Out-Null
    Copy-Item -LiteralPath $File.FullName -Destination $Target -Force
}
Write-Host "Installed $($PayloadFiles.Count) source files."

Write-Step "3. FRONTEND SYNTAX AND ROUTE CONTRACT CHECKS"
$JavascriptFiles = @(
    (Join-Path $FrontendRoot "assets\js\applicant-live-forms.js"),
    (Join-Path $FrontendRoot "assets\js\auth.js")
)
foreach ($File in $JavascriptFiles) {
    & $Node --check $File
    if ($LASTEXITCODE -ne 0) { throw "JavaScript syntax check failed: $File" }
}
$ApplicantScript = Get-Content (Join-Path $FrontendRoot "assets\js\applicant-live-forms.js") -Raw
if ($ApplicantScript -notmatch 'IDMC_CONFIG' -or $ApplicantScript -match 'const API = "/api/v1"') {
    throw "Applicant form API-base contract check failed."
}
$Routes = Get-Content (Join-Path $ProjectRoot "apps\backend\src\routes\index.ts") -Raw
if ($Routes -notmatch 'applicant-self-service') { throw "Applicant self-service route is not mounted." }
Write-Host "Frontend syntax and API route contracts passed."

Write-Step "4. BACKEND TYPESCRIPT BUILD"
Push-Location $BackendRoot
try {
    & $Npm run build
    if ($LASTEXITCODE -ne 0) { throw "Backend build failed with exit code $LASTEXITCODE." }
} finally { Pop-Location }

Write-Step "5. DATABASE MIGRATION"
if ($SkipDatabase) {
    Write-Warning "Database migration skipped. Run this script again without -SkipDatabase before using an APPLICANT role account."
} else {
    Push-Location $ProjectRoot
    try {
        & $Npx supabase db push
        if ($LASTEXITCODE -ne 0) { throw "Supabase migration failed with exit code $LASTEXITCODE. Source files remain installed and the backup is intact." }
    } finally { Pop-Location }
}

if ($RestartServers) {
    Write-Step "6. SAFE SERVER RESTART"
    Stop-ProjectPort -Port 4000 -Root $ProjectRoot
    Stop-ProjectPort -Port 5500 -Root $ProjectRoot
    New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
    Start-Process -FilePath $Npm -ArgumentList @("run", "start") -WorkingDirectory $BackendRoot -RedirectStandardOutput (Join-Path $LogRoot "backend.out.log") -RedirectStandardError (Join-Path $LogRoot "backend.err.log") -WindowStyle Hidden
    Start-Process -FilePath $Npx -ArgumentList @("live-server", "apps/frontend", "--port=5500", "--no-browser") -WorkingDirectory $ProjectRoot -RedirectStandardOutput (Join-Path $LogRoot "frontend.out.log") -RedirectStandardError (Join-Path $LogRoot "frontend.err.log") -WindowStyle Hidden
    Wait-Url "http://127.0.0.1:4000/api/v1/health"
    Wait-Url "http://127.0.0.1:5500/login.html"
    Write-Host "Backend and frontend are ready." -ForegroundColor Green
} else {
    Write-Step "6. SERVER STATUS"
    Write-Host "Source is installed. Use -RestartServers to safely restart IDMC ports 4000 and 5500."
}

if ($OpenBrowser) {
    if (-not $RestartServers) { Wait-Url "http://127.0.0.1:5500/login.html" 8 }
    Start-Process "http://127.0.0.1:5500/login.html"
}

Write-Step "FINAL RESULT"
Write-Host "SECTION 16A COMPLETE" -ForegroundColor Green
Write-Host "Applicant admin form : http://127.0.0.1:5500/applications.html"
Write-Host "Applicant self portal: http://127.0.0.1:5500/applicant-portal.html"
Write-Host "Dashboard            : http://127.0.0.1:5500/dashboard.html"
Write-Host "Backup               : $BackupRoot"
