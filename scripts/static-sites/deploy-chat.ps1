# Deploy minimal phoneserver chat UI to static-sites LXC.
#
# Usage (repo root):
#   .\scripts\static-sites\deploy-chat.ps1
#   .\scripts\static-sites\deploy-chat.ps1 -Url "https://apps-pundef.mooo.com/chat/"

param(
    [string]$HostName = "192.168.50.35",
    [string]$User = "deploy",
    [string]$RemotePath = "/srv/static-sites/chat",
    [string]$KeyPath = "$env:USERPROFILE\.ssh\proxmox_pundef_nopass",
    [string]$Url = "http://192.168.50.35/chat/"
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$ChatDir = Join-Path $RepoRoot "static-sites\chat"

if (-not (Test-Path $ChatDir)) {
    throw "Missing $ChatDir"
}

$sshArgs = @()
if ($KeyPath) {
    if (-not (Test-Path $KeyPath)) { throw "SSH key not found: $KeyPath" }
    $sshArgs += @("-i", $KeyPath)
}

$target = "${User}@${HostName}"
$tmpArchive = Join-Path $env:TEMP ("chat-static-{0}.tgz" -f ([guid]::NewGuid().ToString("N")))
$remoteArchive = "/tmp/$(Split-Path $tmpArchive -Leaf)"

try {
    Write-Host "Packing chat static files..."
    & tar -czf $tmpArchive -C $ChatDir .
    if ($LASTEXITCODE -ne 0) { throw "tar failed" }

    Write-Host "Uploading to ${target}..."
    & scp @sshArgs $tmpArchive "${target}:${remoteArchive}"
    if ($LASTEXITCODE -ne 0) { throw "scp failed" }

    $remoteCmd = @"
set -e
mkdir -p '$RemotePath'
rm -rf '$RemotePath'/*
tar -xzf '$remoteArchive' -C '$RemotePath'
rm -f '$remoteArchive'
ls -la '$RemotePath'
"@
    & ssh @sshArgs $target $remoteCmd
    if ($LASTEXITCODE -ne 0) { throw "remote extract failed" }
}
finally {
    if (Test-Path $tmpArchive) { Remove-Item $tmpArchive -Force }
}

if ($Url) {
    Write-Host "Checking $Url ..."
    $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 10
    if ($r.StatusCode -ge 400) { throw "HTTP $($r.StatusCode)" }
    Write-Host "HTTP $($r.StatusCode) OK"
}

Write-Host "Done. Open: $Url"
