#!/bin/bash
# Generates RSA key pair and JWKS JSON for mock SWA agent.
# Output: mock_private.pem, mock_public.pem, mock_jwks.json
# DEV/TEST ONLY — NOT FOR CUSTOMER USE

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PRIVATE_KEY="$SCRIPT_DIR/mock_private.pem"
PUBLIC_KEY="$SCRIPT_DIR/mock_public.pem"
JWKS_FILE="$SCRIPT_DIR/mock_jwks.json"

if [ -f "$PRIVATE_KEY" ]; then
  echo "      Mock keys already exist — skipping generation"
  echo "      Delete $PRIVATE_KEY to regenerate"
  exit 0
fi

echo "      Generating RSA 2048 key pair..."
openssl genrsa -out "$PRIVATE_KEY" 2048 2>/dev/null
openssl rsa -in "$PRIVATE_KEY" -pubout -out "$PUBLIC_KEY" 2>/dev/null
chmod 600 "$PRIVATE_KEY"

echo "      Building JWKS JSON..."
python3 - "$PRIVATE_KEY" "$JWKS_FILE" <<'PYEOF'
import sys, json, base64

private_key_path = sys.argv[1]
jwks_out_path = sys.argv[2]

# Use openssl to extract modulus and exponent
import subprocess

modulus_hex = subprocess.check_output(
    ["openssl", "rsa", "-in", private_key_path, "-noout", "-modulus"],
    stderr=subprocess.DEVNULL
).decode().strip().replace("Modulus=", "")

# Exponent is always 65537 (AQAB) for keys generated with openssl genrsa
exponent = 65537

def int_to_b64url(n):
    hex_n = hex(n)[2:]
    if len(hex_n) % 2:
        hex_n = "0" + hex_n
    return base64.urlsafe_b64encode(bytes.fromhex(hex_n)).rstrip(b"=").decode()

n_b64 = int_to_b64url(int(modulus_hex, 16))
e_b64 = int_to_b64url(exponent)

# Conjur public-keys envelope format
jwks = {
    "type": "jwks",
    "value": {
        "keys": [{
            "kty": "RSA",
            "use": "sig",
            "alg": "RS256",
            "kid": "mock-swa-key-1",
            "n": n_b64,
            "e": e_b64
        }]
    }
}

with open(jwks_out_path, "w") as f:
    json.dump(jwks, f)

print(f"      JWKS written to {jwks_out_path}")
PYEOF

echo "      Keys generated:"
echo "        Private: $PRIVATE_KEY"
echo "        Public:  $PUBLIC_KEY"
echo "        JWKS:    $JWKS_FILE"
