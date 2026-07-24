#!/bin/bash
# Create or delete the per-VM authn-azure workload record in Conjur.
#
# The workload host maps this VM's Azure managed-identity token to a Conjur
# workload. It is per-activity lifecycle (NOT deploy-time enablement):
#   - activity/solve.sh calls this with `create` before vaulting,
#   - activity/reset.sh calls this with `delete` (best-effort) during reset,
#   - the manual student guide documents creating it by hand instead.
#
# The authn-azure SERVICE enablement, provider-uri, and conjur_authn_azure.env
# are still owned by setup/conjur/setup.sh (shared enablement) and must run first.
set -euo pipefail

export CYBR_DEMOS_PATH="${CYBR_DEMOS_PATH:-/opt/cybr-demos}"
demo_path="$CYBR_DEMOS_PATH/demos/secrets_manager/summon_azure_auth"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"

mode="${1:-create}"

# conjur_authn_azure.env supplies AZURE_*, WORKLOAD_HOST_NAME,
# AUTHN_AZURE_SERVICE_ID, LAB_ID, etc. It is written by setup.sh (enablement).
if [ ! -f "$demo_path/conjur_authn_azure.env" ]; then
  printf "ERROR: %s not found.\n" "$demo_path/conjur_authn_azure.env" >&2
  printf "Run the shared enablement (setup/conjur/setup.sh) first to enable authn-azure and write the env file.\n" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
source "$CYBR_DEMOS_PATH/demos/setup_env.sh"
# shellcheck disable=SC1091
source "$demo_path/setup/vars.env"
# shellcheck disable=SC1091
source "$demo_path/conjur_authn_azure.env"
set +a

: "${LAB_ID:?LAB_ID is required}"
: "${TENANT_ID:?TENANT_ID is required}"
: "${TENANT_SUBDOMAIN:?TENANT_SUBDOMAIN is required}"
: "${CLIENT_ID:?CLIENT_ID is required}"
: "${CLIENT_SECRET:?CLIENT_SECRET is required}"
: "${AZURE_TENANT_ID:?AZURE_TENANT_ID is required}"
: "${AZURE_SUBSCRIPTION_ID:?AZURE_SUBSCRIPTION_ID is required}"
: "${AZURE_RESOURCE_GROUP:?AZURE_RESOURCE_GROUP is required}"
: "${AZURE_USER_ASSIGNED_IDENTITY_NAME:?AZURE_USER_ASSIGNED_IDENTITY_NAME is required}"
: "${AZURE_WORKLOAD_HOST_NAME:?AZURE_WORKLOAD_HOST_NAME is required}"

# Enclosing branch for the workload policy (defaults match setup.sh / workload.tmpl.yaml).
WORKLOAD_POLICY_BRANCH="${WORKLOAD_POLICY_BRANCH:-data}"

printf "\nAuthenticating to Identity...\n"
identity_token="$(get_identity_token "$TENANT_ID" "$CLIENT_ID" "$CLIENT_SECRET")"
if [ -z "$identity_token" ]; then
  printf "ERROR: Failed to get identity token\n" >&2
  exit 1
fi

conjur_token="$(get_conjur_token "$TENANT_SUBDOMAIN" "$identity_token")"
if [ -z "$conjur_token" ]; then
  printf "ERROR: Failed to get Conjur token\n" >&2
  exit 1
fi

case "$mode" in
  create)
    printf "\nCreating workload record '%s' under %s/%s/azure-apps...\n" \
      "$AZURE_WORKLOAD_HOST_NAME" "$WORKLOAD_POLICY_BRANCH" "$LAB_ID"

    # Append (POST) the workload policy — idempotent, re-applying is safe.
    resolve_template "workload.tmpl.yaml" "workload.yaml"
    apply_conjur_policy "$TENANT_SUBDOMAIN" "$conjur_token" "$WORKLOAD_POLICY_BRANCH" "$(cat workload.yaml)" >/dev/null
    printf "Workload policy applied.\n"

    # Grant the workload into the authn-azure apps group (PATCH/update, idempotent).
    resolve_template "authenticator_grant.tmpl.yaml" "authenticator_grant.yaml"
    patch_conjur_policy "$TENANT_SUBDOMAIN" "$conjur_token" "conjur/authn-azure" "$(cat authenticator_grant.yaml)" >/dev/null
    printf "authn-azure apps grant applied.\n"

    printf "\nWorkload created:\n"
    printf "  - Host:  data/%s/azure-apps/%s\n" "$LAB_ID" "$AZURE_WORKLOAD_HOST_NAME"
    printf "  - Group: %s/apps (authn-azure)\n" "$AUTHN_AZURE_SERVICE_ID"
    ;;
  delete)
    printf "\nDeleting workload record '%s' under data/%s/azure-apps...\n" \
      "$AZURE_WORKLOAD_HOST_NAME" "$LAB_ID"

    # Conjur record deletion uses a `!delete` statement loaded in PATCH (update)
    # mode against the enclosing branch (data/<LAB_ID>/azure-apps). Verify against
    # the live tenant. Log-and-continue so reset never fails on a missing record.
    resolve_template "workload_delete.tmpl.yaml" "workload_delete.yaml"
    patch_conjur_policy "$TENANT_SUBDOMAIN" "$conjur_token" "data/${LAB_ID}/azure-apps" "$(cat workload_delete.yaml)" >/dev/null || \
      printf "WARN: workload delete reported an error (may not exist); continuing.\n" >&2

    printf "\nWorkload removed (if present): data/%s/azure-apps/%s\n" "$LAB_ID" "$AZURE_WORKLOAD_HOST_NAME"
    ;;
  *)
    printf "ERROR: unknown mode '%s' (expected 'create' or 'delete')\n" "$mode" >&2
    exit 1
    ;;
esac
