#!/bin/bash
# Bootstrap through M1 only: release, vault, terraform, SWA Server + Agent.
set -euo pipefail

demo_path="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$demo_path/swa_demo_lib.sh"

printf '\n========== SWA demo bootstrap M1 ==========\n\n'

[[ -f "$demo_path/setup/vars.env" ]] || {
  printf '[BLOCKED] Missing setup/vars.env\n'
  exit 1
}
[[ "${SKIP_SWA_PREREQ_CHECK:-}" != "1" ]] && bash "$demo_path/check_prereqs.sh"

swa_demo_init

bash "$demo_path/setup/swa/load_release.sh"
bash "$demo_path/setup/vault/setup.sh"
bash "$demo_path/setup/swa/register.sh"
bash "$demo_path/setup/swa/install_server.sh"
bash "$demo_path/setup/swa/install_agent.sh"

printf '\n========== M1 READY ==========\n'
printf '  Verify: bash smoke_m1.sh\n'
printf '  Next:   bash go_m2.sh\n\n'
