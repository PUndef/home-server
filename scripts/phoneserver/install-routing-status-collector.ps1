# Install routing status collector on phoneserver (systemd timer, no Windows Task Scheduler).
#
# Usage:
#   .\scripts\phoneserver\install-routing-status-collector.ps1
#   .\scripts\phoneserver\install-routing-status-collector.ps1 -PhoneIp 192.168.50.127

param(
    [string]$PhoneIp = $(if ($env:PHONE_IP) { $env:PHONE_IP } else { "192.168.1.227" }),
    [string]$SshUser = "user",
    [string]$PhoneKey = "$env:USERPROFILE\.ssh\phoneserver_nopass",
    [string]$OpenWrtKey = "$env:USERPROFILE\.ssh\openwrt_ax300t_nopass",
    [string]$LxcKey = "$env:USERPROFILE\.ssh\proxmox_pundef_nopass"
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$WslInstall = Join-Path $RepoRoot "scripts\phoneserver\install-routing-status-collector-wsl.sh"

function Invoke-WslInstall {
    param([string]$Ip)
    $wslRepo = (wsl wslpath -a $RepoRoot).Trim()
    $wslScript = "$wslRepo/scripts/phoneserver/install-routing-status-collector-wsl.sh"
    wsl bash -lc "chmod +x '$wslScript' && PHONE_IP='$Ip' '$wslScript'"
    if ($LASTEXITCODE -ne 0) { throw "WSL install failed" }
}

$winPhoneKey = "$env:USERPROFILE\.ssh\phoneserver_nopass"
if (-not (Test-Path $winPhoneKey)) {
    Write-Host "phoneserver key not on Windows — using WSL install..." -ForegroundColor Yellow
    Invoke-WslInstall -Ip $PhoneIp
    Write-Host "Done. Check: curl http://192.168.50.35/network-routing/status.json" -ForegroundColor Green
    return
}

$StagingName = "routing-status-install"
$RemoteStaging = "/tmp/$StagingName"
$LocalStaging = Join-Path $env:TEMP $StagingName

function Resolve-PhoneKey {
    $win = "$env:USERPROFILE\.ssh\phoneserver_nopass"
    if (Test-Path $win) { return $win }
    try {
        $wslUser = (wsl bash -lc "whoami").Trim()
        $wslKey = "\\wsl$\Ubuntu\home\$wslUser\.ssh\phoneserver_nopass"
        if (Test-Path $wslKey) { return $wslKey }
    } catch {}
    throw "phoneserver SSH key not found (Windows or WSL ~/.ssh/phoneserver_nopass)"
}

function Resolve-Key([string]$Path, [string]$WslRel) {
    if (Test-Path $Path) { return $Path }
    $wsl = Join-Path "\\wsl$\Ubuntu\home\$env:USERNAME\.ssh" $WslRel
    if (Test-Path $wsl) { return $wsl }
    throw "SSH key not found: $Path"
}

$PhoneKey = Resolve-PhoneKey
$OpenWrtKey = Resolve-Key $OpenWrtKey "openwrt_ax300t_nopass"
$LxcKey = Resolve-Key $LxcKey "proxmox_pundef_nopass"

$sshOpts = @("-i", $PhoneKey, "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=NUL")
$remote = "${SshUser}@${PhoneIp}"

if (Test-Path $LocalStaging) { Remove-Item $LocalStaging -Recurse -Force }
New-Item -ItemType Directory -Path $LocalStaging | Out-Null

Copy-Item "$RepoRoot\scripts\openwrt\routing_status.py" $LocalStaging
Copy-Item "$RepoRoot\scripts\openwrt\watch_destiny_sessions.py" $LocalStaging
Copy-Item "$RepoRoot\config\openwrt\overrides.json" $LocalStaging
Copy-Item "$RepoRoot\scripts\phoneserver\routing-status-collector.sh" $LocalStaging
Copy-Item "$RepoRoot\scripts\phoneserver\destiny-net-watch-collector.sh" $LocalStaging
Copy-Item "$RepoRoot\scripts\phoneserver\routing-status-collector.service" $LocalStaging
Copy-Item "$RepoRoot\scripts\phoneserver\routing-status-collector.timer" $LocalStaging
Copy-Item "$RepoRoot\scripts\phoneserver\destiny-net-watch-collector.service" $LocalStaging
Copy-Item $OpenWrtKey (Join-Path $LocalStaging "openwrt_collector")
Copy-Item $LxcKey (Join-Path $LocalStaging "lxc_deploy_key")
Copy-Item "$RepoRoot\scripts\phoneserver\install-routing-status-collector.sh" $LocalStaging

Write-Host "=== install routing status collector on $remote ===" -ForegroundColor Cyan
ssh @sshOpts $remote "echo ok"
if ($LASTEXITCODE -ne 0) { throw "SSH to $remote failed" }

ssh @sshOpts $remote "rm -rf '$RemoteStaging' && mkdir -p '$RemoteStaging'"
scp @sshOpts -r "$LocalStaging\*" "${remote}:${RemoteStaging}/"
ssh @sshOpts $remote "chmod 755 '$RemoteStaging/install-routing-status-collector.sh' && sudo '$RemoteStaging/install-routing-status-collector.sh'"

Remove-Item $LocalStaging -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "Done. Check: curl http://192.168.50.35/network-routing/status.json" -ForegroundColor Green
