#Requires -Version 5.1

[CmdletBinding()]
param(
    [string]$ProjectPath = (Get-Location).Path,
    [string]$BackendBaseUrl = "http://127.0.0.1:4000",
    [string]$FrontendBaseUrl = "http://127.0.0.1:5500"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Write-Utf8File {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $Utf8NoBom)
}

function Require-File {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required file haipo: $Path"
    }
}

$ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)
$FrontendPath = Join-Path $ProjectPath "apps\frontend"
$BackendPath = Join-Path $ProjectPath "apps\backend"
$ConfigPath = Join-Path $FrontendPath "assets\js\config.js"
$LoginPath = Join-Path $FrontendPath "login.html"
$PortalPath = Join-Path $FrontendPath "student-portal.html"
$AuthServicePath = Join-Path $BackendPath "src\modules\auth\services\auth.service.ts"
$PackagePath = Join-Path $BackendPath "package.json"

foreach ($RequiredPath in @(
    $ConfigPath,
    $LoginPath,
    $PortalPath,
    $AuthServicePath,
    $PackagePath
)) {
    Require-File -Path $RequiredPath
}

Write-Host ""
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host " IDMC - SECTION 13A STUDENT PORTAL ENTRY" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

# The frontend runs on port 5500 while the API runs on port 4000.
# A relative /api/v1 URL incorrectly sends authentication to port 5500.
$ExpectedApiUrl = "$BackendBaseUrl/api/v1"
$ConfigText = [System.IO.File]::ReadAllText($ConfigPath)
$ApiPattern = 'API_BASE_URL\s*:\s*["''][^"'']+["'']'
$ApiMatch = [regex]::Match($ConfigText, $ApiPattern)

if (-not $ApiMatch.Success) {
    throw "API_BASE_URL haijapatikana ndani ya $ConfigPath"
}

$ExpectedSetting = "API_BASE_URL: `"$ExpectedApiUrl`""
$ConfigChanged = $ApiMatch.Value -ne $ExpectedSetting
$BackupPath = $null

if ($ConfigChanged) {
    $Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $BackupDirectory = Join-Path $ProjectPath "repair-backups\student-portal-entry-$Stamp"
    New-Item -ItemType Directory -Path $BackupDirectory -Force | Out-Null
    $BackupPath = Join-Path $BackupDirectory "config.js"
    Copy-Item -LiteralPath $ConfigPath -Destination $BackupPath -Force

    $UpdatedConfig = [regex]::Replace(
        $ConfigText,
        $ApiPattern,
        $ExpectedSetting,
        1
    )

    Write-Utf8File -Path $ConfigPath -Content $UpdatedConfig
    Write-Host "API ORIGIN : FIXED -> $ExpectedApiUrl" -ForegroundColor Green
    Write-Host "BACKUP     : $BackupPath"
}
else {
    Write-Host "API ORIGIN : ALREADY CORRECT -> $ExpectedApiUrl" -ForegroundColor Green
}

$FinalConfig = [System.IO.File]::ReadAllText($ConfigPath)
if ($FinalConfig -notmatch [regex]::Escape($ExpectedSetting)) {
    throw "API_BASE_URL read-back verification failed."
}

$LoginText = [System.IO.File]::ReadAllText($LoginPath)
$AuthText = [System.IO.File]::ReadAllText($AuthServicePath)

foreach ($RequiredLoginMarker in @(
    'IDMCAuth.login',
    'student-portal.html',
    'Registration No., Application No. or Email'
)) {
    if (-not $LoginText.Contains($RequiredLoginMarker)) {
        throw "Login contract marker haipo: $RequiredLoginMarker"
    }
}

foreach ($RequiredAuthMarker in @(
    'findStudentByIdentifier',
    'ensureStudentAuthAccount',
    'role_code',
    'STUDENT',
    'user_id'
)) {
    if (-not $AuthText.Contains($RequiredAuthMarker)) {
        throw "Student auto-link contract marker haipo: $RequiredAuthMarker"
    }
}

Write-Host "LOGIN UI   : PASS" -ForegroundColor Green
Write-Host "AUTO-LINK  : PASS (backend contract present)" -ForegroundColor Green

$BackendOnline = $false
try {
    $Health = Invoke-RestMethod `
        -Method GET `
        -Uri "$ExpectedApiUrl/health" `
        -TimeoutSec 10 `
        -ErrorAction Stop

    if ($Health.success -eq $true) {
        $BackendOnline = $true
        Write-Host "BACKEND    : ONLINE" -ForegroundColor Green
    }
}
catch {
    Write-Host "BACKEND    : OFFLINE - start it using the command below." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "====================================================" -ForegroundColor Green
Write-Host " SECTION 13A COMPLETE - PORTAL ENTRY READY" -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Green
Write-Host "Student number      : IDMC/2026/00001"
Write-Host "Initial password    : IDMC/2026/00001"
Write-Host "Login URL           : $FrontendBaseUrl/login.html"
Write-Host "Backend online      : $BackendOnline"
Write-Host ""
Write-Host "WINDOW 1 - BACKEND:" -ForegroundColor Cyan
Write-Host "Set-Location `"$BackendPath`""
Write-Host "npm run dev"
Write-Host ""
Write-Host "WINDOW 2 - FRONTEND:" -ForegroundColor Cyan
Write-Host "Set-Location `"$ProjectPath`""
Write-Host "npx live-server apps/frontend --port=5500"
Write-Host ""
Write-Host "LOGIN:" -ForegroundColor Cyan
Write-Host "Open $FrontendBaseUrl/login.html"
Write-Host "Username: IDMC/2026/00001"
Write-Host "Password: IDMC/2026/00001"
Write-Host ""
Write-Host "Successful first login creates/links the user and assigns STUDENT role."
Write-Host "NEXT: SECTION 13B - secure student self-service data endpoints." -ForegroundColor Cyan
