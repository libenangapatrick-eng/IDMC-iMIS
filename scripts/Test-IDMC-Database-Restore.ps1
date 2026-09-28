[CmdletBinding()]param([Parameter(Mandatory)][string]$BackupFile)
$ErrorActionPreference='Stop';if(!(Test-Path $BackupFile)){throw 'Backup file was not found.'};$pg=Get-Command pg_restore -ErrorAction SilentlyContinue;if(!$pg){throw 'pg_restore is required.'}
& $pg.Source --list $BackupFile|Out-Null;if($LASTEXITCODE){throw 'Backup archive validation failed.'};Write-Host '[PASS] Backup archive is readable.' -ForegroundColor Green
$test=$env:IDMC_RESTORE_TEST_DATABASE_URL;if(!$test){Write-Host 'Archive validation complete. Set IDMC_RESTORE_TEST_DATABASE_URL to run an isolated restore test.' -ForegroundColor Yellow;exit 0}
$production=$env:SUPABASE_DB_URL;if(!$production){$production=$env:DATABASE_URL};if($production-and$test-eq$production){throw 'Restore test database must never equal the production database.'}
& $pg.Source --clean --if-exists --no-owner --no-acl --dbname=$test $BackupFile;if($LASTEXITCODE){throw 'Isolated restore test failed.'};Write-Host '[PASS] Isolated restore test completed.' -ForegroundColor Green
