[CmdletBinding()]param([string]$ProjectPath=(Get-Location).Path,[switch]$SkipLiveChecks)
$ErrorActionPreference='Stop'; $ProjectPath=(Resolve-Path $ProjectPath).Path
function Pass($m){Write-Host "[PASS] $m" -ForegroundColor Green}; function Fail($m){throw "[FAIL] $m"}
Write-Host "`nIDMC iMIS PRODUCTION READINESS" -ForegroundColor DarkRed
$backend=Join-Path $ProjectPath 'apps\backend'; $frontend=Join-Path $ProjectPath 'apps\frontend'; $migrations=Join-Path $ProjectPath 'supabase\migrations'
foreach($p in @($backend,$frontend,$migrations)){if(!(Test-Path $p)){Fail "Missing $p"}}
$versions=Get-ChildItem $migrations -File -Filter '*.sql'|ForEach-Object{$_.BaseName.Split('_')[0]};$dupes=$versions|Group-Object|Where-Object Count -gt 1
if($dupes){Fail "Duplicate migration versions: $($dupes.Name -join ', ')"};Pass 'Migration versions are unique'
$envFile=Join-Path $backend '.env';if(!(Test-Path $envFile)){Fail 'apps/backend/.env is missing'}
$envText=Get-Content $envFile -Raw;foreach($name in @('SUPABASE_URL','SUPABASE_SECRET_KEY')){if($envText-notmatch "(?m)^$name=\S+"){Fail "$name is missing"}};Pass 'Required environment names are configured (values not displayed)'
Push-Location $backend;try{& npm run typecheck;if($LASTEXITCODE){Fail 'Typecheck failed'};& npm test;if($LASTEXITCODE){Fail 'Regression tests failed'}}finally{Pop-Location};Pass 'Backend build and regression tests'
$bad=@();Get-ChildItem (Join-Path $frontend 'assets\js') -File -Filter '*.js'|ForEach-Object{& node --check $_.FullName 2>$null;if($LASTEXITCODE){$bad+=$_.Name}};if($bad){Fail "Frontend syntax: $($bad -join ', ')"};Pass 'Frontend JavaScript syntax'
$dash=Get-Content (Join-Path $frontend 'assets\js\dashboard.js') -Raw;$pages=[regex]::Matches($dash,'page:\s*"([^"]+\.html)"')|ForEach-Object{$_.Groups[1].Value}|Sort-Object -Unique;$missing=$pages|Where-Object{!(Test-Path (Join-Path $frontend $_))};if($missing){Fail "Dashboard pages missing: $($missing -join ', ')"};Pass 'Dashboard links resolve to real pages'
if(!$SkipLiveChecks){$h=Invoke-RestMethod 'http://127.0.0.1:4000/api/v1/health' -TimeoutSec 10;if($h.success-ne$true){Fail 'Backend health failed'};$f=Invoke-WebRequest 'http://127.0.0.1:5500/login.html' -UseBasicParsing -TimeoutSec 10;if($f.StatusCode-ne200){Fail 'Frontend health failed'};Pass 'Live backend and frontend health'}
Write-Host "`nREADINESS CHECKS COMPLETE" -ForegroundColor Green
