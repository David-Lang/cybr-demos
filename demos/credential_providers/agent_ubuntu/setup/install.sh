#!/bin/bash
set -euo pipefail

main() {
  set_variables
  install_package
  setup_safe
  setup_app_id
}

# shellcheck disable=SC2153
set_variables() {
  demo_path="$CYBR_DEMOS_PATH/demos/credential_providers/agent_ubuntu"

  # Set environment variables using .env file
  # -a means that every bash variable would become an environment variable
  # Using ‘+’ rather than ‘-’ causes the option to be turned off
  set -a
  source "$CYBR_DEMOS_PATH/demos/setup_env.sh"
  source "$demo_path/setup/vars.env"
  set +a

  tenant_id=$TENANT_ID
  tenant_subdomain=$TENANT_SUBDOMAIN
  client_id=$CLIENT_ID
  client_secret=$CLIENT_SECRET

  installer_id=$INSTALLER_USR
  installer_secret=$INSTALLER_PWD

  asset_s3_uri="$ASSET_S3_URI"
  zip_file="$ZIP_FILE"
  cark_package="$CARK_PACKAGE"
  cp_app_id="$CP_APP_ID"
  safe_name="$SAFE_NAME"

  install_directory_base="/home/ubuntu/cybr-demos-install/credential-provider"

}

install_package() {

  mkdir -p $install_directory_base
  pushd $install_directory_base || exit

  get_s3_asset $asset_s3_uri "$install_directory_base/$zip_file"

  cred_file="$install_directory_base/appprovideruser.cred"
  vault_ini="$install_directory_base/Vault.ini"
  aimparms="$install_directory_base/aimparms"

  vault_address="vault-$TENANT_SUBDOMAIN.privilegecloud.cyberark.cloud"

  unzip -o $zip_file

# create_cred_file
  chmod 700 ./CreateCredFile
  ./CreateCredFile $cred_file Password -Username "$installer_id" -Password "$installer_secret" -Hostname -EntropyFile

  cp Vault.ini Vault.ini.orig
  sed -i "s/ADDRESS=.*/ADDRESS=$vault_address/" Vault.ini
  sed -i "s/VaultName=.*/VaultName=CAMainVault/" Vault.ini


  # shellcheck disable=SC2002
  cat aimparms.sample \
                | sed -e "s#CredFilePath=.*#CredFilePath=$cred_file#g" \
                | sed -e "s#VaultFilePath=.*#VaultFilePath=$vault_ini#g" \
                | sed -e "s#AcceptCyberArkEULA=.*#AcceptCyberArkEULA=Yes#g" \
                | sed -e "s#\#CreateVaultEnvironment=yes#CreateVaultEnvironment=yes#g" > $aimparms
  cp -f $aimparms /var/tmp/aimparms

  identity_token=$(get_identity_token "$tenant_id" "$client_id" "$client_secret")
  add_ip_to_privilege_cloud_allowList "$tenant_subdomain" "$identity_token"

  # Reset installer pwd:  "$tenant_id" "$identity_token" "$installer_id"

  echo Installing agent package
  sudo dpkg -i $cark_package
  popd || exit

}

setup_safe() {
  identity_token=$(get_identity_token "$tenant_id" "$client_id" "$client_secret")

  create_safe "$tenant_subdomain" "$identity_token" "$safe_name"
  add_safe_admin_role "$tenant_subdomain" "$identity_token" "$safe_name" "Privilege Cloud Administrators"

  create_account_ssh_user_1 "$tenant_subdomain" "$identity_token" "$safe_name"

  # awk the Provider ID from the install logs
  # shellcheck disable=SC2005
  # shellcheck disable=SC2046
  prov_id=$(echo $(sudo grep 'Provider \[Prov_ip' /var/opt/CARKaim/logs/APPConsole.log) | nawk -F "[][]" -v var="2" '{print $(var*2)}' -)

  # Check if prov_id is null or empty
  if [ -z "${prov_id:-}" ]; then
      printf "\nERROR: Provisioning ID (prov_id) is missing or empty. Cannot proceed.\n" >&2
      exit 1
  fi

  echo "Adding Provider $prov_id to safe $safe_name"
  add_safe_read_member "$tenant_subdomain" "$identity_token" "$safe_name" "$prov_id"

}

setup_app_id() {
  create_app "$tenant_subdomain" "$identity_token" "$cp_app_id"

  # Add the OS user
  add_app_authentication "$tenant_subdomain" "$identity_token" "$cp_app_id" "OSUser" "$(whoami)"

  # Add the path to demo.sh
  add_app_authentication "$tenant_subdomain" "$identity_token" "$cp_app_id" "Path" "$demo_path/app1.sh"

  # Add the hash of $pwd/demo.sh
  appHash=$(/opt/CARKaim/bin/aimgetappinfo GetHash -FilePath "$demo_path/app1.sh")
  echo "Adding hash authn for appID $cp_app_id: $appHash"
    add_app_authentication "$tenant_subdomain" "$identity_token" "$cp_app_id" "Hash" "$appHash"

  appHash=$(/opt/CARKaim/bin/aimgetappinfo GetHash -FilePath "$demo_path"/app1_imposter.sh)
  echo "Adding hash authn for appID $cp_app_id: $appHash"
  add_app_authentication "$tenant_subdomain" "$identity_token" "$cp_app_id" "Hash" "$appHash"

  echo "Adding AppId $cp_app_id to safe $safe_name"
  add_safe_read_member "$tenant_subdomain" "$identity_token" "$safe_name" "$cp_app_id"

}

main "$@"
