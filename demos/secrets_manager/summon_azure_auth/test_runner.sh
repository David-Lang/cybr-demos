#!/bin/bash
# Non-interactive validation of the workshop ACTIVITY SETUP (the automatable
# part): runs the VM orchestrator, then proves the hardcoded query works against
# the VM-local Postgres.
#
# The secured (Summon) and rotate (SRS) steps require the student to vault the
# credential and the Idira System connector, so they are NOT covered here.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="$SCRIPT_DIR"
ARTIFACTS_DIR="$DEMO_DIR/artifacts"
LABS_ROOT="${LABS_ROOT:-/opt/labs}"
STUDENT_PREFIX="${STUDENT_PREFIX:-student}"
ACTIVITY_DIR_NAME="${ACTIVITY_DIR_NAME:-hardcoded-secret-remediation}"

if [ -f /etc/profile.d/cyberark.sh ]; then
  # shellcheck disable=SC1091
  source /etc/profile.d/cyberark.sh
fi

mkdir -p "$ARTIFACTS_DIR"

log_step() {
  printf "\n[%s] %s\n" "$1" "$2"
}

cd "$DEMO_DIR"

log_step "1/2" "Run the VM orchestrator (setup_vm.sh --skip-clone)"
./setup_vm.sh --skip-clone | tee "$ARTIFACTS_DIR/setup_vm.log"

log_step "2/2" "Prove the hardcoded query works against the local Postgres"
workspace="$LABS_ROOT/${STUDENT_PREFIX}1/$ACTIVITY_DIR_NAME"
if [ ! -x "$workspace/query_db_hardcoded.sh" ]; then
  printf "ERROR: rendered workspace not found: %s\n" "$workspace" >&2
  exit 1
fi
"$workspace/query_db_hardcoded.sh" | tee "$ARTIFACTS_DIR/hardcoded_query.log"

# Expect the seeded rows (row 1 is Star Trek).
grep -q "Star Trek" "$ARTIFACTS_DIR/hardcoded_query.log"

printf "\nActivity-setup validation completed.\n"
printf "Artifacts: %s\n" "$ARTIFACTS_DIR"
printf "Note: the secured (Summon) and rotate (SRS) steps require the student to\n"
printf "vault the credential and the Idira System connector — validate those manually.\n"
