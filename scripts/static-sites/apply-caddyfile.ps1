# Push static-sites/Caddyfile to LXC 102 and reload Caddy.
#
# Usage:
#   .\scripts\static-sites\apply-caddyfile.ps1

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$Caddyfile = Join-Path $RepoRoot "static-sites\Caddyfile"
$KeyPath = "$env:USERPROFILE\.ssh\proxmox_pundef_nopass"
$Python = Join-Path $env:LOCALAPPDATA "Python\bin\python.exe"
if (-not (Test-Path $Python)) { $Python = "py" }

if (-not (Test-Path $Caddyfile)) { throw "Missing $Caddyfile" }

Write-Host "Upload Caddyfile to Proxmox /tmp..."
& $Python (Join-Path $RepoRoot "scripts\proxmox\upload.py") $Caddyfile /tmp/Caddyfile.static-sites

Write-Host "Install + validate + reload on LXC 102..."
& $Python (Join-Path $RepoRoot "scripts\proxmox\proxmox_exec.py") @(
    "pct push 102 /tmp/Caddyfile.static-sites /etc/caddy/Caddyfile"
)
& $Python (Join-Path $RepoRoot "scripts\proxmox\proxmox_exec.py") @(
    "pct exec 102 -- bash -lc 'caddy validate --adapter caddyfile --config /etc/caddy/Caddyfile && systemctl reload caddy && systemctl is-active caddy'"
)

Write-Host "Caddy reloaded."
