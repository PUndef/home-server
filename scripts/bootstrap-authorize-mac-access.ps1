# Authorize the current Cursor/Mac public key on home-server infrastructure.
#
# Run from the main Windows PC where the existing infrastructure keys are present:
#   .\scripts\bootstrap-authorize-mac-access.ps1

param(
    [string]$PublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMLqNfMjJFeaAlEu0WVB8iZsuI+W8R5UIcKgxEyFFu54 home-server-cursor-mac",
    [string]$OpenWrtKey = "$env:USERPROFILE\.ssh\openwrt_ax300t_nopass",
    [string]$PhoneKey = "$env:USERPROFILE\.ssh\phoneserver_nopass",
    [string]$ProxmoxKey = "$env:USERPROFILE\.ssh\proxmox_pundef_nopass"
)

$ErrorActionPreference = "Stop"

function Resolve-Key([string]$Path, [string]$WslRel) {
    if (Test-Path $Path) { return $Path }

    try {
        $wslUser = (wsl bash -lc "whoami").Trim()
        $wslPath = "\\wsl$\Ubuntu\home\$wslUser\.ssh\$WslRel"
        if (Test-Path $wslPath) { return $wslPath }
    } catch {}

    throw "SSH key not found: $Path or WSL ~/.ssh/$WslRel"
}

function Add-AuthorizedKey {
    param(
        [string]$Name,
        [string]$Remote,
        [string]$KeyPath
    )

    $sshOpts = @(
        "-i", $KeyPath,
        "-o", "BatchMode=yes",
        "-o", "StrictHostKeyChecking=no",
        "-o", "UserKnownHostsFile=NUL"
    )

    $remoteCommand = "umask 077; mkdir -p ~/.ssh; touch ~/.ssh/authorized_keys; grep -qxF '$PublicKey' ~/.ssh/authorized_keys || printf '%s\n' '$PublicKey' >> ~/.ssh/authorized_keys; chmod 700 ~/.ssh; chmod 600 ~/.ssh/authorized_keys; echo authorized"

    Write-Host "=== $Name ($Remote) ===" -ForegroundColor Cyan
    ssh @sshOpts $Remote $remoteCommand
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to authorize $Name ($Remote)"
    }
}

$OpenWrtKey = Resolve-Key $OpenWrtKey "openwrt_ax300t_nopass"
$PhoneKey = Resolve-Key $PhoneKey "phoneserver_nopass"
$ProxmoxKey = Resolve-Key $ProxmoxKey "proxmox_pundef_nopass"

Add-AuthorizedKey -Name "OpenWrt" -Remote "root@192.168.1.1" -KeyPath $OpenWrtKey
Add-AuthorizedKey -Name "phoneserver wlan" -Remote "user@192.168.1.227" -KeyPath $PhoneKey
Add-AuthorizedKey -Name "Proxmox" -Remote "root@192.168.50.9" -KeyPath $ProxmoxKey
Add-AuthorizedKey -Name "static-sites deploy" -Remote "deploy@192.168.50.35" -KeyPath $ProxmoxKey

Write-Host ""
Write-Host "Done. Mac key authorized: $PublicKey" -ForegroundColor Green
