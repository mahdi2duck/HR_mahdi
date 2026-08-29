# ─────────────────────────────────────────────────────────────────────────────
# start_tors.ps1  —  Launch all three Tor instances in separate windows
#
#  Instance | SOCKS port | Control port | Data dir
#  ─────────────────────────────────────────────────
#  tor 1    |  9050      |  9051        |  (default inside tor 1\data)
#  tor 2    |  9150      |  9151        |  tor2\  (already set in torrc)
#  tor 3    |  9250      |  9251        |  tor 3\data  (auto-created)
#
# Usage:  .\start_tors.ps1
# ─────────────────────────────────────────────────────────────────────────────

$base = "C:\Users\mahdi\Downloads\Compressed"

# ── Instance definitions ─────────────────────────────────────────────────────
$instances = @(
    @{
        label   = "Tor-1  [9050]"
        exe     = "$base\tor 1\tor\tor"
        torrc   = "$base\tor 1\torrc"
        dataDir = "$base\tor 1\data"
    },
    @{
        label   = "Tor-2  [9150]"
        exe     = "$base\tor 2\tor\tor"
        torrc   = "$base\tor 2\torrc"
        dataDir = "$base\tor2"          # DataDirectory already set in torrc
    },
    @{
        label   = "Tor-3  [9250]"
        exe     = "$base\tor 3\tor\tor"
        torrc   = "$base\tor 3\torrc"
        dataDir = "$base\tor 3\data"
    }
)

foreach ($inst in $instances) {
    # Create the data directory if it doesn't exist
    if (-not (Test-Path $inst.dataDir)) {
        New-Item -ItemType Directory -Path $inst.dataDir -Force | Out-Null
        Write-Host "[+] Created data dir: $($inst.dataDir)"
    }

    # Build the argument list
    $args = "-f `"$($inst.torrc)`" DataDirectory `"$($inst.dataDir)`""

    # Launch in a new, titled PowerShell window
    Start-Process -FilePath "powershell.exe" -ArgumentList `
        "-NoExit", "-Command", `
        "& Write-Host '[Tor] Starting $($inst.label)...' -ForegroundColor Cyan; & '$($inst.exe)' -f '$($inst.torrc)'" `
        -WindowStyle Normal

    Write-Host "[+] Launched: $($inst.label)"
    Start-Sleep -Milliseconds 500   # small stagger so circuits don't all bootstrap at once
}

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
Write-Host "  All Tor instances launched!" -ForegroundColor Green
Write-Host "  SOCKS proxies ready at:" -ForegroundColor Green
Write-Host "    127.0.0.1:9050  (Tor 1)" -ForegroundColor Yellow
Write-Host "    127.0.0.1:9150  (Tor 2)" -ForegroundColor Yellow
Write-Host "    127.0.0.1:9250  (Tor 3)" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
