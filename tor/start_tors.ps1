# ─────────────────────────────────────────────────────────────────────────────
# start_tors.ps1  —  Launch 3 Tor instances in separate windows
#
#  Instance | SOCKS port | Control port | Data dir
#  ─────────────────────────────────────────────────
#  tor 1    |  9050      |  9051        |  tor_instances\tor1
#  tor 2    |  9150      |  9151        |  tor_instances\tor2
#  tor 3    |  9250      |  9251        |  tor_instances\tor3
#
# Usage:  .\start_tors.ps1
# ─────────────────────────────────────────────────────────────────────────────

$ErrorActionPreference = "Stop"

$baseDir   = Split-Path -Parent $PSScriptRoot
$torExe    = "$PSScriptRoot\tor\tor.exe"
$password  = "mahdi2019"
$instances = @(
    @{ socks = 9050; control = 9051; label = "Tor-1 [9050]"; dataDir = "$PSScriptRoot\tor_instances\tor1" },
    @{ socks = 9150; control = 9151; label = "Tor-2 [9150]"; dataDir = "$PSScriptRoot\tor_instances\tor2" },
    @{ socks = 9250; control = 9251; label = "Tor-3 [9250]"; dataDir = "$PSScriptRoot\tor_instances\tor3" }
)

# ── Verify tor.exe exists ───────────────────────────────────────────────────
if (-not (Test-Path $torExe)) {
    Write-Host "[-] tor.exe not found at $torExe" -ForegroundColor Red
    Write-Host "    Run download_tor.ps1 first" -ForegroundColor Yellow
    exit 1
}

# ── Generate hashed control password ────────────────────────────────────────
Write-Host "[*] Generating hashed control password..." -ForegroundColor Cyan
$hashOutput = & $torExe --hash-password $password 2>&1
$hashLine = ($hashOutput | Where-Object { $_ -match "16:" } | Select-Object -Last 1)
if (-not $hashLine) {
    Write-Host "[-] Failed to generate hashed password" -ForegroundColor Red
    Write-Host "    Output: $hashOutput" -ForegroundColor Yellow
    exit 1
}
Write-Host "[OK] Hash: $hashLine" -ForegroundColor Green

# ── Kill any existing Tor processes on our ports ────────────────────────────
Write-Host "[*] Checking for existing Tor processes..."
foreach ($inst in $instances) {
    $existing = Get-NetTCPConnection -LocalPort $inst.socks -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty OwningProcess -Unique
    if ($existing) {
        foreach ($pid in $existing) {
            $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
            if ($proc -and $proc.ProcessName -match "tor") {
                Write-Host "    Killing existing Tor on port $($inst.socks) (PID: $pid)" -ForegroundColor Yellow
                Stop-Process -Id $pid -Force
            }
        }
    }
}

# ── Create data directories and torrc configs ───────────────────────────────
Write-Host "[*] Creating directories and configs..."
foreach ($inst in $instances) {
    if (-not (Test-Path $inst.dataDir)) {
        New-Item -ItemType Directory -Path $inst.dataDir -Force | Out-Null
    }

    # Convert backslashes to forward slashes for Tor (avoids escape sequence errors)
    $dataDirFwd = $inst.dataDir -replace '\\', '/'
    $torrc = @"
SocksPort $($inst.socks)
ControlPort $($inst.control)
HashedControlPassword $hashLine
DataDirectory $dataDirFwd
PidFile $dataDirFwd/tor.pid
Log notice stdout
"@
    $torrcPath = "$PSScriptRoot\torrc_$($inst.socks)"
    [System.IO.File]::WriteAllText($torrcPath, $torrc, [System.Text.UTF8Encoding]::new($false))
}

# ── Start all 3 instances in separate windows ───────────────────────────────
Write-Host "[*] Starting Tor instances..."
foreach ($inst in $instances) {
    $torrcPath = "$PSScriptRoot\torrc_$($inst.socks)"

    Start-Process -FilePath "powershell.exe" -ArgumentList `
        "-NoExit", "-Command", `
        "& Write-Host '[Tor] Starting $($inst.label)...' -ForegroundColor Cyan; & '$torExe' -f '$torrcPath'; Read-Host 'Press Enter to close'" `
        -WindowStyle Normal

    Write-Host "[+] Launched: $($inst.label)" -ForegroundColor Green
    Start-Sleep -Milliseconds 500
}

# ── Wait for SOCKS ports ───────────────────────────────────────────────────
Write-Host ""
Write-Host "[*] Waiting for SOCKS ports to be ready..."
$maxWait = 60
foreach ($inst in $instances) {
    $ready = $false
    for ($i = 0; $i -lt $maxWait; $i++) {
        $conn = Test-NetConnection -ComputerName 127.0.0.1 -Port $inst.socks -WarningAction SilentlyContinue
        if ($conn.TcpTestSucceeded) {
            $ready = $true
            break
        }
        Start-Sleep -Seconds 1
    }
    if ($ready) {
        Write-Host "[OK] $($inst.label) ready" -ForegroundColor Green
    } else {
        Write-Host "[-] $($inst.label) failed to start (${maxWait}s timeout)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
Write-Host "  All Tor instances launched!" -ForegroundColor Green
Write-Host "  SOCKS proxies ready at:" -ForegroundColor Green
Write-Host "    127.0.0.1:9050  (Tor 1)" -ForegroundColor Yellow
Write-Host "    127.0.0.1:9150  (Tor 2)" -ForegroundColor Yellow
Write-Host "    127.0.0.1:9250  (Tor 3)" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
