# Install Beszel agent on one or both VPS targets.
#
# Prerequisites:
#   - SSH key at %USERPROFILE%\.ssh\vps_nopass authorized on each VPS
#   - Per-system TOKEN from Beszel UI (+ Add System)
#
# Usage:
#   .\scripts\vps\install-beszel-agent.ps1 -Target fin
#   .\scripts\vps\install-beszel-agent.ps1 -Target neth
#   .\scripts\vps\install-beszel-agent.ps1 -Target all

param(
    [ValidateSet("fin", "neth", "all")]
    [string]$Target = "all",

    [string]$FinToken = $env:BESZEL_FIN_TOKEN,
    [string]$NethToken = $env:BESZEL_NETH_TOKEN,

    [string]$HubKey = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH9I03DG8DciIm5AklgrMF1GMQoIlYibQxKWbzzdFv3W',
    [string]$HubUrl = "https://apps-pundef.mooo.com/beszel"
)

if ($Target -in @("fin", "all") -and -not $FinToken) {
    throw "Fin TOKEN required: -FinToken or env BESZEL_FIN_TOKEN"
}
if ($Target -in @("neth", "all") -and -not $NethToken) {
    throw "Neth TOKEN required: -NethToken or env BESZEL_NETH_TOKEN"
}

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$Python = Join-Path $env:LOCALAPPDATA "Python\bin\python.exe"
if (-not (Test-Path $Python)) { $Python = "py" }

$Targets = @()
if ($Target -in @("fin", "all")) {
    $Targets += [pscustomobject]@{
        Name  = "fin-sweet-home-vps"
        Host  = "89.44.76.52"
        User  = "root"
        Sudo  = $false
        Token = $FinToken
    }
}
if ($Target -in @("neth", "all")) {
    $Targets += [pscustomobject]@{
        Name  = "sweet-home-vps"
        Host  = "45.154.35.222"
        User  = "pundef"
        Sudo  = $true
        Token = $NethToken
    }
}

function Write-EnvFile([string]$Path, [string]$Token) {
    $content = @"
KEY="$HubKey"
TOKEN=$Token
HUB_URL=$HubUrl
LISTEN=45876
"@
    [System.IO.File]::WriteAllText($Path, $content.Replace("`r`n", "`n"))
}

foreach ($t in $Targets) {
    Write-Host "=== $($t.Name) ($($t.Host)) ===" -ForegroundColor Cyan

    $envFile = Join-Path $env:TEMP "beszel-agent-$($t.Name).env"
    Write-EnvFile $envFile $t.Token

    $env:VPS_HOST = $t.Host
    $env:VPS_USER = $t.User
    & $Python (Join-Path $RepoRoot "scripts\vps\vps_exec.py") hostname
    if ($LASTEXITCODE -ne 0) {
        throw "SSH to $($t.Host) failed. Authorize %USERPROFILE%\.ssh\vps_nopass.pub on the VPS first."
    }

    $upload = Join-Path $RepoRoot "scripts\vps\vps_upload.py"
    $installSh = Join-Path $RepoRoot "scripts\proxmox\beszel-agent-install.sh"
    $vpsSh = Join-Path $RepoRoot "scripts\vps\beszel-agent-install-vps.sh"

    & $Python $upload --host $t.Host --user $t.User $installSh /tmp/beszel-agent-install.sh --chmod 755
    if ($LASTEXITCODE -ne 0) { throw "upload install.sh failed for $($t.Host)" }

    & $Python $upload --host $t.Host --user $t.User $vpsSh /tmp/beszel-agent-install-vps.sh --chmod 755
    if ($LASTEXITCODE -ne 0) { throw "upload vps wrapper failed for $($t.Host)" }

    & $Python $upload --host $t.Host --user $t.User $envFile /tmp/beszel-agent.env --chmod 600
    if ($LASTEXITCODE -ne 0) { throw "upload env failed for $($t.Host)" }

    $runCmd = if ($t.Sudo) { "sudo bash /tmp/beszel-agent-install-vps.sh" } else { "bash /tmp/beszel-agent-install-vps.sh" }
    & $Python (Join-Path $RepoRoot "scripts\vps\vps_exec.py") $runCmd
    if ($LASTEXITCODE -ne 0) { throw "install failed on $($t.Host)" }

    & $Python (Join-Path $RepoRoot "scripts\vps\vps_exec.py") `
        "rm -f /tmp/beszel-agent.env /tmp/beszel-agent-install.sh /tmp/beszel-agent-install-vps.sh /tmp/beszel-agent_linux_amd64_glibc.tar.gz"
    Remove-Item $envFile -Force -ErrorAction SilentlyContinue

    Write-Host "OK: $($t.Name)" -ForegroundColor Green
}

Write-Host "Done. Check https://apps-pundef.mooo.com/beszel/ for online status."
