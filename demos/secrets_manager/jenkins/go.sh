#!/bin/bash
# One-shot bootstrap: Jenkins + TLS + CyberArk policy + plugin + pipeline job.
set -euo pipefail

demo_path="$(cd "$(dirname "$0")" && pwd)"
export CYBR_DEMOS_PATH="${CYBR_DEMOS_PATH:-$(cd "$demo_path/../../.." && pwd)}"

# shellcheck disable=SC1091
source "$demo_path/jenkins_demo_lib.sh"
jenkins_demo_init

printf '\n========== Jenkins demo bootstrap (go.sh) ==========\n\n'

if [[ ! -f "$JENKINS_LOCAL_VARS" ]]; then
  printf '[BLOCKED] Missing %s\n' "$JENKINS_LOCAL_VARS"
  printf '  cp demos/tenant_vars.local.sh.example demos/tenant_vars.local.sh\n'
  printf '  Add TENANT_ID, CLIENT_ID, CLIENT_SECRET from your CyberArk tenant.\n'
  printf '  Re-run: bash go.sh\n\n'
  exit 1
fi

if [[ "${SKIP_JENKINS_PREREQ_CHECK:-}" != "1" ]]; then
  bash "$demo_path/check_prereqs.sh"
fi

jenkins_load_env

# Stage count adapts to the auth target: cloud=6 stages, edge=7 (extra Edge bring-up).
if [[ "${CONJUR_AUTH_TARGET:-cloud}" == "edge" ]]; then
  total=7
else
  total=6
fi
stage=0
next_stage() { stage=$((stage + 1)); printf '\n--- %d/%d %s ---\n' "$stage" "$total" "$1"; }

next_stage 'Jenkins container + public JWKS URL'
cd "$demo_path/setup/jenkins" && ./setup.sh

next_stage 'Render pipeline script'
bash "$demo_path/render_pipeline.sh"

next_stage 'Secrets Manager TLS cert -> Jenkins truststore'
bash "$demo_path/import_sm_cert.sh"

next_stage 'Privilege Cloud safe + Conjur JWT policy'
cd "$demo_path/setup/vault" && ./setup.sh
cd "$demo_path/setup/conjur" && ./setup.sh

# Optional: bring up Conjur Cloud Edge if the demo is configured for edge mode
# AND a SaaS-generated install script is present. Skipped cleanly in cloud mode.
if [[ "${CONJUR_AUTH_TARGET:-cloud}" == "edge" ]]; then
  if [[ -f "$demo_path/setup/edge/install.sh" ]]; then
    next_stage 'Conjur Cloud Edge bring-up (CONJUR_AUTH_TARGET=edge)'
    bash "$demo_path/setup/edge/setup.sh"
  else
    printf '\n[BLOCKED] CONJUR_AUTH_TARGET=edge but setup/edge/install.sh is missing.\n'
    printf '          Generate one in the Secrets Manager UI Edges page and save it there,\n'
    printf '          then re-run: bash go.sh\n'
    printf '          See: setup/edge/README.md for full instructions.\n\n'
    exit 1
  fi
fi

next_stage 'Jenkins plugin + pipeline job'
bash "$demo_path/configure_jenkins.sh"

# configure_jenkins.sh restarts Jenkins, which rotates the plugin's in-memory
# JWKS signing key. finish_setup.sh re-syncs the Conjur trust mode (public-keys
# or jwks-uri), recreates the Jenkins-side credential entries, pushes the
# pipeline, and runs a sanity build.
next_stage 'Bind Conjur authenticator + Jenkins credentials (finish_setup.sh)'
cd "$demo_path" && bash "$demo_path/finish_setup.sh"

printf '\n========== READY ==========\n'
port="${JENKINS_PORT:-8081}"
trust_mode="${JWT_TRUST_MODE:-public-keys}"
auth_target="${CONJUR_AUTH_TARGET:-cloud}"
printf '  Local UI:    http://127.0.0.1:%s\n' "$port"
printf '  Pipeline:    http://127.0.0.1:%s/job/global-credentials-demo/\n' "$port"
printf '  Auth target: %s\n' "$auth_target"
printf '  JWT trust:   %s\n' "$trust_mode"
case "$trust_mode" in
  public-keys) printf '               (Conjur verifies signatures locally against mirrored JWKS)\n' ;;
  jwks-uri)    printf '               (Conjur fetches JWKS over HTTP at policy lookup time)\n' ;;
esac
printf '\n  Verify:  bash ready_check.sh\n'
printf '  Present: bash demo.sh\n'
printf '  Re-bind: bash finish_setup.sh   # if anything looks off after a Jenkins restart\n\n'
