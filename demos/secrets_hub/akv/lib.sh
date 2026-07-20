#!/bin/bash
# shellcheck disable=SC2059
#
# lib.sh — Secrets Hub + Privilege Cloud helper functions for the
# "Onboard Azure AKV" activity. Reverse-engineered from the CyberArk Terraform
# provider (github.com/cyberark/terraform-provider-cyberark, internal/cyberark).
#
# These mirror the existing utility/ubuntu/privilege_functions.sh style (curl +
# jq, Bearer <ISPSS platform token>). They are kept local to the activity for
# now; promote to demos/utility/ubuntu/secretshub_functions.sh if reused.
#
# All functions take the ISPSS platform token as an argument (mint it with
# get_identity_token from identity_functions.sh). Base URLs derive from the
# tenant subdomain:
#   Privilege Cloud : https://<subdomain>.privilegecloud.cyberark.cloud
#   Secrets Hub     : https://<subdomain>.secretshub.cyberark.cloud

set -euo pipefail

# ---------------------------------------------------------------------------
# Privilege Cloud: vault the standalone rotation-demo Azure app registration as
# an Azure account in the App Safe. This is the credential Secrets Hub rotates
# and syncs to the AKV — it is NOT used to access anything.
# ---------------------------------------------------------------------------
vault_azure_app_account() {
  # $1 subdomain, $2 token, $3 safe_name, $4 account_name, $5 app_client_id,
  # $6 app_object_id, $7 app_client_secret, $8 azure_directory_id, [$9 key_id]
  if [ $# -lt 8 ]; then
    printf "\nUsage: vault_azure_app_account <subdomain> <token> <safe_name> <account_name> <app_client_id> <app_object_id> <app_client_secret> <azure_directory_id> [key_id]\n" >&2
    return 1
  fi
  local subdomain="$1" token="$2" safe_name="$3" account_name="$4"
  local app_client_id="$5" app_object_id="$6" app_client_secret="$7"
  local azure_directory_id="$8" key_id="${9:-}"

  printf "\nVaulting Azure app-registration credential as account: %s (safe: %s)\n" "$account_name" "$safe_name"

  # platformId: the tenant's Azure app-keys platform (AzureApplicationKeys =
  # "Microsoft Azure Application Keys Management", a built-in that must be
  # activated). Overridable via ROTATION_ACCOUNT_PLATFORM.
  local platform="${ROTATION_ACCOUNT_PLATFORM:-AzureApplicationKeys}"
  local body
  body=$(jq -cn \
    --arg name "$account_name" \
    --arg user "$app_client_id" \
    --arg platform "$platform" \
    --arg safe "$safe_name" \
    --arg secret "$app_client_secret" \
    --arg appid "$app_client_id" \
    --arg objid "$app_object_id" \
    --arg keyid "$key_id" \
    --arg adid "$azure_directory_id" \
    '{
      name: $name,
      userName: $user,
      platformId: $platform,
      safeName: $safe,
      secretType: "password",
      secret: $secret,
      platformAccountProperties: ({
        ApplicationID: $appid,
        ApplicationObjectID: $objid,
        ActiveDirectoryID: $adid
      } + (if $keyid == "" then {} else {KeyID: $keyid} end)),
      secretManagement: {
        automaticManagementEnabled: false,
        manualManagementReason: "Rotation-demo subject; managed by Secrets Hub sync."
      }
    }')

  # Non-fatal: vaulting the rotation-demo account is demo payload, not required
  # for the store/sync-policy pipeline. Warn clearly on error but don't abort.
  local resp
  resp="$(curl --silent --show-error --location \
    "https://$subdomain.privilegecloud.cyberark.cloud/PasswordVault/API/Accounts/" \
    --header "Authorization: Bearer $token" \
    --header 'Content-Type: application/json' \
    --data "$body")"
  if printf '%s' "$resp" | jq -e '.ErrorCode? // .Details? // empty' >/dev/null 2>&1; then
    printf "WARN: vaulting the rotation-demo account failed (continuing): %s\n" "$resp" >&2
  else
    printf '%s\n' "$resp"
  fi
}

# ---------------------------------------------------------------------------
# Secrets Hub: discover the built-in Privilege Cloud secret store id. This is
# the sync-policy source.id (secrets flow FROM Privilege Cloud TO the AKV).
# ---------------------------------------------------------------------------
get_pcloud_source_store_id() {
  # $1 subdomain, $2 token
  local subdomain="$1" token="$2" response id
  response=$(curl --silent --show-error --location \
    "https://$subdomain.secretshub.cyberark.cloud/api/secret-stores" \
    --header "Authorization: Bearer $token" \
    --header 'Accept: application/json')

  # TODO(confirm): the Privilege Cloud store type discriminator. Observed values
  # for the source store are PAM_PCLOUD / PAM_SELF_HOSTED. Match either, else the
  # first store advertising the SECRETS_SOURCE behavior.
  id=$(printf '%s' "$response" | jq -r '
    (.secretStores // .stores // [])
    | ( map(select(.type == "PAM_PCLOUD" or .type == "PAM_SELF_HOSTED")) )[0].id
      // ( map(select((.behaviors // []) | index("SECRETS_SOURCE")))[0].id )
      // empty')

  if [ -z "$id" ] || [ "$id" = "null" ]; then
    printf "\nERROR: could not find the Privilege Cloud source store.\nResponse: %s\n" "$response" >&2
    return 1
  fi
  printf '%s' "$id"
}

# ---------------------------------------------------------------------------
# Secrets Hub: onboard the AKV individually as an AZURE_AKV secret store target
# using FEDERATED_IDENTITY (Secrets Hub's own federated app reg; no client
# secret). Prints the created store id on success.
# ---------------------------------------------------------------------------
create_azure_akv_store() {
  # $1 subdomain, $2 token, $3 store_name, $4 store_desc, $5 azure_directory_id,
  # $6 vault_url, $7 sh_app_client_id, $8 subscription_id, $9 subscription_name,
  # $10 resource_group
  if [ $# -lt 10 ]; then
    printf "\nUsage: create_azure_akv_store <subdomain> <token> <store_name> <store_desc> <azure_directory_id> <vault_url> <sh_app_client_id> <subscription_id> <subscription_name> <resource_group>\n" >&2
    return 1
  fi
  local subdomain="$1" token="$2" store_name="$3" store_desc="$4"
  local azure_directory_id="$5" vault_url="$6" sh_app_client_id="$7"
  local subscription_id="$8" subscription_name="$9" resource_group="${10}"

  printf "\nOnboarding AKV as Secrets Hub secret store: %s (%s)\n" "$store_name" "$vault_url"

  local body response id
  body=$(jq -cn \
    --arg name "$store_name" \
    --arg desc "$store_desc" \
    --arg dir "$azure_directory_id" \
    --arg url "$vault_url" \
    --arg appid "$sh_app_client_id" \
    --arg sub "$subscription_id" \
    --arg subname "$subscription_name" \
    --arg rg "$resource_group" \
    '{
      type: "AZURE_AKV",
      name: $name,
      description: $desc,
      data: {
        appClientDirectoryId: $dir,
        azureVaultUrl: $url,
        appClientId: $appid,
        authenticationMethod: "FEDERATED_IDENTITY",
        connectionConfig: { connectionType: "PUBLIC" },
        subscriptionId: $sub,
        subscriptionName: $subname,
        resourceGroupName: $rg
      }
    }')

  response=$(curl --silent --show-error --location \
    "https://$subdomain.secretshub.cyberark.cloud/api/secret-stores" \
    --header "Authorization: Bearer $token" \
    --header 'Content-Type: application/json' \
    --data "$body")

  id=$(printf '%s' "$response" | jq -r '.id // empty')
  if [ -z "$id" ] || [ "$id" = "null" ]; then
    printf "\nERROR: create secret store failed.\nResponse: %s\n" "$response" >&2
    return 1
  fi
  printf '%s' "$id"
}

# ---------------------------------------------------------------------------
# Secrets Hub: create the sync policy (source Privilege Cloud safe -> target
# AKV store). Prints the created policy id on success.
# ---------------------------------------------------------------------------
create_sync_policy() {
  # $1 subdomain, $2 token, $3 policy_name, $4 policy_desc, $5 source_id,
  # $6 target_id, $7 safe_name
  if [ $# -lt 7 ]; then
    printf "\nUsage: create_sync_policy <subdomain> <token> <policy_name> <policy_desc> <source_id> <target_id> <safe_name>\n" >&2
    return 1
  fi
  local subdomain="$1" token="$2" policy_name="$3" policy_desc="$4"
  local source_id="$5" target_id="$6" safe_name="$7"

  printf "\nCreating Secrets Hub sync policy: %s (safe %s -> store %s)\n" "$policy_name" "$safe_name" "$target_id"

  local body response id
  body=$(jq -cn \
    --arg name "$policy_name" \
    --arg desc "$policy_desc" \
    --arg src "$source_id" \
    --arg tgt "$target_id" \
    --arg safe "$safe_name" \
    '{
      name: $name,
      description: $desc,
      source: { id: $src },
      target: { id: $tgt },
      filter: { type: "PAM_SAFE", data: { safeName: $safe } }
    }')

  response=$(curl --silent --show-error --location \
    "https://$subdomain.secretshub.cyberark.cloud/api/policies" \
    --header "Authorization: Bearer $token" \
    --header 'Content-Type: application/json' \
    --data "$body")

  id=$(printf '%s' "$response" | jq -r '.id // empty')
  if [ -z "$id" ] || [ "$id" = "null" ]; then
    printf "\nERROR: create sync policy failed.\nResponse: %s\n" "$response" >&2
    return 1
  fi
  printf '%s' "$id"
}
