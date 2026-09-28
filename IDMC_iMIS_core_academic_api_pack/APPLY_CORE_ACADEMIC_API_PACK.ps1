$ErrorActionPreference = "Stop"
$root = "C:\Users\liben\Documents\IDMC_iMIS"
$backend = Join-Path $root "apps\backend"
$pack = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "=== CORE ACADEMIC API PACK ===" -ForegroundColor Cyan

if (-not (Test-Path $backend)) {
    throw "Backend folder not found: $backend"
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backup = Join-Path $backend "backup-core-api-$stamp"
New-Item -ItemType Directory -Force $backup | Out-Null

function Backup-And-Copy([string]$relative) {
    $target = Join-Path $backend $relative
    $source = Join-Path $pack $relative

    if (-not (Test-Path $source)) {
        throw "Pack file not found: $source"
    }

    if (Test-Path $target) {
        $dest = Join-Path $backup $relative
        New-Item -ItemType Directory -Force (Split-Path $dest) | Out-Null
        Copy-Item $target $dest -Force
    }

    New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
    Copy-Item $source $target -Force
}

$coreFiles = @(
    "src\modules\admissions\admissions.routes.ts",
    "src\modules\academic-core\academic-core.routes.ts",
    "src\modules\assessment\assessment.routes.ts",
    "src\modules\examinations\examinations.routes.ts",
    "src\modules\results\results.routes.ts",
    "src\modules\graduation\graduation.routes.ts",
    "src\modules\alumni\alumni.routes.ts",
    "src\routes\core-routes.ts"
)

foreach ($file in $coreFiles) {
    Backup-And-Copy $file
}

$routesIndex = Join-Path $backend "src\routes\index.ts"
if (-not (Test-Path $routesIndex)) {
    throw "Routes index not found: $routesIndex"
}

$routesBackup = Join-Path $backup "src\routes\index.ts"
New-Item -ItemType Directory -Force (Split-Path $routesBackup) | Out-Null
Copy-Item $routesIndex $routesBackup -Force

$content = Get-Content $routesIndex -Raw

$importLine = 'import coreAcademicRoutes from "./core-routes.js";'
$mountLine = 'router.use("/", coreAcademicRoutes);'

if ($content -notmatch [regex]::Escape($importLine)) {
    $importBlock = @"
$importLine
"@
    $content = $content.TrimEnd() + "`r`n`r`n" + $importBlock.TrimEnd() + "`r`n"
}

if ($content -notmatch [regex]::Escape($mountLine)) {
    $mountBlock = @"
$mountLine
"@
    $exportPattern = '(?m)^export default router;\s*$'
    if ($content -match $exportPattern) {
        $content = [regex]::Replace($content, $exportPattern, ($mountBlock.TrimEnd() + "`r`n`r`nexport default router;"), 1)
    } else {
        $content = $content.TrimEnd() + "`r`n`r`n" + $mountBlock.TrimEnd() + "`r`nexport default router;`r`n"
    }
}

Set-Content $routesIndex $content -Encoding UTF8

$migrationsDir = Join-Path $root "supabase\migrations"
$migrationSource = Join-Path $pack "supabase\migrations\20260917250000_core_academic_api_permissions.sql"
$migrationTarget = Join-Path $migrationsDir "20260917250000_core_academic_api_permissions.sql"

if (-not (Test-Path $migrationSource)) {
    throw "Migration source not found: $migrationSource"
}

if (Test-Path $migrationTarget) {
    $existingMigrationBackup = Join-Path $backup "20260917250000_core_academic_api_permissions.sql.bak"
    Copy-Item $migrationTarget $existingMigrationBackup -Force
}

New-Item -ItemType Directory -Force $migrationsDir | Out-Null
Copy-Item $migrationSource $migrationTarget -Force

Push-Location $root
try {
    Write-Host "`n=== SUPABASE DB PUSH ===" -ForegroundColor Cyan
    supabase db push --linked
    if ($LASTEXITCODE -ne 0) { throw "supabase db push failed" }

    Push-Location $backend
    try {
        Write-Host "`n=== BACKEND TYPECHECK ===" -ForegroundColor Cyan
        npm run typecheck
        if ($LASTEXITCODE -ne 0) { throw "backend typecheck failed" }

        Write-Host "`n=== BACKEND BUILD ===" -ForegroundColor Cyan
        npm run build
        if ($LASTEXITCODE -ne 0) { throw "backend build failed" }
    }
    finally {
        Pop-Location
    }

    Write-Host "`nCORE ACADEMIC API PACK APPLIED SUCCESSFULLY." -ForegroundColor Green
    Write-Host "Backup: $backup" -ForegroundColor Yellow
}
finally {
    Pop-Location
}
