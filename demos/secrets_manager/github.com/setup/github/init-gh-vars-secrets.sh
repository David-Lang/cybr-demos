#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  setup/github/init-gh-vars-secrets.sh [--repo OWNER/REPO] [--env NAME]... [--non-interactive]

Description:
  Creates missing GitHub repository variables and secrets for this repo.
  Optionally initializes selected GitHub environments and their variables/secrets.
  Existing values are left unchanged.

Value sources:
  Repository scope:
    SM_URL
    SM_ACCOUNT
    SM_JWT_AUTHN_ID
    SM_SECRET_ID_1
    SM_SECRET_ID_2
    TRUFFLEHOG_OWNER             optional
    SM_USERNAME                   secret
    SM_API_KEY                    secret

  Environment scope:
    Provide environment-specific values as ENVNAME__KEY, for example:
      DEV__SM_URL
      STAGING__SM_SECRET_ID_1
      MAIN__SM_SECRET_ID_2
      TERRAFORM__TFVAR_APPLIANCE_URL
      TERRAFORM__TFVAR_SSL_CERT

Options:
  --repo OWNER/REPO    Target repository. Defaults to the current gh repo.
  --env NAME           Initialize a GitHub environment. Can be repeated.
  --non-interactive    Do not prompt for missing values. Skip them instead.
  -h, --help           Show this help.
EOF
}

require_cmd() {
  local cmd=$1
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    exit 1
  fi
}

log() {
  printf '%s\n' "$*"
}

error() {
  printf 'Error: %s\n' "$*" >&2
}

is_interactive() {
  [[ -t 0 && -t 1 && "${NON_INTERACTIVE}" == "false" ]]
}

normalize_scope_prefix() {
  local scope_name=$1
  printf '%s' "$scope_name" | tr '[:lower:]-' '[:upper:]_'
}

resolve_value() {
  local scope_prefix=${1:-}
  local key=$2
  local env_key=$key
  local value=""

  if [[ -n "$scope_prefix" ]]; then
    env_key="${scope_prefix}__${key}"
  fi

  value=${!env_key-}

  if [[ -z "$value" && -z "$scope_prefix" ]]; then
    value=${!key-}
  fi

  printf '%s' "$value"
}

prompt_value() {
  local label=$1
  local secret_mode=${2:-false}
  local value=""

  if ! is_interactive; then
    printf ''
    return 0
  fi

  if [[ "$secret_mode" == "true" ]]; then
    read -r -s -p "$label: " value
    printf '\n' >&2
  else
    read -r -p "$label: " value
  fi

  printf '%s' "$value"
}

gh_env_exists() {
  local env_name=$1
  gh api "repos/${REPO}/environments/${env_name}" >/dev/null 2>&1
}

ensure_environment() {
  local env_name=$1

  if gh_env_exists "$env_name"; then
    log "Environment ${env_name} already exists"
    return 0
  fi

  log "Creating environment ${env_name}"
  gh api --method PUT "repos/${REPO}/environments/${env_name}" >/dev/null
}

gh_variable_exists() {
  local name=$1
  shift

  gh variable get "$name" --repo "$REPO" "$@" >/dev/null 2>&1
}

gh_secret_exists() {
  local name=$1
  shift

  gh secret list --repo "$REPO" "$@" --json name --jq '.[].name' 2>/dev/null | grep -Fxq "$name"
}

ensure_variable() {
  local name=$1
  local value=$2
  shift 2
  local scope_desc=$1
  shift

  if gh_variable_exists "$name" "$@"; then
    log "Variable ${scope_desc}${name} already exists"
    return 0
  fi

  if [[ -z "$value" ]]; then
    log "Skipping variable ${scope_desc}${name}; no value provided"
    return 0
  fi

  log "Creating variable ${scope_desc}${name}"
  gh variable set "$name" --repo "$REPO" "$@" --body "$value"
}

ensure_secret() {
  local name=$1
  local value=$2
  shift 2
  local scope_desc=$1
  shift

  if gh_secret_exists "$name" "$@"; then
    log "Secret ${scope_desc}${name} already exists"
    return 0
  fi

  if [[ -z "$value" ]]; then
    log "Skipping secret ${scope_desc}${name}; no value provided"
    return 0
  fi

  log "Creating secret ${scope_desc}${name}"
  printf '%s' "$value" | gh secret set "$name" --repo "$REPO" "$@"
}

ensure_repo_variable() {
  local name=$1
  local required=${2:-true}
  local value

  value=$(resolve_value "" "$name")
  if [[ -z "$value" && "$required" == "true" ]]; then
    value=$(prompt_value "Enter repository variable ${name}")
  fi

  ensure_variable "$name" "$value" "repo:"
}

ensure_repo_secret() {
  local name=$1
  local value

  value=$(resolve_value "" "$name")
  if [[ -z "$value" ]]; then
    value=$(prompt_value "Enter repository secret ${name}" true)
  fi

  ensure_secret "$name" "$value" "repo:"
}

ensure_environment_variable() {
  local env_name=$1
  local key=$2
  local required=${3:-false}
  local prefix
  local value

  prefix=$(normalize_scope_prefix "$env_name")
  value=$(resolve_value "$prefix" "$key")

  if [[ -z "$value" && "$required" == "true" ]]; then
    value=$(prompt_value "Enter variable ${key} for environment ${env_name}")
  fi

  ensure_variable "$key" "$value" "env:${env_name}:" --env "$env_name"
}

ensure_environment_secret() {
  local env_name=$1
  local key=$2
  local required=${3:-false}
  local prefix
  local value

  prefix=$(normalize_scope_prefix "$env_name")
  value=$(resolve_value "$prefix" "$key")

  if [[ -z "$value" && "$required" == "true" ]]; then
    value=$(prompt_value "Enter secret ${key} for environment ${env_name}" true)
  fi

  ensure_secret "$key" "$value" "env:${env_name}:" --env "$env_name"
}

NON_INTERACTIVE=false
REPO=""
ENVIRONMENTS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO=${2:?Missing value for --repo}
      shift 2
      ;;
    --env)
      ENVIRONMENTS+=("${2:?Missing value for --env}")
      shift 2
      ;;
    --non-interactive)
      NON_INTERACTIVE=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      error "Unknown argument: $1"
      usage >&2
      exit 1
      ;;
  esac
done

require_cmd gh
require_cmd grep

if [[ -z "$REPO" ]]; then
  REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
fi

gh auth status >/dev/null

log "Target repository: ${REPO}"

REPO_REQUIRED_VARS=(
  SM_URL
  SM_ACCOUNT
  SM_JWT_AUTHN_ID
  SM_SECRET_ID_1
  SM_SECRET_ID_2
)

REPO_OPTIONAL_VARS=(
  TRUFFLEHOG_OWNER
)

REPO_SECRETS=(
  SM_USERNAME
  SM_API_KEY
)

ENV_OVERRIDE_VARS=(
  SM_URL
  SM_ACCOUNT
  SM_JWT_AUTHN_ID
  SM_SECRET_ID_1
  SM_SECRET_ID_2
)

TERRAFORM_ENV_VARS=(
  SM_URL
  SM_ACCOUNT
  SM_JWT_AUTHN_ID
  SM_SECRET_ID_1
  SM_SECRET_ID_2
  TFVAR_APPLIANCE_URL
  TFVAR_ACCOUNT
  TFVAR_SSL_CERT
  TFVAR_sm_secret_id_1
)

# Terraform authenticates to Secrets Manager via the GitHub OIDC JWT, so no
# host login / API key secret is required in the terraform environment.
TERRAFORM_ENV_SECRETS=()

for key in "${REPO_REQUIRED_VARS[@]}"; do
  ensure_repo_variable "$key" true
done

for key in "${REPO_OPTIONAL_VARS[@]}"; do
  ensure_repo_variable "$key" false
done

for key in "${REPO_SECRETS[@]}"; do
  ensure_repo_secret "$key"
done

for env_name in "${ENVIRONMENTS[@]}"; do
  ensure_environment "$env_name"

  case "$env_name" in
    dev|staging|main)
      for key in "${ENV_OVERRIDE_VARS[@]}"; do
        ensure_environment_variable "$env_name" "$key" false
      done
      ;;
    terraform)
      for key in "${TERRAFORM_ENV_VARS[@]}"; do
        ensure_environment_variable "$env_name" "$key" true
      done
      for key in "${TERRAFORM_ENV_SECRETS[@]+"${TERRAFORM_ENV_SECRETS[@]}"}"; do
        ensure_environment_secret "$env_name" "$key" true
      done
      ;;
    *)
      error "Unsupported environment: ${env_name}"
      exit 1
      ;;
  esac
done

log "Initialization complete"
