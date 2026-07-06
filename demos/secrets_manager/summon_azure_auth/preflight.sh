#!/bin/bash
# Preflight: validate tenant/infra prerequisites for the Summon Azure Auth
# workshop BEFORE running setup_vm.sh. Run ON the target Azure VM (it needs
# Azure IMDS and the tenant credentials the control plane provides via the
# environment or /etc/profile.d/cyberark.sh).
#
# Checks tenant credentials, network reachability, the Azure user-assigned
# managed identity (IMDS), tenant authentication (Identity + Conjur), and an
# active PostgreSQL credential platform. Reports [ OK ]/[FAIL] per item and
# exits non-zero if anything fails. It does not change any tenant or lab state
# (it only needs curl/jq/base64 locally to run the checks).
set -o pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export CYBR_DEMOS_PATH="${CYBR_DEMOS_PATH:-$(cd "$SELF_DIR/../../.." && pwd)}"
DEMO_DIR="$CYBR_DEMOS_PATH/demos/secrets_manager/summon_azure_auth"

if [ -f /etc/profile.d/cyberark.sh ]; then
  # shellcheck disable=SC1091
  source /etc/profile.d/cyberark.sh
fi

# Load tenant vars + demo config + helper functions directly (avoids the tool
# auto-install side effect in setup_env.sh). The helper libs set -e; reset to a
# lenient mode afterward so every check runs.
set -a
[ -f "$CYBR_DEMOS_PATH/demos/tenant_vars.sh" ] && source "$CYBR_DEMOS_PATH/demos/tenant_vars.sh" 2>/dev/null
[ -f "$DEMO_DIR/setup/vars.env" ] && source "$DEMO_DIR/setup/vars.env" 2>/dev/null
for lib in identity_functions conjur_functions privilege_functions template_functions; do
  # shellcheck disable=SC1090
  source "$CYBR_DEMOS_PATH/demos/utility/ubuntu/${lib}.sh" 2>/dev/null || true
done
set +a
set +e +u
set +o pipefail

PASS=0
FAIL=0
ok()   { printf "  [ OK ] %s\n" "$1"; PASS=$((PASS + 1)); }
bad()  { printf "  [FAIL] %s\n" "$1"; FAIL=$((FAIL + 1)); }
info() { printf "         %s\n" "$1"; }

decode_jwt_payload() {
  local token="$1" payload
  payload="$(printf "%s" "$token" | cut -d. -f2)"
  payload="${payload//-/+}"
  payload="${payload//_//}"
  case $((${#payload} % 4)) in
    2) payload="${payload}==" ;;
    3) payload="${payload}=" ;;
  esac
  printf "%s" "$payload" | base64 -d 2>/dev/null
}

printf "== Preflight: Summon Azure Auth workshop ==\n\n"

# 1. Tenant credentials present -------------------------------------------------
printf "1. Tenant credentials\n"
for v in TENANT_ID TENANT_SUBDOMAIN CLIENT_ID CLIENT_SECRET LAB_ID; do
  val="${!v:-}"
  if [ -n "$val" ] && [ "${val#SET_}" = "$val" ]; then
    ok "$v is set"
  else
    bad "$v is missing or a placeholder"
  fi
done

# 2. Network reachability -------------------------------------------------------
printf "\n2. Network reachability\n"
if curl -sS -o /dev/null --connect-timeout 2 --max-time 10 -H "Metadata: true" \
     "http://169.254.169.254/metadata/instance?api-version=2021-02-01" 2>/dev/null; then
  ok "Azure IMDS reachable"
else
  bad "Azure IMDS not reachable (is this an Azure VM?)"
fi
if [ -n "${TENANT_SUBDOMAIN:-}" ]; then
  if curl -sS -o /dev/null --connect-timeout 5 --max-time 15 \
       "https://${TENANT_SUBDOMAIN}.privilegecloud.cyberark.cloud/PasswordVault/API/Server" 2>/dev/null; then
    ok "Privilege Cloud reachable"
  else
    bad "Privilege Cloud not reachable"
  fi
  if curl -sS -o /dev/null --connect-timeout 5 --max-time 15 \
       "https://${TENANT_SUBDOMAIN}.secretsmgr.cyberark.cloud/" 2>/dev/null; then
    ok "Secrets Manager reachable"
  else
    bad "Secrets Manager not reachable"
  fi
fi
if curl -sS -o /dev/null --connect-timeout 5 --max-time 15 "https://github.com" 2>/dev/null; then
  ok "GitHub reachable (repo clone)"
else
  bad "GitHub not reachable"
fi

# 3. Tenant authentication (proves the creds actually work) ---------------------
printf "\n3. Tenant authentication\n"
identity_token=""
if command -v get_identity_token >/dev/null 2>&1 \
   && [ -n "${TENANT_ID:-}" ] && [ -n "${CLIENT_ID:-}" ] && [ -n "${CLIENT_SECRET:-}" ]; then
  identity_token="$(get_identity_token "$TENANT_ID" "$CLIENT_ID" "$CLIENT_SECRET" 2>/dev/null)"
  if [ -n "$identity_token" ]; then
    ok "Identity authentication (token acquired)"
  else
    bad "Identity authentication failed (check CLIENT_ID / CLIENT_SECRET / TENANT_ID)"
  fi
else
  bad "Skipped Identity auth (helpers or creds unavailable)"
fi
if command -v get_conjur_token >/dev/null 2>&1 && [ -n "$identity_token" ] && [ -n "${TENANT_SUBDOMAIN:-}" ]; then
  conjur_token="$(get_conjur_token "$TENANT_SUBDOMAIN" "$identity_token" 2>/dev/null)"
  if [ -n "$conjur_token" ]; then
    ok "Conjur (Secrets Manager) authentication (token acquired)"
  else
    bad "Conjur authentication failed"
  fi
fi

# 4. Azure user-assigned managed identity via IMDS ------------------------------
printf "\n4. Azure user-assigned managed identity\n"
imds_res="$(jq -rn --arg v "${AZURE_IMDS_RESOURCE:-https://management.azure.com/}" '$v|@uri' 2>/dev/null)"
imds_url="http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=${imds_res}"
if [ -n "${AZURE_CLIENT_ID:-}" ]; then
  imds_url="${imds_url}&client_id=$(jq -rn --arg v "$AZURE_CLIENT_ID" '$v|@uri' 2>/dev/null)"
fi
token_json="$(curl -sS --connect-timeout 2 --max-time 15 -H "Metadata: true" "$imds_url" 2>/dev/null)"
access_token="$(printf '%s' "$token_json" | jq -r '.access_token // empty' 2>/dev/null)"
if [ -n "$access_token" ]; then
  ok "IMDS returned a managed-identity token"
  mirid="$(decode_jwt_payload "$access_token" | jq -r '.xms_mirid // empty' 2>/dev/null)"
  if printf '%s' "$mirid" | grep -qi 'userassignedidentities'; then
    ok "User-assigned identity confirmed"
    info "$mirid"
  else
    bad "Token is not a user-assigned identity"
    info "xms_mirid: ${mirid:-<none>} — attach a UMAI (set AZURE_CLIENT_ID if the VM has more than one)"
  fi
else
  bad "IMDS did not return a managed-identity token"
  info "Attach a user-assigned managed identity to the VM (set AZURE_CLIENT_ID if more than one)."
fi

# 5. PostgreSQL credential platform on the tenant -------------------------------
printf "\n5. PostgreSQL credential platform\n"
if command -v postgres_platform_available >/dev/null 2>&1 && [ -n "$identity_token" ] && [ -n "${TENANT_SUBDOMAIN:-}" ]; then
  if postgres_platform_available "$TENANT_SUBDOMAIN" "$identity_token" "postgre"; then
    ok "Active PostgreSQL credential platform found on the tenant"
  else
    bad "No active PostgreSQL credential platform found"
    info "Import and activate a PostgreSQL platform in Privilege Cloud (needed for onboarding + SRS rotation)."
  fi
else
  bad "Skipped platform check (no identity token or helper unavailable)"
fi

printf "\n== Summary: %s passed, %s failed ==\n" "$PASS" "$FAIL"
if [ "$FAIL" -eq 0 ]; then
  printf "All prerequisites satisfied — you can run setup_vm.sh.\n"
  exit 0
fi
printf "Resolve the failed items above before running setup_vm.sh.\n"
exit 1
