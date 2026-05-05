#!/bin/bash
# shellcheck disable=SC2059
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# --- Source utilities and variables ---
# shellcheck disable=SC1091
source "$CYBR_DEMOS_PATH/demos/utility/ubuntu/ansi_colors.sh"
# shellcheck disable=SC1091
source "$CYBR_DEMOS_PATH/demos/utility/ubuntu/demo_utility.sh"
# shellcheck disable=SC1091
source "$CYBR_DEMOS_PATH/demos/tenant_vars.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/setup/vars.env"

# --- Validate required variables ---
required_vars=(TENANT_SUBDOMAIN CONJUR_ACCOUNT CONJUR_JWT_SERVICE_ID SWA_WORKLOAD_ID SWA_AGENT_BIN)
for var_name in "${required_vars[@]}"; do
  if [ -z "${!var_name:-}" ]; then
    printf "${Red}ERROR:${Color_Off} Missing required variable: %s\n" "$var_name" >&2
    exit 1
  fi
done

CONJUR_URL="https://${TENANT_SUBDOMAIN}.secretsmgr.cyberark.cloud/api"
AUTHN_URL="${CONJUR_URL}/authn-jwt/${CONJUR_JWT_SERVICE_ID}/${CONJUR_ACCOUNT}/authenticate"
SECRET_URL="${CONJUR_URL}/secrets/${CONJUR_ACCOUNT}/variable"

print_line

printf "${BWhite}Demo: Secrets Manager — Secure Workload Access${Color_Off}\n"
printf "${BWhite}Workload authenticates using identity, not a static credential.${Color_Off}\n"
print_line

# =============================================================================
# Scene 1 — No hardcoded credentials
# =============================================================================
printf "${BCyan}[1/8]${Color_Off} Checking workload script for hardcoded credentials...\n\n"

print_prompt "grep -E '(password|api_key|secret|token)\\s*=' demo.sh"
echo ""

if grep -Ei "(password|api_key|secret|token)\s*=\s*['\"]" "$SCRIPT_DIR/demo.sh" \
     > /dev/null 2>&1; then
  printf "  ${Red}FAIL:${Color_Off} Credentials found in workload script.\n"
  exit 1
else
  printf "  ${Green}OK${Color_Off}   No hardcoded credentials found.\n"
fi

print_line

# =============================================================================
# Scene 2 — SWA Server status
# =============================================================================
printf "${BCyan}[2/8]${Color_Off} SWA Server status (${SWA_SERVER_HOST}:8081)...\n\n"

print_prompt "curl -s http://${SWA_SERVER_HOST}:8081/health"
echo ""

if [[ "$SWA_MODE" == "mock" ]]; then
  printf "  Mode:     ${Yellow}mock${Color_Off} (SWA Server not running — skipped)\n"
  printf "  Domain:   ${SWA_DOMAIN}\n"
  printf "  Status:   ${Yellow}SIMULATED${Color_Off}\n"
else
  if curl -sf "http://${SWA_SERVER_HOST}:8081/health" > /dev/null 2>&1; then
    printf "  Host:     ${SWA_SERVER_HOST}:8081\n"
    printf "  Domain:   ${SWA_DOMAIN}\n"
    printf "  Status:   ${Green}RUNNING${Color_Off}\n"
  else
    printf "  ${Red}ERROR:${Color_Off} SWA Server not reachable at ${SWA_SERVER_HOST}:8081\n"
    printf "  Run setup.sh first and ensure swa-server is running.\n"
    exit 1
  fi
fi

print_line

# =============================================================================
# Scene 3 — SWA Agent status
# =============================================================================
printf "${BCyan}[3/8]${Color_Off} SWA Agent status...\n\n"

# TODO(needs-info #13): Confirm systemctl service name when binaries arrive.
if [[ "$SWA_MODE" == "mock" ]]; then
  print_prompt "ls -la /run/swa-agent/api.sock"
  echo ""
  printf "  Mode:     ${Yellow}mock${Color_Off} (SWA Agent binary not running)\n"
  printf "  Agent:    %s\n" "$SWA_AGENT_BIN"
  printf "  Status:   ${Yellow}SIMULATED${Color_Off}\n"
else
  print_prompt "systemctl status swa-agent"
  echo ""
  if [ -S "/run/swa-agent/api.sock" ]; then
    printf "  Socket:   /run/swa-agent/api.sock\n"
    printf "  Server:   ${SWA_SERVER_HOST}:8081\n"
    printf "  Status:   ${Green}RUNNING${Color_Off}\n"
  else
    printf "  ${Red}ERROR:${Color_Off} SWA Agent socket not found at /run/swa-agent/api.sock\n"
    printf "  Run setup.sh first and ensure swa-agent is running.\n"
    exit 1
  fi
fi

print_line

# =============================================================================
# Scene 4 — Workload identity policy in Conjur
# =============================================================================
printf "${BCyan}[4/8]${Color_Off} Workload identity policy in Conjur...\n\n"

print_prompt "curl .../resources/conjur/host/data/workloads/swa/${SWA_WORKLOAD_ID}"
echo ""

# shellcheck disable=SC1091
source "$CYBR_DEMOS_PATH/demos/utility/ubuntu/identity_functions.sh"
# shellcheck disable=SC1091
source "$CYBR_DEMOS_PATH/demos/utility/ubuntu/conjur_functions.sh"

identity_token=$(get_identity_token "$TENANT_ID" "$CLIENT_ID" "$CLIENT_SECRET")
conjur_token=$(get_conjur_token "$TENANT_SUBDOMAIN" "$identity_token")

host_check=$(curl --silent \
  "https://${TENANT_SUBDOMAIN}.secretsmgr.cyberark.cloud/api/resources/conjur/host/data%2Fworkloads%2Fswa%2F${SWA_WORKLOAD_ID}" \
  --header "Authorization: Token token=\"${conjur_token}\"")

if echo "$host_check" | grep -q "data/workloads/swa/${SWA_WORKLOAD_ID}"; then
  printf "  Identity:   spiffe://${SWA_DOMAIN#spiffe://}/${SWA_WORKLOAD_ID}\n"
  printf "  Host:       data/workloads/swa/${SWA_WORKLOAD_ID}\n"
  printf "  Secret:     ${DEMO_SECRET_ID}\n"
  printf "  Permission: ${Green}read   OK${Color_Off}\n"
else
  printf "  ${Red}ERROR:${Color_Off} Workload host not found in Conjur.\n"
  printf "  Run setup.sh to load workload identity policy.\n"
  exit 1
fi

print_line

# =============================================================================
# Scene 5 — Fetch JWT SVID from SWA Agent
# =============================================================================
printf "${BCyan}[5/8]${Color_Off} Fetching JWT SVID from SWA Agent...\n\n"

if [[ "$SWA_MODE" == "mock" ]]; then
  print_prompt "${SWA_AGENT_BIN} api fetch jwt --audience conjur"
  echo ""
  JWT=$("$SWA_AGENT_BIN" api fetch jwt --audience conjur)
else
  print_prompt "${SWA_AGENT_BIN} api fetch jwt --audience conjur --socketPath ${SWA_SOCKET_PATH}"
  echo ""
  # Real agent returns JSON: [{"svid":{"token":"eyJ..."},...}]
  JWT_JSON=$("$SWA_AGENT_BIN" api fetch jwt \
    --audience conjur \
    --socketPath "$SWA_SOCKET_PATH" \
    --output json 2>/dev/null)
  JWT=$(printf '%s' "$JWT_JSON" | python3 -c \
    "import sys,json; svids=json.load(sys.stdin); print(svids[0]['svid']['token'])" 2>/dev/null || true)
fi

if [ -z "$JWT" ]; then
  printf "  ${Red}ERROR:${Color_Off} No JWT returned from SWA Agent.\n"
  exit 1
fi

printf "  Token:  %.60s...\n" "$JWT"
printf "  Status: ${Green}OK${Color_Off}\n"

print_line

# =============================================================================
# Scene 6 — Decode and display JWT claims
# =============================================================================
printf "${BCyan}[6/8]${Color_Off} Decoding JWT claims...\n\n"

# Extract payload (second segment), pad and decode
JWT_PAYLOAD=$(printf '%s' "$JWT" | cut -d. -f2)
PADDED="${JWT_PAYLOAD}$(printf '%0.s=' $(seq 1 $((4 - ${#JWT_PAYLOAD} % 4))))"
CLAIMS=$(printf '%s' "$PADDED" | base64 -d 2>/dev/null | tr -d '\0')

sub=$(printf '%s' "$CLAIMS"  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('sub','(not found)'))")
aud=$(printf '%s' "$CLAIMS"  | python3 -c "import sys,json; d=json.load(sys.stdin); a=d.get('aud','(not found)'); print(a if isinstance(a,str) else a[0])")
iss=$(printf '%s' "$CLAIMS"  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('iss','(not found)'))")
iat=$(printf '%s' "$CLAIMS"  | python3 -c "import sys,json,datetime; d=json.load(sys.stdin); print(datetime.datetime.utcfromtimestamp(d['iat']).strftime('%Y-%m-%dT%H:%M:%SZ'))")
exp=$(printf '%s' "$CLAIMS"  | python3 -c "import sys,json,datetime; d=json.load(sys.stdin); print(datetime.datetime.utcfromtimestamp(d['exp']).strftime('%Y-%m-%dT%H:%M:%SZ'))")
ttl=$(printf '%s' "$CLAIMS"  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['exp']-d['iat'])")

printf "  sub:  ${Green}%s${Color_Off}\n" "$sub"
printf "  aud:  %s\n" "$aud"
printf "  iss:  %s\n" "$iss"
printf "  iat:  %s\n" "$iat"
printf "  exp:  %s  (TTL: %ss)\n" "$exp" "$ttl"

print_line

# =============================================================================
# Scene 7 — Authenticate to Conjur with JWT
# =============================================================================
printf "${BCyan}[7/8]${Color_Off} Authenticating to Conjur with JWT...\n\n"

print_prompt "curl -X POST ${AUTHN_URL} --data-urlencode jwt=\$JWT"
echo ""

SESSION_TOKEN=$(curl --silent \
  --request POST "$AUTHN_URL" \
  --header "Content-Type: application/x-www-form-urlencoded" \
  --header "Accept-Encoding: base64" \
  --data-urlencode "jwt=${JWT}")

if [ -z "$SESSION_TOKEN" ]; then
  printf "  ${Red}ERROR:${Color_Off} Conjur JWT authentication failed.\n"
  printf "  Check: JWT authenticator enabled, policy loaded, JWKS configured.\n"
  exit 1
fi

printf "  Endpoint: %s\n" "$AUTHN_URL"
printf "  Status:   ${Green}Conjur session token issued   OK${Color_Off}\n"

print_line

# =============================================================================
# Scene 8 — Retrieve secret from Conjur
# =============================================================================
printf "${BCyan}[8/8]${Color_Off} Retrieving secret from Conjur...\n\n"

ENCODED_SECRET_ID=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${DEMO_SECRET_ID}', safe=''))")
print_prompt "curl ${SECRET_URL}/${ENCODED_SECRET_ID}"
echo ""

SECRET_VALUE=$(curl --silent \
  "${SECRET_URL}/${ENCODED_SECRET_ID}" \
  --header "Authorization: Token token=\"${SESSION_TOKEN}\"")

if [ -z "$SECRET_VALUE" ]; then
  printf "  ${Red}ERROR:${Color_Off} Secret retrieval failed.\n"
  exit 1
fi

printf "  ${Green}%s = %s${Color_Off}\n\n" "$DEMO_SECRET_ID" "$SECRET_VALUE"
printf "  ${BWhite}No static credential was stored on this workload.${Color_Off}\n"

print_line
printf "${BGreen}Done.${Color_Off}\n\n"
