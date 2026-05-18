#!/bin/bash
# secure_ai_agents/spiffe_conjur — top-level setup.
#
# Stages (each is independently runnable from setup/<stage>/setup.sh):
#   1. SPIRE on minikube                 setup/spire/setup.sh
#   2. Workloads (BEFORE + AFTER pods)   setup/workloads/setup.sh
#   3. Cloudflared OIDC tunnel           setup/oidc/setup.sh
#   4. Conjur Cloud authn-jwt + secret   setup/conjur/setup.sh

# shellcheck disable=SC1091
set -euo pipefail

# Auto-detect CYBR_DEMOS_PATH from this script's own location so users can
# `cd <demo>; ./setup.sh` without first exporting it.
if [ -z "${CYBR_DEMOS_PATH:-}" ]; then
  CYBR_DEMOS_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
  export CYBR_DEMOS_PATH
fi

demo_path="$CYBR_DEMOS_PATH/demos/secure_ai_agents/spiffe_conjur"

# First-run convenience: seed vars.env from the tracked example so the user
# doesn't have to remember to `cp` before the first setup.
if [ ! -f "$demo_path/setup/vars.env" ] && [ -f "$demo_path/setup/vars.env.example" ]; then
  printf "[INFO] Seeding setup/vars.env from setup/vars.env.example (edit if needed)\n"
  cp "$demo_path/setup/vars.env.example" "$demo_path/setup/vars.env"
fi

set -a
source "$CYBR_DEMOS_PATH/demos/setup_env.sh"
source "$demo_path/setup/vars.env"
set +a

printf "\n[INFO] Secure AI Agents: SPIFFE -> Conjur Cloud Demo Setup\n"
printf "[INFO] USECASE_ID         : %s\n" "$USECASE_ID"
printf "[INFO] Tenant subdomain   : %s\n" "$TENANT_SUBDOMAIN"
printf "[INFO] Trust domain       : %s\n" "$TRUST_DOMAIN"
printf "[INFO] Workload SPIFFE ID : %s\n" "$SPIFFE_HOST_ID"
printf "[INFO] Conjur secret      : %s\n" "$CONJUR_SECRET_VARIABLE"

printf "\n[INFO] Stage 1: SPIRE control plane on minikube\n"
cd "$demo_path/setup/spire"
./setup.sh

printf "\n[INFO] Stage 2: Workloads (vulnerable + attested agents)\n"
cd "$demo_path/setup/workloads"
./setup.sh

printf "\n[INFO] Stage 3: Cloudflared tunnel + SPIRE jwtIssuer alignment\n"
cd "$demo_path/setup/oidc"
./setup.sh

printf "\n[INFO] Stage 4: Conjur Cloud authn-jwt + vaulted secret\n"
cd "$demo_path/setup/conjur"
./setup.sh

printf "\n[INFO] Setup complete. Run demo.sh to walk through the scenario.\n"
