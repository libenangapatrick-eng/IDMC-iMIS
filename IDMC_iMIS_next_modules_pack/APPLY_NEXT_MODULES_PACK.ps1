$ErrorActionPreference = "Stop"

$projectRoot = "C:\Users\liben\Documents\IDMC_iMIS"
$backendRoot = Join-Path $projectRoot "apps\backend"
$packRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not (Test-Path $backendRoot)) {
    throw "Backend folder not found: $backendRoot"
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupRoot = Join-Path $backendRoot "backup-next-modules-$timestamp"
New-Item -ItemType Directory -Force $backupRoot | Out-Null

Write-Host "== Backing up central routes file =="
$existingIndex = Join-Path $backendRoot "src\routes\index.ts"
if (Test-Path $existingIndex) {
    Copy-Item $existingIndex (Join-Path $backupRoot "src-routes-index.ts") -Force
}

Write-Host "== Backing up any existing next-module route files =="
$routeTargets = @(
    "src\modules\research\research.routes.ts",
    "src\modules\communications\communications.routes.ts",
    "src\modules\reports\reports.routes.ts",
    "src\modules\system\system.routes.ts"
)
foreach ($relative in $routeTargets) {
    $src = Join-Path $backendRoot $relative
    if (Test-Path $src) {
        $dest = Join-Path $backupRoot ($relative -replace '[\\:]','_')
        Copy-Item $src $dest -Force
    }
}

Write-Host "== Copying migrations =="
$migrationDest = Join-Path $projectRoot "supabase\migrations"
New-Item -ItemType Directory -Force $migrationDest | Out-Null
Get-ChildItem (Join-Path $packRoot "supabase\migrations\*.sql") | ForEach-Object {
    Copy-Item $_.FullName (Join-Path $migrationDest $_.Name) -Force
}

Write-Host "== Copying backend route APIs =="
foreach ($relative in $routeTargets) {
    $src = Join-Path $packRoot $relative
    $dest = Join-Path $backendRoot $relative
    $destDir = Split-Path -Parent $dest
    New-Item -ItemType Directory -Force $destDir | Out-Null
    Copy-Item $src $dest -Force
}

Copy-Item (Join-Path $packRoot "src\routes\index.ts") $existingIndex -Force

Write-Host ""
Write-Host "== Current migration status =="
Push-Location $projectRoot
try {
    supabase migration list

    Write-Host ""
    Write-Host "== Pushing migrations =="
    supabase db push

    Write-Host ""
    Write-Host "== Backend typecheck =="
    Push-Location $backendRoot
    try {
        npm run typecheck
        Write-Host ""
        Write-Host "== Backend build =="
        npm run build
    }
    finally {
        Pop-Location
    }

    Write-Host ""
    Write-Host "NEXT MODULES PACK APPLIED SUCCESSFULLY."
    Write-Host "Backup: $backupRoot"
}
finally {
    Pop-Location
}
