# Install Uptime Kuma on phoneserver (postmarketOS / OpenRC).
#
# Prerequisites:
#   - SSH key: %USERPROFILE%\.ssh\phoneserver_nopass (or WSL ~/.ssh/phoneserver_nopass)
#   - phoneserver reachable (eth 192.168.1.227 or USB 172.16.42.1 after wsl-usbnet-up.sh)
#
# Usage:
#   .\scripts\phoneserver\install-uptime-kuma.ps1
#   $env:PHONE_IP='172.16.42.1'; .\scripts\phoneserver\install-uptime-kuma.ps1

param(
    [string]$PhoneIp = $(if ($env:PHONE_IP) { $env:PHONE_IP } else { "192.168.1.227" }),
    [string]$SshUser = "pmos",
    [string]$SshKey = "$env:USERPROFILE\.ssh\phoneserver_nopass",
    [string]$KumaVersion = "2.3.2",
    [int]$KumaPort = 3001
)

if (-not (Test-Path $SshKey)) {
    $wslKey = "\\wsl$\Ubuntu\home\$env:USERNAME\.ssh\phoneserver_nopass"
    if (Test-Path $wslKey) {
        $SshKey = $wslKey
        Write-Host "Using WSL key: $SshKey"
    } else {
        throw "Missing SSH key: $SshKey (or WSL ~/.ssh/phoneserver_nopass)"
    }
}

$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$installSh = Join-Path $RepoRoot "scripts\phoneserver\uptime-kuma-install.sh"
$remote = "${SshUser}@${PhoneIp}"
$sshOpts = @("-o", "StrictHostKeyChecking=no", "-o", "ServerAliveInterval=30", "-o", "ServerAliveCountMax=120", "-i", $SshKey)

Write-Host "=== phoneserver Uptime Kuma ($PhoneIp) ===" -ForegroundColor Cyan

ssh @sshOpts $remote "echo ok" 2>$null
if ($LASTEXITCODE -ne 0) {
    throw @"
SSH to $remote failed.
  Wi-Fi: .\scripts\phoneserver\install-uptime-kuma.ps1
  USB:   wsl-usbnet-up.sh, then `$env:PHONE_IP='172.16.42.1'; .\scripts\phoneserver\install-uptime-kuma.ps1
"@
}

scp @sshOpts $installSh "${remote}:/tmp/uptime-kuma-install.sh"
if ($LASTEXITCODE -ne 0) { throw "scp failed" }

ssh @sshOpts $remote "chmod 755 /tmp/uptime-kuma-install.sh; sudo env KUMA_VERSION='$KumaVersion' KUMA_PORT='$KumaPort' /tmp/uptime-kuma-install.sh"
if ($LASTEXITCODE -ne 0) { throw "install failed — see /var/log/uptime-kuma-install.log on phone" }

Write-Host ""
Write-Host "Done. Open http://${PhoneIp}:${KumaPort}/ and create admin account." -ForegroundColor Green
