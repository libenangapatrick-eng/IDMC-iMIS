[CmdletBinding()]
param(
    [string]$ProjectPath = "C:\Users\liben\Documents\IDMC_iMIS",
    [switch]$NoBrowser,
    [switch]$SkipContinuation
)

$ErrorActionPreference = "Stop"
$ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
$MigrationDir = Join-Path $ProjectPath "supabase\migrations"
$BackupDir = Join-Path $ProjectPath "repair-backups\migration-version-collision"
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

if (-not (Test-Path -LiteralPath $MigrationDir)) {
    throw "Supabase migrations folder was not found: $MigrationDir"
}

function Move-MigrationSafely {
    param(
        [Parameter(Mandatory=$true)][string]$OldName,
        [Parameter(Mandatory=$true)][string]$NewName
    )

    $source = Join-Path $MigrationDir $OldName
    $destination = Join-Path $MigrationDir $NewName

    if (-not (Test-Path -LiteralPath $source)) {
        Write-Host "Not present (already repaired or not installed): $OldName" -ForegroundColor DarkGray
        return
    }

    if (Test-Path -LiteralPath $destination) {
        $sourceHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
        $destinationHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
        if ($sourceHash -ne $destinationHash) {
            throw "Both old and new migration files exist with different content: $OldName / $NewName"
        }
        if (-not (Test-Path -LiteralPath $BackupDir)) {
            New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
        }
        $backup = Join-Path $BackupDir $OldName
        if (-not (Test-Path -LiteralPath $backup)) {
            Move-Item -LiteralPath $source -Destination $backup
        }
        else {
            $backupHash = (Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash
            if ($backupHash -ne $sourceHash) {
                throw "Existing backup differs from the duplicate migration: $backup"
            }
            Remove-Item -LiteralPath $source
        }
        Write-Host "Archived identical old duplicate: $OldName" -ForegroundColor Yellow
        return
    }

    Move-Item -LiteralPath $source -Destination $destination
    Write-Host "Renamed $OldName -> $NewName" -ForegroundColor Green
}

$knownOldNames = @(
    "202609260001_student_engagement_services.sql",
    "202609260001_regno_results_import.sql",
    "202609260002_student_portal_completion.sql",
    "202609260001_migration_history_marker.sql"
)

$unknown = @(
    Get-ChildItem -LiteralPath $MigrationDir -File |
        Where-Object {
            $_.Name -like "202609260001_*.sql" -and
            $_.Name -notin $knownOldNames
        }
)

if ($unknown.Count -gt 0) {
    throw "Unknown migration also uses version 202609260001: $($unknown.Name -join ', '). Rename it deliberately before continuing."
}

# Re-apply both real migrations under unique versions. Version 202609260001
# remains only as a local history marker because the failed push already wrote
# that version to supabase_migrations.schema_migrations.
Move-MigrationSafely `
    -OldName "202609260001_student_engagement_services.sql" `
    -NewName "20260926151501_student_engagement_services.sql"

Move-MigrationSafely `
    -OldName "202609260001_regno_results_import.sql" `
    -NewName "20260926151502_regno_results_import.sql"

Move-MigrationSafely `
    -OldName "202609260002_student_portal_completion.sql" `
    -NewName "20260926151503_student_portal_completion.sql"

$marker = Join-Path $MigrationDir "202609260001_migration_history_marker.sql"
if (-not (Test-Path -LiteralPath $marker)) {
    $markerText = @"
-- Migration history marker.
-- Version 202609260001 was recorded remotely during the earlier collision.
-- The actual migrations were moved to unique versions 20260926151501+
-- so each real migration is applied and tracked independently.
"@
    [System.IO.File]::WriteAllText($marker, $markerText, $Utf8NoBom)
    Write-Host "Created migration history marker: 202609260001" -ForegroundColor Green
}

$referenceFiles = @(
    (Join-Path $ProjectPath "Apply-IDMC-REGNO-Results-P0.ps1"),
    (Join-Path $ProjectPath "Apply-IDMC-Student-Portal-Completion.ps1"),
    (Join-Path $ProjectPath "Test-IDMC-Student-Portal-E2E.ps1")
)

foreach ($file in $referenceFiles) {
    if (-not (Test-Path -LiteralPath $file)) { continue }
    $content = [System.IO.File]::ReadAllText($file)
    $updated = $content.Replace(
        "202609260001_regno_results_import.sql",
        "20260926151502_regno_results_import.sql"
    ).Replace(
        "202609260002_student_portal_completion.sql",
        "20260926151503_student_portal_completion.sql"
    )
    if ($updated -ne $content) {
        [System.IO.File]::WriteAllText($file, $updated, $Utf8NoBom)
        Write-Host "Updated migration references in $([System.IO.Path]::GetFileName($file))" -ForegroundColor Green
    }
}

$duplicates = Get-ChildItem -LiteralPath $MigrationDir -File |
    Group-Object { ($_.BaseName -split "_")[0] } |
    Where-Object { $_.Count -gt 1 }

if ($duplicates) {
    $detail = $duplicates | ForEach-Object { "$($_.Name): $($_.Group.Name -join ', ')" }
    throw "Duplicate Supabase migration versions still exist: $($detail -join '; ')"
}

Write-Host "Migration versions are now unique. Applying migrations..." -ForegroundColor Cyan
Push-Location $ProjectPath
try {
    npx --yes supabase db push
    if ($LASTEXITCODE -ne 0) {
        throw "Supabase migration push still failed. Do not use migration repair --status applied. Send the new error output for review."
    }
}
finally {
    Pop-Location
}

$applyScript = Join-Path $ProjectPath "Apply-IDMC-Student-Portal-Completion.ps1"
if (-not (Test-Path -LiteralPath $applyScript)) {
    throw "Completion installer was not found: $applyScript"
}

Write-Host "Database migrations succeeded. Continuing build, restart and E2E audit..." -ForegroundColor Cyan
if ($SkipContinuation) {
    Write-Host "Migration collision repair completed." -ForegroundColor Green
    return
}
& $applyScript -ProjectPath $ProjectPath -SkipDatabase -NoBrowser:$NoBrowser
