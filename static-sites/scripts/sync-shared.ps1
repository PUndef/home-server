param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot
)

$ErrorActionPreference = "Stop"

$staticSitesRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$sharedSrc = Join-Path $staticSitesRoot "shared\site-urls.ts"
$dest = Join-Path $ProjectRoot "src\lib\site-urls.ts"

if (-not (Test-Path $sharedSrc)) {
    throw "Shared site-urls.ts not found: $sharedSrc"
}

$destDir = Split-Path $dest -Parent
if (-not (Test-Path $destDir)) {
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
}

Copy-Item $sharedSrc $dest -Force
Write-Host "Synced shared/site-urls.ts -> $dest"
