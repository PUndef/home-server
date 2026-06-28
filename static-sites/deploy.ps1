param(
    [ValidateSet("all", "warframe", "requiem", "wf-farm", "wf-twitch")]
    [string]$App = "all",
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot

$apps = if ($App -eq "all") {
    @("warframe", "requiem", "wf-farm", "wf-twitch")
} else {
    @($App)
}

foreach ($name in $apps) {
    $script = Join-Path $Root "$name\scripts\deploy.ps1"
    if (-not (Test-Path $script)) {
        throw "Deploy script not found: $script"
    }

    Write-Host "=== Deploy $name ===" -ForegroundColor Cyan
    if ($SkipBuild) {
        & $script -SkipBuild
    } else {
        & $script
    }
}

Write-Host "All deploys finished." -ForegroundColor Green
