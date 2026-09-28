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
$BackupRoot = Join-Path $ProjectRoot ("repair-backups\section-14b-staff-{0}" -f $Timestamp)
$Manifest = @(
    "apps\backend\src\routes\index.ts",
    "apps\backend\src\modules\workflows\workflow.routes.ts",
    "apps\backend\src\modules\staff-workspace\staff-workspace.service.ts",
    "apps\backend\src\modules\staff-workspace\staff-workspace.controller.ts",
    "apps\backend\src\modules\staff-workspace\staff-workspace.routes.ts",
    "apps\frontend\assets\css\staff-institutional.css",
    "apps\frontend\assets\js\staff-workspace.js",
    "apps\frontend\assets\js\auth.js",
    "apps\frontend\lecturer-portal.html",
    "apps\frontend\finance-portal.html",
    "apps\frontend\registry-portal.html",
    "database\migrations\202609210029_staff_role_workspaces.sql",
    "supabase\migrations\202609210029_staff_role_workspaces.sql",
    "SECTION-14B-STAFF-PORTALS-AUDIT.md"
)

Write-Host "====================================================" -ForegroundColor DarkRed
Write-Host " SECTION 14B - STAFF ROLE PORTALS" -ForegroundColor White
Write-Host "====================================================" -ForegroundColor DarkRed

if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) { throw "Project root does not exist: $ProjectRoot" }
if (-not (Test-Path -LiteralPath $BackendRoot -PathType Container)) { throw "Backend folder does not exist: $BackendRoot" }
if (-not (Test-Path -LiteralPath $PayloadRoot -PathType Container)) { throw "Installer payload is missing: $PayloadRoot" }

Write-Section "1. PREFLIGHT"
Require-Command "node.exe"; Require-Command "npm.cmd"
if ((-not $SkipDatabase) -or $StartServers) { Require-Command "npx.cmd" }
foreach ($RelativePath in $Manifest) { if (-not (Test-Path -LiteralPath (Join-Path $PayloadRoot $RelativePath) -PathType Leaf)) { throw "Payload file is missing: $RelativePath" } }
$Section14A = Join-Path $ProjectRoot "supabase\migrations\202609210028_student_self_service_completion.sql"
if (-not (Test-Path -LiteralPath $Section14A -PathType Leaf)) { throw "Section 14A migration is missing. Complete Section 14A before installing Section 14B." }
Write-Host "Project, Section 14A dependency, payload and commands verified." -ForegroundColor Green

if (-not $SkipSourceInstall) {
    Write-Section "2. SAFE SOURCE INSTALL"
    New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
    foreach ($RelativePath in $Manifest) {
        $SourcePath=Join-Path $PayloadRoot $RelativePath; $TargetPath=Join-Path $ProjectRoot $RelativePath
        New-Item -ItemType Directory -Path (Split-Path -Parent $TargetPath) -Force | Out-Null
        if (Test-Path -LiteralPath $TargetPath -PathType Leaf) { $BackupPath=Join-Path $BackupRoot $RelativePath; New-Item -ItemType Directory -Path (Split-Path -Parent $BackupPath) -Force | Out-Null; Copy-Item -LiteralPath $TargetPath -Destination $BackupPath -Force }
        Copy-Item -LiteralPath $SourcePath -Destination $TargetPath -Force
    }
    Write-Host "Source installed. Backup: $BackupRoot" -ForegroundColor Green
} else { Write-Section "2. SOURCE INSTALL SKIPPED" }

Write-Section "3. JAVASCRIPT SYNTAX"
Invoke-Checked "node.exe" @("--check",(Join-Path $ProjectRoot "apps\frontend\assets\js\staff-workspace.js")) $ProjectRoot
Invoke-Checked "node.exe" @("--check",(Join-Path $ProjectRoot "apps\frontend\assets\js\auth.js")) $ProjectRoot
Write-Host "Staff portal JavaScript passed syntax validation." -ForegroundColor Green

Write-Section "4. BACKEND BUILD"
Invoke-Checked "npm.cmd" @("run","build") $BackendRoot
Write-Host "TypeScript backend build passed." -ForegroundColor Green

Write-Section "5. CONTRACT CHECKS"
$Checks=@(
    @{Path="apps\backend\src\routes\index.ts";Text='router.use("/staff-workspace"'},
    @{Path="apps\backend\src\modules\staff-workspace\staff-workspace.routes.ts";Text='requirePermission("portal.lecturer")'},
    @{Path="apps\frontend\assets\css\staff-institutional.css";Text="Times New Roman"},
    @{Path="apps\frontend\assets\js\auth.js";Text="registry-portal.html"},
    @{Path="supabase\migrations\202609210029_staff_role_workspaces.sql";Text="idmc_record_staff_payment"}
)
foreach($Check in $Checks){$Path=Join-Path $ProjectRoot $Check.Path;if(-not(Select-String -LiteralPath $Path -SimpleMatch $Check.Text -Quiet)){throw "Contract check failed: $($Check.Path)"}}
Write-Host "Role routing, scoped APIs, finance transaction and institutional UI verified." -ForegroundColor Green

if (-not $SkipDatabase) {
    Write-Section "6. DATABASE AND RBAC MIGRATION"
    if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot "supabase\config.toml") -PathType Leaf)) { throw "Supabase project configuration is missing." }
    Invoke-Checked "npx.cmd" @("supabase","db","push","--linked","--yes") $ProjectRoot
    Write-Host "Section 14B database migration applied." -ForegroundColor Green
} else { Write-Section "6. DATABASE MIGRATION SKIPPED"; Write-Host "Do not test staff actions until the database migration is applied." -ForegroundColor Yellow }

if ($StartServers) {
    Write-Section "7. START BACKEND AND FRONTEND"
    $EscapedBackend=$BackendRoot.Replace("'","''");$EscapedProject=$ProjectRoot.Replace("'","''")
    Start-Process powershell.exe -ArgumentList @("-NoExit","-Command","Set-Location -LiteralPath '$EscapedBackend'; npm.cmd run dev")
    Start-Process powershell.exe -ArgumentList @("-NoExit","-Command","Set-Location -LiteralPath '$EscapedProject'; npx.cmd live-server apps/frontend --port=5500")
    Write-Host "Backend and frontend start commands opened in separate windows." -ForegroundColor Green
}

Write-Host "";Write-Host "====================================================" -ForegroundColor DarkRed
Write-Host " SECTION 14B COMPLETE - STAFF PORTALS INSTALLED" -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor DarkRed
Write-Host "Lecturer : http://127.0.0.1:5500/lecturer-portal.html"
Write-Host "Finance  : http://127.0.0.1:5500/finance-portal.html"
Write-Host "Registry : http://127.0.0.1:5500/registry-portal.html"
Write-Host "Assign existing users the correct roles from the administrator Roles/User interface before login testing."
