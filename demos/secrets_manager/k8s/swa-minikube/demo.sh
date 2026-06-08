#!/bin/bash
# Secure Workload Access (SWA) + CyberArk Secrets Manager — interactive demo.
#
# Tells the full story standalone for a mixed technical + leadership audience:
#   what SPIFFE / SPIFFE IDs / SVIDs are and why they matter, how SWA attests
#   nodes and workloads, how a pod earns a cryptographic identity with NO shared
#   secret, how that identity unlocks a Conjur Cloud secret synced from Privilege
#   Cloud, live rotation, and a red-team test of the identity boundary.
#
# Presentation layer uses `gum` (https://github.com/charmbracelet/gum) when
# available for bordered panels, markdown rendering, and colored status — with a
# plain-ANSI fallback so the demo still runs anywhere.
set -uo pipefail

# Two-tone brand palette: CyberArk blue + Palo Alto orange (+ neutral gray).
RST=$'\033[0m'; BOLD=$'\033[1m'
BLUE=$'\033[38;5;33m'; ORANGE=$'\033[38;5;208m'; GRAY=$'\033[38;5;244m'
C_BLUE=33; C_ORANGE=208

export CLICOLOR_FORCE=1
HAVE_GUM=0; command -v gum >/dev/null 2>&1 && HAVE_GUM=1
TTY=0; [ -t 0 ] && TTY=1

# Panel width fills the terminal (capped for readability).
term_cols="$(tput cols 2>/dev/null)"; [ -z "$term_cols" ] && term_cols="${COLUMNS:-100}"
UIW=$(( term_cols - 2 )); [ "$UIW" -gt 118 ] && UIW=118; [ "$UIW" -lt 72 ] && UIW=72

demo_path="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$demo_path/swa_demo_lib.sh"
if ! swa_demo_init >/dev/null 2>&1; then
  printf "%sERROR: copy setup/vars.env.example to setup/vars.env first.%s\n" "$ORANGE" "$RST"
  exit 1
fi
# Sourced utility libs enable errexit; the demo must survive transient probe failures.
set +e

APP_DEPLOY="swa-demo-app"

# ── presentation helpers ───────────────────────────────────────────────────
ui_banner() {
  if [ "$HAVE_GUM" = 1 ]; then
    gum style --border double --border-foreground "$C_BLUE" --foreground "$C_BLUE" \
      --bold --align center --padding "1 4" --margin "1 0" --width "$UIW" \
      "SECURE WORKLOAD ACCESS" "CyberArk Secrets Manager  ·  SPIFFE identity for machines"
  else
    printf "\n%s== SECURE WORKLOAD ACCESS ==%s\n" "$BLUE$BOLD" "$RST"
  fi
}

ui_step() {  # $1 num  $2 total  $3 title
  printf '\n'
  if [ "$HAVE_GUM" = 1 ]; then
    gum style --foreground "$C_ORANGE" --bold "  SECURE WORKLOAD ACCESS  ·  STEP $1 / $2"
    gum style --border double --border-foreground "$C_BLUE" --foreground 255 --bold \
      --padding "0 3" --width "$UIW" "$3"
  else
    printf "%s  STEP %s/%s  %s%s\n" "$ORANGE$BOLD" "$1" "$2" "$3" "$RST"
  fi
}

# Lightweight markdown -> two-tone ANSI (no glamour theme, strict blue/orange).
# Expands a known set of demo vars via @PLACEHOLDER@.
ui_md() {
  local b="$BOLD" r="$RST" o="$ORANGE" bl="$BLUE"
  sed -e "s|@SPIFFE_ID@|${SWA_SPIFFE_ID}|g" \
      -e "s|@AUTHN@|${SWA_AUTHN_ID}|g" \
      -e "s|@TRUST_DOMAIN@|${SWA_TRUST_DOMAIN}|g" \
      -e "s|@AUD@|${SWA_JWT_AUDIENCE}|g" \
      -e "s|@SAFE@|${SAFE_NAME}|g" \
      -e "s|@USER_ID@|${SM_SECRET_USERNAME_ID}|g" \
      -e "s|@PASS_ID@|${SM_SECRET_PASSWORD_ID}|g" \
  | while IFS= read -r line; do
      case "$line" in
        '## '*) printf '\n  %s%s%s%s\n' "$o" "$b" "${line#'## '}" "$r" ;;
        '- '*)  printf '  %s•%s %s\n' "$bl" "$r" "$(printf '%s' "${line#- }" | sed -E "s/\*\*([^*]+)\*\*/${b}\1${r}/g; s/\`([^\`]+)\`/${o}\1${r}/g")" ;;
        '')     printf '\n' ;;
        *)      printf '  %s\n' "$(printf '%s' "$line" | sed -E "s/\*\*([^*]+)\*\*/${b}\1${r}/g; s/\`([^\`]+)\`/${o}\1${r}/g")" ;;
      esac
    done
}

ui_label() { printf "  %s%s%s%s\n" "$BLUE" "$BOLD" "$1" "$RST"; }
ui_attack(){ printf "\n  %s%s%s%s\n" "$ORANGE" "$BOLD" "$1" "$RST"; }

ui_run() {  # show a command (gray) then run it, indenting output
  local disp="$*"
  [ "$1" = "bash" ] && [ "$2" = "-c" ] && disp="$3"
  printf "  %s❯ %s%s\n" "$GRAY" "$disp" "$RST"
  "$@" 2>&1 | while IFS= read -r line; do printf "    %s%s%s\n" "$GRAY" "$line" "$RST"; done
}

ui_box() {  # bordered panel (blue) around stdin
  local color="${1:-$C_BLUE}"
  if [ "$HAVE_GUM" = 1 ]; then gum style --border rounded --border-foreground "$color" --padding "0 2" --width "$UIW"
  else sed 's/^/    /'; fi
}

ui_ok()   { printf "  %s✔%s  %s\n" "$BLUE" "$RST" "$1"; }
ui_warn() { printf "  %s▸%s  %s\n" "$ORANGE" "$RST" "$1"; }
ui_fail() { printf "  %s✘%s  %s\n" "$ORANGE" "$RST" "$1"; }

ui_note() {  # business-value callout (orange)
  if [ "$HAVE_GUM" = 1 ]; then
    printf '%s' "Business value — $1" | gum style --border rounded --border-foreground "$C_ORANGE" \
      --foreground "$C_ORANGE" --padding "0 2" --margin "1 0" --width "$UIW"
  else
    printf "\n  %s%sBusiness value:%s %s%s\n" "$ORANGE" "$BOLD" "$RST" "$ORANGE" "$1$RST"
  fi
}

say() { printf "    %s%s%s\n" "$GRAY" "$1" "$RST"; }

ui_pause() {
  [ "$TTY" = 1 ] || { printf '\n'; return 0; }
  printf "\n  %s▶ press ENTER to continue%s" "$GRAY" "$RST"
  read -r; printf '\n'
}

ui_confirm() {  # returns 0 for yes; auto-no when not a TTY unless CYBR_DEMO_AUTO_YES=1
  if [ "$TTY" != 1 ]; then
    [ "${CYBR_DEMO_AUTO_YES:-}" = 1 ]
    return
  fi
  if [ "$HAVE_GUM" = 1 ]; then
    gum confirm "$1" --selected.background="$C_BLUE" --selected.foreground="255" --prompt.foreground="$C_ORANGE"
  else
    local ans; printf "\n  %s▶ %s [Y/n] %s" "$ORANGE" "$1" "$RST"; read -r ans; [[ -z "$ans" || "$ans" =~ ^[yY] ]]
  fi
}

# ── crypto / kube helpers ──────────────────────────────────────────────────
b64url_decode() {
  local data="${1//-/+}"; data="${data//_//}"
  local rem=$(( ${#data} % 4 ))
  [ "$rem" -gt 0 ] && data="${data}$(printf '=%.0s' $(seq $((4 - rem))))"
  printf '%s' "$data" | base64 -d 2>/dev/null
}

extract_svid() {
  jq -r '
    (.. | objects | select(has("svid")) | .svid) //
    (if type=="array" then .[0] else . end | (.token // .jwt))
  ' "$1" 2>/dev/null | head -1
}

get_live_svid() {
  local ns="$1" deploy="$2" j f
  j="$(kubectl exec -n "$ns" deploy/"$deploy" -c app -- cat /spiffe/svid.json 2>/dev/null || true)"
  [[ -z "$j" ]] && return 1
  f="$(mktemp)"; printf '%s' "$j" > "$f"; extract_svid "$f"; rm -f "$f"
}

svid_sub() {
  local svid="$1" payload_b64
  payload_b64="${svid#*.}"; payload_b64="${payload_b64%%.*}"
  b64url_decode "$payload_b64" | jq -r '.sub' 2>/dev/null
}

# Full retrieval the way the workload does it — using the pod's own JWT-SVID.
# Echoes "<username>\t<password>" or fails.
workload_retrieve() {
  local svid ctoken u p
  svid="$(get_live_svid "$SWA_APP_NAMESPACE" "$APP_DEPLOY" || true)"
  [[ "$svid" == *.*.* ]] || return 1
  ctoken="$(curl -s --data-urlencode "jwt=${svid}" -H "Accept-Encoding: base64" \
    "https://${SM_FQDN}/api/authn-jwt/${SWA_AUTHN_ID}/conjur/authenticate" 2>/dev/null || true)"
  [[ -n "$ctoken" ]] && ! printf '%s' "$ctoken" | grep -qi 'error' || return 1
  u="$(curl -s -H "Authorization: Token token=\"${ctoken}\"" \
    "https://${SM_FQDN}/api/secrets/conjur/variable/${SM_SECRET_USERNAME_ID}" 2>/dev/null || true)"
  p="$(curl -s -H "Authorization: Token token=\"${ctoken}\"" \
    "https://${SM_FQDN}/api/secrets/conjur/variable/${SM_SECRET_PASSWORD_ID}" 2>/dev/null || true)"
  [[ -n "$u" && -n "$p" ]] || return 1
  printf '%s\t%s' "$u" "$p"
}

# The pod fetches its SVID once at start and it is short-lived. If the current
# one expired, restart the workload so the walkthrough always shows success.
ensure_fresh_svid() {
  local last
  last="$(kubectl logs -n "$SWA_APP_NAMESPACE" deploy/"$APP_DEPLOY" -c app --tail=1 2>/dev/null || true)"
  printf '%s' "$last" | grep -q "retrieved via SWA" && return 0
  say "Refreshing the workload's SVID for a clean run (one-time, ~40s)..."
  kubectl rollout restart deployment/"$APP_DEPLOY" -n "$SWA_APP_NAMESPACE" >/dev/null 2>&1
  kubectl rollout status deployment/"$APP_DEPLOY" -n "$SWA_APP_NAMESPACE" --timeout=120s >/dev/null 2>&1
  local i=0
  while [ "$i" -lt 12 ]; do
    if kubectl logs -n "$SWA_APP_NAMESPACE" deploy/"$APP_DEPLOY" -c app --tail=5 2>/dev/null | grep -q "retrieved via SWA"; then
      ui_ok "Fresh SVID issued and secret retrieved — ready to present"; return 0
    fi
    sleep 5; i=$((i + 1))
  done
  ui_warn "Could not confirm a fresh retrieval; steps will show current state"
}

# ───────────────────────────────────────────────────────────────────────────
if ! kubectl cluster-info --request-timeout=5s >/dev/null 2>&1; then
  printf "%sERROR: cannot reach the Kubernetes API. Start minikube first.%s\n" "$ORANGE" "$RST" >&2
  exit 1
fi

# ═══ Intro ═════════════════════════════════════════════════════════════════
ui_banner
ui_md <<'MD'
## The problem

Every workload — a pod, a CI job, a microservice — needs secrets: database
passwords, API keys, SSH credentials. The old answer is to hand each one a
**long-lived shared secret** and hope it never leaks. Those secrets get copied
into images, baked into manifests, and outlive the workloads that used them.
They are the #1 source of breaches.

## A better question

What if a workload could **prove what it is** — cryptographically, with no
shared secret — and that proof was all it needed to get a secret? That is
exactly what **SPIFFE + CyberArk Secure Workload Access (SWA)** deliver.
MD

ui_label "The architecture, from the ground up — follow the numbers ①→⑥"
cat <<DIAGRAM | ui_box "$C_BLUE"

 ROOT OF TRUST
   Trust domain:  ${SWA_TRUST_DOMAIN}
   • signs every SVID with its private key (RSA)
   • publishes the matching public keys as a JWKS so anyone can verify a signature
        │
        ▼  delegates issuance to in-cluster components it vouches for
 IN THE CLUSTER (Kubernetes)
   SWA Server  ──①  node attestation (k8s_psat: proves WHICH node) ──▶  SWA Agent
   identity authority                                                   issuer, one per node
        │
        ▼  ②  workload attestation — proves the pod's namespace + service account
   Workload Pod  ◀── receives an SVID  =  SPIFFE ID  +  RSA signature  (its passport)
        │
        ▼  ③  the pod presents its SVID
 CONJUR CLOUD — authn-jwt/${SWA_AUTHN_ID}
   ④ verifies the signature against the trust domain's JWKS  (no shared secret involved)
   ⑤ maps the SPIFFE ID  →  an authorized host  →  returns the secret
        ▲
        │  ⑥  the secret originates in Privilege Cloud and is mirrored here by Conjur Sync
 PRIVILEGE CLOUD safe (source of truth)  ──(Conjur Sync)──▶  Conjur Cloud store

DIAGRAM

ui_md <<'MD'
By the end you will have seen a pod with **zero embedded credentials** retrieve
a real password — using only a cryptographic identity that was minted, verified,
and expired automatically. A full color architecture walkthrough with diagrams
lives in `demo_setup.md`.
MD

if kubectl get deploy/swa-server -n "$SWA_NAMESPACE" >/dev/null 2>&1; then
  ui_ok "SWA control plane detected (run bash go.sh if anything is missing)"
  if kubectl get deploy/"$APP_DEPLOY" -n "$SWA_APP_NAMESPACE" >/dev/null 2>&1; then
    ensure_fresh_svid
  fi
else
  ui_warn "SWA not installed yet — run: bash go.sh"
fi
ui_pause

# ═══ 1 ═════════════════════════════════════════════════════════════════════
ui_step "1" "11" "SPIFFE in plain language — the vocabulary"
ui_md <<'MD'
Four terms power this entire demo. Learn these and the rest is easy.

**SPIFFE** — *Secure Production Identity Framework For Everyone.* An open
standard for verifiable workload identities — "passports for software",
vendor- and cloud-neutral.

**SPIFFE ID** — the identity itself, written as a URI. In this demo:

`@SPIFFE_ID@`

It encodes the namespace and service account: identity is derived from **what
the workload actually is**, not a name someone typed.

**SVID** — *SPIFFE Verifiable Identity Document*, the cryptographic passport
that proves a SPIFFE ID. This demo uses the **JWT-SVID**: a signed, short-lived
JSON Web Token whose `sub` claim is the SPIFFE ID.

**Trust domain** — the root of trust that signs SVIDs: your CyberArk tenant
`@TRUST_DOMAIN@`. Anyone holding its public keys (JWKS) can verify them.

**Attestation** — how an SVID is *earned*: the platform proves a workload's
properties (node, namespace, service account) before any identity is issued.
Identity is **attested, never asserted**.
MD
ui_note "A common, open identity standard means one model for workload identity across every cloud, cluster, and VM — no per-platform credential sprawl, no vendor lock-in."
ui_pause

# ═══ 2 ═════════════════════════════════════════════════════════════════════
ui_step "2" "11" "The control plane — SWA Server + Agent"
ui_md <<'MD'
SWA runs two components inside the cluster, both managed by CyberArk Conjur
Cloud (the control plane):

- **SWA Server** (Deployment) — the in-cluster identity authority. It registered
  with Conjur Cloud and decides which **nodes** are trusted.
- **SWA Agent** (DaemonSet) — one per node, the local issuer. It attests the
  workloads on its node and hands them SVIDs over a Unix socket (the SPIFFE
  *Workload API*). No workload ever calls the control plane for its identity.
MD
ui_run kubectl get pods -n "$SWA_NAMESPACE" -o wide
if [[ "$(kubectl get deploy/swa-server -n "$SWA_NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)" == "1" ]]; then
  ui_ok "SWA Server ready — the cluster's identity authority is online"
else
  ui_warn "SWA Server not ready"
fi
ds_ready="$(kubectl get ds/swa-agent -n "$SWA_NAMESPACE" -o jsonpath='{.status.numberReady}' 2>/dev/null || echo 0)"
ds_want="$(kubectl get ds/swa-agent -n "$SWA_NAMESPACE" -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo 0)"
if [[ "${ds_want:-0}" -gt 0 && "${ds_ready:-0}" == "${ds_want:-0}" ]]; then
  ui_ok "SWA Agent ready on ${ds_ready}/${ds_want} node(s) — local issuer online"
else
  ui_warn "SWA Agent not fully ready (${ds_ready:-0}/${ds_want:-0})"
fi
ui_note "Identity is issued where the workloads run — no central secret to steal and no per-workload network round-trip. It scales with the cluster and survives control-plane blips."
ui_pause

# ═══ 3 ═════════════════════════════════════════════════════════════════════
ui_step "3" "11" "Node attestation — how the Agent earns trust (k8s_psat)"
ui_md <<'MD'
Before the Agent can issue **any** identity, it must prove which node it runs
on. SWA uses **k8s_psat** (Kubernetes Projected Service Account Token):

1. The Agent presents a projected service-account token to the Server.
2. The Server verifies it via the Kubernetes **TokenReview** API.
3. The Server checks the Agent's service account against an allow-list in the
   SWA server group (policy-as-code).

Only an allow-listed, verified Agent is admitted — the trust root is the
cluster's own token issuer, not a password we configured.
MD
ui_label "Server group allow-list (terraform-managed):"
ui_run grep -E "service_account_allow_list|cluster|audience" "$demo_path/setup/swa/terraform/main.tf"
ui_label "Proof the Agent attested and is serving identities:"
ui_run bash -c "kubectl logs -n '$SWA_NAMESPACE' ds/swa-agent --tail=60 2>/dev/null | grep -iE 'attest|broadcast|bundle' | tail -4"
ui_note "A workload's identity can only originate from a node CyberArk has cryptographically verified. Compromised or rogue nodes cannot mint identities — closing a major lateral-movement path."
ui_pause

# ═══ 4 ═════════════════════════════════════════════════════════════════════
ui_step "4" "11" "Workload attestation — the pod earns its SPIFFE ID"
ui_md <<'MD'
When our pod started, its init container connected to the node-local Agent over
the Workload API socket. The Agent confirmed the caller's **namespace** and
**service account**, then minted an SVID whose SPIFFE ID follows the node
group's template:

`spiffe://{{ .trustdomain }}/{{ .nodegroup }}/ns/{{ .k8s.ns }}/sa/{{ .k8s.sa }}`

For this workload that resolves to:

`@SPIFFE_ID@`

Change the namespace or service account → a **different** SPIFFE ID → different
(or no) access. Identity is bound to what the workload actually is.
MD
ui_run kubectl get pods -n "$SWA_APP_NAMESPACE" -o wide
ui_label "The pod's service account (the basis of its identity):"
ui_run kubectl get deploy/"$APP_DEPLOY" -n "$SWA_APP_NAMESPACE" -o jsonpath='{.spec.template.spec.serviceAccountName}'
printf "\n"
ui_note "Access follows verifiable workload properties, not human-managed names or shared accounts. Audit answers 'which exact workload' — not 'which team's service account', the usual audit dead end."
ui_pause

# ═══ 5 ═════════════════════════════════════════════════════════════════════
ui_step "5" "11" "The SVID up close — decode the passport"
ui_md <<'MD'
Let's open the actual JWT-SVID the pod holds. The init container fetched it with
`swa-agent api fetch jwt -a @AUD@` and wrote it to a shared volume. A JWT has
three parts — **header.payload.signature** — all base64url-encoded.
MD
svid_json="$(kubectl exec -n "$SWA_APP_NAMESPACE" deploy/"$APP_DEPLOY" -c app -- cat /spiffe/svid.json 2>/dev/null || true)"
if [[ -z "$svid_json" ]]; then
  ui_warn "SVID file not found — the pod may still be starting (kubectl get pods -n $SWA_APP_NAMESPACE)"
else
  tmp_svid="$(mktemp)"; printf '%s' "$svid_json" > "$tmp_svid"
  svid="$(extract_svid "$tmp_svid")"; rm -f "$tmp_svid"
  if [[ "$svid" == *.*.* ]]; then
    header_b64="${svid%%.*}"; rest="${svid#*.}"; payload_b64="${rest%%.*}"
    ui_label "Header — how it is signed:"
    b64url_decode "$header_b64" | jq . 2>/dev/null | ui_box "$C_BLUE"
    ui_label "Payload — the claims (who, for whom, from where, until when):"
    b64url_decode "$payload_b64" | jq . 2>/dev/null | ui_box "$C_BLUE"
    exp="$(b64url_decode "$payload_b64" | jq -r '.exp' 2>/dev/null)"
    now="$(date +%s)"
    if [[ "$exp" =~ ^[0-9]+$ ]]; then
      ttl=$(( exp - now ))
      ui_label "Claim guide for newcomers:"
      printf "      %salg%s  RS256   the trust domain signs with RSA; tamper = invalid\n" "$BLUE$BOLD" "$RST"
      printf "      %ssub%s  ......  the SPIFFE ID — WHO this workload is\n" "$BLUE$BOLD" "$RST"
      printf "      %saud%s  %s  WHO may accept it (Conjur), blocks replay elsewhere\n" "$BLUE$BOLD" "$RST" "$SWA_JWT_AUDIENCE"
      printf "      %siss%s  ......  the trust domain that minted it\n" "$BLUE$BOLD" "$RST"
      printf "      %sexp%s  ......  hard expiry — this SVID dies in ~%ss\n" "$BLUE$BOLD" "$RST" "$ttl"
      if [ "$ttl" -gt 0 ]; then ui_ok "This passport is currently valid for ~${ttl} more seconds"
      else ui_warn "This SVID has expired — restart the workload (or re-run demo.sh) for a fresh one"; fi
    fi
  else
    ui_label "Raw SVID document:"
    printf '%s\n' "$svid_json" | head -c 600 | ui_box
  fi
fi
ui_note "Short-lived, signed, audience-bound credentials mean a stolen token is near-worthless: it expires in minutes and only Conjur will accept it. The opposite of a long-lived API key in a repo."
ui_pause

# ═══ 6 ═════════════════════════════════════════════════════════════════════
ui_step "6" "11" "Authorization — mapping the SVID to a secret in Conjur"
ui_md <<'MD'
An identity is not access. Conjur Cloud decides what this SPIFFE ID may read,
via the **authn-jwt/@AUTHN@** authenticator and policy-as-code. At runtime:

1. Verify the SVID signature against the trust domain's JWKS.
2. Read the `sub` claim (the SPIFFE ID).
3. Map it to a workload host under `data/poc-workloads` via the
   `authn-jwt/@AUTHN@/sub` annotation.
4. Confirm that host is in the authenticator's **apps** group **and** the
   safe's **delegation/consumers** group.
5. Only then return a secret.

Pull any one of these grants and the read instantly stops.
MD
ui_label "Authenticator definition (authenticator.tmpl.yaml):"
ui_run sed -n '1,30p' "$demo_path/setup/conjur/authenticator.tmpl.yaml"
ui_label "Workload host — SPIFFE ID bound to a Conjur identity:"
ui_run sed -n '14,40p' "$demo_path/setup/conjur/workload.tmpl.yaml"
ui_label "Safe access grant (least privilege):"
ui_run sed -n '1,40p' "$demo_path/setup/conjur/grant_safe_access.tmpl.yaml"
ui_note "Access is least-privilege and auditable as code: each workload sees only the exact safe paths granted to its identity. Reviews and approvals happen in Git, not scattered config."
ui_pause

# ═══ 7 ═════════════════════════════════════════════════════════════════════
ui_step "7" "11" "The source of truth — Privilege Cloud + Conjur Sync"
ui_md <<'MD'
The secret never originated in Kubernetes. It lives in a Privilege Cloud safe
(**@SAFE@**) and is replicated to Conjur Cloud by **Conjur Sync**. The workload
reads:

`@USER_ID@`
`@PASS_ID@`

Rotate the account in Privilege Cloud and the next fetch returns the new value —
no redeploy, no secret to update in the cluster.
MD
if swa_get_tokens >/dev/null 2>&1; then
  uval="$(curl -sf -H "Authorization: Token token=\"$SWA_CONJUR_TOKEN\"" \
    "https://${SM_FQDN}/api/secrets/conjur/variable/${SM_SECRET_USERNAME_ID}" 2>/dev/null || true)"
  if [[ -n "$uval" ]]; then
    ui_ok "Secret present in Conjur Cloud (synced from Privilege Cloud)"
    say "username currently = $uval"
  else
    ui_warn "Could not read the synced secret (check Conjur Sync / safe membership)"
  fi
else
  ui_warn "Could not acquire a Conjur token to confirm the synced secret"
fi
ui_note "One governed source of truth for secrets (Privilege Cloud) feeds every consumer. Rotation, audit, and policy stay centralized while workloads consume just-in-time."
ui_pause

# ═══ 8 ═════════════════════════════════════════════════════════════════════
ui_step "8" "11" "The payoff — a pod with no credentials reads a real secret"
ui_md <<'MD'
The workload presents **only** its JWT-SVID; Conjur verifies the identity and
the policy and returns the secret. No password in the image, no API key in the
manifest, no static service-account token shipped anywhere.

Let's not read a log — let's retrieve the secret **live, on demand**, using the
pod's own JWT-SVID (the exact three calls the app makes).
MD
if ui_confirm "Run the live retrieval now?"; then
  printf '\n'
  say "❯ kubectl exec ${APP_DEPLOY} -- cat /spiffe/svid.json     # the pod's identity"
  say "❯ curl .../authn-jwt/${SWA_AUTHN_ID}/conjur/authenticate  # identity -> token"
  say "❯ curl .../secrets/conjur/variable/<path>                 # token -> secret"
  if out="$(workload_retrieve)"; then
    u="${out%%$'\t'*}"; p="${out##*$'\t'}"
    ui_ok "Conjur accepted the SPIFFE identity and returned an access token"
    printf "    %sSecret retrieved live:%s  username=%s%s%s  password=%s%s%s\n" \
      "$BOLD" "$RST" "$ORANGE" "$u" "$RST" "$ORANGE" "$p" "$RST"
  else
    ui_warn "Live call didn't complete (SVID may have just expired) — app log below"
    ui_run bash -c "kubectl logs -n '$SWA_APP_NAMESPACE' deploy/'$APP_DEPLOY' -c app --tail=4 2>/dev/null | grep -E 'retrieved via SWA' | tail -2"
  fi
else
  ui_label "From the app's own continuous loop:"
  ui_run bash -c "kubectl logs -n '$SWA_APP_NAMESPACE' deploy/'$APP_DEPLOY' -c app --tail=4 2>/dev/null | grep -E 'retrieved via SWA' | tail -2"
fi
ui_label "Manifest check — the pod consumes NO Kubernetes Secret and embeds NO creds:"
secret_refs="$(kubectl get deploy/"$APP_DEPLOY" -n "$SWA_APP_NAMESPACE" -o jsonpath='{.spec.template.spec.containers[*].env[*].valueFrom.secretKeyRef.name}{.spec.template.spec.initContainers[*].env[*].valueFrom.secretKeyRef.name}{.spec.template.spec.volumes[*].secret.secretName}' 2>/dev/null)"
if [[ -z "$secret_refs" ]]; then
  ui_ok "No secretKeyRef and no Secret-backed volumes anywhere in the pod spec"
else
  ui_warn "Secret references found: $secret_refs"
fi
ui_label "Its only env vars are non-sensitive config (note: Conjur PATHS, not values):"
ui_run kubectl get deploy/"$APP_DEPLOY" -n "$SWA_APP_NAMESPACE" -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}{" = "}{.value}{"\n"}{end}'
ui_note "Developers ship apps with zero secrets in code or config. Security governs access centrally. The two teams stop fighting over secret distribution — the platform handles it, provably."
ui_pause

# ═══ 9 ═════════════════════════════════════════════════════════════════════
ui_step "9" "11" "Rotate the secret live — change it upstream, watch the pod follow"
ui_md <<'MD'
The real test of a secrets platform: rotate the credential at the **source** and
see consumers pick it up with **no redeploy and no new identity**. We'll change
the password in Privilege Cloud, watch Conjur Sync replicate it, then have the
**same pod (same SVID)** read the new value live.
MD
ui_label "Current value (retrieved live by the workload):"
before="$(workload_retrieve || true)"
if [[ -n "$before" ]]; then
  printf "    password = %s%s%s\n" "$ORANGE" "${before##*$'\t'}" "$RST"
else
  ui_warn "Could not read the current value via the workload (continuing)"
fi

if ui_confirm "Rotate the password in Privilege Cloud now?"; then
  new_pw="Rotated-$(date +%H%M%S)!"
  printf "\n"; ui_label "Setting a new password in Privilege Cloud: $new_pw"
  if swa_get_tokens >/dev/null 2>&1; then
    op_identity="$(get_identity_token "$TENANT_ID" "$CLIENT_ID" "$CLIENT_SECRET" 2>/dev/null || true)"
    acct_id="$(get_account_id_by_safe "$TENANT_SUBDOMAIN" "$op_identity" "$SAFE_NAME" 2>/dev/null || true)"
    if [[ -n "$acct_id" && -n "$op_identity" ]]; then
      if set_account_password "$TENANT_SUBDOMAIN" "$op_identity" "$acct_id" "$new_pw"; then
        ui_ok "Privilege Cloud account updated (id ${acct_id}) — no CPM target needed"
        printf "    %sWaiting for Conjur Sync to replicate the change%s" "$GRAY" "$RST"
        synced=""
        for _ in $(seq 1 40); do
          cur="$(curl -s -H "Authorization: Token token=\"$SWA_CONJUR_TOKEN\"" \
            "https://${SM_FQDN}/api/secrets/conjur/variable/${SM_SECRET_PASSWORD_ID}" 2>/dev/null || true)"
          [[ "$cur" == "$new_pw" ]] && { synced="yes"; break; }
          printf "."; sleep 3
        done
        printf "\n"
        if [[ -n "$synced" ]]; then
          ui_ok "Conjur Cloud now serves the rotated value"
          ui_label "Same pod, same SVID — read the secret again, live:"
          after="$(workload_retrieve || true)"
          if [[ -n "$after" ]]; then
            printf "    password %s(before)%s = %s%s%s\n" "$GRAY" "$RST" "$GRAY" "${before##*$'\t'}" "$RST"
            printf "    password %s(after) %s = %s%s%s\n" "$GRAY" "$RST" "$ORANGE" "${after##*$'\t'}" "$RST"
            if [[ "${after##*$'\t'}" == "$new_pw" ]]; then
              ui_ok "The running workload retrieved the NEW value — zero redeploy"
            else
              ui_warn "Workload still shows the old value (Conjur Sync or app loop may need a moment)"
            fi
          fi
        else
          ui_warn "Sync still in progress (>120s); the pod will pick up the new value on its next fetch"
        fi
      else
        ui_warn "Privilege Cloud rejected the password update — skipping rotation demo"
      fi
    else
      ui_warn "Could not resolve the Privilege Cloud account id — skipping rotation"
    fi
  else
    ui_warn "Could not acquire tokens for rotation — skipping"
  fi
else
  say "Skipped rotation. (Tip: rotation is the everyday win — worth showing.)"
fi
ui_note "Rotate at the source and every consumer follows automatically. No redeploys, no secret copies to chase, no downtime — and the workload's identity never changed. Lifecycle management, not key sprawl."
ui_pause

# ═══ 10 ════════════════════════════════════════════════════════════════════
ui_step "10" "11" "Red-team the boundary — try to break in (live)"
ui_md <<'MD'
Talk is cheap. Let's **attack** the system live and watch it hold. Two classic
attacks against machine credentials:

1. Steal a token and tamper with it.
2. Stand up a look-alike workload and ask for the secret.

We'll do **both** right now, against the real Conjur Cloud tenant.
MD

# Attack 1 — tamper with the SVID signature
ui_attack "Attack #1 — steal the token and forge it"
say "We take the pod's REAL JWT-SVID, flip one character of its signature, and"
say "present the forged token to Conjur — exactly what a thief would try."
real_svid="$(get_live_svid "$SWA_APP_NAMESPACE" "$APP_DEPLOY" || true)"
if [[ "$real_svid" == *.*.* ]]; then
  sig="${real_svid##*.}"; hp="${real_svid%.*}"
  flip="A"; [[ "${sig:0:1}" == "A" ]] && flip="B"
  forged="${hp}.${flip}${sig:1}"
  ui_label "Present the FORGED token to authn-jwt/${SWA_AUTHN_ID}:"
  forged_code="$(curl -s -o /dev/null -w '%{http_code}' \
    --data-urlencode "jwt=${forged}" -H "Accept-Encoding: base64" \
    "https://${SM_FQDN}/api/authn-jwt/${SWA_AUTHN_ID}/conjur/authenticate" 2>/dev/null || true)"
  if [[ "$forged_code" == "200" ]]; then
    ui_fail "Forged token was ACCEPTED (HTTP 200) — unexpected; investigate"
  else
    ui_fail "Conjur REJECTED the forged token — HTTP ${forged_code:-no-response}"
    say "The signature no longer matches the trust domain's keys, so Conjur refuses"
    say "before it even looks at policy. Tampering is detected."
  fi
  ui_label "For contrast, the UNMODIFIED token still works:"
  real_code="$(curl -s -o /dev/null -w '%{http_code}' \
    --data-urlencode "jwt=${real_svid}" -H "Accept-Encoding: base64" \
    "https://${SM_FQDN}/api/authn-jwt/${SWA_AUTHN_ID}/conjur/authenticate" 2>/dev/null || true)"
  if [[ "$real_code" == "200" ]]; then
    ui_ok "Genuine SVID accepted — HTTP 200 (Conjur returns an access token)"
  else
    ui_warn "Genuine SVID returned HTTP ${real_code} (may have expired — ensure_fresh_svid restarts the pod)"
  fi
else
  ui_warn "Could not read a live SVID to tamper with (is the workload running?)"
fi
ui_note "A stolen SVID cannot be modified or extended — any edit invalidates the signature. Combined with minutes-long expiry, theft buys an attacker almost nothing. Unforgeable identity, not a shared password."
ui_pause

# Attack 2 — imposter workload (wrong identity)
ui_attack "Attack #2 — deploy a look-alike workload and ask for the secret"
say "The scary one: we deploy the EXACT same image and code as our trusted app,"
say "but into a different namespace with a different service account. If access"
say "were based on the image, it would succeed. With SWA it should fail."
ROGUE_NS="swa-rogue"; ROGUE_DEPLOY="rogue-app"; ROGUE_SA="rogue-app"
if ui_confirm "Deploy the imposter into namespace '${ROGUE_NS}' now? (~60s)"; then
  say "Cloning the trusted deployment into ${ROGUE_NS}/${ROGUE_SA}..."
  kubectl create namespace "$ROGUE_NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1
  kubectl create serviceaccount "$ROGUE_SA" -n "$ROGUE_NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1
  if kubectl get deploy/"$APP_DEPLOY" -n "$SWA_APP_NAMESPACE" -o json 2>/dev/null \
      | jq --arg ns "$ROGUE_NS" --arg sa "$ROGUE_SA" --arg nm "$ROGUE_DEPLOY" '
          .metadata.namespace=$ns
          | .metadata.name=$nm
          | .spec.selector.matchLabels.app=$nm
          | .spec.template.metadata.labels.app=$nm
          | .spec.template.spec.serviceAccountName=$sa
          | del(.status, .metadata.uid, .metadata.resourceVersion,
                .metadata.creationTimestamp, .metadata.generation,
                .metadata.annotations, .spec.template.metadata.creationTimestamp)
        ' | kubectl apply -f - >/dev/null 2>&1; then
    kubectl rollout status deploy/"$ROGUE_DEPLOY" -n "$ROGUE_NS" --timeout=90s >/dev/null 2>&1 || true
    sleep 8
    rogue_svid="$(get_live_svid "$ROGUE_NS" "$ROGUE_DEPLOY" || true)"
    ui_label "Did SWA still issue the imposter an identity?"
    if [[ "$rogue_svid" == *.*.* ]]; then
      rogue_id="$(svid_sub "$rogue_svid")"
      ui_ok "Yes — SWA fairly issued an SVID (identity is not a secret)"
      say "imposter SPIFFE ID: $rogue_id"
      say "trusted  SPIFFE ID: $SWA_SPIFFE_ID"
      say "Different namespace + service account => a DIFFERENT SPIFFE ID."
    else
      ui_ok "SWA refused to issue an SVID to the unrecognized workload"
    fi
    ui_label "Present the imposter's (valid) SVID to Conjur for the secret:"
    if [[ "$rogue_svid" == *.*.* ]]; then
      rogue_resp="$(curl -s -w $'\n%{http_code}' \
        --data-urlencode "jwt=${rogue_svid}" -H "Accept-Encoding: base64" \
        "https://${SM_FQDN}/api/authn-jwt/${SWA_AUTHN_ID}/conjur/authenticate" 2>/dev/null || true)"
      rogue_code="${rogue_resp##*$'\n'}"; rogue_body="${rogue_resp%$'\n'*}"
      if [[ "$rogue_code" == "200" ]]; then
        ui_fail "Imposter AUTHENTICATED — unexpected; check the host mapping"
      else
        ui_fail "Conjur REJECTED the imposter — HTTP ${rogue_code:-no-response}"
        [[ -n "$rogue_body" ]] && say "Conjur says: $(printf '%s' "$rogue_body" | head -c 160)"
        ui_ok "Identity issued, but it maps to NO authorized Conjur host — access denied"
      fi
    else
      ui_ok "No usable SVID for the imposter — denied at issuance"
    fi
    ui_label "Side by side:"
    printf "    %s  ✔ trusted%s  ns/%s  sa/%s  -> SVID issued -> Conjur ALLOW -> secret\n" "$BLUE" "$RST" "$SWA_APP_NAMESPACE" "$SWA_APP_SA"
    printf "    %s  ✘ imposter%s ns/%s  sa/%s     -> SVID issued -> Conjur DENY  -> nothing\n" "$ORANGE" "$RST" "$ROGUE_NS" "$ROGUE_SA"
    say "Cleaning up the imposter namespace..."
    kubectl delete namespace "$ROGUE_NS" --wait=false >/dev/null 2>&1 || true
    ui_ok "Imposter removed"
  else
    ui_warn "Could not clone the deployment (jq/kubectl issue) — skipping imposter"
    kubectl delete namespace "$ROGUE_NS" --wait=false >/dev/null 2>&1 || true
  fi
else
  say "Skipped. (The trusted app keeps running untouched.)"
fi
ui_note "Identity is bound to the workload's real properties, not its image or code. An attacker who copies your container still cannot become your workload — so least-privilege access actually holds at runtime."
ui_pause

# ═══ 11 ════════════════════════════════════════════════════════════════════
ui_step "11" "11" "Demo complete"
ui_md <<'MD'
## What we demonstrated

- SPIFFE concepts from zero: SPIFFE ID, SVID, trust domain, attestation
- SWA Server + Agent issuing identities **inside** the cluster
- Node attestation (k8s_psat) — only verified nodes can issue
- Workload attestation — identity bound to namespace + service account
- A live JWT-SVID decoded claim by claim (signed, audience-bound, short-lived)
- **authn-jwt/@AUTHN@** mapping the SPIFFE ID to least-privilege access as code
- Secret sourced from Privilege Cloud via Conjur Sync
- **Live retrieval** on demand, and **live rotation** with zero redeploy
- **Red-team:** a tampered SVID rejected, a look-alike imposter denied

## Executive takeaway

Secure Workload Access replaces long-lived, leak-prone machine secrets with
short-lived, cryptographically attested identities — an open standard (SPIFFE)
governed by CyberArk:

- Dramatically reduced credential attack surface (no static keys)
- Provable, least-privilege, audit-as-code access for every workload
- One identity model across clouds, clusters, and VMs — no lock-in
- Faster delivery: developers ship with no secrets to manage
MD

if [ "$TTY" = 1 ] && ui_confirm "Explore live with k9s?"; then
  command -v k9s >/dev/null 2>&1 && k9s -n "$SWA_APP_NAMESPACE"
fi
printf "\n"
