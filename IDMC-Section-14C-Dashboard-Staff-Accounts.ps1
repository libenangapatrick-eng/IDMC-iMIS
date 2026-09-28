[CmdletBinding()]
param(
    [string]$ProjectRoot = "C:\Users\liben\Documents\IDMC_iMIS",
    [switch]$SkipSourceInstall,
    [switch]$SkipDatabase,
    [switch]$StartServers
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Write-Section([string]$Title) { Write-Host ""; Write-Host ("===== {0} =====" -f $Title) -ForegroundColor Cyan }
function Require-Command([string]$Name) { if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) { throw "Required command '$Name' was not found in PATH." } }
function Invoke-Checked([string]$FilePath,[string[]]$Arguments,[string]$WorkingDirectory) {
    Push-Location $WorkingDirectory
    try { & $FilePath @Arguments; if ($LASTEXITCODE -ne 0) { throw "Command failed ($LASTEXITCODE): $FilePath $($Arguments -join ' ')" } }
    finally { Pop-Location }
}

$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
$PayloadRoot = Join-Path $PSScriptRoot "payload"
$BackendRoot = Join-Path $ProjectRoot "apps\backend"
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$BackupRoot = Join-Path $ProjectRoot ("repair-backups\section-14c-staff-accounts-{0}" -f $Timestamp)
$Manifest = @(
    "apps\backend\src\modules\users\services\users.service.ts",
    "apps\backend\src\modules\staff-workspace\staff-workspace.service.ts",
    "apps\backend\src\modules\staff-workspace\staff-workspace.controller.ts",
    "apps\backend\src\modules\staff-workspace\staff-workspace.routes.ts",
    "apps\frontend\dashboard.html",
    "apps\frontend\staff-accounts.html",
    "apps\frontend\assets\js\staff-account-admin.js",
    "database\migrations\202609210030_staff_account_provisioning.sql",
    "supabase\migrations\202609210030_staff_account_provisioning.sql",
    "SECTION-14C-DASHBOARD-STAFF-ACCOUNTS.md"
)

Write-Host "====================================================" -ForegroundColor DarkRed
Write-Host " SECTION 14C - DASHBOARD / REAL STAFF ACCOUNTS" -ForegroundColor White
Write-Host "====================================================" -ForegroundColor DarkRed

if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) { throw "Project root does not exist: $ProjectRoot" }
if (-not (Test-Path -LiteralPath $BackendRoot -PathType Container)) { throw "Backend folder does not exist: $BackendRoot" }
if (-not (Test-Path -LiteralPath $PayloadRoot -PathType Container)) { throw "Installer payload is missing: $PayloadRoot" }

Write-Section "1. PREFLIGHT"
Require-Command "node.exe"; Require-Command "npm.cmd"
if ((-not $SkipDatabase) -or $StartServers) { Require-Command "npx.cmd" }
foreach ($RelativePath in $Manifest) {
    if (-not (Test-Path -LiteralPath (Join-Path $PayloadRoot $RelativePath) -PathType Leaf)) { throw "Payload file is missing: $RelativePath" }
}
$Section14B = Join-Path $ProjectRoot "supabase\migrations\202609210029_staff_role_workspaces.sql"
if (-not (Test-Path -LiteralPath $Section14B -PathType Leaf)) { throw "Section 14B migration is missing. Install Section 14B first." }
Write-Host "Project, Section 14B dependency, payload and commands verified." -ForegroundColor Green

if (-not $SkipSourceInstall) {
    Write-Section "2. SAFE SOURCE INSTALL"
    New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
    foreach ($RelativePath in $Manifest) {
        $SourcePath = Join-Path $PayloadRoot $RelativePath
        $TargetPath = Join-Path $ProjectRoot $RelativePath
        New-Item -ItemType Directory -Path (Split-Path -Parent $TargetPath) -Force | Out-Null
        if (Test-Path -LiteralPath $TargetPath -PathType Leaf) {
            $BackupPath = Join-Path $BackupRoot $RelativePath
            New-Item -ItemType Directory -Path (Split-Path -Parent $BackupPath) -Force | Out-Null
            Copy-Item -LiteralPath $TargetPath -Destination $BackupPath -Force
        }
        Copy-Item -LiteralPath $SourcePath -Destination $TargetPath -Force
    }
    Write-Host "Source installed. Backup: $BackupRoot" -ForegroundColor Green
} else { Write-Section "2. SOURCE INSTALL SKIPPED" }

Write-Section "3. FRONTEND SYNTAX"
Invoke-Checked "node.exe" @("--check",(Join-Path $ProjectRoot "apps\frontend\assets\js\staff-account-admin.js")) $ProjectRoot
Invoke-Checked "node.exe" @("--check",(Join-Path $ProjectRoot "apps\frontend\assets\js\staff-workspace.js")) $ProjectRoot
Write-Host "Staff administration and portal JavaScript passed syntax validation." -ForegroundColor Green

Write-Section "4. BACKEND BUILD"
Invoke-Checked "npm.cmd" @("run","build") $BackendRoot
Write-Host "TypeScript backend build passed." -ForegroundColor Green

Write-Section "5. SECURITY CONTRACT CHECKS"
$Checks = @(
    @{Path="apps\frontend\dashboard.html";Text='data-permission="portal.lecturer"'},
    @{Path="apps\frontend\dashboard.html";Text='data-permission="portal.finance"'},
    @{Path="apps\frontend\dashboard.html";Text='data-permission="portal.registry"'},
    @{Path="apps\frontend\dashboard.html";Text='data-permission="staff.accounts.manage"'},
    @{Path="apps\backend\src\modules\staff-workspace\staff-workspace.routes.ts";Text='requirePermission("staff.accounts.manage")'},
    @{Path="apps\backend\src\modules\staff-workspace\staff-workspace.service.ts";Text='identity.staff?.institution_id'},
    @{Path="supabase\migrations\202609210030_staff_account_provisioning.sql";Text="staff.accounts.manage"}
)
foreach ($Check in $Checks) {
    $Path = Join-Path $ProjectRoot $Check.Path
    if (-not (Select-String -LiteralPath $Path -SimpleMatch $Check.Text -Quiet)) { throw "Contract check failed: $($Check.Path)" }
}
Write-Host "Dashboard RBAC, staff provisioning permission and institution scoping verified." -ForegroundColor Green

if (-not $SkipDatabase) {
    Write-Section "6. DATABASE AND RBAC MIGRATION"
    if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot "supabase\config.toml") -PathType Leaf)) { throw "Supabase project configuration is missing." }
    Invoke-Checked "npx.cmd" @("supabase","db","push","--linked","--yes") $ProjectRoot
    Write-Host "Section 14C permission migration applied." -ForegroundColor Green
} else { Write-Section "6. DATABASE MIGRATION SKIPPED"; Write-Host "Do not provision staff accounts until the migration is applied." -ForegroundColor Yellow }

if ($StartServers) {
    Write-Section "7. START BACKEND AND FRONTEND"
    $EscapedBackend = $BackendRoot.Replace("'","''")
    $EscapedProject = $ProjectRoot.Replace("'","''")
    Start-Process powershell.exe -ArgumentList @("-NoExit","-Command","Set-Location -LiteralPath '$EscapedBackend'; npm.cmd run dev")
    Start-Process powershell.exe -ArgumentList @("-NoExit","-Command","Set-Location -LiteralPath '$EscapedProject'; npx.cmd live-server apps/frontend --port=5500")
    Write-Host "Backend and frontend start commands opened in separate windows." -ForegroundColor Green
}

Write-Host ""; Write-Host "====================================================" -ForegroundColor DarkRed
Write-Host " SECTION 14C COMPLETE - DASHBOARD AND STAFF ACCOUNTS" -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor DarkRed
Write-Host "Dashboard      : http://127.0.0.1:5500/dashboard.html"
Write-Host "Staff Accounts : http://127.0.0.1:5500/staff-accounts.html"
Write-Host "Use only verified staff identity and role information."
