# Stop Destiny net watch started by start-destiny-net-watch.ps1
#
# Usage:
#   .\scripts\openwrt\stop-destiny-net-watch.ps1

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$LockFile = Join-Path $RepoRoot "logs\destiny-net-watch\.watch.lock"

if (-not (Test-Path $LockFile)) {
    Write-Host "No lock file — watcher not running?" -ForegroundColor Yellow
    exit 0
}

try {
    $lock = Get-Content $LockFile -Raw | ConvertFrom-Json
    $watcherPid = [int]$lock.pid
} catch {
    Remove-Item $LockFile -Force -ErrorAction SilentlyContinue
    Write-Host "Removed stale lock file."
    exit 0
}

$proc = Get-Process -Id $watcherPid -ErrorAction SilentlyContinue
if ($proc) {
    Stop-Process -Id $watcherPid -Force
    Write-Host "Stopped watcher PID $watcherPid"
} else {
    Write-Host "Process $watcherPid not found (already stopped)"
}

Remove-Item $LockFile -Force -ErrorAction SilentlyContinue
