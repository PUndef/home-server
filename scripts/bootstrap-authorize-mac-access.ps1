# Authorize the current Cursor/Mac public key on home-server infrastructure.
#
# Run from the main Windows PC where the existing infrastructure keys are present:
#   .\scripts\bootstrap-authorize-mac-access.ps1

param(
    [string]$PublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMLqNfMjJFeaAlEu0WVB8iZsuI+W8R5UIcKgxEyFFu54 home-server-cursor-mac"
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path $PSScriptRoot -Parent
$WslRepoRoot = (wsl wslpath -a $RepoRoot).Trim()
$WslScript = "$WslRepoRoot/scripts/bootstrap-authorize-mac-access-wsl.sh"

Write-Host "Using WSL SSH keys for home-server access bootstrap..." -ForegroundColor Cyan
wsl bash "$WslScript" --pubkey "$PublicKey"
if ($LASTEXITCODE -ne 0) {
    throw "WSL bootstrap failed"
}
