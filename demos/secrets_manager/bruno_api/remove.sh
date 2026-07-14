#!/bin/bash
# shellcheck disable=SC2059
# Tears down an ALM app created by the Bruno demo:
#   - deletes the Conjur workload policy branch data/<app>
#   - deletes the Privilege Cloud safe <app> (accounts first, then the safe)
#   - best-effort: deletes the ISP "<app>-admins" role
#
# Target app resolves from APP_NAME, else "<UseCaseAlmAppName base>-<LAB_ID>".
set -euo pipefail

source "$CYBR_DEMOS_PATH/demos/setup_env.sh"

APP_BASE="${UseCaseAlmAppName:-poc-alm-app}"
APP_NAME="${APP_NAME:-${APP_BASE}-${LAB_ID:-}}"

main() {
  : "${TENANT_ID:?TENANT_ID must be set}"
  : "${TENANT_SUBDOMAIN:?TENANT_SUBDOMAIN must be set}"
  case "$APP_NAME" in
    ""|*-) printf "ERROR: set APP_NAME (or LAB_ID) to the app to remove.\n" >&2; exit 1 ;;
  esac

  local isp_id="$TENANT_ID" isp_subdomain="$TENANT_SUBDOMAIN"
  local client_id="$CLIENT_ID" client_secret="$CLIENT_SECRET"

  printf "\nRemoving ALM app: %s\n" "$APP_NAME"
  local identity_token conjur_token
  identity_token=$(get_identity_token "$isp_id" "$client_id" "$client_secret")
  conjur_token=$(get_conjur_token "$isp_subdomain" "$identity_token")

  # 1. Delete the Conjur workload policy branch (data/<app>).
  printf "\n[conjur] deleting policy data/%s\n" "$APP_NAME"
  patch_conjur_policy "$isp_subdomain" "$conjur_token" "data" \
    "$(printf -- '---\n- !delete\n  record: !policy %s\n' "$APP_NAME")"

  # 2. Delete Privilege Cloud safe accounts, then the safe.
  delete_safe_accounts "$isp_subdomain" "$identity_token" "$APP_NAME"
  delete_safe "$isp_subdomain" "$identity_token" "$APP_NAME"

  # 3. Best-effort: delete the ISP "<app>-admins" role.
  if delete_app_admins_role "$isp_id" "$identity_token" "${APP_NAME}-admins"; then
    printf "[isp] deleted role %s-admins\n" "$APP_NAME"
  else
    printf "[isp] role %s-admins not deleted (remove manually if it lingers)\n" "$APP_NAME"
  fi

  printf "\nRemoval complete for %s\n" "$APP_NAME"
}

delete_safe_accounts() {
  # $1 isp_subdomain, $2 identity_token, $3 safe
  local sub="$1" token="$2" safe="$3" ids id
  ids=$(curl -s --location \
    "https://$sub.privilegecloud.cyberark.cloud/PasswordVault/API/Accounts?filter=safeName%20eq%20$safe" \
    --header "Authorization: Bearer $token" | jq -r '.value[].id // empty' 2>/dev/null)
  for id in $ids; do
    printf "[vault] deleting account %s in safe %s\n" "$id" "$safe"
    curl -s --request DELETE \
      --location "https://$sub.privilegecloud.cyberark.cloud/PasswordVault/API/Accounts/$id" \
      --header "Authorization: Bearer $token" >/dev/null
  done
}

delete_app_admins_role() {
  # $1 isp_id, $2 identity_token, $3 role_name  (best-effort)
  # Note: deletion requires the role's RowKey (looked up via Redrock) passed as
  # "Name" to /SaasManage/DeleteRole. /Roles/DeleteRole silently no-ops here.
  local isp="$1" token="$2" role="$3" rowkey resp
  rowkey=$(curl -s --request POST "https://$isp.id.cyberark.cloud/Redrock/query" \
    --header "Authorization: Bearer $token" --header "Content-Type: application/json" \
    --data "$(jq -cn --arg n "$role" '{Script: ("SELECT ID FROM Role WHERE Name=\u0027" + $n + "\u0027")}')" \
    | jq -r '.Result.Results[0].Row.ID // empty' 2>/dev/null)
  [ -n "$rowkey" ] || return 1
  resp=$(curl -s --request POST "https://$isp.id.cyberark.cloud/SaasManage/DeleteRole" \
    --header "Authorization: Bearer $token" --header "Content-Type: application/json" \
    --data "$(jq -cn --arg id "$rowkey" '{Name: $id}')")
  [ "$(echo "$resp" | jq -r '.success // false' 2>/dev/null)" = "true" ]
}

main "$@"
