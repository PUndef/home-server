param(
    [string]$HostName = "192.168.50.35",
    [string]$User = "deploy",
    [string]$RemotePath = "/srv/static-sites/relics",
    [string]$KeyPath = "$env:USERPROFILE\.ssh\proxmox_pundef_nopass",
    [string]$Url = "http://192.168.50.35/relics/",
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"

function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$FilePath failed with exit code $LASTEXITCODE"
    }
}

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$distPath = Join-Path $projectRoot "dist"
$target = "$User@$HostName"

$sshArgs = @()
if ($KeyPath) {
    if (-not (Test-Path $KeyPath)) {
        throw "SSH key not found: $KeyPath"
    }
    $sshArgs += @("-i", $KeyPath)
}

if (-not $SkipBuild) {
    Write-Host "Building relics-helper..."
    Push-Location $projectRoot
    try {
        Invoke-Native npm ci
        Invoke-Native npm run sync-drops
        Invoke-Native npm run build
    }
    finally {
        Pop-Location
    }
}

if (-not (Test-Path $distPath)) {
    throw "Build output was not found: $distPath"
}

$tmpArchive = Join-Path $env:TEMP ("relics-dist-{0}.tgz" -f ([guid]::NewGuid().ToString("N")))
$remoteArchive = "/tmp/$(Split-Path $tmpArchive -Leaf)"

try {
    Write-Host "Packing dist into $tmpArchive..."
    Invoke-Native tar -czf $tmpArchive -C $distPath "."

    Write-Host "Uploading archive to ${target}:${remoteArchive}..."
    Invoke-Native scp @sshArgs $tmpArchive "${target}:${remoteArchive}"

    Write-Host "Extracting on remote into $RemotePath..."
    $remoteCmd = "set -e; mkdir -p '$RemotePath'; rm -rf '$RemotePath'/*; tar -xzf '$remoteArchive' -C '$RemotePath'; rm -f '$remoteArchive'; ls -la '$RemotePath' | head"
    Invoke-Native ssh @sshArgs $target $remoteCmd
}
finally {
    if (Test-Path $tmpArchive) {
        Remove-Item $tmpArchive -Force
    }
}

if ($Url) {
    Write-Host "Checking $Url..."
    $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 10
    if ($response.StatusCode -lt 200 -or $response.StatusCode -ge 400) {
        throw "Unexpected HTTP status: $($response.StatusCode)"
    }
    Write-Host "HTTP $($response.StatusCode)"
}

Write-Host "Deploy complete."
