#!/bin/bash
set -euo pipefail

source "$CYBR_DEMOS_PATH/demo_utility.sh"

echo
echo
# shellcheck disable=SC2059
app_id="cp_app1"
safe="cp_app1"
user_name="account-ssh-user-1"

# shellcheck disable=SC2154
printf "app_id:    ${Green}$app_id${Color_Off}\n"
printf "safe:      ${Green}$safe${Color_Off}\n"
printf "user_name: ${Green}$user_name${Color_Off}\n"
echo
echo
printf -- "/opt/CARKaim/sdk/clipasswordsdk GetPassword \\ \n"
# shellcheck disable=SC2154
printf -- "-p AppDescs.AppID=${UGreen}$app_id${Color_Off} \\ \n"
printf -- "-p QueryFormat=2 \\ \n"
printf -- "-p Query=\"Safe=${UGreen}$safe${Color_Off};UserName=${UGreen}$user_name${Color_Off}\" \\ \n"
printf -- "-p Reason=\"CP from jumpbox demo\" \\ \n"
printf -- "-o Password \n"
echo
echo

echo "$(pwd)/app1.sh"
bash "$(pwd)/app1.sh" || true
echo
echo

echo "$(pwd)/app1_imposter.sh"
bash "$(pwd)/app1_imposter.sh" || true
echo
echo

echo "$(pwd)/app1_modified.sh"
bash "$(pwd)/app1_modified.sh" || true
echo
echo

# shellcheck disable=SC2059
printf -- "/opt/CARKaim/bin/appprvmgr ShowParms \n"
/opt/CARKaim/bin/appprvmgr ShowParms