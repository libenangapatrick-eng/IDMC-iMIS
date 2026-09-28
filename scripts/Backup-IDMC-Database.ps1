[CmdletBinding()]param([string]$BackupDirectory="$env:USERPROFILE\Documents\IDMC-Backups",[int]$RetentionDays=35)
$ErrorActionPreference='Stop';$url=$env:SUPABASE_DB_URL;if(!$url){$url=$env:DATABASE_URL};if(!$url){throw 'Set SUPABASE_DB_URL or DATABASE_URL for the official database.'}
$pg=Get-Command pg_dump -ErrorAction SilentlyContinue;if(!$pg){throw 'pg_dump is required. Install PostgreSQL client tools first.'}
New-Item -ItemType Directory -Force -Path $BackupDirectory|Out-Null;$stamp=Get-Date -Format 'yyyyMMdd-HHmmss';$file=Join-Path $BackupDirectory "IDMC-$stamp.dump"
& $pg.Source --format=custom --no-owner --no-acl --file=$file $url;if($LASTEXITCODE){throw 'Database backup failed.'}
$hash=(Get-FileHash $file -Algorithm SHA256).Hash;Set-Content -LiteralPath "$file.sha256" -Value "$hash  $([IO.Path]::GetFileName($file))" -Encoding ascii
Get-ChildItem $BackupDirectory -File -Filter 'IDMC-*.dump'|Where-Object LastWriteTime -lt (Get-Date).AddDays(-$RetentionDays)|Remove-Item -Force
Write-Host "Backup complete: $file" -ForegroundColor Green;Write-Host "SHA256: $hash"
