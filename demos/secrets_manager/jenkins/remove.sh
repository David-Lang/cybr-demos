#!/bin/bash
set -euo pipefail

demo_path="$CYBR_DEMOS_PATH/demos/secrets_manager/jenkins"
vars_file="$demo_path/setup/vars.env"

if [ ! -f "$vars_file" ]; then
  printf "Missing %s — nothing to remove.\n" "$vars_file" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
source "$CYBR_DEMOS_PATH/demos/setup_env.sh"
# shellcheck disable=SC1091
source "$vars_file"
set +a

cd "$demo_path/setup/conjur" && ./remove.sh

cd "$demo_path/setup/vault" && ./remove.sh

# Optional: stop the Edge container if it was used. Always safe to call even
# when Edge was never set up (the script is a no-op if no container exists).
if [[ -x "$demo_path/setup/edge/remove.sh" ]]; then
  cd "$demo_path/setup/edge" && ./remove.sh
fi

cd "$demo_path/setup/jenkins" && ./remove.sh

printf "\n[INFO] Jenkins demo teardown complete.\n"
