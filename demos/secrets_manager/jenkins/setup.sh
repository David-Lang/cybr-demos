#!/bin/bash
# Full setup when CyberArk credentials are configured (same stages as go.sh).
set -euo pipefail

demo_path="$(cd "$(dirname "$0")" && pwd)"
export CYBR_DEMOS_PATH="${CYBR_DEMOS_PATH:-$(cd "$demo_path/../../.." && pwd)}"
vars_example="$demo_path/setup/vars.env.example"
vars_file="$demo_path/setup/vars.env"

if [ ! -f "$vars_file" ]; then
  if [ -f "$vars_example" ]; then
    cp "$vars_example" "$vars_file"
    printf "Created %s from example — edit SAFE_NAME / DEPLOY_PROFILE, then re-run setup.sh\n" "$vars_file"
    exit 1
  fi
  printf "Missing %s\n" "$vars_file" >&2
  exit 1
fi

if [[ "${SKIP_JENKINS_PREREQ_CHECK:-}" != "1" ]]; then
  bash "$demo_path/check_prereqs.sh"
fi

exec bash "$demo_path/go.sh"
