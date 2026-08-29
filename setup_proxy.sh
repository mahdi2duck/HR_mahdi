#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# setup_proxy.sh  —  Install microsocks + cloudflared, start SOCKS5 proxy,
#                     create Cloudflare quick tunnel, verify, output URL
#
# Required env vars:  PROXY_USER, PROXY_PASS
# Outputs:            TUNNEL_URL, PROXY_URL, RUNNER_IP
# ─────────────────────────────────────────────────────────────────────────────

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Proxy Runner — Starting setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── 1. Install microsocks ────────────────────────────────────────────────────
echo "[1/6] Installing microsocks..."
if command -v microsocks &>/dev/null; then
    echo "  [OK] microsocks already installed"
else
    sudo apt-get update -qq 2>/dev/null
    sudo apt-get install -y -qq microsocks 2>/dev/null || {
        echo "  [APT FAIL] Building from source..."
        sudo apt-get install -y -qq build-essential git 2>/dev/null
        cd /tmp && git clone https://github.com/rofl0r/microsocks.git 2>/dev/null
        cd /tmp/microsocks && make 2>/dev/null
        sudo install -m 755 microsocks /usr/local/bin/microsocks
    }
    echo "  [OK] microsocks installed"
fi

# ── 2. Install cloudflared ───────────────────────────────────────────────────
echo "[2/6] Installing cloudflared..."
if command -v cloudflared &>/dev/null; then
    echo "  [OK] cloudflared already installed"
else
    curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \
        -o /tmp/cloudflared
    sudo install -m 755 /tmp/cloudflared /usr/local/bin/cloudflared
    echo "  [OK] cloudflared installed"
fi

# ── 3. Start SOCKS5 proxy ────────────────────────────────────────────────────
echo "[3/6] Starting SOCKS5 proxy on :1080..."
pkill microsocks 2>/dev/null || true
sleep 1

# Start microsocks and capture stderr for debugging
microsocks -1 -q -u "$PROXY_USER" -P "$PROXY_PASS" -i 0.0.0.0 -p 1080 2>/tmp/microsocks.err &
MICROSOCKS_PID=$!
sleep 2

if kill -0 "$MICROSOCKS_PID" 2>/dev/null; then
    echo "  [OK] microsocks running (PID: $MICROSOCKS_PID)"
else
    echo "  [FAIL] microsocks failed to start"
    echo "  [DEBUG] Error output:"
    cat /tmp/microsocks.err 2>/dev/null || echo "  (no error output)"
    echo "  [DEBUG] Checking port 1080:"
    ss -tlnp | grep 1080 || echo "  (port 1080 not in use)"
    echo "  [DEBUG] microsocks binary:"
    which microsocks || echo "  (not found)"
    exit 1
fi

# ── 4. Start Cloudflare quick tunnel ─────────────────────────────────────────
echo "[4/6] Starting Cloudflare quick tunnel..."
pkill cloudflared 2>/dev/null || true
sleep 1

CF_LOG="/tmp/cloudflared.log"
cloudflared tunnel --no-autoupdate --url "socks5://localhost:1080" >"$CF_LOG" 2>&1 &
CF_PID=$!
echo "  cloudflared PID: $CF_PID"

# ── 5. Parse tunnel URL ──────────────────────────────────────────────────────
echo "[5/6] Waiting for tunnel URL..."
TUNNEL_URL=""
MAX_RETRIES=60

for i in $(seq 1 $MAX_RETRIES); do
    TUNNEL_URL=$(grep -oP 'https://[a-z0-9-]+\.trycloudflare\.com' "$CF_LOG" 2>/dev/null | head -1 || true)

    if [ -n "$TUNNEL_URL" ]; then
        break
    fi

    if ! kill -0 "$CF_PID" 2>/dev/null; then
        echo "  [WARN] cloudflared exited, checking for rate limit..."
        if grep -q "429" "$CF_LOG" 2>/dev/null; then
            echo "  [RATE LIMITED] Waiting 30s before retry..."
            sleep 30
            cloudflared tunnel --no-autoupdate --url "socks5://localhost:1080" >"$CF_LOG" 2>&1 &
            CF_PID=$!
        else
            echo "  [FAIL] cloudflared died unexpectedly"
            cat "$CF_LOG"
            exit 1
        fi
    fi

    sleep 1
    echo "  Waiting... ($i/$MAX_RETRIES)"
done

if [ -z "$TUNNEL_URL" ]; then
    echo "  [FAIL] Could not get tunnel URL after ${MAX_RETRIES}s"
    cat "$CF_LOG"
    exit 1
fi

echo "  [OK] Tunnel URL: $TUNNEL_URL"

# ── 6. Verify proxy works ────────────────────────────────────────────────────
echo "[6/6] Verifying proxy..."
VERIFY_OUTPUT=$(curl -x "socks5h://${PROXY_USER}:${PROXY_PASS}@127.0.0.1:1080" \
    -s --max-time 15 \
    https://httpbin.org/ip 2>/dev/null || echo '{"error":"verify_failed"}')

RUNNER_IP=$(echo "$VERIFY_OUTPUT" | grep -oP '"origin":\s*"\K[^"]+' || echo "unknown")
echo "  [OK] Runner IP: $RUNNER_IP"

# ── Output results ───────────────────────────────────────────────────────────
PROXY_URL="socks5h://${PROXY_USER}:${PROXY_PASS}@$(echo "$TUNNEL_URL" | sed 's|https://||')"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  PROXY READY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Tunnel:  $TUNNEL_URL"
echo "  Proxy:   $PROXY_URL"
echo "  IP:      $RUNNER_IP"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Write outputs for GitHub Actions
if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "TUNNEL_URL=$TUNNEL_URL" >> "$GITHUB_OUTPUT"
    echo "PROXY_URL=$PROXY_URL" >> "$GITHUB_OUTPUT"
    echo "RUNNER_IP=$RUNNER_IP" >> "$GITHUB_OUTPUT"
fi

# Write to job summary if available
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    cat >> "$GITHUB_STEP_SUMMARY" <<EOF
## Proxy #${MATRIX_ID:-?}

| Field | Value |
|-------|-------|
| Tunnel | $TUNNEL_URL |
| Proxy | \`$PROXY_URL\` |
| Runner IP | $RUNNER_IP |
| Created | $(date -u +"%Y-%m-%dT%H:%M:%SZ") |
EOF
fi
