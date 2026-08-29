#!/bin/bash
# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
# setup_proxy.sh  â€”  Install microsocks + cloudflared, start SOCKS5 proxy,
#                     run named Cloudflare tunnel, create DNS record, verify
#
# Required env vars:  PROXY_USER, PROXY_PASS, CLOUDFLARE_TUNNEL_TOKEN,
#                     CLOUDFLARE_API_TOKEN, CLOUDFLARE_ZONE_ID, MATRIX_ID
# Outputs:            TUNNEL_URL, PROXY_URL, RUNNER_IP
# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

set -euo pipefail

PROXY_HOST="proxies.filmfiend.me"
SUBDOMAIN="proxy-${MATRIX_ID}"
HOSTNAME="${SUBDOMAIN}.${PROXY_HOST}"

echo "â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”"
echo "  Proxy Runner #${MATRIX_ID} â€” Starting setup"
echo "  Target: $HOSTNAME"
echo "â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”"

# â”€â”€ 1. Install microsocks â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

# â”€â”€ 2. Install cloudflared â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
echo "[2/7] Installing cloudflared..."
if command -v cloudflared &>/dev/null; then
    echo "  [OK] cloudflared already installed"
else
    curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \
        -o /tmp/cloudflared
    sudo install -m 755 /tmp/cloudflared /usr/local/bin/cloudflared
    echo "  [OK] cloudflared installed"
fi

# â”€â”€ 3. Start SOCKS5 proxy â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
echo "[3/7] Starting SOCKS5 proxy on :1080..."
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

# â”€â”€ 4. Create DNS record via Cloudflare API â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
echo "[4/7] Creating DNS record: $HOSTNAME â†’ tunnel..."
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
            echo "  [WARN] Make sure DNS record exists: CNAME $HOSTNAME â†’ ${TUNNEL_UUID}.cfargotunnel.com"
        fi
    else
        echo "  [OK] DNS record already exists"
    fi
else
    echo "  [SKIP] No CLOUDFLARE_API_TOKEN / CLOUDFLARE_ZONE_ID set"
    echo "  [WARN] Ensure CNAME $HOSTNAME â†’ ${TUNNEL_UUID}.cfargotunnel.com exists"
fi

# â”€â”€ 5. Start Cloudflare named tunnel â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
echo "[5/7] Starting Cloudflare named tunnel..."
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

# â”€â”€ 6. Verify proxy works â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
echo "[6/7] Verifying proxy..."
TUNNEL_URL="https://${HOSTNAME}"
VERIFY_OUTPUT=$(curl -x "socks5h://${PROXY_USER}:${PROXY_PASS}@127.0.0.1:1080" \
    -s --max-time 15 \
    https://httpbin.org/ip 2>/dev/null || echo '{"error":"verify_failed"}')

RUNNER_IP=$(echo "$VERIFY_OUTPUT" | grep -oP '"origin":\s*"\K[^"]+' || echo "unknown")
echo "  [OK] Runner IP: $RUNNER_IP"

# â”€â”€ 7. Output results â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
PROXY_URL="socks5h://${PROXY_USER}:${PROXY_PASS}@${HOSTNAME}"

echo ""
echo "â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”"
echo "  PROXY READY"
echo "â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”"
echo "  Tunnel:  $TUNNEL_URL"
echo "  Proxy:   $PROXY_URL"
echo "  IP:      $RUNNER_IP"
echo "â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”"

# Write outputs for GitHub Actions
if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "TUNNEL_URL=$TUNNEL_URL" >> "$GITHUB_OUTPUT"
    echo "PROXY_URL=$PROXY_URL" >> "$GITHUB_OUTPUT"
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
| Proxy | \`$PROXY_URL\` |
| Runner IP | $RUNNER_IP |
| Created | $(date -u +"%Y-%m-%dT%H:%M:%SZ") |
EOF
fi
