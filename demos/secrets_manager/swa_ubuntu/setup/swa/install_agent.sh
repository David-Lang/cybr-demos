#!/bin/bash
# install_agent.sh — Install SWA Agent binary, write config, and start systemd service.
# Run on the same VM as the SWA Server (co-located for this demo).
#
# Requires: swa_registered.env (created by register_control_plane.sh)
# Requires: sudo for binary install and systemd operations

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
REGISTERED_ENV="$SCRIPT_DIR/swa_registered.env"

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
SWA_SOCKET_DIR="/run/swa-agent"
SWA_AGENT_CONFIG="$SWA_CONFIG_DIR/agentConfig.yaml"
SWA_AGENT_BIN_PATH="${SWA_INSTALL_DIR}/swa-agent"

echo "=========================================="
echo "SWA Agent Installation"
echo "=========================================="
echo ""
echo "  Trust domain:  $SWA_TRUST_DOMAIN_NAME"
echo "  Server:        ${SWA_SERVER_HOST}:8081"
echo "  Socket:        ${SWA_SOCKET_DIR}/api.sock"
echo ""

# --- Step 1: Install binary ---
echo "[1/4] Installing SWA Agent binary..."

ARCH=$(uname -m)
case "$ARCH" in
  x86_64)  BIN_ARCH="linux_amd64" ;;
  aarch64) BIN_ARCH="linux_arm64" ;;
  *)       echo "ERROR: Unsupported architecture: $ARCH" >&2; exit 1 ;;
esac

S3_PATH="s3://mis-cybr-demos/pm/swa_binaries/swa-agent_0.0.0-SNAPSHOT_${BIN_ARCH}/swa-agent"

sudo mkdir -p "$SWA_INSTALL_DIR"

if [ -f "$SWA_AGENT_BIN_PATH" ]; then
  echo "      swa-agent already installed — skipping download"
else
  echo "      Downloading from $S3_PATH..."
  aws s3 cp "$S3_PATH" /tmp/swa-agent
  sudo mv /tmp/swa-agent "$SWA_AGENT_BIN_PATH"
fi

sudo chmod +x "$SWA_AGENT_BIN_PATH"
echo "      $SWA_AGENT_BIN_PATH   OK"
echo ""

# --- Step 2: Copy x509pop certs ---
echo "[2/4] Installing x509pop agent certs..."
sudo mkdir -p "$SWA_CONFIG_DIR"

sudo cp "$SWA_X509POP_AGENT_CERT" "$SWA_CONFIG_DIR/x509pop.pem"
sudo cp "$SWA_X509POP_AGENT_KEY"  "$SWA_CONFIG_DIR/x509pop.key"
sudo chmod 600 "$SWA_CONFIG_DIR/x509pop.key"
echo "      $SWA_CONFIG_DIR/x509pop.pem   OK"
echo ""

# --- Step 3: Write agentConfig.yaml ---
echo "[3/4] Writing agentConfig.yaml..."
sudo tee "$SWA_AGENT_CONFIG" > /dev/null <<EOF
trustDomain:
  name: ${SWA_TRUST_DOMAIN_NAME}
servers:
  - addr: ${SWA_SERVER_HOST}:8081
agent:
  socketPath: ${SWA_SOCKET_DIR}/api.sock
  key:
    type: ECP256
    ttl: 1h
  nodeAttestor:
    type: x509pop
    config:
      cert: ${SWA_CONFIG_DIR}/x509pop.pem
      key: ${SWA_CONFIG_DIR}/x509pop.key
workload:
  key:
    type: ECP256
    ttl: 1h
  attestors:
    - type: unix
telemetry:
  logging:
    level: info
EOF
echo "      $SWA_AGENT_CONFIG   OK"
echo ""

# --- Step 4: Install and start systemd service ---
echo "[4/4] Installing and starting swa-agent systemd service..."

sudo tee /etc/systemd/system/swa-agent.service > /dev/null <<EOF
[Unit]
Description=SWA Agent
After=network-online.target swa-server.service
Wants=network-online.target
Requires=swa-server.service

[Service]
RuntimeDirectory=swa-agent
RuntimeDirectoryMode=0755
ExecStart=${SWA_AGENT_BIN_PATH} run --configDir ${SWA_CONFIG_DIR} --config ${SWA_AGENT_CONFIG}
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=swa-agent

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable swa-agent
sudo systemctl restart swa-agent

sleep 5
echo ""
if sudo systemctl is-active --quiet swa-agent; then
  echo "      swa-agent   RUNNING   OK"
  if [ -S "${SWA_SOCKET_DIR}/api.sock" ]; then
    echo "      Socket:     ${SWA_SOCKET_DIR}/api.sock   OK"
  else
    echo "      WARNING: Socket not yet present — agent may still be attesting"
  fi
else
  echo "      ERROR: swa-agent failed to start"
  sudo journalctl -u swa-agent -n 20 --no-pager >&2
  exit 1
fi

echo ""
echo "=========================================="
echo "SWA Agent installation complete."
echo ""
echo "Verify:  sudo systemctl status swa-agent"
echo "Logs:    sudo journalctl -u swa-agent -f"
echo "Socket:  ls -la ${SWA_SOCKET_DIR}/api.sock"
echo "=========================================="
