#!/bin/bash
# VM orchestrator for the Summon Azure Auth workshop.
#
# Single entrypoint the deployment app triggers on the provisioned VM. Runs the
# full deployment-enablement chain, in order:
#
#   1. ensure the cybr-demos repo is present   (clone)
#   2. demo setup.sh                           (authn-azure + workload + Postgres
#                                                platform validation + secrets.yml)
#   3. activity/db_setup.sh                    (local Postgres container, initial cred)
#   4. install Docker + psql                   (ensure; db_setup self-installs Docker)
#   5. activity/setup_activity.sh              (render the student workspace)
#
# It does NOT vault the DB credential or create the safe — the student does that
# in the activity, and the workload->safe consumers grant is applied afterward by
# setup/conjur/grant_consumers.sh.
#
# Tenant credentials (TENANT_ID/TENANT_SUBDOMAIN/CLIENT_ID/CLIENT_SECRET, LAB_ID)
# are supplied by the control plane via the environment or /etc/profile.d/cyberark.sh;
# this script does not manage them.
set -euo pipefail

SCRIPT_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Repo root: default to the checkout this script lives in; override with env/flag.
CYBR_DEMOS_PATH="${CYBR_DEMOS_PATH:-$(cd "$SCRIPT_SELF_DIR/../../.." && pwd)}"
REPO_URL="${CYBR_DEMOS_REPO_URL:-https://github.com/David-Lang/cybr-demos.git}"
REPO_REF="${CYBR_DEMOS_REPO_REF:-main}"
UPDATE_REPO="${UPDATE_REPO:-false}"
SKIP_CLONE="${SKIP_CLONE:-false}"
STUDENT_COUNT="${STUDENT_COUNT:-1}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Orchestrates VM setup for the Summon Azure Auth workshop.

Options:
  --path DIR           cybr-demos checkout path. Default: ${CYBR_DEMOS_PATH}
  --repo-url URL       Git URL to clone when the repo is absent. Default: ${REPO_URL}
  --repo-ref REF       Branch/tag to clone/checkout. Default: ${REPO_REF}
  --update             If the repo is present, fetch + checkout --repo-ref.
  --skip-clone         Skip the repo-ensure step entirely.
  --student-count N    Workspaces to render. Default: ${STUDENT_COUNT}
  -h, --help           Show this help.

Environment: CYBR_DEMOS_PATH, CYBR_DEMOS_REPO_URL, CYBR_DEMOS_REPO_REF,
UPDATE_REPO, SKIP_CLONE, STUDENT_COUNT, plus tenant creds for setup.sh.
EOF
}

is_true() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    1|true|yes|y|on) return 0 ;;
    *) return 1 ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --path) CYBR_DEMOS_PATH="$2"; shift 2 ;;
    --repo-url) REPO_URL="$2"; shift 2 ;;
    --repo-ref) REPO_REF="$2"; shift 2 ;;
    --update) UPDATE_REPO=true; shift ;;
    --skip-clone) SKIP_CLONE=true; shift ;;
    --student-count) STUDENT_COUNT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

export CYBR_DEMOS_PATH
export STUDENT_COUNT

ensure_git() {
  command -v git >/dev/null 2>&1 && return 0
  echo "Installing git..."
  sudo apt-get update && sudo apt-get install -y git
}

ensure_repo() {
  if is_true "$SKIP_CLONE"; then
    echo "[1/5] Skipping repo ensure (--skip-clone)."
    return 0
  fi

  if [ -d "$CYBR_DEMOS_PATH/.git" ]; then
    echo "[1/5] Repo present at ${CYBR_DEMOS_PATH}"
    if is_true "$UPDATE_REPO"; then
      ensure_git
      echo "  Updating to ${REPO_REF}..."
      git -C "$CYBR_DEMOS_PATH" fetch origin "$REPO_REF"
      git -C "$CYBR_DEMOS_PATH" checkout "$REPO_REF"
      git -C "$CYBR_DEMOS_PATH" pull --ff-only || true
    fi
    return 0
  fi

  if [ -z "$REPO_URL" ]; then
    echo "ERROR: ${CYBR_DEMOS_PATH} is not a git checkout and no --repo-url/CYBR_DEMOS_REPO_URL was given." >&2
    echo "Provision the repo first, or pass --repo-url to bootstrap the clone." >&2
    exit 1
  fi

  ensure_git
  echo "[1/5] Cloning ${REPO_URL}@${REPO_REF} -> ${CYBR_DEMOS_PATH}"
  if ! git clone --branch "$REPO_REF" --depth 1 "$REPO_URL" "$CYBR_DEMOS_PATH" 2>/dev/null; then
    sudo mkdir -p "$(dirname "$CYBR_DEMOS_PATH")"
    sudo git clone --branch "$REPO_REF" --depth 1 "$REPO_URL" "$CYBR_DEMOS_PATH"
    sudo chown -R "$(id -un):$(id -gn)" "$CYBR_DEMOS_PATH"
  fi
}

ensure_tool() {
  # $1 tool/command name; installer is compute_init/ubuntu/install_<name>.sh
  local tool="$1"
  local installer="$CYBR_DEMOS_PATH/compute_init/ubuntu/install_${tool}.sh"
  if command -v "$tool" >/dev/null 2>&1; then
    echo "  ${tool} present"
    return 0
  fi
  if [ -f "$installer" ]; then
    echo "  Installing ${tool} via ${installer}"
    bash "$installer"
  else
    echo "ERROR: installer not found for ${tool}: ${installer}" >&2
    return 1
  fi
}

# --- Orchestration ----------------------------------------------------------
ensure_repo

DEMO_DIR="$CYBR_DEMOS_PATH/demos/secrets_manager/summon_azure_auth"
if [ ! -d "$DEMO_DIR" ]; then
  echo "ERROR: demo directory not found: ${DEMO_DIR}" >&2
  exit 1
fi

printf "\n[2/5] Deployment enablement (setup.sh: authn-azure + workload + platform validation)...\n"
bash "$DEMO_DIR/setup.sh"

printf "\n[3/5] Standing up the local Postgres (db_setup.sh)...\n"
bash "$DEMO_DIR/activity/db_setup.sh"

printf "\n[4/5] Ensuring Docker and the psql client...\n"
ensure_tool docker
ensure_tool psql

printf "\n[5/5] Rendering the student activity workspace (setup_activity.sh)...\n"
bash "$DEMO_DIR/activity/setup_activity.sh"

printf "\n==========================================\n"
printf "VM setup complete.\n"
printf "==========================================\n"
printf "The DB credential is NOT vaulted yet. In the activity, the student:\n"
printf "  1. runs ./query_db_hardcoded.sh (exposed), then vaults the credential in idira,\n"
printf "  2. (control plane) run: %s/setup/conjur/grant_consumers.sh   # after the safe syncs\n" "$DEMO_DIR"
printf "  3. runs ./run_secured_query.sh (secured), then rotates via SRS.\n"
printf "Workspace: /opt/labs/student1/hardcoded-secret-remediation\n"
