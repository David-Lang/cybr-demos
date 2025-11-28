#!/bin/bash
set -euo pipefail

main() {
  set_variables
  add_ip_to_privledge_cloud_allowList
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
  source "$CYBR_DEMOS_PATH/demos/setup_vars.env.sh"
  source "$demo_path/setup/vars.env"
  set +a

  tenant_id=$TENANT_ID
  tenant_subdomain=$TENANT_SUBDOMAIN
  client_id=$CLIENT_ID
  client_secret=$CLIENT_SECRET

  asset_s3_uri="$ASSET_S3_URI"
  zip_file="$ZIP_FILE"
  cark_package="$CARK_PACKAGE"
  cp_app_id="$CP_APP_ID"
  safe_name="$SAFE_NAME"

  install_directory_base="/home/ubuntu/cybr-demos-install/credential-provider"
}

add_ip_to_privilege_cloud_allowList(){
  ip=$(curl --silent "https://checkip.amazonaws.com/")
  ip_cidr="${ip}/32"
  ip_list="[\"${ip_cidr}\"]"
  identity_token=$(get_identity_token "$isp_id" "$client_id" "$client_secret")
  update_ip_allowlist "$tenant_subdomain" "$identity_token" "$ip_list"
  printf "\nWaiting 10 minutes for Privilege Cloud Allow List update to complete...\n"
  sleep 600
}

install_package() {
  mkdir -p $install_directory_base
  pushd $install_directory_base || exit

  get_s3_asset $asset_s3_uri "$install_directory_base/$zip_file"

  cred_file="$install_directory_base/appprovideruser.cred"
  vault_ini="$install_directory_base/Vault.ini"
  aimparms="$install_directory_base/aimparms"

  pas_username="$CLIENT_ID"
  pas_password="$CLIENT_SECRET"
  vault_address="vault.$TENANT_SUBDOMAIN.privilegecloud.cyberark.cloud"

  unzip -o $zip_file

# create_cred_file
  chmod 700 ./CreateCredFile
  ./CreateCredFile $cred_file Password -Username "$pas_username" -Password "$pas_password" -Hostname -EntropyFile

# setup_vault_ini
  mv Vault.ini Vault.ini.orig
  # shellcheck disable=SC2002
  cat Vault.ini.orig | sed "s/ADDRESS=.*/ADDRESS=$vault_address/" > $vault_ini
  cat Vault.ini.orig | sed "s/VaultName=.*/VaultName=CAMainVault/" > $vault_ini

  # shellcheck disable=SC2002
  cat aimparms.sample \
                | sed -e "s#CredFilePath=.*#CredFilePath=$cred_file#g" \
                | sed -e "s#VaultFilePath=.*#VaultFilePath=$vault_ini#g" \
                | sed -e "s#AcceptCyberArkEULA=.*#AcceptCyberArkEULA=Yes#g" \
                | sed -e "s#\#CreateVaultEnvironment=yes#CreateVaultEnvironment=yes#g" > $aimparms
  cp -f $aimparms /var/tmp/aimparms

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

  echo "Adding AppId $cp_app_id to safe $cp_safe"
  add_safe_read_member "$tenant_subdomain" "$identity_token" "$safe_name" "$cp_app_id"
}

main "$@"
