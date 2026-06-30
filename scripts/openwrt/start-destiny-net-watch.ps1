# Start Destiny conntrack watcher in a new console window (single instance).
#
# Usage:
#   .\scripts\openwrt\start-destiny-net-watch.ps1
#   .\scripts\openwrt\start-destiny-net-watch.ps1 -ClientIp 192.168.1.133

param(
    [string]$ClientIp = $(if ($env:DESTINY_CLIENT_IP) { $env:DESTINY_CLIENT_IP } else { "192.168.1.208" }),
    [int]$Interval = 5
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$LogDir = Join-Path $RepoRoot "logs\destiny-net-watch"
$LockFile = Join-Path $LogDir ".watch.lock"
$PyScript = Join-Path $RepoRoot "scripts\openwrt\watch_destiny_sessions.py"

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

if (Test-Path $LockFile) {
    try {
        $lock = Get-Content $LockFile -Raw | ConvertFrom-Json
        $pid = [int]$lock.pid
        $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
        if ($proc) {
            Write-Host "Watcher already running (PID $pid). Stop first:" -ForegroundColor Yellow
            Write-Host "  .\scripts\openwrt\stop-destiny-net-watch.ps1"
            exit 1
        }
        Remove-Item $LockFile -Force
    } catch {
        Remove-Item $LockFile -Force -ErrorAction SilentlyContinue
    }
}

$cmd = @"
Set-Location '$RepoRoot'
Write-Host 'Destiny net watch — leave this window open while playing.' -ForegroundColor Cyan
Write-Host 'Logs: $LogDir' -ForegroundColor Green
Write-Host 'Stop: Ctrl+C or stop-destiny-net-watch.ps1' -ForegroundColor DarkGray
py -3 '$PyScript' --client-ip '$ClientIp' --interval $Interval
"@

Start-Process powershell -ArgumentList "-NoExit", "-Command", $cmd
Write-Host "Watcher started (client=$ClientIp, every ${Interval}s)."
Write-Host "Logs: $LogDir"
