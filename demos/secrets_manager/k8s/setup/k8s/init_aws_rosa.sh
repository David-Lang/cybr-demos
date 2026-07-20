#!/bin/bash
set -euo pipefail

# -----------------------------------------------------------------------------------------------------------
# init_aws_rosa.sh
#
# One-off initializer for running the Secrets Manager K8s demo on
# Red Hat OpenShift Service on AWS (ROSA).
#
# ROSA is OpenShift, so this reuses the OCP-style authenticator path:
#   - The service account issuer discovery service (/.well-known/openid-configuration)
#     and the JWKS endpoint (/openid/v1/jwks) are NOT anonymously public on ROSA/OpenShift;
#     they require a bearer token. Therefore Secrets Manager cannot fetch a public
#     `jwks-uri` and we MUST embed the JWKS as static `public-keys`.
#   - This script retrieves the JWKS with an authenticated call and writes it to
#     K8S_PUBLIC_KEYS in setup/vars.env, and sets K8S_TYPE=ocp so the unchanged
#     setup/sm/setup.sh selects the static public-keys authenticator path.
#
# The default OpenShift service account issuer is `https://kubernetes.default.svc`,
# which matches the issuer value already used by setup/sm/setup.sh.
#
# Prereqs on the runner: oc, jq (kubectl and the rosa CLI are optional helpers).
#
# Auth options (in priority order):
#   1. An existing, valid `oc` session (oc whoami succeeds) is reused as-is.
#   2. ROSA_API_URL + ROSA_TOKEN env vars           -> oc login --token
#   3. ROSA_API_URL + ROSA_USER (+ ROSA_PASSWORD)   -> oc login -u
# -----------------------------------------------------------------------------------------------------------

export CYBR_DEMOS_PATH="${CYBR_DEMOS_PATH:-/opt/cybr-demos}"
demo_path="$CYBR_DEMOS_PATH/demos/secrets_manager/k8s"
vars_file="$demo_path/setup/vars.env"

# Hardcoded issuer used by setup/sm/setup.sh; we cross-check the cluster against it.
expected_issuer="https://kubernetes.default.svc"

# -----------------------------------------------------------------------------------------------------------
# Tooling checks
# -----------------------------------------------------------------------------------------------------------
command -v oc >/dev/null 2>&1 || { echo "[ERROR] 'oc' CLI is required for ROSA/OpenShift." >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "[ERROR] 'jq' is required." >&2; exit 1; }

echo "[INFO] CYBR_DEMOS_PATH=$CYBR_DEMOS_PATH"
echo "[INFO] demo_path=$demo_path"
echo "[INFO] vars_file=$vars_file"
[[ -f "$vars_file" ]] || { echo "[ERROR] missing vars file: $vars_file" >&2; exit 1; }

# -----------------------------------------------------------------------------------------------------------
# Authenticate to the ROSA cluster
# -----------------------------------------------------------------------------------------------------------
# Optionally log in to the ROSA control plane (informational; requires the rosa CLI + token).
if command -v rosa >/dev/null 2>&1 && [[ -n "${ROSA_LOGIN_TOKEN:-}" ]]; then
  echo "[INFO] rosa login"
  rosa login --token="$ROSA_LOGIN_TOKEN" || echo "[WARN] rosa login failed (continuing; oc login is what matters)"
fi

if oc whoami >/dev/null 2>&1; then
  echo "[INFO] Reusing existing oc session: $(oc whoami) @ $(oc whoami --show-server)"
elif [[ -n "${ROSA_API_URL:-}" && -n "${ROSA_TOKEN:-}" ]]; then
  echo "[INFO] oc login via token to $ROSA_API_URL"
  oc login --token="$ROSA_TOKEN" --server="$ROSA_API_URL"
elif [[ -n "${ROSA_API_URL:-}" && -n "${ROSA_USER:-}" ]]; then
  echo "[INFO] oc login via user to $ROSA_API_URL"
  if [[ -n "${ROSA_PASSWORD:-}" ]]; then
    oc login -u "$ROSA_USER" -p "$ROSA_PASSWORD" "$ROSA_API_URL"
  else
    oc login -u "$ROSA_USER" "$ROSA_API_URL"
  fi
else
  echo "[ERROR] No active oc session and no ROSA_API_URL/ROSA_TOKEN (or ROSA_USER) provided." >&2
  echo "[HINT] Export ROSA_API_URL and ROSA_TOKEN, or run 'oc login ...' before this script." >&2
  exit 1
fi

echo "[INFO] whoami:        $(oc whoami)"
echo "[INFO] show-server:   $(oc whoami --show-server)"

# oc login writes kubeconfig, so kubectl works against the same context.
if command -v kubectl >/dev/null 2>&1; then
  echo "[INFO] cluster nodes:"
  kubectl get nodes || echo "[WARN] kubectl get nodes failed (context/RBAC?)"
fi

# -----------------------------------------------------------------------------------------------------------
# Discover OIDC / JWKS (authenticated calls)
# -----------------------------------------------------------------------------------------------------------
printf "\n\n[INFO] openid-configuration\n"
discovery="$(oc get --raw /.well-known/openid-configuration)"
echo "$discovery" | jq .

issuer="$(echo "$discovery" | jq -r '.issuer')"
jwks_uri="$(echo "$discovery" | jq -r '.jwks_uri')"
echo "[INFO] issuer=$issuer"
echo "[INFO] jwks_uri=$jwks_uri  (NOT anonymously reachable on ROSA -> using static public-keys)"

printf "\n\n[INFO] jwks (raw)\n"
oc get --raw /openid/v1/jwks | jq .

# Compact JWKS JSON for embedding into vars.env / the authenticator public-keys variable.
escaped_keys="$(oc get --raw /openid/v1/jwks | jq -c .)"
[[ -n "$escaped_keys" && "$escaped_keys" != "null" ]] || { echo "[ERROR] failed to retrieve JWKS" >&2; exit 1; }

# -----------------------------------------------------------------------------------------------------------
# JWKS / issuer sanity check
#
# setup/sm/setup.sh hardcodes the authenticator issuer to https://kubernetes.default.svc.
# Confirm the cluster's SA-token issuer actually matches so token validation will succeed.
# -----------------------------------------------------------------------------------------------------------
if [[ "$issuer" != "$expected_issuer" ]]; then
  echo "[WARN] Cluster SA issuer '$issuer' differs from the value used by sm/setup.sh ('$expected_issuer')." >&2
  echo "[WARN] This can happen on ROSA-STS clusters with a custom serviceAccountIssuer." >&2
  echo "[WARN] If workload authentication fails, update the issuer in setup/sm/setup.sh to match." >&2
fi

# Best-effort: decode a live projected SA token to confirm its 'iss' claim.
if oc create token default -n default >/dev/null 2>&1; then
  sa_token="$(oc create token default -n default)"
  token_iss="$(echo "$sa_token" | cut -d. -f2 | tr '_-' '/+' | { cat; printf '=='; } | base64 -d 2>/dev/null | jq -r '.iss' 2>/dev/null || true)"
  [[ -n "${token_iss:-}" ]] && echo "[INFO] projected SA token iss=$token_iss"
  if [[ -n "${token_iss:-}" && "$token_iss" != "$expected_issuer" ]]; then
    echo "[WARN] Projected SA token iss '$token_iss' != '$expected_issuer' (used by sm/setup.sh)." >&2
  fi
fi

# -----------------------------------------------------------------------------------------------------------
# Persist to setup/vars.env (mirrors init_rancher.sh behavior)
#   - K8S_TYPE=ocp        -> selects the static public-keys authenticator path in sm/setup.sh
#   - K8S_PUBLIC_KEYS     -> the embedded JWKS
#   - K8S_JWKS_URI        -> discovered uri, kept for reference (unused in public-keys mode)
# -----------------------------------------------------------------------------------------------------------
sed -i.bak "s|^K8S_TYPE=.*|K8S_TYPE=\"ocp\"|" "$vars_file"
sed -i.bak "s|^K8S_PUBLIC_KEYS=.*|K8S_PUBLIC_KEYS='$escaped_keys'|" "$vars_file"
sed -i.bak "s|^K8S_JWKS_URI=.*|K8S_JWKS_URI='$jwks_uri'|" "$vars_file"

echo
echo "[INFO] Updated $vars_file:"
grep -E '^(K8S_TYPE|K8S_PUBLIC_KEYS|K8S_JWKS_URI)=' "$vars_file"
echo "[INFO] done"
