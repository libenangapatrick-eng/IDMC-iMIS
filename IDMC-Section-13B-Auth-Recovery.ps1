#Requires -Version 5.1

[CmdletBinding()]
param(
    [string]$ProjectPath = (Get-Location).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Require-File {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required file haipo: $Path"
    }
}

function Test-AuthContract {
    param([Parameter(Mandatory = $true)][string]$Path)

    $Text = [System.IO.File]::ReadAllText($Path)
    $Markers = @(
        'resolveStudentLoginEmail',
        '.ilike("username", value)',
        '.ilike("user_number", value)',
        'supabase.auth.signInWithPassword'
    )

    foreach ($Marker in $Markers) {
        if (-not $Text.Contains($Marker)) {
            return $false
        }
    }

    return $true
}

$ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)
$BackendPath = Join-Path $ProjectPath "apps\backend"
$TargetPath = Join-Path $BackendPath "src\modules\auth\services\auth.service.ts"
$StudentLoginPath = Join-Path $BackendPath "src\modules\auth\services\student-login.service.ts"
$KnownGoodPath = Join-Path $ProjectPath "repair-backups\student-staff-login-20260920-164334\auth.service.ts"
$PackagePath = Join-Path $BackendPath "package.json"

foreach ($RequiredPath in @(
    $TargetPath,
    $StudentLoginPath,
    $KnownGoodPath,
    $PackagePath
)) {
    Require-File -Path $RequiredPath
}

if (-not (Test-AuthContract -Path $KnownGoodPath)) {
    throw "Known-good auth backup failed contract validation: $KnownGoodPath"
}

Write-Host ""
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host " IDMC - SECTION 13B AUTHENTICATION RECOVERY" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

$AlreadyRepaired = Test-AuthContract -Path $TargetPath
$RollbackPath = $null

if ($AlreadyRepaired) {
    Write-Host "AUTH RESOLVER : ALREADY REPAIRED" -ForegroundColor Green
}
else {
    $Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $BackupDirectory = Join-Path $ProjectPath "repair-backups\auth-recovery-$Stamp"
    New-Item -ItemType Directory -Path $BackupDirectory -Force | Out-Null

    $RollbackPath = Join-Path $BackupDirectory "auth.service.ts"
    Copy-Item -LiteralPath $TargetPath -Destination $RollbackPath -Force
    Copy-Item -LiteralPath $KnownGoodPath -Destination $TargetPath -Force

    if (-not (Test-AuthContract -Path $TargetPath)) {
        Copy-Item -LiteralPath $RollbackPath -Destination $TargetPath -Force
        throw "Auth resolver read-back verification failed; original file was restored."
    }

    Write-Host "AUTH RESOLVER : RESTORED" -ForegroundColor Green
    Write-Host "SUPPORTED     : email / username / user number / student number / application number" -ForegroundColor Green
    Write-Host "BACKUP       : $RollbackPath"
}

$BuildPassed = $false

Push-Location $BackendPath
try {
    Write-Host ""
    Write-Host "===== TYPESCRIPT TYPECHECK =====" -ForegroundColor Cyan
    & npm.cmd run typecheck
    if ($LASTEXITCODE -ne 0) {
        throw "TypeScript typecheck failed with exit code $LASTEXITCODE."
    }

    Write-Host ""
    Write-Host "===== PRODUCTION BUILD =====" -ForegroundColor Cyan
    & npm.cmd run build
    if ($LASTEXITCODE -ne 0) {
        throw "Production build failed with exit code $LASTEXITCODE."
    }

    $BuildPassed = $true
}
catch {
    $Failure = $_

    if ($null -ne $RollbackPath -and (Test-Path -LiteralPath $RollbackPath -PathType Leaf)) {
        Copy-Item -LiteralPath $RollbackPath -Destination $TargetPath -Force
        Write-Host "BUILD FAILED - ORIGINAL AUTH SERVICE RESTORED" -ForegroundColor Red

        try {
            & npm.cmd run build | Out-Host
        }
        catch {
            Write-Host "Original source was restored, but rebuilding the old dist also failed." -ForegroundColor Yellow
        }
    }

    throw $Failure
}
finally {
    Pop-Location
}

if (-not $BuildPassed) {
    throw "Authentication recovery did not complete."
}

Write-Host ""
Write-Host "====================================================" -ForegroundColor Green
Write-Host " SECTION 13B COMPLETE - AUTHENTICATION RECOVERED" -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Green
Write-Host "Student login       : registration/application number"
Write-Host "Staff login         : email, username, or user number"
Write-Host "Student             : IDMC/2026/00001"
Write-Host "Initial password    : IDMC/2026/00001"
Write-Host "Data deleted        : NO"
Write-Host "Passwords reset     : NO"
Write-Host "Typecheck           : PASS"
Write-Host "Production build    : PASS"
Write-Host ""
Write-Host "If npm run dev is already open, wait for its automatic restart." -ForegroundColor Cyan
Write-Host "Then press Ctrl+F5 on the login page and sign in again."
Write-Host "NEXT: SECTION 13C - linked student read-back and secure self-service APIs." -ForegroundColor Cyan
