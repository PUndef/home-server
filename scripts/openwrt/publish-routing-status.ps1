# Collect OpenWrt routing status from PC (lan SSH) and publish to static-sites LXC.
# LXC srv segment cannot SSH to router — collector runs here, not on .35.
#
# Usage:
#   .\scripts\openwrt\publish-routing-status.ps1
#   .\scripts\openwrt\publish-routing-status.ps1 -InstallTask

param(
    [string]$HostName = "192.168.50.35",
    [string]$User = "deploy",
    [string]$KeyPath = "$env:USERPROFILE\.ssh\proxmox_pundef_nopass",
    [string]$RemoteDir = "/srv/static-sites/network-routing",
    [switch]$InstallTask
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$StatusPy = Join-Path $RepoRoot "scripts\openwrt\routing_status.py"
$LocalStatus = Join-Path $env:TEMP "network-routing-status.json"
$HistoryLocal = Join-Path $env:TEMP "network-routing-history-line.jsonl"
$target = "${User}@${HostName}"

function Invoke-Native {
    param([string]$FilePath, [string[]]$Arguments)
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$FilePath failed with exit code $LASTEXITCODE" }
}

if (-not (Test-Path $KeyPath)) { throw "SSH key not found: $KeyPath" }

Invoke-Native py @("-3", $StatusPy, "--out", $LocalStatus)

Invoke-Native scp @("-i", $KeyPath, $LocalStatus, "${target}:${RemoteDir}/status.json")

$overallVal = "unknown"
$tsVal = (Get-Date).ToUniversalTime().ToString("o")
$failVal = "0"
$content = Get-Content $LocalStatus -Raw
if ($content -match '"overall": "([^"]+)"') { $overallVal = $Matches[1] }
if ($content -match '"timestamp": "([^"]+)"') { $tsVal = $Matches[1] }
if ($content -match '"fail": (\d+)') { $failVal = $Matches[1] }

"{""timestamp"":""$tsVal"",""overall"":""$overallVal"",""fail"":$failVal}" | Set-Content -Path $HistoryLocal -Encoding Ascii
Invoke-Native scp @("-i", $KeyPath, $HistoryLocal, "${target}:${RemoteDir}/history-append.jsonl")

$remoteCmd = @"
mkdir -p '$RemoteDir' && cat '$RemoteDir/history-append.jsonl' >> '$RemoteDir/history.jsonl' && rm -f '$RemoteDir/history-append.jsonl' && tail -n 480 '$RemoteDir/history.jsonl' > '$RemoteDir/history.jsonl.tmp' && mv '$RemoteDir/history.jsonl.tmp' '$RemoteDir/history.jsonl'
"@
Invoke-Native ssh @("-i", $KeyPath, $target, $remoteCmd)

Write-Host "Published status.json (overall=$overallVal) to ${target}:${RemoteDir}/"

if ($InstallTask) {
    $taskName = "home-server-publish-routing-status"
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$PSScriptRoot\publish-routing-status.ps1`""
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 3) -RepetitionDuration (New-TimeSpan -Days 3650)
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Force | Out-Null
    Write-Host "Scheduled task '$taskName' (every 3 min)"
}
