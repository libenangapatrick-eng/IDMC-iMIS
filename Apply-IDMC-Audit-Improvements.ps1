[CmdletBinding()]
param(
    [string]$ProjectPath = "C:\Users\liben\Documents\IDMC_iMIS",
    [switch]$NoBrowser
)
$ErrorActionPreference = "Stop"
$ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
$MigrationDir = Join-Path $ProjectPath "supabase\migrations"
$RepairScript = Join-Path $ProjectPath "Repair-IDMC-Migration-Version-Collision.ps1"
$CompletionScript = Join-Path $ProjectPath "Apply-IDMC-Student-Portal-Completion.ps1"

foreach ($required in @($MigrationDir,$RepairScript,$CompletionScript,(Join-Path $ProjectPath "scripts\audit-integration.mjs"))) {
    if (-not (Test-Path -LiteralPath $required)) { throw "Required improvement component is missing: $required" }
}

$legacyMigrationNames = @(
    "202609260001_student_engagement_services.sql",
    "202609260001_regno_results_import.sql",
    "202609260002_student_portal_completion.sql"
)
$requiresRepair = $legacyMigrationNames | Where-Object { Test-Path -LiteralPath (Join-Path $MigrationDir $_) }

$versionDuplicates = Get-ChildItem -LiteralPath $MigrationDir -File -Filter "*.sql" |
    Group-Object { ($_.BaseName -split "_")[0] } |
    Where-Object { $_.Count -gt 1 }

if ($requiresRepair -or $versionDuplicates) {
    Write-Host "Legacy/duplicate migration versions detected; running safe collision repair first..." -ForegroundColor Yellow
    & $RepairScript -ProjectPath $ProjectPath -NoBrowser -SkipContinuation
    & $CompletionScript -ProjectPath $ProjectPath -SkipDatabase -NoBrowser:$NoBrowser
}
else {
    & $CompletionScript -ProjectPath $ProjectPath -NoBrowser:$NoBrowser
}

Write-Host "IDMC audit improvements completed successfully." -ForegroundColor Green
