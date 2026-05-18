#!/bin/bash
# secure_ai_agents/spiffe_conjur — interactive demo (~12 min).
#
# Three acts, eight steps:
#   ACT I   — BEFORE  : a vulnerable AI agent ships a hardcoded API key
#   ACT II  — ACTION  : SPIRE attests the workload, Conjur Cloud federates
#                       that identity into a vaulted, rotatable secret
#   ACT III — PAYOFF  : live revoke (one policy = both sides) + before/after
#
# Prereqs: setup.sh has completed (or the four setup/<stage>/setup.sh scripts
# have been run individually). cloudflared tunnel is running.

# shellcheck disable=SC1091 disable=SC2059 disable=SC2154
set -euo pipefail

if [ -z "${CYBR_DEMOS_PATH:-}" ]; then
  CYBR_DEMOS_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
  export CYBR_DEMOS_PATH
fi

demo_path="$CYBR_DEMOS_PATH/demos/secure_ai_agents/spiffe_conjur"

set -a
source "$CYBR_DEMOS_PATH/demos/setup_env.sh"
source "$CYBR_DEMOS_PATH/demos/utility/ubuntu/demo_utility.sh"
source "$demo_path/setup/vars.env"
[ -f "$demo_path/setup/.oidc.env" ] && source "$demo_path/setup/.oidc.env"
set +a

# ─── Helpers ─────────────────────────────────────────────────────────────────
pause_demo() {
  printf "\n${IBlack}Press ENTER to continue...${Color_Off}"
  read -r
  printf "\n"
}

kctx() { kubectl --context "$MINIKUBE_PROFILE" "$@"; }
agent() { kctx exec -n "$WORKLOADS_NAMESPACE" "$ATTESTED_AGENT_NAME" -c agent -- /bin/sh -c "$*"; }

mask_secret() {
  local s="$1" len=${#1}
  if (( len <= 12 )); then printf '%s' "$s"; else printf '%s...%s' "${s:0:6}" "${s: -4}"; fi
}

# ─── Banner ──────────────────────────────────────────────────────────────────
clear
printf "${BWhite}"
printf "╔══════════════════════════════════════════════════════════════════════╗\n"
printf "║   CyberArk Secure AI Agents — SPIFFE / SPIRE → Conjur Cloud          ║\n"
printf "║   AI Agent Identity & Vaulted Secrets via authn-jwt                  ║\n"
printf "╚══════════════════════════════════════════════════════════════════════╝\n"
printf "${Color_Off}\n"

printf "${Cyan}Scenario:${Color_Off} An AI agent today ships with a hardcoded API key in env.\n"
printf "          Anyone with kubectl exec leaks it. Rotation = redeploy.\n"
printf "          Compromise = exfil with no audit trail.\n\n"

printf "${Cyan}Solution:${Color_Off}\n"
printf "  ${BIGreen}①${Color_Off}  ${BWhite}SPIRE${Color_Off} attests the workload via Kubernetes (no shared secret)\n"
printf "  ${BIGreen}②${Color_Off}  Workload presents a ${BWhite}JWT-SVID${Color_Off} to ${BWhite}CyberArk Conjur Cloud${Color_Off} authn-jwt\n"
printf "  ${BIGreen}③${Color_Off}  Conjur returns a short-lived ${BWhite}access token${Color_Off} (≤ 8 min)\n"
printf "  ${BIGreen}④${Color_Off}  Workload retrieves the ${BWhite}vaulted secret${Color_Off} — never on disk, never in env\n"
printf "  ${BIGreen}⑤${Color_Off}  ${BWhite}One${Color_Off} policy change revokes ${BWhite}both${Color_Off} sides of the trust chain\n\n"

printf "${IBlack}Tenant: %s | Lab: %s | Trust domain: %s${Color_Off}\n" \
  "$TENANT_SUBDOMAIN" "$LAB_ID" "$TRUST_DOMAIN"
printf "${IBlack}OIDC public URL: %s${Color_Off}\n" "${OIDC_PUBLIC_URL:-not set — run setup/oidc/setup.sh}"
print_line
pause_demo

# ═══════════════════════════════════════════════════════════════════════════
printf "${BIRed}╔════════════════════════════════════════════════════════════════════╗${Color_Off}\n"
printf "${BIRed}║                       A C T   I   —   B E F O R E                  ║${Color_Off}\n"
printf "${BIRed}╚════════════════════════════════════════════════════════════════════╝${Color_Off}\n"

# ─── 1/8 ────────────────────────────────────────────────────────────────────
printf "\n${BYellow}STEP 1/8: The Vulnerable Agent${Color_Off}\n"
printf "${IBlack}A typical AI agent today: hardcoded API key in env via a K8s Secret${Color_Off}\n\n"

print_prompt "kubectl get pod -n vulnerable-agents vulnerable-agent -o wide"
kctx get pod -n "$VULNERABLE_NAMESPACE" vulnerable-agent -o wide
echo

printf "${BWhite}Where the key lives:${Color_Off}\n"
print_prompt "kubectl get pod -n vulnerable-agents vulnerable-agent -o yaml | grep -A1 'secretKeyRef\\|name: OPENAI\\|name: AGENT'"
kctx get pod -n "$VULNERABLE_NAMESPACE" vulnerable-agent -o yaml \
  | grep -E '(secretKeyRef|name: OPENAI|name: AGENT)' -A1 || true
echo

printf "${BWhite}The K8s Secret itself:${Color_Off}  ${IBlack}base64 is encoding, not encryption${Color_Off}\n"
print_prompt "kubectl get secret -n vulnerable-agents openai-credentials -o jsonpath='{.data.api-key}' | base64 -d"
kctx get secret -n "$VULNERABLE_NAMESPACE" openai-credentials -o jsonpath='{.data.api-key}' | base64 -d
echo
echo

printf "${BWhite}Anyone with ${BIRed}kubectl exec${BWhite} into this pod sees the key:${Color_Off}\n"
print_prompt "kubectl exec -n vulnerable-agents vulnerable-agent -- env | grep -E 'OPENAI|AGENT'"
kctx exec -n "$VULNERABLE_NAMESPACE" vulnerable-agent -- env | grep -E 'OPENAI|AGENT' || true
echo

printf "${BIRed}This pod is shippable. It works. It's also a leak.${Color_Off}\n"
printf "  ${IBlack}• Key is in${Color_Off} ${BWhite}etcd${Color_Off} ${IBlack}(plaintext if KMS isn't enabled)${Color_Off}\n"
printf "  ${IBlack}• Key is in the${Color_Off} ${BWhite}pod spec${Color_Off} ${IBlack}(any kubectl get pod sees it)${Color_Off}\n"
printf "  ${IBlack}• Key is in the${Color_Off} ${BWhite}env${Color_Off} ${IBlack}(any debug log can leak it)${Color_Off}\n"
printf "  ${IBlack}• Compromise =${Color_Off} ${BWhite}exfil${Color_Off}${IBlack}, no rotation, no audit trail${Color_Off}\n"
print_line
pause_demo

# ═══════════════════════════════════════════════════════════════════════════
printf "${BYellow}╔════════════════════════════════════════════════════════════════════╗${Color_Off}\n"
printf "${BYellow}║                       A C T   I I   —   A C T I O N                ║${Color_Off}\n"
printf "${BYellow}╚════════════════════════════════════════════════════════════════════╝${Color_Off}\n"

# ─── 2/8 ────────────────────────────────────────────────────────────────────
printf "\n${BYellow}STEP 2/8: The Architecture${Color_Off}\n"
printf "${IBlack}Two open primitives, one CyberArk product, zero credentials in pods${Color_Off}\n\n"

printf "  ${IBlack}┌─────────────┐${Color_Off}\n"
printf "  ${IBlack}│${Color_Off}  ${BWhite}K8s Pod${Color_Off}    ${IBlack}│${Color_Off}   ${IBlack}no secret. no env. no init container. just a CSI volume.${Color_Off}\n"
printf "  ${IBlack}└──────┬──────┘${Color_Off}\n"
printf "  ${IBlack}       │${Color_Off}   ${BCyan}①${Color_Off} ${BWhite}attestation${Color_Off}   ${IBlack}(k8s_psat: namespace + sa + pod label)${Color_Off}\n"
printf "  ${IBlack}       ▼${Color_Off}\n"
printf "  ${BCyan}┌─────────────┐${Color_Off}\n"
printf "  ${BCyan}│${Color_Off}  ${BWhite}SPIRE${Color_Off}      ${BCyan}│${Color_Off}   ${IBlack}mints X.509 SVID + JWT-SVID for this pod${Color_Off}\n"
printf "  ${BCyan}└──────┬──────┘${Color_Off}\n"
printf "  ${IBlack}       │${Color_Off}   ${BCyan}②${Color_Off} ${BWhite}JWT-SVID${Color_Off}   ${IBlack}(sub: %s)${Color_Off}\n" "$SPIFFE_HOST_ID"
printf "  ${IBlack}       ▼${Color_Off}\n"
printf "  ${BYellow}┌─────────────────────────────────────────┐${Color_Off}\n"
printf "  ${BYellow}│${Color_Off}  ${BWhite}CyberArk Conjur Cloud — authn-jwt${Color_Off}   ${BYellow}│${Color_Off}   ${IBlack}validates JWKS via OIDC discovery${Color_Off}\n"
printf "  ${BYellow}│${Color_Off}  ${IBlack}validates JWT signature against SPIRE${Color_Off}  ${BYellow}│${Color_Off}\n"
printf "  ${BYellow}└──────────────────┬──────────────────────┘${Color_Off}\n"
printf "  ${IBlack}                   │${Color_Off}   ${BCyan}③${Color_Off} ${BWhite}8-min access token${Color_Off}\n"
printf "  ${IBlack}                   ▼${Color_Off}\n"
printf "  ${BIGreen}┌─────────────────────────────────────────┐${Color_Off}\n"
printf "  ${BIGreen}│${Color_Off}  ${BWhite}Vaulted secret${Color_Off}                       ${BIGreen}│${Color_Off}   ${IBlack}%s${Color_Off}\n" "$CONJUR_SECRET_VARIABLE"
printf "  ${BIGreen}│${Color_Off}  ${IBlack}rotated by Conjur, never on disk${Color_Off}       ${BIGreen}│${Color_Off}\n"
printf "  ${BIGreen}└─────────────────────────────────────────┘${Color_Off}\n"
echo
printf "${BWhite}SPIRE${Color_Off}                = the open identity primitive\n"
printf "${BWhite}CyberArk Conjur Cloud${Color_Off} = the vault that trusts that identity\n"
print_line
pause_demo

# ─── 3/8 ────────────────────────────────────────────────────────────────────
printf "\n${BYellow}STEP 3/8: SPIRE Attests the Workload${Color_Off}\n"
printf "${IBlack}One CRD declares who gets which identity${Color_Off}\n\n"

print_prompt "kubectl get clusterspiffeid workloads-default -o jsonpath='{.spec.spiffeIDTemplate}'"
kctx get clusterspiffeid workloads-default -o jsonpath='{.spec.spiffeIDTemplate}'; echo
echo

printf "${BWhite}The attested-agent pod (no secrets in spec):${Color_Off}\n"
print_prompt "kubectl get pod -n $WORKLOADS_NAMESPACE $ATTESTED_AGENT_NAME -o wide"
kctx get pod -n "$WORKLOADS_NAMESPACE" "$ATTESTED_AGENT_NAME" -o wide
echo

SECRETS_IN_SPEC=$(kctx get pod "$ATTESTED_AGENT_NAME" -n "$WORKLOADS_NAMESPACE" -o yaml | grep -cE '(secretName:|secretKeyRef)' || true)
if [ "$SECRETS_IN_SPEC" -eq 0 ]; then
  printf "${BIGreen}  ✔  Zero Secret references — identity comes from attestation${Color_Off}\n"
else
  printf "${BIRed}  ✘  Found %s Secret references${Color_Off}\n" "$SECRETS_IN_SPEC"
fi
echo

printf "${BWhite}SPIRE issued this pod an X.509 SVID. URI SAN:${Color_Off}\n"
print_prompt "spire-agent api fetch x509 (inside the pod)"
SAN_URI=$(agent "spire-agent api fetch x509 -socketPath /spiffe-workload-api/spire-agent.sock 2>&1 | grep 'SPIFFE ID' | head -1 | awk '{print \$3}'" 2>/dev/null || echo "")
if [ -z "$SAN_URI" ]; then
  printf "${BIRed}  ✘  agent could not fetch an SVID — check spire-controller-manager logs${Color_Off}\n"
  exit 1
fi
printf "  ${BCyan}SPIFFE ID:${Color_Off} %s\n" "$SAN_URI"
echo
if [ "$SAN_URI" = "$SPIFFE_HOST_ID" ]; then
  printf "${BIGreen}  ✔  Matches the host id Conjur Cloud is configured to trust${Color_Off}\n"
else
  printf "${BIRed}  ⚠  Differs from expected %s${Color_Off}\n" "$SPIFFE_HOST_ID"
fi
print_line
pause_demo

# ─── 4/8 ────────────────────────────────────────────────────────────────────
printf "\n${BYellow}STEP 4/8: JWT-SVID — The Bridge to CyberArk${Color_Off}\n"
printf "${IBlack}Same identity. Different format. Suitable for REST APIs.${Color_Off}\n\n"

JWT=$(agent "spire-agent api fetch jwt -audience conjur -socketPath /spiffe-workload-api/spire-agent.sock 2>/dev/null | grep -oE 'eyJ[A-Za-z0-9_.-]+' | head -1" || echo "")
if [ -z "$JWT" ]; then
  printf "${BIRed}  ✘  Could not fetch JWT-SVID${Color_Off}\n"
  exit 1
fi

printf "${BWhite}JWT-SVID payload (this is what Conjur Cloud will validate):${Color_Off}\n"
agent "echo '$JWT' | cut -d. -f2 | tr '_-' '/+' | sed 's/$/===/' | base64 -d 2>/dev/null | jq ." 2>/dev/null \
  | while IFS= read -r line; do
      case "$line" in
        *'"sub"'*|*'"iss"'*|*'"aud"'*) printf "  ${BIYellow}%s${Color_Off}\n" "$line" ;;
        *) printf "  ${BCyan}%s${Color_Off}\n" "$line" ;;
      esac
    done
echo

printf "${BWhite}The Conjur Cloud host policy that pairs to this JWT:${Color_Off}\n"
sed -n '/^- !host/,/member: !host/p' "$demo_path/setup/conjur/policy/02-spiffe-apps-hosts.yaml" \
  | head -10 | while IFS= read -r line; do printf "  ${BCyan}%s${Color_Off}\n" "$line"; done
echo
printf "${IBlack}sub claim ─► host id in Conjur Cloud — no mapping table, the identity IS the credential${Color_Off}\n"
print_line
pause_demo

# ─── 5/8 ────────────────────────────────────────────────────────────────────
printf "\n${BYellow}STEP 5/8: Live Handshake — JWT-SVID ⇄ Conjur Access Token${Color_Off}\n"
printf "${IBlack}Agent POSTs its JWT-SVID to Conjur Cloud's authn-jwt endpoint${Color_Off}\n\n"

print_prompt "curl -X POST https://$TENANT_SUBDOMAIN.secretsmgr.cyberark.cloud/api/authn-jwt/$CONJUR_AUTHN_SERVICE_ID/conjur/authenticate --data-urlencode jwt=<JWT-SVID>"

CONJUR_RESP=$(agent "set -e
JWT=\$(spire-agent api fetch jwt -audience conjur -socketPath /spiffe-workload-api/spire-agent.sock 2>/dev/null | grep -oE 'eyJ[A-Za-z0-9_.-]+' | head -1)
curl -sS -w '\\n--- HTTP %{http_code} time=%{time_total}s ---\\n' \
  -X POST \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -H 'Accept-Encoding: base64' \
  --data-urlencode \"jwt=\${JWT}\" \
  \"\${CONJUR_URL}/authn-jwt/\${CONJUR_AUTHENTICATOR_ID#authn-jwt/}/\${CONJUR_ACCOUNT}/authenticate\"
" 2>&1 || true)

ACCESS_TOKEN=$(printf '%s' "$CONJUR_RESP" | grep -oE '^[A-Za-z0-9+/=]+$' | head -1)
HTTP_LINE=$(printf '%s' "$CONJUR_RESP" | grep '^--- HTTP' | head -1)

printf "${BWhite}Response:${Color_Off}\n"
if [ -n "$ACCESS_TOKEN" ]; then
  TOKEN_PREVIEW="${ACCESS_TOKEN:0:60}…${ACCESS_TOKEN: -20}"
  printf "  ${BIGreen}%s${Color_Off}\n" "$TOKEN_PREVIEW"
else
  printf '%s\n' "$CONJUR_RESP" | sed -n '1,8p' | while IFS= read -r line; do printf "  ${IBlack}%s${Color_Off}\n" "$line"; done
fi
printf "  ${BIYellow}%s${Color_Off}\n" "$HTTP_LINE"

if [ -z "$ACCESS_TOKEN" ]; then
  echo
  printf "${BIRed}  ✘  Conjur Cloud rejected the JWT-SVID${Color_Off}\n"
  printf "${IBlack}     Check: JWKS URL reachable, jwtIssuer matches OIDC URL,${Color_Off}\n"
  printf "${IBlack}            host policy loaded, authenticator enabled.${Color_Off}\n"
  printf "${IBlack}     Recovery: re-run setup/oidc/setup.sh && setup/conjur/setup.sh${Color_Off}\n"
  exit 1
fi

echo
printf "${BIGreen}  ✔  Conjur Cloud validated the JWT-SVID against SPIRE's JWKS${Color_Off}\n"
printf "${BIGreen}  ✔  Returned a short-lived access token (NOT the secret yet)${Color_Off}\n"
print_line
pause_demo

# ─── 6/8 ────────────────────────────────────────────────────────────────────
printf "\n${BYellow}STEP 6/8: Fetch the Vaulted Secret${Color_Off}\n"
printf "${IBlack}Use the 8-minute access token to GET the secret${Color_Off}\n\n"

print_prompt "curl https://$TENANT_SUBDOMAIN.secretsmgr.cyberark.cloud/api/secrets/conjur/variable/$CONJUR_SECRET_VARIABLE -H 'Authorization: Token token=...'"

encoded_var=$(printf '%s' "$CONJUR_SECRET_VARIABLE" | sed 's|/|%2F|g')
SECRET_VALUE=$(agent "set -e
JWT=\$(spire-agent api fetch jwt -audience conjur -socketPath /spiffe-workload-api/spire-agent.sock 2>/dev/null | grep -oE 'eyJ[A-Za-z0-9_.-]+' | head -1)
TOKEN=\$(curl -sS -X POST \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -H 'Accept-Encoding: base64' \
  --data-urlencode \"jwt=\${JWT}\" \
  \"\${CONJUR_URL}/authn-jwt/\${CONJUR_AUTHENTICATOR_ID#authn-jwt/}/\${CONJUR_ACCOUNT}/authenticate\")
curl -sS \
  -H \"Authorization: Token token=\\\"\${TOKEN}\\\"\" \
  \"\${CONJUR_URL}/secrets/\${CONJUR_ACCOUNT}/variable/$encoded_var\"
" 2>&1 || true)

MASKED=$(mask_secret "$SECRET_VALUE")
printf "\n${BWhite}Vaulted secret value:${Color_Off}  ${IBlack}(masked — full value never logged)${Color_Off}\n"
printf "  ${BIGreen}OPENAI_API_KEY = ${BIYellow}%s${Color_Off}\n\n" "$MASKED"

printf "${BIGreen}  ✔  Same value the vulnerable agent had — but now ephemeral and identity-scoped${Color_Off}\n"
printf "${BIGreen}  ✔  Never on disk, never in env, never in a K8s Secret, never in etcd${Color_Off}\n"
echo

printf "${BWhite}Side-by-side — same workload, different credential surface:${Color_Off}\n\n"
printf "  ${BIRed}BEFORE${Color_Off}                                ${BIGreen}AFTER${Color_Off}\n"
printf "  ${BIRed}─────────────────────────────────${Color_Off}    ${BIGreen}─────────────────────────────────${Color_Off}\n"
printf "  ${BIRed}env:${Color_Off}                                ${BIGreen}volumes:${Color_Off}\n"
printf "  ${BIRed}  - name: OPENAI_API_KEY${Color_Off}            ${BIGreen}  - name: spiffe-workload-api${Color_Off}\n"
printf "  ${BIRed}    valueFrom:${Color_Off}                      ${BIGreen}    csi:${Color_Off}\n"
printf "  ${BIRed}      secretKeyRef:${Color_Off}                 ${BIGreen}      driver: csi.spiffe.io${Color_Off}\n"
printf "  ${BIRed}        name: openai-credentials${Color_Off}    ${BIGreen}      readOnly: true${Color_Off}\n"
printf "  ${BIRed}        key: api-key${Color_Off}\n"
echo
printf "  ${BIRed}✘  Key in etcd${Color_Off}                      ${BIGreen}✔  Nothing in etcd${Color_Off}\n"
printf "  ${BIRed}✘  Key in pod spec${Color_Off}                  ${BIGreen}✔  Nothing in pod spec${Color_Off}\n"
printf "  ${BIRed}✘  Key in env${Color_Off}                       ${BIGreen}✔  Nothing in env${Color_Off}\n"
printf "  ${BIRed}✘  Rotation = redeploy${Color_Off}              ${BIGreen}✔  Rotation = update Conjur variable${Color_Off}\n"
printf "  ${BIRed}✘  Compromise = forever${Color_Off}             ${BIGreen}✔  Compromise = 8-minute window${Color_Off}\n"
print_line
pause_demo

# ═══════════════════════════════════════════════════════════════════════════
printf "${BIGreen}╔════════════════════════════════════════════════════════════════════╗${Color_Off}\n"
printf "${BIGreen}║                       A C T   I I I   —   P A Y O F F              ║${Color_Off}\n"
printf "${BIGreen}╚════════════════════════════════════════════════════════════════════╝${Color_Off}\n"

# ─── 7/8 ────────────────────────────────────────────────────────────────────
printf "\n${BYellow}STEP 7/8: Live Revoke + Re-grant — Policy as Source of Truth${Color_Off}\n"
printf "${IBlack}Scenario: agent suspected of compromise. Cut its access NOW.${Color_Off}\n\n"

printf "  Delete ${BWhite}one${Color_Off} ClusterSPIFFEID and:\n"
printf "    ${BCyan}①${Color_Off} SPIRE refuses to mint new SVIDs\n"
printf "    ${BCyan}②${Color_Off} Conjur Cloud authn-jwt fails (no JWT to present)\n"
printf "    ${BCyan}③${Color_Off} Existing access tokens expire in ${BWhite}≤ 8 min${Color_Off}\n"
echo

print_prompt "kubectl delete clusterspiffeid workloads-default"
kctx delete clusterspiffeid workloads-default
echo

printf "${BWhite}Polling: SPIRE drops cached identity, then attempts Conjur authn:${Color_Off}\n\n"
revoked=0
for i in 1 2 3 4 5 6 7 8 9 10; do
  TS=$(date +"%H:%M:%S")
  AUTHN=$(agent "
JWT=\$(spire-agent api fetch jwt -audience conjur -socketPath /spiffe-workload-api/spire-agent.sock 2>&1)
if echo \"\$JWT\" | grep -q 'no identity issued\|PermissionDenied'; then
  echo 'SPIRE_DENIED'
  exit 0
fi
JWT_TOKEN=\$(echo \"\$JWT\" | grep -oE 'eyJ[A-Za-z0-9_.-]+' | head -1)
HTTP=\$(curl -sS -o /dev/null -w '%{http_code}' -X POST \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode \"jwt=\${JWT_TOKEN}\" \
  \"\${CONJUR_URL}/authn-jwt/\${CONJUR_AUTHENTICATOR_ID#authn-jwt/}/\${CONJUR_ACCOUNT}/authenticate\")
echo \"CONJUR_HTTP=\${HTTP}\"
" 2>&1 || true)
  if echo "$AUTHN" | grep -q 'SPIRE_DENIED'; then
    printf "  ${BIRed}[%s]  ✘  SPIRE refuses to issue a JWT-SVID${Color_Off}  ${IBlack}(after %ds)${Color_Off}\n" "$TS" "$(( i * 3 ))"
    printf "  ${BIRed}    agent has no identity to present to Conjur Cloud${Color_Off}\n"
    revoked=1
    break
  fi
  if echo "$AUTHN" | grep -qE 'CONJUR_HTTP=(401|403)'; then
    printf "  ${BIRed}[%s]  ✘  Conjur Cloud rejected the JWT (%s)${Color_Off}  ${IBlack}(after %ds)${Color_Off}\n" \
      "$TS" "$(echo "$AUTHN" | grep -oE 'CONJUR_HTTP=[0-9]+')" "$(( i * 3 ))"
    printf "  ${BIRed}    no access token can be obtained for this workload${Color_Off}\n"
    revoked=1
    break
  fi
  printf "  ${IBlack}[%s]  ◌  caches still warm, retrying...${Color_Off}\n" "$TS"
  sleep 3
done
[ "$revoked" -eq 0 ] && printf "${BIYellow}  ⚠  neither side blocked yet — caches may extend the window${Color_Off}\n"
pause_demo

printf "\n${BWhite}Re-grant the policy and watch identity ${BIGreen}+${BWhite} access return:${Color_Off}\n\n"
print_prompt "kubectl apply -f setup/spire/manifests/10-cluster-spiffe-ids.yaml"
kctx apply -f "$demo_path/setup/spire/manifests/10-cluster-spiffe-ids.yaml"
echo
regranted=0
for i in 1 2 3 4 5 6 7 8 9 10; do
  TS=$(date +"%H:%M:%S")
  RESULT=$(agent "
JWT=\$(spire-agent api fetch jwt -audience conjur -socketPath /spiffe-workload-api/spire-agent.sock 2>&1)
JWT_TOKEN=\$(echo \"\$JWT\" | grep -oE 'eyJ[A-Za-z0-9_.-]+' | head -1)
[ -z \"\$JWT_TOKEN\" ] && { echo 'NO_JWT'; exit 0; }
HTTP=\$(curl -sS -o /dev/null -w '%{http_code}' -X POST \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode \"jwt=\${JWT_TOKEN}\" \
  \"\${CONJUR_URL}/authn-jwt/\${CONJUR_AUTHENTICATOR_ID#authn-jwt/}/\${CONJUR_ACCOUNT}/authenticate\")
echo \"HTTP=\${HTTP}\"
" 2>&1 || true)
  if echo "$RESULT" | grep -q 'HTTP=200'; then
    printf "  ${BIGreen}[%s]  ✔  identity restored AND Conjur Cloud accepts JWT (HTTP 200)${Color_Off}  ${IBlack}(after %ds)${Color_Off}\n" "$TS" "$(( i * 3 ))"
    regranted=1
    break
  fi
  printf "  ${IBlack}[%s]  ◌  controller-manager reconciling...${Color_Off}\n" "$TS"
  sleep 3
done
echo
if [ "$regranted" -eq 1 ]; then
  printf "${BIGreen}  ✔  ONE policy change. Both SPIRE and Conjur Cloud restored. No app restart.${Color_Off}\n"
else
  printf "${BIYellow}  ⚠  Identity not yet restored — check spire-controller-manager logs${Color_Off}\n"
fi
print_line
pause_demo

# ─── 8/8 ────────────────────────────────────────────────────────────────────
printf "\n${BYellow}STEP 8/8: What You Just Saw${Color_Off}\n\n"

printf "${BWhite}The pipeline:${Color_Off}\n\n"
printf "  ${BCyan}①${Color_Off}  SPIRE issues an identity to a workload it can attest\n"
printf "  ${BCyan}②${Color_Off}  CyberArk Conjur Cloud validates that identity (authn-jwt)\n"
printf "  ${BCyan}③${Color_Off}  Conjur returns a short-lived, identity-scoped access token\n"
printf "  ${BCyan}④${Color_Off}  Agent fetches the vaulted secret with that token\n"
printf "  ${BCyan}⑤${Color_Off}  Policy revocation kills both sides in one move\n\n"

printf "${BWhite}What this means in your environment:${Color_Off}\n\n"
printf "  ${BWhite}Inventory${Color_Off}      ${IBlack}every agent has a registered SPIFFE ID${Color_Off}\n"
printf "  ${BWhite}Audit${Color_Off}          ${IBlack}every secret read is logged in Conjur${Color_Off}\n"
printf "  ${BWhite}Rotation${Color_Off}       ${IBlack}'conjur variable set' — instant, no redeploy${Color_Off}\n"
printf "  ${BWhite}Revocation${Color_Off}     ${IBlack}delete one CR — both planes refuse${Color_Off}\n"
printf "  ${BWhite}Federation${Color_Off}     ${IBlack}Conjur sees ALL agents, K8s + non-K8s${Color_Off}\n"
printf "  ${BWhite}Compliance${Color_Off}     ${IBlack}no long-lived secrets, no shared accounts${Color_Off}\n\n"

printf "${BWhite}Where this fits in CyberArk's portfolio:${Color_Off}\n\n"
printf "  ${BCyan}•${Color_Off}  ${BWhite}Conjur Cloud authn-jwt${Color_Off}      ${IBlack}what you saw — JWT-SVID validation${Color_Off}\n"
printf "  ${BCyan}•${Color_Off}  ${BWhite}Secrets Hub${Color_Off}                 ${IBlack}sync vaulted secrets from PAM into Conjur${Color_Off}\n"
printf "  ${BCyan}•${Color_Off}  ${BWhite}Discovery${Color_Off}                   ${IBlack}inventory every SPIFFE-attested workload${Color_Off}\n"
printf "  ${BCyan}•${Color_Off}  ${BWhite}AI Gateway / SAI${Color_Off}            ${IBlack}policy enforcement for what the agent can DO${Color_Off}\n"
printf "  ${BCyan}•${Color_Off}  ${BWhite}Identity Security Platform${Color_Off}  ${IBlack}end-to-end machine identity governance${Color_Off}\n\n"

printf "${IBlack}Rotate the demo secret${Color_Off}: edit DEMO_SECRET_VALUE in setup/vars.env, re-run setup/conjur/setup.sh\n"
printf "${IBlack}Tear down${Color_Off}             : ./cleanup.sh\n"
print_line
