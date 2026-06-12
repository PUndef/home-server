# Install Uptime Kuma on static-sites LXC 102 (Windows, no WSL).
#
# Usage:
#   .\scripts\proxmox\install-uptime-kuma.ps1
#
# Then create admin: http://192.168.50.35:3001/
# Then seed: .\scripts\phoneserver\seed-kuma-monitors.ps1

$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$BashScript = Join-Path $RepoRoot 'scripts\proxmox\install-uptime-kuma.sh'

if (-not (Test-Path $BashScript)) {
    throw "missing: $BashScript"
}

Write-Host "=== Uptime Kuma on static-sites (LXC 102) ===" -ForegroundColor Cyan

# No WSL - proxmox via py -3 only
$installSh = Join-Path $RepoRoot 'scripts\proxmox\uptime-kuma-install.sh'
$fixSh = Join-Path $RepoRoot 'scripts\proxmox\fix-kuma-monitors-lxc.sh'

py -3 (Join-Path $RepoRoot 'scripts\proxmox\upload.py') $installSh /tmp/uptime-kuma-install.sh --chmod 755
py -3 (Join-Path $RepoRoot 'scripts\proxmox\upload.py') $fixSh /tmp/fix-kuma-monitors-lxc.sh --chmod 755
py -3 (Join-Path $RepoRoot 'scripts\proxmox\proxmox_exec.py') `
    'pct push 102 /tmp/uptime-kuma-install.sh /tmp/uptime-kuma-install.sh --perms 0755'
py -3 (Join-Path $RepoRoot 'scripts\proxmox\proxmox_exec.py') `
    'pct push 102 /tmp/fix-kuma-monitors-lxc.sh /tmp/fix-kuma-monitors-lxc.sh --perms 0755'
py -3 (Join-Path $RepoRoot 'scripts\proxmox\proxmox_exec.py') `
    "pct exec 102 -- bash -lc 'KUMA_VERSION=2.3.2 /tmp/uptime-kuma-install.sh'"
py -3 (Join-Path $RepoRoot 'scripts\proxmox\proxmox_exec.py') `
    'pct exec 102 -- bash /tmp/fix-kuma-monitors-lxc.sh'

$code = (curl.exe -sS -m 8 -o NUL -w '%{http_code}' 'http://192.168.50.35:3001/').Trim()
Write-Host "Kuma HTTP $code"
Write-Host "done - http://192.168.50.35:3001/" -ForegroundColor Green
Write-Host "next: admin in UI, then .\scripts\phoneserver\seed-kuma-monitors.ps1"
