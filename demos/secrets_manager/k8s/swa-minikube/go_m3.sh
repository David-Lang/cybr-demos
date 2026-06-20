#!/bin/bash
# Bootstrap M3: demo workload + spiffe-info + acme-carrier (requires M2).
set -euo pipefail

demo_path="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$demo_path/swa_demo_lib.sh"
swa_demo_init

printf '\n========== SWA demo bootstrap M3 ==========\n\n'

bash "$demo_path/setup/swa/deploy_workload.sh"

if [[ "${SKIP_SPIFFE_INFO:-}" != "1" ]]; then
  bash "$demo_path/setup/swa/deploy_spiffe_info.sh" || \
    printf '[WARN] spiffe-info deploy failed — set SKIP_SPIFFE_INFO=1 to skip\n'
fi

if [[ "${SKIP_ACME:-}" != "1" ]]; then
  bash "$demo_path/setup/swa/deploy_acme.sh" || \
    printf '[WARN] acme-carrier deploy failed — set SKIP_ACME=1 to skip\n'
fi

printf '\n========== M3 READY ==========\n'
printf '  Verify: bash ready_check.sh\n'
printf '  Smoke:  bash smoke.sh\n'
printf '  Present: bash demo.sh\n\n'
