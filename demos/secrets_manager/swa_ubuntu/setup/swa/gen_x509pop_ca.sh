#!/bin/bash
# Generates x509pop CA key/cert and a signed agent cert for SWA node attestation.
# Run before Terraform — the CA cert is passed to swa_server_group.
# Idempotent: skips generation if CA key already exists.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CA_KEY="$SCRIPT_DIR/x509pop_ca.key"
CA_CERT="$SCRIPT_DIR/x509pop_ca.pem"
AGENT_KEY="$SCRIPT_DIR/x509pop_agent.key"
AGENT_CERT="$SCRIPT_DIR/x509pop_agent.pem"

SUBJECT_CN="${1:-swa-demo-node}"
DAYS="${2:-365}"

if [ -f "$CA_KEY" ]; then
  echo "      x509pop CA already exists — skipping"
  echo "      Delete $CA_KEY to regenerate"
  exit 0
fi

echo "      Generating x509pop CA..."
openssl genrsa -out "$CA_KEY" 2048 2>/dev/null
openssl req -new -x509 -key "$CA_KEY" -out "$CA_CERT" -days "$DAYS" \
  -subj "/CN=swa-x509pop-ca/O=swa-demo" 2>/dev/null
chmod 600 "$CA_KEY"

echo "      Generating agent cert (CN=${SUBJECT_CN})..."
openssl genrsa -out "$AGENT_KEY" 2048 2>/dev/null
openssl req -new -key "$AGENT_KEY" -subj "/CN=${SUBJECT_CN}" \
  | openssl x509 -req \
      -CA "$CA_CERT" -CAkey "$CA_KEY" -CAcreateserial \
      -out "$AGENT_CERT" -days "$DAYS" 2>/dev/null
chmod 600 "$AGENT_KEY"

echo "      x509pop certs:"
echo "        CA cert:     $CA_CERT"
echo "        CA key:      $CA_KEY"
echo "        Agent cert:  $AGENT_CERT"
echo "        Agent key:   $AGENT_KEY"
