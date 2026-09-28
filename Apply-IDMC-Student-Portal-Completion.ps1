[CmdletBinding()]
param(
    [string]$ProjectPath = $PSScriptRoot,
    [switch]$SkipDatabase,
    [switch]$RequireDatabase,
    [switch]$SkipE2E,
    [switch]$NoBrowser
)
$ErrorActionPreference="Stop"
$ProjectPath=(Resolve-Path -LiteralPath $ProjectPath).Path
$BackendPath=Join-Path $ProjectPath "apps\backend"
$required=@(
  "supabase\migrations\20260926151502_regno_results_import.sql",
  "supabase\migrations\20260926151503_student_portal_completion.sql",
  "apps\backend\src\modules\student-management\students\student-self-service.routes.ts",
  "apps\frontend\student-transcript.html",
  "Start-IDMC.ps1"
)
foreach($relative in $required){if(-not(Test-Path -LiteralPath (Join-Path $ProjectPath $relative))){throw "Required completion file is missing: $relative"}}

Write-Host "Running migration, route, form and frontend integration audit..." -ForegroundColor Cyan
Push-Location $BackendPath
try {
  npm run audit:write
  if($LASTEXITCODE -ne 0){throw "Integration audit failed; database deployment was stopped."}
  npm test
  if($LASTEXITCODE -ne 0){throw "Automated tests failed; database deployment was stopped."}
}
finally{Pop-Location}

if(-not $SkipDatabase){
  Write-Host "Applying all pending Supabase migrations..." -ForegroundColor Cyan
  Push-Location $ProjectPath
  try{
    $migrationOutput = @(& npx.cmd --yes supabase db push 2>&1)
    $migrationExitCode = $LASTEXITCODE
    $migrationOutput | ForEach-Object { Write-Host ([string]$_) }

    if($migrationExitCode -ne 0){
      $migrationText = [string]::Join([Environment]::NewLine, @($migrationOutput | ForEach-Object { [string]$_ }))
      $transportFailure = $migrationText -match '(?i)TransportError|Initialising login role|network|timed?\s*out|connection\s+(refused|reset)'

      if($transportFailure -and -not $RequireDatabase){
        Write-Warning "Supabase CLI transport failed before SQL execution. Source installation and local startup will continue; migrations remain pending."
        Write-Warning "Run 'npx supabase db push --debug' later after Supabase connectivity is restored, or rerun this script with -RequireDatabase to make that failure blocking."
      }
      else {
        throw "Supabase migration failed; SQL or connectivity requires attention."
      }
    }
  }
  finally{Pop-Location}
}

Write-Host "Typechecking and building backend..." -ForegroundColor Cyan
Push-Location $BackendPath
try{npm run typecheck;if($LASTEXITCODE -ne 0){throw "Backend typecheck failed."};npm run build;if($LASTEXITCODE -ne 0){throw "Backend build failed."}}
finally{Pop-Location}

Write-Host "Starting IDMC backend and frontend..." -ForegroundColor Cyan
& (Join-Path $ProjectPath "Start-IDMC.ps1") -ProjectPath $ProjectPath -NoBrowser

if(-not $SkipE2E){
  Write-Host "Running public/static E2E audit..." -ForegroundColor Cyan
  & (Join-Path $ProjectPath "Test-IDMC-Student-Portal-E2E.ps1") -ProjectPath $ProjectPath
}
Write-Host "All student portal completion phases were applied successfully." -ForegroundColor Green
if(-not $NoBrowser){Start-Process "http://127.0.0.1:5500/login/"}
