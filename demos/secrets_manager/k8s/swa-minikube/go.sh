#!/bin/bash
# One-shot bootstrap for the SWA (Secure Workload Access) Kubernetes demo.
set -euo pipefail

demo_path="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$demo_path/swa_demo_lib.sh"

printf '\n========== SWA demo bootstrap (go.sh) ==========\n\n'

if [[ ! -f "$demo_path/setup/vars.env" ]]; then
  printf '[BLOCKED] Missing setup/vars.env\n'
  printf '  cp setup/vars.env.example setup/vars.env  (then edit)\n\n'
  exit 1
fi

if [[ "${SKIP_SWA_PREREQ_CHECK:-}" != "1" ]]; then
  bash "$demo_path/check_prereqs.sh"
fi

swa_demo_init

total=8
stage=0
next_stage() { stage=$((stage + 1)); printf '\n--- %d/%d %s ---\n' "$stage" "$total" "$1"; }

next_stage 'Stage SWA release (extract, minikube image load, terraform provider mirror)'
bash "$demo_path/setup/swa/load_release.sh"

next_stage 'Privilege Cloud safe + account + Conjur Sync'
bash "$demo_path/setup/vault/setup.sh"

next_stage 'Register SWA objects in Conjur Cloud (terraform)'
bash "$demo_path/setup/swa/register.sh"

next_stage 'Install SWA Server + Agent (helm)'
bash "$demo_path/setup/swa/install_server.sh"
bash "$demo_path/setup/swa/install_agent.sh"

next_stage 'Configure authn-jwt/secureWorkloadAccess + workload grants'
bash "$demo_path/setup/conjur/enable_swa_authenticator.sh"

next_stage 'Deploy demo workload'
bash "$demo_path/setup/swa/deploy_workload.sh"

if [[ "${SKIP_SPIFFE_INFO:-}" != "1" ]]; then
  next_stage 'Deploy spiffe-info inspector (optional UI)'
  bash "$demo_path/setup/swa/deploy_spiffe_info.sh" || \
    printf '[WARN] spiffe-info deploy failed (image pull?) — set SKIP_SPIFFE_INFO=1 to skip\n'
fi

if [[ "${SKIP_ACME:-}" != "1" ]]; then
  next_stage 'Deploy foreign trust-domain acme-carrier (trust-boundary demo)'
  bash "$demo_path/setup/swa/deploy_acme.sh" || \
    printf '[WARN] acme-carrier deploy failed — set SKIP_ACME=1 to skip\n'
fi

printf '\n========== READY ==========\n'
printf '  Verify:  bash ready_check.sh   (M3)\n'
printf '  Smoke:   bash smoke.sh         (M1 + M2 + M3)\n'
printf '  Present: bash demo.sh\n'
printf '  UI:      kubectl port-forward -n %s svc/spiffe-info 8080:80\n' "$SWA_APP_NAMESPACE"
printf '  Logs:    kubectl logs -n %s deploy/swa-demo-app -c app -f\n\n' "$SWA_APP_NAMESPACE"
