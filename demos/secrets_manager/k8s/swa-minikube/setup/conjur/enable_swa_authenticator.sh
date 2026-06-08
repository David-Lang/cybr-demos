#!/bin/bash
# Configure + activate authn-jwt/secureWorkloadAccess and grant the SWA workload
# host access to the demo safe. Idempotent (append-policy + secret upserts).
set -euo pipefail

demo_path="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=/dev/null
source "$demo_path/swa_demo_lib.sh"
swa_demo_init
swa_get_tokens

cd "$demo_path/setup/conjur"

# ── Resolve the trust domain JWKS + issuer the authenticator validates against ─
# Prefer explicit vars.env values; otherwise attempt OIDC discovery, then fall back.
td_jwks="${SWA_TD_JWKS_URI:-}"
td_issuer="${SWA_TD_ISSUER:-}"
if [[ -z "$td_jwks" || -z "$td_issuer" ]]; then
  echo "[INFO] Discovering trust domain OIDC config for '$SWA_TRUST_DOMAIN'"
  base="${SWA_CONTROL_PLANE_URL%/}"
  td_base="${base}/api/swa/trust-domains/${SWA_TRUST_DOMAIN}"
  for disc in \
    "${td_base}/.well-known/openid-configuration" \
    "${base}/swa/trust-domains/${SWA_TRUST_DOMAIN}/.well-known/openid-configuration" \
    "https://${SWA_TRUST_DOMAIN}/.well-known/openid-configuration"; do
    cfg="$(curl -fsSL "$disc" 2>/dev/null || true)"
    if [[ -n "$cfg" ]] && echo "$cfg" | jq -e '.jwks_uri' >/dev/null 2>&1; then
      td_jwks="$(echo "$cfg" | jq -r '.jwks_uri')"
      td_issuer="$(echo "$cfg" | jq -r '.issuer')"
      echo "[INFO] OIDC discovery succeeded at: $disc"
      break
    fi
  done
fi
if [[ -z "$td_jwks" || -z "$td_issuer" ]]; then
  td_issuer="${base}/api/swa/trust-domains/${SWA_TRUST_DOMAIN}"
  td_jwks="${td_issuer}/.well-known/jwks"
  echo "[WARN] OIDC discovery failed — using constructed defaults. VERIFY these against your tenant:"
  echo "[WARN]   issuer:   $td_issuer"
  echo "[WARN]   jwks_uri: $td_jwks"
  echo "[WARN] Override with SWA_TD_JWKS_URI / SWA_TD_ISSUER in setup/vars.env if wrong."
fi

# ── Authenticator policy + configuration ─────────────────────────────────────
echo "[INFO] Applying authenticator policy (conjur/authn-jwt/$SWA_AUTHN_ID)"
resolve_template "authenticator.tmpl.yaml" "authenticator.yaml"
apply_conjur_policy "$TENANT_SUBDOMAIN" "$SWA_CONJUR_TOKEN" "conjur/authn-jwt" "$(cat authenticator.yaml)"

echo "[INFO] Configuring authenticator variables"
apply_conjur_secret "$TENANT_SUBDOMAIN" "$SWA_CONJUR_TOKEN" "conjur/authn-jwt/$SWA_AUTHN_ID/jwks-uri" "$td_jwks"
apply_conjur_secret "$TENANT_SUBDOMAIN" "$SWA_CONJUR_TOKEN" "conjur/authn-jwt/$SWA_AUTHN_ID/issuer" "$td_issuer"
apply_conjur_secret "$TENANT_SUBDOMAIN" "$SWA_CONJUR_TOKEN" "conjur/authn-jwt/$SWA_AUTHN_ID/token-app-property" "sub"
apply_conjur_secret "$TENANT_SUBDOMAIN" "$SWA_CONJUR_TOKEN" "conjur/authn-jwt/$SWA_AUTHN_ID/identity-path" "data/poc-workloads"
apply_conjur_secret "$TENANT_SUBDOMAIN" "$SWA_CONJUR_TOKEN" "conjur/authn-jwt/$SWA_AUTHN_ID/audience" "$SWA_JWT_AUDIENCE"

echo "[INFO] Activating authn-jwt/$SWA_AUTHN_ID"
activate_conjur_service "$TENANT_SUBDOMAIN" "$SWA_CONJUR_TOKEN" "authn-jwt/$SWA_AUTHN_ID"

# ── Workload identity + grants ───────────────────────────────────────────────
echo "[INFO] Applying workload host (SPIFFE: $SWA_SPIFFE_ID)"
resolve_template "workload.tmpl.yaml" "workload.yaml"
apply_conjur_policy "$TENANT_SUBDOMAIN" "$SWA_CONJUR_TOKEN" "data" "$(cat workload.yaml)"

echo "[INFO] Granting authenticator access"
resolve_template "grant_authenticator.tmpl.yaml" "grant_authenticator.yaml"
apply_conjur_policy "$TENANT_SUBDOMAIN" "$SWA_CONJUR_TOKEN" "conjur/authn-jwt" "$(cat grant_authenticator.yaml)"

echo "[INFO] Granting safe consumer access (safe: $SAFE_NAME)"
resolve_template "grant_safe_access.tmpl.yaml" "grant_safe_access.yaml"
apply_conjur_policy "$TENANT_SUBDOMAIN" "$SWA_CONJUR_TOKEN" "data" "$(cat grant_safe_access.yaml)"

echo "[INFO] secureWorkloadAccess authenticator configured."
