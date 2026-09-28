[CmdletBinding()]
param(
    [string]$ProjectPath = $PSScriptRoot,
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) ("IDMC_iMIS_SAFE_RELEASE_{0}.zip" -f (Get-Date -Format "yyyyMMdd-HHmmss")))
)
$ErrorActionPreference = "Stop"
$ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("idmc-release-" + [guid]::NewGuid().ToString("N"))
$StageProject = Join-Path $TempRoot "IDMC_iMIS"

try {
    Push-Location (Join-Path $ProjectPath "apps\backend")
    try {
        npm run audit:write
        if ($LASTEXITCODE -ne 0) { throw "Integration audit failed." }
        npm run test:ci
        if ($LASTEXITCODE -ne 0) { throw "Automated tests failed." }
        npm run build
        if ($LASTEXITCODE -ne 0) { throw "Backend build failed." }
    }
    finally { Pop-Location }

    New-Item -ItemType Directory -Path $StageProject -Force | Out-Null
    robocopy $ProjectPath $StageProject /E /NFL /NDL /NJH /NJS /NP `
        /XD node_modules dist .git repair-backups storage releases `
        /XF .env .env.local .env.production "*.zip" | Out-Null
    if ($LASTEXITCODE -gt 7) { throw "Unable to stage the safe release (robocopy exit $LASTEXITCODE)." }

    if (Test-Path -LiteralPath $OutputPath) { throw "Output already exists: $OutputPath" }
    Compress-Archive -LiteralPath $StageProject -DestinationPath $OutputPath -CompressionLevel Optimal

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($OutputPath)
    try {
        $unsafe = @($archive.Entries | Where-Object {
            (($_.FullName -match '(^|/|\\)\.env($|\.)') -and ($_.FullName -notmatch '\.env\.example$')) -or
            $_.FullName -match '(^|/|\\)(node_modules|dist|releases)(/|\\)'
        })
        if ($unsafe.Count) { throw "Unsafe file entered release: $($unsafe[0].FullName)" }
    }
    finally { $archive.Dispose() }

    $hash = (Get-FileHash -LiteralPath $OutputPath -Algorithm SHA256).Hash
    Write-Host "Safe release created:" -ForegroundColor Green
    Write-Host $OutputPath -ForegroundColor Cyan
    Write-Host "SHA256: $hash" -ForegroundColor Green
}
finally {
    if (Test-Path -LiteralPath $TempRoot) { Remove-Item -LiteralPath $TempRoot -Recurse -Force }
}
