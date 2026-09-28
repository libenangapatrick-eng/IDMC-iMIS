[CmdletBinding()]
param(
    [string]$ProjectRoot = (Get-Location).Path,
    [switch]$SkipDatabase,
    [Alias("StartServers")][switch]$RestartServers,
    [switch]$OpenBrowser
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Step([string]$Text) { Write-Host "`n===== $Text =====" -ForegroundColor Cyan }
function Executable([string[]]$Names) { foreach($Name in $Names){$Item=Get-Command $Name -ErrorAction SilentlyContinue;if($Item){return $Item.Source}};throw "Executable not found: $($Names -join ', ')" }
function Wait-Url([string]$Url,[int]$Seconds=35){$End=(Get-Date).AddSeconds($Seconds);do{try{$Result=Invoke-WebRequest $Url -UseBasicParsing -TimeoutSec 3;if($Result.StatusCode -ge 200){return}}catch{Start-Sleep -Milliseconds 750}}while((Get-Date) -lt $End);throw "Service did not start: $Url"}
function Stop-NodePort([int]$Port){foreach($Connection in @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)){$Process=Get-CimInstance Win32_Process -Filter "ProcessId=$($Connection.OwningProcess)" -ErrorAction SilentlyContinue;if(-not $Process){continue};if([string]$Process.Name -notmatch '^node(\.exe)?$'){throw "Port $Port is occupied by non-Node process $($Process.Name), PID $($Process.ProcessId)."};Stop-Process -Id $Process.ProcessId -Force;Write-Host "Stopped Node PID $($Process.ProcessId) on port $Port."}}

$ProjectRoot=[IO.Path]::GetFullPath($ProjectRoot)
$Backend=Join-Path $ProjectRoot "apps\backend"
$Frontend=Join-Path $ProjectRoot "apps\frontend"
$Payload=Join-Path $PSScriptRoot "payload"
if(-not(Test-Path(Join-Path $Backend "package.json"))){throw "ProjectRoot is invalid: $ProjectRoot"}
if(-not(Test-Path $Payload)){throw "Payload folder is missing beside the Section 16B script."}
$Node=Executable @("node.exe","node");$Npm=Executable @("npm.cmd","npm");$Npx=Executable @("npx.cmd","npx")
$Stamp=Get-Date -Format "yyyyMMdd-HHmmss";$Backup=Join-Path $ProjectRoot "repair-backups\section-16B-$Stamp";$Logs=Join-Path $ProjectRoot "runtime-logs"

Write-Host "====================================================" -ForegroundColor DarkRed
Write-Host " SECTION 16B - MISSING ADMIN MODULES / DATABASE" -ForegroundColor DarkRed
Write-Host "====================================================" -ForegroundColor DarkRed

Step "1. VALIDATE PAYLOAD AND BACK UP"
$Files=@(Get-ChildItem $Payload -Recurse -File);if(-not $Files.Count){throw "Payload is empty."}
foreach($File in $Files){$Relative=$File.FullName.Substring($Payload.Length).TrimStart([char]'\',[char]'/');$Target=Join-Path $ProjectRoot $Relative;if(Test-Path $Target){$Copy=Join-Path $Backup $Relative;New-Item (Split-Path $Copy) -ItemType Directory -Force|Out-Null;Copy-Item $Target $Copy -Force}}
Write-Host "Backup: $Backup"

Step "2. INSTALL CUMULATIVE SECTION 16A + 16B SOURCE"
foreach($File in $Files){$Relative=$File.FullName.Substring($Payload.Length).TrimStart([char]'\',[char]'/');$Target=Join-Path $ProjectRoot $Relative;New-Item (Split-Path $Target) -ItemType Directory -Force|Out-Null;Copy-Item $File.FullName $Target -Force}
Write-Host "Installed $($Files.Count) verified files."

Step "3. FRONTEND AND DASHBOARD CONTRACT CHECK"
foreach($File in @("assets\js\idmc-resource-page.js","assets\js\student-placements.js","assets\js\applicant-live-forms.js","assets\js\auth.js")){& $Node --check (Join-Path $Frontend $File);if($LASTEXITCODE -ne 0){throw "JavaScript check failed: $File"}}
$Dashboard=Get-Content (Join-Path $Frontend "assets\js\dashboard.js") -Raw
$Pages=[regex]::Matches($Dashboard,'page:\s*["'']([^"'']+\.html)["'']')|ForEach-Object{$_.Groups[1].Value}|Sort-Object -Unique
$Missing=@($Pages|Where-Object{-not(Test-Path(Join-Path $Frontend $_))})
if($Missing.Count){throw "Dashboard pages missing: $($Missing -join ', ')"}
Write-Host "Dashboard pages verified: $($Pages.Count)/$($Pages.Count)."

Step "4. BACKEND TYPESCRIPT BUILD"
Push-Location $Backend;try{& $Npm run build;if($LASTEXITCODE -ne 0){throw "Backend build failed."}}finally{Pop-Location}

Step "5. APPLY DATABASE TABLES AND PERMISSIONS"
if($SkipDatabase){Write-Warning "Database migration skipped. Payroll, Clinical and Field pages require another run without -SkipDatabase."}
else{Push-Location $ProjectRoot;try{& $Npx supabase db push;if($LASTEXITCODE -ne 0){throw "Supabase migration failed. The backup remains at $Backup"}}finally{Pop-Location}}

if($RestartServers){
  Step "6. RESTART AND HEALTH CHECK"
  Stop-NodePort 4000;Stop-NodePort 5500;New-Item $Logs -ItemType Directory -Force|Out-Null
  Start-Process $Npm -ArgumentList @("run","start") -WorkingDirectory $Backend -RedirectStandardOutput (Join-Path $Logs "backend.out.log") -RedirectStandardError (Join-Path $Logs "backend.err.log") -WindowStyle Hidden
  Start-Process $Npx -ArgumentList @("live-server","apps/frontend","--port=5500","--no-browser") -WorkingDirectory $ProjectRoot -RedirectStandardOutput (Join-Path $Logs "frontend.out.log") -RedirectStandardError (Join-Path $Logs "frontend.err.log") -WindowStyle Hidden
  Wait-Url "http://127.0.0.1:4000/api/v1/health";Wait-Url "http://127.0.0.1:5500/login.html";Write-Host "Backend and frontend are ready." -ForegroundColor Green
}
if($OpenBrowser){if(-not $RestartServers){Wait-Url "http://127.0.0.1:5500/login.html" 8};Start-Process "http://127.0.0.1:5500/dashboard.html"}

Step "SECTION 16B COMPLETE"
Write-Host "Dashboard  : http://127.0.0.1:5500/dashboard.html"
Write-Host "Payroll    : http://127.0.0.1:5500/payroll.html"
Write-Host "Clinical   : http://127.0.0.1:5500/clinical-placement.html"
Write-Host "Field      : http://127.0.0.1:5500/field-practical.html"
Write-Host "Student    : http://127.0.0.1:5500/student-placements.html"
Write-Host "Backup     : $Backup"
