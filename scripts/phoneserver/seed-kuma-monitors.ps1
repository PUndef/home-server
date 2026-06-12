# Seed Uptime Kuma monitors from kuma-monitors.json (Windows, no WSL).
#
# Prerequisites:
#   - Admin created in http://192.168.50.35:3001/
#   - py -3 on PATH (Windows Python launcher)
#
# Usage (from repo root or any cwd):
#   $env:KUMA_USERNAME = 'admin'
#   $env:KUMA_PASSWORD = 'your-password'
#   .\scripts\phoneserver\seed-kuma-monitors.ps1
#
# Optional:
#   $env:KUMA_URL = 'http://192.168.50.35:3001'
#   .\scripts\phoneserver\seed-kuma-monitors.ps1 -DryRun

param(
    [switch]$DryRun,
    [string]$KumaUrl = $(if ($env:KUMA_URL) { $env:KUMA_URL } else { 'http://192.168.50.35:3001' }),
    [string]$Username = $env:KUMA_USERNAME,
    [string]$Password = $env:KUMA_PASSWORD
)

$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$PyScript = Join-Path $RepoRoot 'scripts\phoneserver\seed-kuma-monitors.py'
$Config = Join-Path $RepoRoot 'scripts\phoneserver\kuma-monitors.json'

if (-not (Test-Path $PyScript)) {
    throw "missing: $PyScript"
}
if (-not $Username -or -not $Password) {
    throw @"
Set credentials first:
  `$env:KUMA_USERNAME = 'admin'
  `$env:KUMA_PASSWORD = '...'
  .\scripts\phoneserver\seed-kuma-monitors.ps1
"@
}

Write-Host "=== Kuma seed -> $KumaUrl ===" -ForegroundColor Cyan

# Reachability
try {
    $code = (curl.exe -sS -m 8 -o NUL -w '%{http_code}' $KumaUrl).Trim()
    if ($code -eq '000') { throw "Kuma not reachable at $KumaUrl" }
    Write-Host "Kuma HTTP $code"
} catch {
    throw "Cannot reach $KumaUrl - open it in browser first"
}

Write-Host "installing uptime-kuma-api-v2 (py -3)..." -ForegroundColor DarkGray
py -3 -m pip install -q uptime-kuma-api-v2
if ($LASTEXITCODE -ne 0) { throw 'pip install uptime-kuma-api-v2 failed' }

$env:KUMA_URL = $KumaUrl
$env:KUMA_USERNAME = $Username
$env:KUMA_PASSWORD = $Password

$seedArgs = @($PyScript, '--config', $Config)
if ($DryRun) { $seedArgs += '--dry-run' }

py -3 @seedArgs
if ($LASTEXITCODE -ne 0) { throw "seed failed (exit $LASTEXITCODE)" }

if (-not $DryRun) {
    Write-Host "=== cleanup dupes + HTTP status codes ===" -ForegroundColor Cyan
    py -3 (Join-Path $RepoRoot 'scripts\proxmox\kuma_cleanup.py')
}

Write-Host "done - $KumaUrl" -ForegroundColor Green
