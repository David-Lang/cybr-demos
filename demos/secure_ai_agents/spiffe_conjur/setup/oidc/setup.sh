#!/bin/bash
# setup/oidc/setup.sh
#
# Stage 3: expose the SPIRE OIDC discovery provider via cloudflared so that
# CyberArk Conjur Cloud's authn-jwt authenticator can fetch the JWKS over the
# public internet. Then helm-upgrade SPIRE Server's jwtIssuer to match the
# tunnel URL so JWT-SVID `iss` claims line up with what Conjur Cloud sees.
#
# Modes:
#   - Quick tunnel (default): no cloudflared account required, ephemeral URL.
#     Re-run this stage and re-run setup/conjur/setup.sh after each restart.
#   - Named tunnel: set CLOUDFLARED_TUNNEL_NAME + CLOUDFLARED_TUNNEL_HOSTNAME
#     in setup/vars.env for a stable URL across demo sessions.
#
# Stop with: setup/oidc/setup.sh --stop
# Status   : setup/oidc/setup.sh --status

# shellcheck disable=SC1091
set -euo pipefail

if [ -z "${CYBR_DEMOS_PATH:-}" ]; then
  CYBR_DEMOS_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
  export CYBR_DEMOS_PATH
fi

demo_path="$CYBR_DEMOS_PATH/demos/secure_ai_agents/spiffe_conjur"

set -a
source "$CYBR_DEMOS_PATH/demos/setup_env.sh"
source "$demo_path/setup/vars.env"
set +a

stage_dir="$demo_path/setup/oidc"
state_dir="$stage_dir/state"
mkdir -p "$state_dir"

PORT_FORWARD_PID_FILE="$state_dir/port-forward.pid"
CLOUDFLARED_PID_FILE="$state_dir/cloudflared.pid"
CLOUDFLARED_LOG="$state_dir/cloudflared.log"
PORT_FORWARD_LOG="$state_dir/port-forward.log"
ENV_LOCAL="$demo_path/setup/.oidc.env"
SVC_NAME="spire-spiffe-oidc-discovery-provider"

kctx() { kubectl --context "$MINIKUBE_PROFILE" "$@"; }

stop_tunnel() {
  printf "\n[INFO] OIDC: stopping tunnel + port-forward\n"
  for f in "$CLOUDFLARED_PID_FILE" "$PORT_FORWARD_PID_FILE"; do
    if [ -f "$f" ]; then
      pid=$(cat "$f")
      if kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
        sleep 1
        kill -9 "$pid" 2>/dev/null || true
        printf "[INFO] OIDC: killed pid %s (%s)\n" "$pid" "$(basename "$f")"
      fi
      rm -f "$f"
    fi
  done
  pkill -f "kubectl.*port-forward.*$SVC_NAME" 2>/dev/null || true
  pkill -f "cloudflared.*tunnel.*localhost:$CLOUDFLARED_LOCAL_PORT" 2>/dev/null || true
}

case "${1:-start}" in
  --stop|stop) stop_tunnel; exit 0 ;;
  --status|status)
    if [ -f "$CLOUDFLARED_PID_FILE" ] && kill -0 "$(cat "$CLOUDFLARED_PID_FILE")" 2>/dev/null; then
      printf "[INFO] OIDC: cloudflared running (pid %s)\n" "$(cat "$CLOUDFLARED_PID_FILE")"
      [ -f "$ENV_LOCAL" ] && grep OIDC_PUBLIC_URL "$ENV_LOCAL" || true
    else
      printf "[WARN] OIDC: cloudflared not running\n"
    fi
    exit 0
    ;;
esac

if ! command -v cloudflared >/dev/null 2>&1; then
  printf "[FAIL] cloudflared not installed (brew install cloudflared / see compute_init)\n" >&2
  exit 1
fi
if ! kctx -n "$SPIRE_NAMESPACE" get svc "$SVC_NAME" >/dev/null 2>&1; then
  printf "[FAIL] svc/%s missing in namespace %s — run setup/spire/setup.sh first\n" "$SVC_NAME" "$SPIRE_NAMESPACE" >&2
  exit 1
fi

[ -f "$CLOUDFLARED_PID_FILE" ] && { printf "[INFO] OIDC: previous tunnel detected — restarting\n"; stop_tunnel; }

printf "\n[INFO] OIDC: kubectl port-forward localhost:%s -> %s:8080\n" "$CLOUDFLARED_LOCAL_PORT" "$SVC_NAME"
kctx -n "$SPIRE_NAMESPACE" port-forward "svc/$SVC_NAME" "$CLOUDFLARED_LOCAL_PORT:8080" >"$PORT_FORWARD_LOG" 2>&1 &
PF_PID=$!
echo "$PF_PID" >"$PORT_FORWARD_PID_FILE"

for _ in $(seq 1 30); do
  if curl -sf "http://localhost:$CLOUDFLARED_LOCAL_PORT/.well-known/openid-configuration" >/dev/null 2>&1; then
    break
  fi
  sleep 0.5
done
if ! curl -sf "http://localhost:$CLOUDFLARED_LOCAL_PORT/.well-known/openid-configuration" >/dev/null 2>&1; then
  printf "[FAIL] port-forward never became reachable on localhost:%s\n" "$CLOUDFLARED_LOCAL_PORT" >&2
  cat "$PORT_FORWARD_LOG" >&2 || true
  exit 1
fi
printf "[INFO] OIDC: port-forward live (pid %s)\n" "$PF_PID"

if [ -n "${CLOUDFLARED_TUNNEL_NAME:-}" ]; then
  printf "\n[INFO] OIDC: starting NAMED cloudflared tunnel %s\n" "$CLOUDFLARED_TUNNEL_NAME"
  nohup cloudflared tunnel --no-autoupdate run --url "http://localhost:$CLOUDFLARED_LOCAL_PORT" "$CLOUDFLARED_TUNNEL_NAME" \
    >"$CLOUDFLARED_LOG" 2>&1 &
  CF_PID=$!
  TUNNEL_URL="https://$CLOUDFLARED_TUNNEL_HOSTNAME"
else
  printf "\n[INFO] OIDC: starting QUICK cloudflared tunnel -> http://localhost:%s\n" "$CLOUDFLARED_LOCAL_PORT"
  printf "[INFO] OIDC: (set CLOUDFLARED_TUNNEL_NAME in vars.env for a stable URL)\n"
  nohup cloudflared tunnel --no-autoupdate --url "http://localhost:$CLOUDFLARED_LOCAL_PORT" \
    >"$CLOUDFLARED_LOG" 2>&1 &
  CF_PID=$!
  TUNNEL_URL=""
  for _ in $(seq 1 60); do
    if [ -s "$CLOUDFLARED_LOG" ]; then
      TUNNEL_URL=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$CLOUDFLARED_LOG" | head -1 || true)
      [ -n "$TUNNEL_URL" ] && break
    fi
    sleep 1
  done
fi

echo "$CF_PID" >"$CLOUDFLARED_PID_FILE"

if [ -z "$TUNNEL_URL" ]; then
  printf "[FAIL] cloudflared did not produce a public URL; tail -f %s\n" "$CLOUDFLARED_LOG" >&2
  exit 1
fi
printf "[INFO] OIDC: tunnel URL = %s\n" "$TUNNEL_URL"

printf "\n[INFO] OIDC: probing %s/keys (cloudflared edge propagation)\n" "$TUNNEL_URL"
JWKS_OK=0
for _ in $(seq 1 30); do
  if curl -sf "$TUNNEL_URL/keys" | grep -q '"keys"'; then
    JWKS_OK=1
    break
  fi
  sleep 1
done
[ "$JWKS_OK" -eq 1 ] && printf "[INFO] OIDC: JWKS endpoint reachable from public internet\n" \
                       || printf "[WARN] OIDC: JWKS endpoint not yet responding (try: curl -v %s/keys)\n" "$TUNNEL_URL"

printf "\n[INFO] OIDC: writing %s\n" "$ENV_LOCAL"
cat >"$ENV_LOCAL" <<EOF
# Generated by setup/oidc/setup.sh on $(date -u +%FT%TZ)
# DO NOT COMMIT. Regenerated each time the cloudflared tunnel restarts.
OIDC_PUBLIC_URL="$TUNNEL_URL"
OIDC_JWKS_URL="$TUNNEL_URL/keys"
OIDC_ISSUER="$TUNNEL_URL"
EOF

printf "\n[INFO] OIDC: helm upgrade SPIRE Server jwtIssuer to %s\n" "$TUNNEL_URL"
helm upgrade spire "$SPIRE_HELM_REPO_NAME/spire" \
  --version "$SPIRE_VERSION" \
  --namespace "$SPIRE_NAMESPACE" \
  --reuse-values \
  --set "global.spire.jwtIssuer=$TUNNEL_URL" \
  --wait --timeout 5m

kctx -n "$SPIRE_NAMESPACE" rollout restart statefulset/spire-server
kctx -n "$SPIRE_NAMESPACE" rollout status  statefulset/spire-server --timeout=180s

printf "\n[INFO] OIDC: stage complete — JWT-SVIDs now issued with iss=%s\n" "$TUNNEL_URL"
