[CmdletBinding()]
param(
    [string]$ProjectRoot = "C:\Users\liben\Documents\IDMC_iMIS",
    [switch]$SkipSourceInstall,
    [switch]$SkipDatabase,
    [switch]$StartServers
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Write-Section([string]$Title) {
    Write-Host ""
    Write-Host ("===== {0} =====" -f $Title) -ForegroundColor Cyan
}

function Require-Command([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found in PATH."
    }
}

function Invoke-Checked([string]$FilePath, [string[]]$Arguments, [string]$WorkingDirectory) {
    Push-Location $WorkingDirectory
    try {
        & $FilePath @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "Command failed ($LASTEXITCODE): $FilePath $($Arguments -join ' ')"
        }
    }
    finally {
        Pop-Location
    }
}

$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
$PayloadRoot = Join-Path $PSScriptRoot "payload"
$BackendRoot = Join-Path $ProjectRoot "apps\backend"
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$BackupRoot = Join-Path $ProjectRoot ("repair-backups\section-14a-deep-{0}" -f $Timestamp)

$Manifest = @(
    "apps\backend\src\utils\resourceCrud.ts",
    "apps\backend\src\modules\admissions\admissions.routes.ts",
    "apps\backend\src\modules\workflows\workflow.routes.ts",
    "apps\backend\src\modules\student-management\students\students.service.ts",
    "apps\backend\src\modules\student-management\students\student-self-service.service.ts",
    "apps\backend\src\modules\student-management\students\students.controller.ts",
    "apps\backend\src\modules\student-management\students\students.routes.ts",
    "apps\frontend\assets\css\student-institutional.css",
    "apps\frontend\assets\js\student-institutional.js",
    "apps\frontend\assets\js\applicant-live-forms.js",
    "apps\frontend\assets\js\module-contracts.js",
    "apps\frontend\assets\js\module-crud.js",
    "apps\frontend\student-portal.html",
    "apps\frontend\student-registration.html",
    "apps\frontend\student-attendance.html",
    "apps\frontend\student-results.html",
    "apps\frontend\student-timetable.html",
    "apps\frontend\student-fees.html",
    "apps\frontend\student-documents.html",
    "apps\frontend\student-notifications.html",
    "apps\frontend\student-profile.html",
    "apps\frontend\student-requests.html",
    "apps\frontend\student-accommodation.html",
    "apps\frontend\student-help.html",
    "apps\frontend\student-security.html",
    "database\migrations\202609210028_student_self_service_completion.sql",
    "supabase\migrations\202609210028_student_self_service_completion.sql",
    "SECTION-14A-DEEP-AUDIT.md"
)

Write-Host "====================================================" -ForegroundColor DarkRed
Write-Host " SECTION 14A - DEEP STUDENT PORTAL REPAIR" -ForegroundColor White
Write-Host "====================================================" -ForegroundColor DarkRed

if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) {
    throw "Project root does not exist: $ProjectRoot"
}
if (-not (Test-Path -LiteralPath $BackendRoot -PathType Container)) {
    throw "Backend folder does not exist: $BackendRoot"
}
if (-not (Test-Path -LiteralPath $PayloadRoot -PathType Container)) {
    throw "Installer payload is missing: $PayloadRoot"
}

Write-Section "1. PREFLIGHT"
Require-Command "node.exe"
Require-Command "npm.cmd"
if ((-not $SkipDatabase) -or $StartServers) { Require-Command "npx.cmd" }

foreach ($RelativePath in $Manifest) {
    $SourcePath = Join-Path $PayloadRoot $RelativePath
    if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
        throw "Payload file is missing: $RelativePath"
    }
}
Write-Host "Project, payload and required commands verified." -ForegroundColor Green

if (-not $SkipSourceInstall) {
    Write-Section "2. SAFE SOURCE INSTALL"
    New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null

    foreach ($RelativePath in $Manifest) {
        $SourcePath = Join-Path $PayloadRoot $RelativePath
        $TargetPath = Join-Path $ProjectRoot $RelativePath
        $TargetDirectory = Split-Path -Parent $TargetPath
        New-Item -ItemType Directory -Path $TargetDirectory -Force | Out-Null

        if (Test-Path -LiteralPath $TargetPath -PathType Leaf) {
            $BackupPath = Join-Path $BackupRoot $RelativePath
            New-Item -ItemType Directory -Path (Split-Path -Parent $BackupPath) -Force | Out-Null
            Copy-Item -LiteralPath $TargetPath -Destination $BackupPath -Force
        }

        Copy-Item -LiteralPath $SourcePath -Destination $TargetPath -Force
    }

    Write-Host "Source installed. Backup: $BackupRoot" -ForegroundColor Green
}
else {
    Write-Section "2. SOURCE INSTALL SKIPPED"
}

Write-Section "3. JAVASCRIPT SYNTAX"
$JavaScriptFiles = @(
    "apps\frontend\assets\js\student-institutional.js",
    "apps\frontend\assets\js\applicant-live-forms.js",
    "apps\frontend\assets\js\module-contracts.js",
    "apps\frontend\assets\js\module-crud.js"
)
foreach ($RelativePath in $JavaScriptFiles) {
    Invoke-Checked "node.exe" @("--check", (Join-Path $ProjectRoot $RelativePath)) $ProjectRoot
}
Write-Host "All modified JavaScript files passed syntax validation." -ForegroundColor Green

Write-Section "4. BACKEND BUILD"
Invoke-Checked "npm.cmd" @("run", "build") $BackendRoot
Write-Host "TypeScript backend build passed." -ForegroundColor Green

Write-Section "5. SOURCE CONTRACT CHECK"
$RequiredChecks = @(
    @{ Path = "apps\backend\src\modules\student-management\students\students.routes.ts"; Text = 'router.get("/me/portal"' },
    @{ Path = "apps\frontend\student-portal.html"; Text = "student-institutional.js" },
    @{ Path = "apps\frontend\assets\css\student-institutional.css"; Text = "Times New Roman" },
    @{ Path = "apps\frontend\assets\js\applicant-live-forms.js"; Text = "applicant-profile-photo" },
    @{ Path = "supabase\migrations\202609210028_student_self_service_completion.sql"; Text = "students.self.manage" }
)
foreach ($Check in $RequiredChecks) {
    $CheckPath = Join-Path $ProjectRoot $Check.Path
    if (-not (Select-String -LiteralPath $CheckPath -SimpleMatch $Check.Text -Quiet)) {
        throw "Source contract check failed: $($Check.Path) does not contain $($Check.Text)"
    }
}
Write-Host "Portal, RBAC, admission-photo and migration contracts verified." -ForegroundColor Green

if (-not $SkipDatabase) {
    Write-Section "6. DATABASE MIGRATION"
    $SupabaseConfig = Join-Path $ProjectRoot "supabase\config.toml"
    if (-not (Test-Path -LiteralPath $SupabaseConfig -PathType Leaf)) {
        throw "Supabase project configuration is missing: $SupabaseConfig"
    }
    Invoke-Checked "npx.cmd" @("supabase", "db", "push", "--linked", "--yes") $ProjectRoot
    Write-Host "Supabase migrations applied." -ForegroundColor Green
}
else {
    Write-Section "6. DATABASE MIGRATION SKIPPED"
    Write-Host "Run the installer later without -SkipDatabase before testing student writes." -ForegroundColor Yellow
}

if ($StartServers) {
    Write-Section "7. START BACKEND AND FRONTEND"
    $EscapedBackend = $BackendRoot.Replace("'", "''")
    $EscapedProject = $ProjectRoot.Replace("'", "''")
    Start-Process powershell.exe -ArgumentList @("-NoExit", "-Command", "Set-Location -LiteralPath '$EscapedBackend'; npm.cmd run dev")
    Start-Process powershell.exe -ArgumentList @("-NoExit", "-Command", "Set-Location -LiteralPath '$EscapedProject'; npx.cmd live-server apps/frontend --port=5500")
    Write-Host "Backend and frontend start commands opened in separate windows." -ForegroundColor Green
}

Write-Host ""
Write-Host "====================================================" -ForegroundColor DarkRed
Write-Host " SECTION 14A COMPLETE - STUDENT PORTAL INSTALLED" -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor DarkRed
Write-Host "Student portal : http://127.0.0.1:5500/student-portal.html"
Write-Host "Login page     : http://127.0.0.1:5500/login.html"
Write-Host "Audit report   : $ProjectRoot\SECTION-14A-DEEP-AUDIT.md"
Write-Host "NEXT           : verify the student portal, then build Section 14B staff role workspaces."
