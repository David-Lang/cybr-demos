#!/bin/bash
# GitHub Actions + CyberArk Secrets Manager demo walkthrough.
# Interactive script: press ENTER to advance.
set -euo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

DEMO_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$DEMO_DIR/../../.." && pwd)"
VARS_FILE="$DEMO_DIR/setup/vars.env"
WORKFLOW_DIR="$DEMO_DIR/setup/github/workflows"
JWT_SERVICE_FILE="$DEMO_DIR/setup/conjur/jwt_service_github.yaml"
WORKLOAD_TMPL_FILE="$DEMO_DIR/setup/conjur/workload1.tmpl.yaml"
SETTINGS_TMPL_FILE="$DEMO_DIR/setup/github/settings_variables.tmpl.env"
IDENTITY_FUNCS_FILE="$REPO_ROOT/demos/utility/ubuntu/identity_functions.sh"
CONJUR_FUNCS_FILE="$REPO_ROOT/demos/utility/ubuntu/conjur_functions.sh"

if [ ! -f "$VARS_FILE" ]; then
  printf "${RED}Missing vars file: %s${NC}\n" "$VARS_FILE"
  exit 1
fi

if [ -f "$REPO_ROOT/demos/tenant_vars.sh" ]; then
  # shellcheck disable=SC1091
  source "$REPO_ROOT/demos/tenant_vars.sh"
fi
# shellcheck disable=SC1091
source "$VARS_FILE"
# shellcheck disable=SC1091
source "$IDENTITY_FUNCS_FILE"
# shellcheck disable=SC1091
source "$CONJUR_FUNCS_FILE"

require_var() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    printf "${RED}Missing required variable: %s${NC}\n" "$name"
    exit 1
  fi
}

require_var SAFE_NAME
require_var GITHUB_REPOSITORY
require_var GITHUB_WORKFLOW
require_var TENANT_SUBDOMAIN

CONJUR_ACCOUNT="conjur"
CONJUR_JWT_AUTHN_ID="github"
CONJUR_SECRET_ID_1="data/vault/${SAFE_NAME}/account-ssh-user-1/username"
CONJUR_SECRET_ID_2="data/vault/${SAFE_NAME}/account-ssh-user-1/password"
CONJUR_URL="https://${TENANT_SUBDOMAIN}.secretsmgr.cyberark.cloud/api"

header() {
  printf "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
  printf "${BOLD}  %s${NC}\n" "$1"
  printf "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

pause() {
  printf "\n${YELLOW}▶ Press ENTER to continue...${NC}"
  read -r
  echo
}

run_cmd() {
  printf "${GREEN}\$ %s${NC}\n" "$*"
  "$@"
}

prompt_yes_no() {
  local prompt="$1"
  local answer
  printf "%s (y/n) " "$prompt"
  read -r answer
  [ "$answer" = "y" ] || [ "$answer" = "Y" ]
}

print_github_variables_preview() {
  cat <<EOF
CONJUR_ACCOUNT="$CONJUR_ACCOUNT"
CONJUR_JWT_AUTHN_ID="$CONJUR_JWT_AUTHN_ID"
CONJUR_SECRET_ID_1="$CONJUR_SECRET_ID_1"
CONJUR_SECRET_ID_2="$CONJUR_SECRET_ID_2"
CONJUR_URL="$CONJUR_URL"
EOF
}

mask_secret() {
  local value="$1"
  local length=${#value}
  if [ "$length" -le 4 ]; then
    printf '****'
    return 0
  fi
  printf '%s***%s' "${value:0:2}" "${value: -2}"
}

header "GitHub Actions OIDC + CyberArk Demo"
cat <<'INTRO'

  This walkthrough uses a guided CLI motion for CI/CD:
    GitHub Actions OIDC token -> Conjur JWT authn -> secret retrieval

  The key value:
    • No static CyberArk credentials in GitHub
    • Policy-based workload identity using JWT claims
    • Native GitHub workflow experience from the CLI

INTRO
pause

header "Step 1: Local Demo Inputs"
printf "Loaded from ${BOLD}setup/vars.env${NC} and ${BOLD}demos/tenant_vars.sh${NC}:\n\n"
printf "  SAFE_NAME:            %s\n" "$SAFE_NAME"
printf "  GITHUB_REPOSITORY:    %s\n" "$GITHUB_REPOSITORY"
printf "  GITHUB_WORKFLOW:      %s\n" "$GITHUB_WORKFLOW"
printf "  TENANT_SUBDOMAIN:     %s\n" "$TENANT_SUBDOMAIN"
printf "\n${BOLD}Why it matters:${NC} repository + workflow claims map to the Conjur host; the safe name scopes secret paths.\n"
pause

header "Step 2: Conjur JWT Service Definition"
cat <<'EXPLAIN'

  This policy defines the GitHub JWT authenticator service (Secrets Manager SaaS pattern):
    • jwks-uri points at GitHub's OIDC signing keys
    • token-app-property is set to workflow (primary identity segment)
    • identity-path is data/github-apps (hosts live under data/github-apps/<workflow>)
    • enforced-claims requires workflow and repository in the JWT

EXPLAIN
run_cmd sed -n '1,220p' "$JWT_SERVICE_FILE"
pause

header "Step 3: Workload Identity Policy"
cat <<'EXPLAIN'

  This policy creates a host under data/github-apps/<workflow> with
  authn-jwt/github/repository and authn-jwt/github/workflow annotations,
  then grants Safe access via delegation/consumers.

EXPLAIN
printf "${BOLD}Template:${NC}\n"
run_cmd sed -n '1,220p' "$WORKLOAD_TMPL_FILE"
printf "\n${BOLD}Rendered preview:${NC}\n"
sed \
  -e "s|{{ .GITHUB_REPOSITORY }}|$GITHUB_REPOSITORY|g" \
  -e "s|{{ .GITHUB_WORKFLOW }}|$GITHUB_WORKFLOW|g" \
  -e "s|{{ .SAFE_NAME }}|$SAFE_NAME|g" \
  "$WORKLOAD_TMPL_FILE"
printf "\n${BOLD}Why it matters:${NC} authorization is policy-as-code and fully auditable.\n"
pause

header "Step 4: GitHub Variables to Configure"
cat <<'EXPLAIN'

  These repository-level variables tell the workflow where to auth
  and which secrets to fetch from Conjur.

EXPLAIN
printf "${BOLD}Template source:${NC}\n"
run_cmd sed -n '1,120p' "$SETTINGS_TMPL_FILE"
printf "\n${BOLD}Resolved values for this demo:${NC}\n"
print_github_variables_preview
pause

header "Step 5: Choose Workflow Pattern"
cat <<'EXPLAIN'

  Available workflow patterns in setup/github/workflows:
    • conjur-cloud-jwt-plugin.yml  (recommended)
    • conjur-cloud-jwt-direct.yml  (raw API flow)
    • conjur-cloud-apikey-plugin.yml (legacy static credential flow)

  Recommended value motion:
    Use jwt-plugin to keep auth keyless and platform-native.

EXPLAIN
run_cmd ls "$WORKFLOW_DIR"
pause

TARGET_REPO=""
WORKFLOW_FILE="conjur-cloud-jwt-plugin.yml"

header "Step 6: Optional GitHub CLI Automation"
printf "Enter target GitHub repo (owner/name), or press ENTER to skip live execution: "
read -r TARGET_REPO

if [ -z "$TARGET_REPO" ]; then
  REPO_PLACEHOLDER="owner/repo"
  printf "\n${YELLOW}Skipping live GitHub steps.${NC}\n"
  printf "Use these commands later:\n\n"
  cat <<EOF
gh variable set CONJUR_ACCOUNT --repo "$REPO_PLACEHOLDER" --body "$CONJUR_ACCOUNT"
gh variable set CONJUR_JWT_AUTHN_ID --repo "$REPO_PLACEHOLDER" --body "$CONJUR_JWT_AUTHN_ID"
gh variable set CONJUR_SECRET_ID_1 --repo "$REPO_PLACEHOLDER" --body "$CONJUR_SECRET_ID_1"
gh variable set CONJUR_SECRET_ID_2 --repo "$REPO_PLACEHOLDER" --body "$CONJUR_SECRET_ID_2"
gh variable set CONJUR_URL --repo "$REPO_PLACEHOLDER" --body "$CONJUR_URL"
gh workflow run "$WORKFLOW_FILE" --repo "$REPO_PLACEHOLDER"
gh run list --repo "$REPO_PLACEHOLDER" --workflow "$WORKFLOW_FILE" --limit 1
EOF
  pause
else
  if ! command -v gh >/dev/null 2>&1; then
    printf "${RED}gh CLI is not installed. Install it to run live steps.${NC}\n"
    exit 1
  fi

  if ! gh auth status >/dev/null 2>&1; then
    printf "${RED}gh is not authenticated. Run: gh auth login${NC}\n"
    exit 1
  fi

  printf "\nWorkflow file to run [%s]: " "$WORKFLOW_FILE"
  read -r selected_workflow
  if [ -n "$selected_workflow" ]; then
    WORKFLOW_FILE="$selected_workflow"
  fi

  if prompt_yes_no "Set/update GitHub repository variables now?"; then
    run_cmd gh variable set CONJUR_ACCOUNT --repo "$TARGET_REPO" --body "$CONJUR_ACCOUNT"
    run_cmd gh variable set CONJUR_JWT_AUTHN_ID --repo "$TARGET_REPO" --body "$CONJUR_JWT_AUTHN_ID"
    run_cmd gh variable set CONJUR_SECRET_ID_1 --repo "$TARGET_REPO" --body "$CONJUR_SECRET_ID_1"
    run_cmd gh variable set CONJUR_SECRET_ID_2 --repo "$TARGET_REPO" --body "$CONJUR_SECRET_ID_2"
    run_cmd gh variable set CONJUR_URL --repo "$TARGET_REPO" --body "$CONJUR_URL"
  fi

  if prompt_yes_no "Dispatch the workflow now?"; then
    run_cmd gh workflow run "$WORKFLOW_FILE" --repo "$TARGET_REPO"
    run_cmd gh run list --repo "$TARGET_REPO" --workflow "$WORKFLOW_FILE" --limit 1

    RUN_ID="$(gh run list --repo "$TARGET_REPO" --workflow "$WORKFLOW_FILE" --limit 1 --json databaseId --jq '.[0].databaseId')"
    if [ -n "$RUN_ID" ] && prompt_yes_no "Watch this run until completion?"; then
      if ! gh run watch "$RUN_ID" --repo "$TARGET_REPO" --exit-status; then
        printf "${RED}Workflow failed. Inspect logs with:${NC}\n"
        printf "  gh run view %s --repo %s --log-failed\n" "$RUN_ID" "$TARGET_REPO"
      fi
    fi
  fi
fi

header "Step 7: CyberArk Tenant Verification (Real Secret)"
cat <<'VERIFY_INTRO'

  This step proves the live tenant state behind the workflow:
    1) Verify the real account exists in the target Safe
    2) Authenticate to Conjur with tenant service identity
    3) Retrieve the same secret paths used by GitHub workflow

VERIFY_INTRO

if prompt_yes_no "Run live tenant verification now?"; then
  require_var TENANT_ID
  require_var CLIENT_ID
  require_var CLIENT_SECRET

  if ! command -v jq >/dev/null 2>&1; then
    printf "${RED}jq is required for tenant verification.${NC}\n"
    exit 1
  fi

  printf "\n${BOLD}Fetching identity token from tenant...${NC}\n"
  IDENTITY_TOKEN="$(get_identity_token "$TENANT_ID" "$CLIENT_ID" "$CLIENT_SECRET")"
  printf "${GREEN}✓ Identity token acquired.${NC}\n"

  printf "${BOLD}Fetching Conjur session token...${NC}\n"
  SESSION_TOKEN="$(get_conjur_token "$TENANT_SUBDOMAIN" "$IDENTITY_TOKEN")"
  printf "${GREEN}✓ Conjur session token acquired.${NC}\n"

  printf "${BOLD}Checking Privilege Cloud account in safe '%s'...${NC}\n" "$SAFE_NAME"
  ACCOUNT_JSON="$(curl --silent --show-error --fail \
    --location "https://${TENANT_SUBDOMAIN}.privilegecloud.cyberark.cloud/PasswordVault/API/Accounts?search=account-ssh-user-1&filter=safeName%20eq%20${SAFE_NAME}" \
    --header "Authorization: Bearer ${IDENTITY_TOKEN}")"

  ACCOUNT_ID="$(printf '%s' "$ACCOUNT_JSON" | jq -r '.value[0].id // empty')"
  ACCOUNT_USERNAME="$(printf '%s' "$ACCOUNT_JSON" | jq -r '.value[0].userName // empty')"
  ACCOUNT_SAFE="$(printf '%s' "$ACCOUNT_JSON" | jq -r '.value[0].safeName // empty')"

  if [ -z "$ACCOUNT_ID" ]; then
    printf "${RED}Account account-ssh-user-1 was not found in safe '%s'.${NC}\n" "$SAFE_NAME"
    exit 1
  fi

  printf "${GREEN}✓ Account found.${NC}\n"
  printf "  Account ID:   %s\n" "$ACCOUNT_ID"
  printf "  Safe:         %s\n" "$ACCOUNT_SAFE"
  printf "  Username:     %s\n" "$ACCOUNT_USERNAME"

  printf "\n${BOLD}Retrieving secret values from Conjur variable API...${NC}\n"
  SECRET_1_VALUE="$(curl --silent --show-error --fail \
    --location "${CONJUR_URL}/secrets/${CONJUR_ACCOUNT}/variable/${CONJUR_SECRET_ID_1}" \
    --header "Authorization: Token token=\"${SESSION_TOKEN}\"")"
  SECRET_2_VALUE="$(curl --silent --show-error --fail \
    --location "${CONJUR_URL}/secrets/${CONJUR_ACCOUNT}/variable/${CONJUR_SECRET_ID_2}" \
    --header "Authorization: Token token=\"${SESSION_TOKEN}\"")"

  printf "${GREEN}✓ Real secrets retrieved from tenant.${NC}\n"
  printf "  %s = %s\n" "$CONJUR_SECRET_ID_1" "$SECRET_1_VALUE"
  printf "  %s = " "$CONJUR_SECRET_ID_2"
  mask_secret "$SECRET_2_VALUE"
  printf "  (masked)\n"

  if prompt_yes_no "Reveal full password value in terminal?"; then
    printf "  password = %s\n" "$SECRET_2_VALUE"
  fi

  printf "\n${BOLD}What this proves:${NC}\n"
  printf "  • The Safe/account exists in your CyberArk tenant\n"
  printf "  • Conjur authn flow is live against your tenant endpoints\n"
  printf "  • GitHub workflow variable paths resolve to real tenant secrets\n"
fi

header "Step 8: Key Value Recap"
cat <<'SUMMARY'

  What this GitHub motion demonstrates:
    ✓ GitHub OIDC identity is the authenticator input
    ✓ Conjur maps enforced workflow + repository claims to a host under data/github-apps
    ✓ Safe access is enforced by policy and delegation groups
    ✓ Workflows retrieve secrets without static API keys

  Why this is high value:
    • Reduces credential sprawl in CI/CD systems
    • Keeps identity + authorization centralized in CyberArk
    • Preserves developer-friendly GitHub Actions workflow patterns

SUMMARY
