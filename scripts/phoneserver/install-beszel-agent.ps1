# Install Beszel agent on phoneserver (postmarketOS / OpenRC).
#
# Prerequisites:
#   - SSH key: %USERPROFILE%\.ssh\phoneserver_nopass (or WSL ~/.ssh/phoneserver_nopass)
#   - In Beszel UI: + Add System "phoneserver", host 192.168.1.116, port 45876 → copy TOKEN
#   - phoneserver reachable (Wi-Fi/LAN 192.168.1.116 or USB 172.16.42.1)
#
# Usage:
#   .\scripts\phoneserver\install-beszel-agent.ps1 -Token "<uuid-from-beszel-ui>"
#   $env:BESZEL_PHONESERVER_TOKEN="<uuid>"; .\scripts\phoneserver\install-beszel-agent.ps1

param(
    [string]$Token = $env:BESZEL_PHONESERVER_TOKEN,
    [string]$PhoneIp = $(if ($env:PHONE_IP) { $env:PHONE_IP } else { "192.168.1.116" }),
    [string]$SshUser = "pmos",
    [string]$SshKey = "$env:USERPROFILE\.ssh\phoneserver_nopass",

    [string]$HubKey = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH9I03DG8DciIm5AklgrMF1GMQoIlYibQxKWbzzdFv3W',
    # Internal URL: phoneserver on lan, hub on srv (no NAT hairpin).
    [string]$HubUrl = "http://192.168.50.35/beszel",

    [string]$BeszelVersion = "v0.18.7"
)

if (-not $Token) {
    throw @"
TOKEN required.

1. Open https://apps-pundef.mooo.com/beszel/
2. + Add System: Name phoneserver, Host $PhoneIp, Port 45876
3. Copy TOKEN from the docker run modal
4. Run: .\scripts\phoneserver\install-beszel-agent.ps1 -Token '<uuid>'
"@
}

if (-not (Test-Path $SshKey)) {
    $wslKey = "\\wsl$\Ubuntu\home\$env:USERNAME\.ssh\phoneserver_nopass"
    if (Test-Path $wslKey) {
        $SshKey = $wslKey
        Write-Host "Using WSL key: $SshKey"
    } else {
        throw "SSH key not found. Expected $SshKey or WSL ~/.ssh/phoneserver_nopass (setup-ssh-key.sh in WSL)."
    }
}

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$TarName = "beszel-agent_linux_arm64.tar.gz"
$TarLocal = Join-Path $env:TEMP $TarName
$TarUrl = "https://github.com/henrygd/beszel/releases/download/$BeszelVersion/$TarName"

if (-not (Test-Path $TarLocal)) {
    Write-Host "Downloading $TarUrl ..."
    curl.exe -fsSL -o $TarLocal $TarUrl
}

$envFile = Join-Path $env:TEMP "beszel-agent-phoneserver.env"
@"
KEY="$HubKey"
TOKEN=$Token
HUB_URL=$HubUrl
LISTEN=45876
"@ | Set-Content -Path $envFile -Encoding utf8NoBOM -NoNewline

$installSh = Join-Path $RepoRoot "scripts\phoneserver\beszel-agent-install.sh"
$sshOpts = @("-i", $SshKey, "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=NUL")
$remote = "${SshUser}@${PhoneIp}"

Write-Host "=== phoneserver Beszel agent ($PhoneIp) ===" -ForegroundColor Cyan

ssh @sshOpts $remote "echo ok"
if ($LASTEXITCODE -ne 0) {
    throw "SSH to $remote failed. Try USB: `$env:PHONE_IP='172.16.42.1'; .\scripts\phoneserver\install-beszel-agent.ps1 -Token '...'"
}

scp @sshOpts $TarLocal "${remote}:/tmp/$TarName"
scp @sshOpts $installSh "${remote}:/tmp/beszel-agent-install.sh"
scp @sshOpts $envFile "${remote}:/tmp/beszel-agent.env"

ssh @sshOpts $remote "chmod 755 /tmp/beszel-agent-install.sh; chmod 600 /tmp/beszel-agent.env; sudo /tmp/beszel-agent-install.sh"

Remove-Item $envFile -Force -ErrorAction SilentlyContinue
Write-Host "Done. Check https://apps-pundef.mooo.com/beszel/ - phoneserver should be online." -ForegroundColor Green
