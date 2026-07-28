#!/bin/bash
# Grant the workload read access to the demo safe's synced consumers group.
#
# Run this AFTER the student has created the safe and vaulted the DB credential
# (in the activity), so the `vault/<safe>/delegation/consumers` group exists in
# Conjur. It is deliberately NOT part of deploy-time setup, which must not depend
# on a safe existing.
#
# Requires privileged Conjur/tenant access (CLIENT_ID/CLIENT_SECRET via
# demos/setup_env.sh), so it is run by the control plane / instructor, not the
# student. SAFE_NAME defaults to the VM name (see setup/vars.env).
set -euo pipefail

export CYBR_DEMOS_PATH="${CYBR_DEMOS_PATH:-/opt/cybr-demos}"
demo_path="$CYBR_DEMOS_PATH/demos/secrets_manager/summon_azure_auth"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"

set -a
# shellcheck disable=SC1091
source "$CYBR_DEMOS_PATH/demos/setup_env.sh"
# shellcheck disable=SC1091
source "$demo_path/setup/vars.env"
# conjur_authn_azure.env (written by the enablement setup.sh) supplies the runtime
# AZURE_* + AZURE_WORKLOAD_HOST_NAME. Source it LAST so it overrides vars.env's
# empty default — the grant targets THIS VM's workload host, not the whole group.
if [ -f "$demo_path/conjur_authn_azure.env" ]; then
  # shellcheck disable=SC1091
  source "$demo_path/conjur_authn_azure.env"
fi
set +a

: "${LAB_ID:?LAB_ID is required}"
: "${TENANT_ID:?TENANT_ID is required}"
: "${TENANT_SUBDOMAIN:?TENANT_SUBDOMAIN is required}"
: "${CLIENT_ID:?CLIENT_ID is required}"
: "${CLIENT_SECRET:?CLIENT_SECRET is required}"
: "${SAFE_NAME:?SAFE_NAME is required}"
: "${AZURE_WORKLOAD_HOST_NAME:?AZURE_WORKLOAD_HOST_NAME is required (run the enablement setup first)}"

printf "Granting workload read access to safe '%s' consumers...\n" "$SAFE_NAME"

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

# The safe's synced delegation group must exist before the grant can reference it.
printf "Waiting for the safe to synchronize into Conjur...\n"
wait_for_synchronizer "$TENANT_SUBDOMAIN" "$conjur_token" "$SAFE_NAME"

resolve_template "consumers_grant.tmpl.yaml" "consumers_grant.yaml"
apply_conjur_policy "$TENANT_SUBDOMAIN" "$conjur_token" "data" "$(cat consumers_grant.yaml)" >/dev/null

printf "Consumers grant applied: data/%s/azure-apps/%s -> vault/%s/delegation/consumers\n" "$LAB_ID" "$AZURE_WORKLOAD_HOST_NAME" "$SAFE_NAME"
