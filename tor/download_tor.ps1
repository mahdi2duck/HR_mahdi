# ─────────────────────────────────────────────────────────────────────────────
# download_tor.ps1  —  Download & extract Tor Expert Bundle (Windows x86_64)
#
# Usage:  .\download_tor.ps1
# ─────────────────────────────────────────────────────────────────────────────

$ErrorActionPreference = "Stop"

$torVersion = "15.0.20"
$url = "https://www.torproject.org/dist/torbrowser/$torVersion/tor-expert-bundle-windows-x86_64-$torVersion.tar.gz"
$tarFile = "$PSScriptRoot\tor.tar.gz"
$torDir   = "$PSScriptRoot\tor"

Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "  Downloading Tor Expert Bundle v$torVersion" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan

# ── Skip if already downloaded ──────────────────────────────────────────────
if (Test-Path "$torDir\tor\tor.exe") {
    Write-Host "[OK] Tor already downloaded at $torDir\tor\tor.exe" -ForegroundColor Green
    exit 0
}

# ── Download ────────────────────────────────────────────────────────────────
Write-Host "[1/3] Downloading from $url ..."
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $url -OutFile $tarFile -UseBasicParsing
} catch {
    Write-Host "[-] Download failed: $_" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Downloaded $([math]::Round((Get-Item $tarFile).Length / 1MB, 1)) MB" -ForegroundColor Green

# ── Extract ─────────────────────────────────────────────────────────────────
Write-Host "[2/3] Extracting..."
if (Test-Path $torDir) { Remove-Item $torDir -Recurse -Force }

# tar.exe is built into Windows 10+
tar -xzf $tarFile -C $PSScriptRoot
if ($LASTEXITCODE -ne 0) {
    Write-Host "[-] tar extraction failed" -ForegroundColor Red
    exit 1
}

# ── Cleanup ─────────────────────────────────────────────────────────────────
Write-Host "[3/3] Cleaning up..."
Remove-Item $tarFile -Force

# ── Verify ──────────────────────────────────────────────────────────────────
if (Test-Path "$torDir\tor\tor.exe") {
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
    Write-Host "  Tor installed successfully!" -ForegroundColor Green
    Write-Host "  Location: $torDir\tor\tor.exe" -ForegroundColor Yellow
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
} else {
    # Some bundles extract to a flat structure — check alternative paths
    $torExe = Get-ChildItem -Path $PSScriptRoot -Filter "tor.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($torExe) {
        Write-Host ""
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
        Write-Host "  Tor installed successfully!" -ForegroundColor Green
        Write-Host "  Location: $($torExe.FullName)" -ForegroundColor Yellow
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
    } else {
        Write-Host "[-] tor.exe not found after extraction" -ForegroundColor Red
        Write-Host "    Check $torDir manually" -ForegroundColor Yellow
    }
}
