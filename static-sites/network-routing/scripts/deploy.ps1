param(
    [string]$HostName = "192.168.50.35",
    [string]$User = "deploy",
    [string]$RemotePath = "/srv/static-sites/network-routing",
    [string]$KeyPath = "$env:USERPROFILE\.ssh\proxmox_pundef_nopass",
    [string]$Url = "http://network.home",
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
    Write-Host "Building network-routing..."
    Push-Location $projectRoot
    try {
        Invoke-Native npm ci
        Invoke-Native npm run build
    }
    finally {
        Pop-Location
    }
}

if (-not (Test-Path $distPath)) {
    throw "Build output was not found: $distPath"
}

$tmpArchive = Join-Path $env:TEMP ("network-routing-dist-{0}.tgz" -f ([guid]::NewGuid().ToString("N")))
$remoteArchive = "/tmp/$(Split-Path $tmpArchive -Leaf)"

try {
    Write-Host "Packing dist into $tmpArchive..."
    Invoke-Native tar -czf $tmpArchive -C $distPath "."

    Write-Host "Uploading archive to ${target}:${remoteArchive}..."
    Invoke-Native scp @sshArgs $tmpArchive "${target}:${remoteArchive}"

    Write-Host "Extracting on remote into $RemotePath..."
    $remoteCmd = "set -e; mkdir -p '$RemotePath'; find '$RemotePath' -mindepth 1 -maxdepth 1 ! -name 'status.json' ! -name 'history.jsonl' -exec rm -rf {} +; tar -xzf '$remoteArchive' -C '$RemotePath'; rm -f '$remoteArchive'; ls -la '$RemotePath' | head"
    Invoke-Native ssh @sshArgs $target $remoteCmd
}
finally {
    if (Test-Path $tmpArchive) {
        Remove-Item $tmpArchive -Force
    }
}

if ($Url) {
    Write-Host "Checking $Url..."
    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 10
        if ($response.StatusCode -lt 200 -or $response.StatusCode -ge 400) {
            throw "Unexpected HTTP status: $($response.StatusCode)"
        }
        Write-Host "HTTP $($response.StatusCode)"
    }
    catch {
        $fallback = "http://${HostName}/network-routing/"
        Write-Host "WARN: $Url failed ($($_.Exception.Message)); trying $fallback"
        $response = Invoke-WebRequest -Uri $fallback -UseBasicParsing -TimeoutSec 10
        Write-Host "HTTP $($response.StatusCode) ($fallback)"
    }
}

Write-Host "Deploy complete."
