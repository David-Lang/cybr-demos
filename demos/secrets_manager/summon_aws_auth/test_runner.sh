#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="$SCRIPT_DIR"
ARTIFACTS_DIR="$DEMO_DIR/artifacts"

if [ -f /etc/profile.d/cyberark.sh ]; then
  # shellcheck disable=SC1091
  source /etc/profile.d/cyberark.sh
fi

mkdir -p "$ARTIFACTS_DIR"

log_step() {
  printf "\n[%s] %s\n" "$1" "$2"
}

require_file() {
  local file_path="$1"
  if [ ! -f "$file_path" ]; then
    printf "ERROR: Required file not found: %s\n" "$file_path" >&2
    exit 1
  fi
}

cd "$DEMO_DIR"

log_step "1/4" "Run demo setup"
./setup.sh | tee "$ARTIFACTS_DIR/setup.log"

log_step "2/4" "Load runtime environment"
require_file "$DEMO_DIR/conjur_authn_iam.env"
# shellcheck disable=SC1091
source "$DEMO_DIR/conjur_authn_iam.env"
env | grep -E '^(CONJUR|AUTHN_IAM|WORKLOAD_HOST_ID|AWS_)' | sort > "$ARTIFACTS_DIR/runtime_env.log"

log_step "3/4" "Capture AWS caller identity"
aws sts get-caller-identity | tee "$ARTIFACTS_DIR/aws_identity.log"

log_step "4/4" "Run Summon demo"
./demo.sh | tee "$ARTIFACTS_DIR/demo.log"

grep -Eq '^SECRET1: .+' "$ARTIFACTS_DIR/demo.log"
grep -Eq '^SECRET2: .+' "$ARTIFACTS_DIR/demo.log"
grep -Eq '^SECRET3: .+' "$ARTIFACTS_DIR/demo.log"

printf "\nTest run completed successfully.\n"
printf "Artifacts: %s\n" "$ARTIFACTS_DIR"
