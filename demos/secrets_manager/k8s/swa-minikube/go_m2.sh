#!/bin/bash
# Bootstrap M2: Conjur authn-jwt + workload grants (requires M1).
set -euo pipefail

demo_path="$(cd "$(dirname "$0")" && pwd)"

printf '\n========== SWA demo bootstrap M2 ==========\n\n'
bash "$demo_path/setup/conjur/enable_swa_authenticator.sh"

printf '\n========== M2 READY ==========\n'
printf '  Verify: bash smoke_m2.sh\n'
printf '  Next:   bash go_m3.sh\n\n'
