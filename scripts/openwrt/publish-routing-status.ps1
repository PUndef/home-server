# One-shot: collect OpenWrt routing status from PC and publish to static-sites LXC.
# Periodic collection runs on phoneserver (systemd timer) — NOT Windows Task Scheduler.
#
# Usage:
#   .\scripts\openwrt\publish-routing-status.ps1
#   .\scripts\openwrt\publish-routing-status.ps1 -RemoveTask   # cleanup legacy Windows task
#   .\scripts\phoneserver\install-routing-status-collector.ps1 # install phoneserver timer

param(
    [string]$HostName = "192.168.50.35",
    [string]$User = "deploy",
    [string]$KeyPath = "$env:USERPROFILE\.ssh\proxmox_pundef_nopass",
    [string]$RemoteDir = "/srv/static-sites/network-routing",
    [switch]$Hidden,
    [switch]$RemoveTask
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$StatusPy = Join-Path $RepoRoot "scripts\openwrt\routing_status.py"
$LocalStatus = Join-Path $env:TEMP "network-routing-status.json"
$HistoryLocal = Join-Path $env:TEMP "network-routing-history-line.jsonl"
$target = "${User}@${HostName}"
$legacyTaskName = "home-server-publish-routing-status"

function Invoke-External {
    param([string]$FilePath, [string[]]$Arguments)

    if (-not $Hidden) {
        & $FilePath @Arguments
        if ($LASTEXITCODE -ne 0) { throw "$FilePath failed with exit code $LASTEXITCODE" }
        return
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = [string]::Join(" ", ($Arguments | ForEach-Object {
        if ($_ -match '\s|"') { '"{0}"' -f ($_ -replace '"', '\"') } else { $_ }
    }))
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    if ($proc.ExitCode -ne 0) {
        throw "$FilePath failed with exit code $($proc.ExitCode): $stderr$stdout"
    }
}

if ($RemoveTask) {
    Unregister-ScheduledTask -TaskName $legacyTaskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "Removed legacy scheduled task '$legacyTaskName' (if present)"
    return
}

if (-not (Test-Path $KeyPath)) { throw "SSH key not found: $KeyPath" }

Invoke-External py @("-3", $StatusPy, "--out", $LocalStatus)
Invoke-External scp @("-i", $KeyPath, $LocalStatus, "${target}:${RemoteDir}/status.json")

$overallVal = "unknown"
$tsVal = (Get-Date).ToUniversalTime().ToString("o")
$failVal = "0"
$content = Get-Content $LocalStatus -Raw
if ($content -match '"overall": "([^"]+)"') { $overallVal = $Matches[1] }
if ($content -match '"timestamp": "([^"]+)"') { $tsVal = $Matches[1] }
if ($content -match '"fail": (\d+)') { $failVal = $Matches[1] }

"{""timestamp"":""$tsVal"",""overall"":""$overallVal"",""fail"":$failVal}" | Set-Content -Path $HistoryLocal -Encoding Ascii
Invoke-External scp @("-i", $KeyPath, $HistoryLocal, "${target}:${RemoteDir}/history-append.jsonl")

$remoteCmd = @"
mkdir -p '$RemoteDir' && cat '$RemoteDir/history-append.jsonl' >> '$RemoteDir/history.jsonl' && rm -f '$RemoteDir/history-append.jsonl' && tail -n 480 '$RemoteDir/history.jsonl' > '$RemoteDir/history.jsonl.tmp' && mv '$RemoteDir/history.jsonl.tmp' '$RemoteDir/history.jsonl'
"@
Invoke-External ssh @("-i", $KeyPath, $target, $remoteCmd)

if (-not $Hidden) {
    Write-Host "Published status.json (overall=$overallVal) to ${target}:${RemoteDir}/"
}
