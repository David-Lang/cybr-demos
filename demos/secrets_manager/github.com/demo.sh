#!/bin/bash
# shellcheck disable=SC2059
# Runs the github.com demo: triggers the GitHub Actions workflows via the gh CLI.
# Assumes setup.sh has already provisioned the server side and configured the repo.
set -euo pipefail

demo_path="$CYBR_DEMOS_PATH/demos/secrets_manager/github.com"

# Load demo inputs (GH_REPO, GH_ENVIRONMENTS, TRUFFLEHOG_REPOS, TFVAR_*).
set -a
# shellcheck disable=SC1091
source "$demo_path/setup/vars.env"
set +a

# Ref to run the workflows on (branch or tag present on the remote).
GH_REF="${GH_REF:-aardvark}"

run_workflow() {
  local wf="$1"
  printf "  [run] %s\n" "$wf"
  gh workflow run "$wf" --ref "$GH_REF" --repo "$GH_REPO"
}

skip_workflow() {
  printf "  [skip] %s\n" "$*"
}

main() {
  command -v gh >/dev/null 2>&1 || { printf "ERROR: gh CLI is required\n" >&2; exit 1; }
  : "${GH_REPO:?GH_REPO must be set}"
  gh auth status >/dev/null

  printf "\nRunning GitHub Actions demos on %s (ref: %s)\n\n" "$GH_REPO" "$GH_REF"

  # Core workflows (repo-level vars/secrets are enough).
  run_workflow "sm-plugin-jwt.yml"
  run_workflow "sm-direct-jwt.yml"
  run_workflow "sm-plugin-apikey.yml"
  run_workflow "sm-plugin-jwt-env-aware.yml"
  run_workflow "trufflehog-single-scan.yml"

  # Terraform needs an AWS-credentials JSON secret (TFVAR_sm_secret_id_1).
  if [ -n "${TFVAR_sm_secret_id_1:-}" ]; then
    run_workflow "sm-plugin-jwt-terraform.yml"
  else
    skip_workflow "sm-plugin-jwt-terraform.yml (set TFVAR_sm_secret_id_1 to an AWS-creds JSON secret to run)"
  fi

  # Multi-scan needs a repo list.
  if [ -n "${TRUFFLEHOG_REPOS:-}" ]; then
    run_workflow "trufflehog-multi-scan.yml"
  else
    skip_workflow "trufflehog-multi-scan.yml (set TRUFFLEHOG_REPOS to run)"
  fi

  printf "\nDispatched. Recent runs:\n\n"
  gh run list --repo "$GH_REPO" --branch "$GH_REF" --limit 10

  printf "\nWatch a run with:\n  gh run watch <run-id> --repo %s\n" "$GH_REPO"
}

main "$@"
