[CmdletBinding()]
param(
    [string]$ProjectPath = $PSScriptRoot,
    [switch]$SkipDatabase,
    [switch]$NoBrowser
)

$ErrorActionPreference = "Stop"
$ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
$BackendPath = Join-Path $ProjectPath "apps\backend"
$MigrationPath = Join-Path $ProjectPath "supabase\migrations\20260926151502_regno_results_import.sql"
$StartScript = Join-Path $ProjectPath "Start-IDMC.ps1"

if (-not (Test-Path -LiteralPath $MigrationPath)) {
    throw "REGNO results migration was not found: $MigrationPath"
}

if (-not (Test-Path -LiteralPath (Join-Path $BackendPath "package.json"))) {
    throw "Backend package.json was not found: $BackendPath"
}

if (-not $SkipDatabase) {
    Write-Host "Applying pending Supabase migrations..." -ForegroundColor Cyan
    Push-Location $ProjectPath
    try {
        npx --yes supabase db push
        if ($LASTEXITCODE -ne 0) {
            throw "Supabase migration failed. Read the error above; application startup was stopped."
        }
    }
    finally {
        Pop-Location
    }
}

Write-Host "Checking and building the backend..." -ForegroundColor Cyan
Push-Location $BackendPath
try {
    npm run typecheck
    if ($LASTEXITCODE -ne 0) { throw "Backend typecheck failed." }
    npm run build
    if ($LASTEXITCODE -ne 0) { throw "Backend build failed." }
}
finally {
    Pop-Location
}

if (-not (Test-Path -LiteralPath $StartScript)) {
    throw "Start-IDMC.ps1 was not found: $StartScript"
}

Write-Host "REGNO + Results Import P0 applied successfully." -ForegroundColor Green
& $StartScript -ProjectPath $ProjectPath -NoBrowser:$NoBrowser
