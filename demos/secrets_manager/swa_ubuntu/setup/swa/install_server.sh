#!/bin/bash
# install_server.sh — Install SWA Server binary, write config, and start systemd service.
# Run on the VM that hosts the SWA Server (same VM as the agent for this demo).
#
# Requires: swa_registered.env (created by register_control_plane.sh)
# Requires: sudo for binary install and systemd operations

# shellcheck disable=SC2059
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
REGISTERED_ENV="$SCRIPT_DIR/swa_registered.env"

# shellcheck disable=SC1091
source "$CYBR_DEMOS_PATH/demos/utility/ubuntu/identity_functions.sh"
# shellcheck disable=SC1091
source "$CYBR_DEMOS_PATH/demos/tenant_vars.sh"
# shellcheck disable=SC1091
source "$DEMO_DIR/setup/vars.env"

if [ ! -f "$REGISTERED_ENV" ]; then
  echo "ERROR: $REGISTERED_ENV not found." >&2
  echo "       Run register_control_plane.sh first." >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$REGISTERED_ENV"

SWA_INSTALL_DIR="/opt/swa/bin"
SWA_CONFIG_DIR="/etc/swa"
SWA_TRUST_ROOT="/var/swa/certs"
SWA_TOKEN_FILE="/etc/swa/token"
SWA_SERVER_BIN="${SWA_INSTALL_DIR}/swa-server"
CONJUR_URL="https://${TENANT_SUBDOMAIN}.secretsmgr.cyberark.cloud"

echo "=========================================="
echo "SWA Server Installation"
echo "=========================================="
echo ""
echo "  Trust domain:  $SWA_TRUST_DOMAIN_NAME"
echo "  Login URL:     $SWA_SERVER_LOGIN_URL"
echo "  Server port:   8081 (API)  8080 (web)"
echo ""

# --- Step 1: Install binary ---
echo "[1/5] Installing SWA Server binary..."

ARCH=$(uname -m)
case "$ARCH" in
  x86_64)  BIN_ARCH="linux_amd64" ;;
  aarch64) BIN_ARCH="linux_arm64" ;;
  *)       echo "ERROR: Unsupported architecture: $ARCH" >&2; exit 1 ;;
esac

S3_PATH="s3://mis-cybr-demos/pm/swa_binaries/swa-server_0.0.0-SNAPSHOT_${BIN_ARCH}/swa-server"

sudo mkdir -p "$SWA_INSTALL_DIR"

if [ -f "$SWA_SERVER_BIN" ]; then
  echo "      swa-server already installed — skipping download"
else
  echo "      Downloading from $S3_PATH..."
  aws s3 cp "$S3_PATH" /tmp/swa-server
  sudo mv /tmp/swa-server "$SWA_SERVER_BIN"
fi

sudo chmod +x "$SWA_SERVER_BIN"
echo "      $SWA_SERVER_BIN   OK"
echo ""

# --- Step 2: Create config directory and copy x509pop certs ---
echo "[2/5] Creating config directory and installing x509pop certs..."
sudo mkdir -p "$SWA_CONFIG_DIR"
sudo mkdir -p "$SWA_TRUST_ROOT"

sudo cp "$SWA_X509POP_CA_CERT"    "$SWA_CONFIG_DIR/x509pop_ca.pem"
sudo cp "$SWA_X509POP_AGENT_CERT" "$SWA_CONFIG_DIR/x509pop.pem"
sudo cp "$SWA_X509POP_AGENT_KEY"  "$SWA_CONFIG_DIR/x509pop.key"
sudo chmod 600 "$SWA_CONFIG_DIR/x509pop.key"
echo "      $SWA_CONFIG_DIR   OK"
echo ""

# --- Step 3: Write bootstrapConfig.yaml ---
echo "[3/5] Writing bootstrapConfig.yaml..."
sudo tee "$SWA_CONFIG_DIR/bootstrapConfig.yaml" > /dev/null <<EOF
trustDomain:
  name: ${SWA_TRUST_DOMAIN_NAME}
controlPlane:
  url: ${CONJUR_URL}/api
  useVCP: false
  syncInterval: 15m
  auth:
    type: jwt
    loginURL: ${SWA_SERVER_LOGIN_URL}
    tokenPath: ${SWA_TOKEN_FILE}
server:
  apiAddr: 0.0.0.0:8081
  webAddr: 0.0.0.0:8080
  trustRootDir: ${SWA_TRUST_ROOT}
telemetry:
  logging:
    level: info
EOF
echo "      $SWA_CONFIG_DIR/bootstrapConfig.yaml   OK"
echo ""

# --- Step 4: Write initial ISP token to tokenPath ---
# The SWA Server reads this JWT to authenticate to Conjur at startup.
# A systemd timer (swa-token-refresh) refreshes it before expiry.
echo "[4/5] Writing initial ISP token to $SWA_TOKEN_FILE..."
isp_token=$(get_identity_token "$TENANT_ID" "$CLIENT_ID" "$CLIENT_SECRET")
echo "$isp_token" | sudo tee "$SWA_TOKEN_FILE" > /dev/null
sudo chmod 600 "$SWA_TOKEN_FILE"
echo "      $SWA_TOKEN_FILE   OK"
echo ""

# --- Step 5: Install and start systemd service ---
echo "[5/5] Installing and starting swa-server systemd service..."

sudo tee /etc/systemd/system/swa-server.service > /dev/null <<EOF
[Unit]
Description=SWA Server
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=${SWA_SERVER_BIN} run --configDir ${SWA_CONFIG_DIR}
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=swa-server

[Install]
WantedBy=multi-user.target
EOF

# Write credentials to a secure env file — values are single-quoted so systemd
# EnvironmentFile does not truncate at '#' or other special characters.
# (systemd treats unquoted '#' as a comment delimiter; single-quoted values are literal.)
{
  printf 'TENANT_ID=%s\n'         "${TENANT_ID}"
  printf 'CLIENT_ID=%s\n'         "${CLIENT_ID}"
  printf "CLIENT_SECRET='%s'\n"   "${CLIENT_SECRET}"
  printf 'CYBR_DEMOS_PATH=%s\n'   "${CYBR_DEMOS_PATH}"
  printf 'SWA_TOKEN_FILE=%s\n'    "${SWA_TOKEN_FILE}"
} | sudo tee /etc/swa/refresh.env > /dev/null
sudo chmod 600 /etc/swa/refresh.env

# Token refresh timer — ISP tokens expire in ~15 min; refresh every 10 min to stay ahead
sudo tee /etc/systemd/system/swa-token-refresh.service > /dev/null <<EOF
[Unit]
Description=Refresh SWA Server ISP token

[Service]
Type=oneshot
EnvironmentFile=/etc/swa/refresh.env
ExecStart=/bin/bash -c 'source \${CYBR_DEMOS_PATH}/demos/utility/ubuntu/identity_functions.sh && get_identity_token "\${TENANT_ID}" "\${CLIENT_ID}" "\${CLIENT_SECRET}" > \${SWA_TOKEN_FILE} && chmod 600 \${SWA_TOKEN_FILE}'
EOF

sudo tee /etc/systemd/system/swa-token-refresh.timer > /dev/null <<EOF
[Unit]
Description=Refresh SWA Server ISP token every 10 minutes

[Timer]
OnBootSec=1min
OnUnitActiveSec=10min

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable swa-server
sudo systemctl enable swa-token-refresh.timer
sudo systemctl start swa-token-refresh.timer
sudo systemctl restart swa-server

# Wait briefly and check status
sleep 3
echo ""
if sudo systemctl is-active --quiet swa-server; then
  echo "      swa-server   RUNNING   OK"
  echo "      Port 8081:   $(sudo ss -tlnp | grep ':8081' | awk '{print $4}' || echo 'listening')"
else
  echo "      ERROR: swa-server failed to start"
  sudo journalctl -u swa-server -n 20 --no-pager >&2
  exit 1
fi

echo ""
echo "=========================================="
echo "SWA Server installation complete."
echo ""
echo "Verify:  sudo systemctl status swa-server"
echo "Logs:    sudo journalctl -u swa-server -f"
echo "Port:    sudo ss -tlnp | grep ':8081'"
echo "=========================================="
