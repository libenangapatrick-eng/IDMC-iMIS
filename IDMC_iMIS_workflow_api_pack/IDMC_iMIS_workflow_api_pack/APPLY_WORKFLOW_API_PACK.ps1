$ErrorActionPreference = 'Stop'

$projectRoot = 'C:\Users\liben\Documents\IDMC_iMIS'
$backendRoot = Join-Path $projectRoot 'apps\backend'
$packRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not (Test-Path $backendRoot)) { throw "Backend directory not found: $backendRoot" }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupRoot = Join-Path $backendRoot "backup-workflow-api-$stamp"
New-Item -ItemType Directory -Force $backupRoot | Out-Null

function Backup-IfExists([string]$path) {
    if (Test-Path $path) {
        $relative = $path.Substring($backendRoot.Length).TrimStart('\')
        $target = Join-Path $backupRoot $relative
        New-Item -ItemType Directory -Force (Split-Path $target -Parent) | Out-Null
        Copy-Item $path $target -Force
    }
}

$workflowRoute = Join-Path $backendRoot 'src\modules\workflows\workflow.routes.ts'
$indexFile = Join-Path $backendRoot 'src\routes\index.ts'
Backup-IfExists $workflowRoute
Backup-IfExists $indexFile

New-Item -ItemType Directory -Force (Split-Path $workflowRoute -Parent) | Out-Null
Copy-Item (Join-Path $packRoot 'src\modules\workflows\workflow.routes.ts') $workflowRoute -Force

$index = Get-Content $indexFile -Raw
if ($index -notmatch 'workflow\.routes\.js') {
    $index += @'

import workflowRoutes from "../modules/workflows/workflow.routes.js";
router.use("/workflows", workflowRoutes);
'@
    Set-Content $indexFile $index -Encoding UTF8
}

$migrationSource = Join-Path $packRoot 'supabase\migrations\202609180001_workflow_permissions.sql'
$migrationsDir = Join-Path $projectRoot 'supabase\migrations'
New-Item -ItemType Directory -Force $migrationsDir | Out-Null
Copy-Item $migrationSource (Join-Path $migrationsDir '202609180001_workflow_permissions.sql') -Force

Write-Host ''
Write-Host '== Workflow migration == ' -ForegroundColor Cyan
Push-Location $projectRoot
try {
    supabase db push --linked
    if ($LASTEXITCODE -ne 0) { throw 'supabase db push failed.' }
} finally { Pop-Location }

Write-Host ''
Write-Host '== Backend typecheck == ' -ForegroundColor Cyan
Push-Location $backendRoot
try {
    npm run typecheck
    if ($LASTEXITCODE -ne 0) { throw 'Backend typecheck failed.' }
    Write-Host ''
    Write-Host '== Backend build == ' -ForegroundColor Cyan
    npm run build
    if ($LASTEXITCODE -ne 0) { throw 'Backend build failed.' }
} finally { Pop-Location }

Write-Host ''
Write-Host 'WORKFLOW API PACK APPLIED SUCCESSFULLY.' -ForegroundColor Green
Write-Host "Backup: $backupRoot" -ForegroundColor Yellow
