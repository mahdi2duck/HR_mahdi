#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# setup_proxy.sh  —  Install microsocks + cloudflared, start SOCKS5 proxy,
#                     run named Cloudflare tunnel, create DNS record, verify
#
# Required env vars:  PROXY_USER, PROXY_PASS, CLOUDFLARE_TUNNEL_TOKEN,
#                     CLOUDFLARE_API_TOKEN, CLOUDFLARE_ZONE_ID, MATRIX_ID
# Outputs:            TUNNEL_URL, PROXY_URL, RUNNER_IP
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

PROXY_HOST="proxies.filmfiend.me"
SUBDOMAIN="proxy-${MATRIX_ID}"
HOSTNAME="${SUBDOMAIN}.${PROXY_HOST}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Proxy Runner #${MATRIX_ID} — Starting setup"
echo "  Target: $HOSTNAME"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── 1. Install microsocks ────────────────────────────────────────────────────
echo "[1/7] Installing microsocks..."
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
echo "[2/7] Installing cloudflared..."
if command -v cloudflared &>/dev/null; then
    echo "  [OK] cloudflared already installed"
else
    curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \
        -o /tmp/cloudflared
    sudo install -m 755 /tmp/cloudflared /usr/local/bin/cloudflared
    echo "  [OK] cloudflared installed"
fi

# ── 3. Start SOCKS5 proxy ────────────────────────────────────────────────────
echo "[3/8] Starting SOCKS5 proxy on :1080..."
pkill microsocks 2>/dev/null || true
sleep 1

microsocks -1 -u "$PROXY_USER" -P "$PROXY_PASS" -i 0.0.0.0 -p 1080 2>/tmp/microsocks.err &
MICROSOCKS_PID=$!
sleep 2

if kill -0 "$MICROSOCKS_PID" 2>/dev/null; then
    echo "  [OK] microsocks running (PID: $MICROSOCKS_PID)"
else
    echo "  [FAIL] microsocks failed to start"
    cat /tmp/microsocks.err 2>/dev/null || true
    exit 1
fi

# ── 4. Install & start tinyproxy (HTTP proxy for Playwright) ─────────────────
echo "[4/8] Installing tinyproxy..."
sudo apt-get install -y -qq tinyproxy 2>/dev/null || true

# Configure tinyproxy: listen on 0.0.0.0:8080, allow local + all
cat > /tmp/tinyproxy.conf <<'TPCONF'
Port 8080
Listen 0.0.0.0
Timeout 600
Allow 0.0.0.0/0
Upstream socks5 127.0.0.1:1080
TPCONF

pkill tinyproxy 2>/dev/null || true
sleep 1
sudo cp /tmp/tinyproxy.conf /etc/tinyproxy/tinyproxy.conf 2>/dev/null || \
    sudo cp /tmp/tinyproxy.conf /etc/tinyproxy.conf 2>/dev/null || true
sudo tinyproxy 2>/tmp/tinyproxy.err &
TINYPROXY_PID=$!
sleep 2

if kill -0 "$TINYPROXY_PID" 2>/dev/null; then
    echo "  [OK] tinyproxy running on :8080 (PID: $TINYPROXY_PID)"
else
    echo "  [WARN] tinyproxy failed, falling back to microsocks-only"
    cat /tmp/tinyproxy.err 2>/dev/null || true
fi

# ── 5. Create DNS record via Cloudflare API ──────────────────────────────────
echo "[5/8] Creating DNS record: $HOSTNAME → tunnel..."
TUNNEL_UUID="71d6f80e-10ad-4618-9996-b919a1a88443"

if [ -n "${CLOUDFLARE_API_TOKEN:-}" ] && [ -n "${CLOUDFLARE_ZONE_ID:-}" ]; then
    # Check if record already exists
    EXISTING=$(curl -s -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?type=CNAME&name=${HOSTNAME}" \
        2>/dev/null || echo '{"result":[]}')

    RECORD_COUNT=$(echo "$EXISTING" | grep -oP '"total_count":\s*\K\d+' || echo "0")

    if [ "$RECORD_COUNT" = "0" ]; then
        DNS_RESP=$(curl -s -X POST \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            -H "Content-Type: application/json" \
            "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
            -d "{
                \"type\": \"CNAME\",
                \"name\": \"${SUBDOMAIN}\",
                \"content\": \"${TUNNEL_UUID}.cfargotunnel.com\",
                \"ttl\": 1,
                \"proxied\": true
            }" 2>/dev/null || echo '{"success":false}')

        if echo "$DNS_RESP" | grep -q '"success":true'; then
            echo "  [OK] DNS record created: $HOSTNAME"
        else
            echo "  [WARN] DNS creation failed (code: $(echo "$DNS_RESP" | grep -oP '"code":\s*\K\d+' || echo '?'))"
            echo "  [WARN] Make sure DNS record exists: CNAME $HOSTNAME → ${TUNNEL_UUID}.cfargotunnel.com"
        fi
    else
        echo "  [OK] DNS record already exists"
    fi
else
    echo "  [SKIP] No CLOUDFLARE_API_TOKEN / CLOUDFLARE_ZONE_ID set"
    echo "  [WARN] Ensure CNAME $HOSTNAME → ${TUNNEL_UUID}.cfargotunnel.com exists"
fi

# ── 6. Start Cloudflare named tunnel ─────────────────────────────────────────
echo "[6/8] Starting Cloudflare named tunnel..."
pkill cloudflared 2>/dev/null || true
sleep 1

CF_LOG="/tmp/cloudflared.log"
cloudflared tunnel --no-autoupdate --logfile "$CF_LOG" run --token "$CLOUDFLARE_TUNNEL_TOKEN" &
CF_PID=$!
echo "  cloudflared PID: $CF_PID"

# Wait for tunnel to register
echo "  Waiting for tunnel to connect..."
sleep 5

if ! kill -0 "$CF_PID" 2>/dev/null; then
    echo "  [FAIL] cloudflared exited immediately"
    cat "$CF_LOG" 2>/dev/null || true
    exit 1
fi

echo "  [OK] cloudflared running"

# ── 7. Verify proxy works ────────────────────────────────────────────────────
echo "[7/8] Verifying proxy..."
TUNNEL_URL="https://${HOSTNAME}"
VERIFY_OUTPUT=$(curl -x "socks5h://${PROXY_USER}:${PROXY_PASS}@127.0.0.1:1080" \
    -s --max-time 15 \
    https://httpbin.org/ip 2>/dev/null || echo '{"error":"verify_failed"}')

RUNNER_IP=$(echo "$VERIFY_OUTPUT" | grep -oP '"origin":\s*"\K[^"]+' || echo "unknown")
echo "  [OK] Runner IP: $RUNNER_IP"

# ── 8. Output results ────────────────────────────────────────────────────────
PROXY_URL_SOCKS="socks5h://${PROXY_USER}:${PROXY_PASS}@${HOSTNAME}"
PROXY_URL_HTTP="http://${HOSTNAME}"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  PROXY READY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Tunnel:  $TUNNEL_URL"
echo "  HTTP:    $PROXY_URL_HTTP"
echo "  SOCKS5:  $PROXY_URL_SOCKS"
echo "  IP:      $RUNNER_IP"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Write outputs for GitHub Actions
if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "TUNNEL_URL=$TUNNEL_URL" >> "$GITHUB_OUTPUT"
    echo "PROXY_URL=$PROXY_URL_HTTP" >> "$GITHUB_OUTPUT"
    echo "PROXY_URL_SOCKS=$PROXY_URL_SOCKS" >> "$GITHUB_OUTPUT"
    echo "RUNNER_IP=$RUNNER_IP" >> "$GITHUB_OUTPUT"
fi

# Write to job summary if available
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    cat >> "$GITHUB_STEP_SUMMARY" <<EOF
## Proxy #${MATRIX_ID}

| Field | Value |
|-------|-------|
| Hostname | \`$HOSTNAME\` |
| Tunnel | $TUNNEL_URL |
| HTTP Proxy | \`$PROXY_URL_HTTP\` |
| SOCKS5 Proxy | \`$PROXY_URL_SOCKS\` |
| Runner IP | $RUNNER_IP |
| Created | $(date -u +"%Y-%m-%dT%H:%M:%SZ") |
EOF
fi
