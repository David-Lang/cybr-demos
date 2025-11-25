#!/bin/bash
set -euo pipefail

main() {
  set_variables
  install_package
#  setup_safe
#  setup_app_id
}

# shellcheck disable=SC2153
set_variables() {
  # Set environment variables using .env file
  # -a means that every bash variable would become an environment variable
  # Using ‘+’ rather than ‘-’ causes the option to be turned off
  set -a
  source "$demo_path/setup/vars.env"
  set +a

  asset_s3_uri="s3://cybr-demos/marketplace/credential-providers/AAM-Ubuntu-Intel64-Rls-v14.2.4.3.zip"
  zip_file="AAM-Ubuntu-Intel64-Rls-v14.2.4.3.zip"
  cark_package="CARKaim-14.02.4.3.amd64.deb"
  install_directory_base="/home/ubuntu/cybr-demos-install/credential-provider"

#  cp_app_id="cp_app1"
#  cp_safe="app1_safe"
}

install_package() {
  mkdir -p $install_directory_base
  pushd $install_directory_base || exit

  get_s3_asset $asset_s3_uri "$install_directory_base/$zip_file"

  cred_file="$install_directory_base/appprovideruser.cred"
  vault_ini="$install_directory_base/Vault.ini"
  aimparms="$install_directory_base/aimparms"

  unzip $zip_file

# create_cred_file
  chmod 700 ./CreateCredFile
  ./CreateCredFile $cred_file Password -Username "$pas_username" -Password "$pas_password" -Hostname -EntropyFile

# massage_vault_ini
  mv Vault.ini Vault.ini.orig
  # shellcheck disable=SC2002
  cat Vault.ini.orig | sed "s/ADDRESS=.*/ADDRESS=$vault_ip/" > $vault_ini

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

#add_provider_to_safe() {
#  # awk the Provider ID from the install logs
#  # shellcheck disable=SC2005
#  # shellcheck disable=SC2046
#  prov_id=$(echo $(sudo grep 'Adding \[Prov' /var/tmp/aim-install-logs/CreateEnv.log) | nawk -F "[][]" -v var="2" '{print $(var*2)}' -)
#
#  echo "Adding Provider $prov_id to safe $cp_safe"
#  cybr safes add-member -m "$prov_id" -s "$cp_safe" --view-safe-members --list-accounts --retrieve-accounts --use-accounts --access-content-without-confirmation
#}
#
#create_app_id() {
#  cybr applications add -a $cp_app_id -l "\\"
#}
#
#create_app_id_authn() {
#  # Add the OS user
#  cybr applications add-authn -a $cp_app_id --auth-type OSUser --auth-value "$(whoami)"
#
#  # Add the path to demo.sh
#  cybr applications add-authn -a $cp_app_id --auth-type Path --auth-value "$(pwd)"/app1.sh
#
#  # Add the hash of $pwd/demo.sh
#  appHash=$(/opt/CARKaim/bin/aimgetappinfo GetHash -FilePath "$(pwd)"/app1.sh)
#  echo "Adding hash authn for appID $cp_app_id: $appHash"
#  cybr applications add-authn -a $cp_app_id --auth-type Hash --auth-value "$appHash"
#
#  appHash=$(/opt/CARKaim/bin/aimgetappinfo GetHash -FilePath "$(pwd)"/app1_imposter.sh)
#  echo "Adding hash authn for appID $cp_app_id: $appHash"
#  cybr applications add-authn -a $cp_app_id --auth-type Hash --auth-value "$appHash"
#
#}
#
#add_app_id_to_safe() {
#  echo "Adding Provider $cp_app_id to safe $cp_safe"
#  cybr safes add-member -m "$cp_app_id" -s "$cp_safe" --list-accounts --retrieve-accounts --use-accounts --access-content-without-confirmation
#}

main "$@"
