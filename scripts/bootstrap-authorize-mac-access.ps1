# Authorize the current Cursor/Mac public key on home-server infrastructure.
#
# Run from the main Windows PC where the existing infrastructure keys are present:
#   .\scripts\bootstrap-authorize-mac-access.ps1

param(
    [string]$PublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMLqNfMjJFeaAlEu0WVB8iZsuI+W8R5UIcKgxEyFFu54 home-server-cursor-mac",
    [string]$OpenWrtKey = "$env:USERPROFILE\.ssh\openwrt_ax300t_nopass",
    [string]$PhoneKey = "$env:USERPROFILE\.ssh\phoneserver_nopass",
    [string]$ProxmoxKey = "$env:USERPROFILE\.ssh\proxmox_pundef_nopass",
    [switch]$UseWsl
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

function Test-WindowsKeys {
    return (Test-Path $OpenWrtKey) -and (Test-Path $PhoneKey) -and (Test-Path $ProxmoxKey)
}

function Invoke-WslBootstrap {
    $encodedKey = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($PublicKey))
    $script = @'
set -eu
pub="$(printf %s "__PUB_B64__" | base64 -d)"

openwrt_key="${OPENWRT_KEY:-$HOME/.ssh/openwrt_ax300t_nopass}"
phone_key="${PHONE_KEY:-$HOME/.ssh/phoneserver_nopass}"
proxmox_key="${PROXMOX_KEY:-$HOME/.ssh/proxmox_pundef_nopass}"

for item in "$openwrt_key" "$phone_key" "$proxmox_key"; do
  if [ ! -f "$item" ]; then
    echo "missing SSH key in WSL: $item" >&2
    exit 1
  fi
  chmod 600 "$item" 2>/dev/null || true
done

add_key() {
  name="$1"
  remote="$2"
  key="$3"
  echo "=== $name ($remote) ==="
  ssh -i "$key" -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$remote" \
    "umask 077; mkdir -p ~/.ssh; touch ~/.ssh/authorized_keys; grep -qxF '$pub' ~/.ssh/authorized_keys || printf '%s\n' '$pub' >> ~/.ssh/authorized_keys; chmod 700 ~/.ssh; chmod 600 ~/.ssh/authorized_keys; echo authorized"
}

add_key "OpenWrt" "root@192.168.1.1" "$openwrt_key"
add_key "phoneserver wlan" "user@192.168.1.227" "$phone_key"
add_key "Proxmox" "root@192.168.50.9" "$proxmox_key"
add_key "static-sites deploy" "deploy@192.168.50.35" "$proxmox_key"

echo
echo "Done. Mac key authorized: $pub"
'@
    $script = $script.Replace("__PUB_B64__", $encodedKey)
    wsl bash -lc $script
    if ($LASTEXITCODE -ne 0) {
        throw "WSL bootstrap failed"
    }
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

if ($UseWsl -or -not (Test-WindowsKeys)) {
    Write-Host "Windows SSH keys not found or -UseWsl requested — using WSL ~/.ssh keys..." -ForegroundColor Yellow
    Invoke-WslBootstrap
    return
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
