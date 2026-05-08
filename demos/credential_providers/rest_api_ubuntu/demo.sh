#!/bin/bash
set -euo pipefail

source "$CYBR_DEMOS_PATH/demos/utility/ubuntu/demo_utility.sh"
demo_path="$CYBR_DEMOS_PATH/demos/credential_providers/rest_api_ubuntu"

set -a
source "$CYBR_DEMOS_PATH/demos/setup_env.sh"
source "$demo_path/setup/vars.env"
set +a

cd "$demo_path"

echo
echo
# shellcheck disable=SC2059
# shellcheck disable=SC2153
pas_base_url="$PAS_BASE_URL"
app1_id="$CCP_APP1_ID"
app2_id="$CCP_APP2_ID"
app3_id="$CCP_APP3_ID"
safe="$SAFE_NAME"
user_name="ssh-user-1"

# shellcheck disable=SC2154
printf "cert_serial_number: ${Yellow}$(cat cert_serial_number)${Color_Off}\n"
echo
# shellcheck disable=SC2154
printf "pas_base_url: ${Green}$pas_base_url${Color_Off}\n"
printf "app_id: ${Green}$app1_id${Color_Off}\n"
printf "app_id: ${Green}$app2_id${Color_Off}\n"
printf "app_id: ${Green}$app3_id${Color_Off}\n"
printf "safe: ${Green}$safe${Color_Off}\n"
printf "user_name: ${Green}$user_name${Color_Off}\n"
echo
echo

# shellcheck disable=SC2154
printf  "curl -sk \"$pas_base_url/AIMWebService/api/Accounts?AppID=${UGreen}$app1_id${Color_Off}"
printf  "&Safe=${UGreen}$safe${Color_Off}&UserName=${UGreen}$user_name${Color_Off}\" | jq \n"
echo
curl -sk "$pas_base_url/AIMWebService/api/Accounts?AppID=$app1_id&Safe=$safe&UserName=$user_name" | jq
echo
echo

printf  "curl -sk \"$pas_base_url/AIMWebService/api/Accounts?AppID=${UGreen}$app2_id${Color_Off}"
printf  "&Safe=${UGreen}$safe${Color_Off}&UserName=${UGreen}$user_name${Color_Off}\" "
printf -- "--cert ${UGreen}app.crt${Color_Off} --key ${UGreen}app.key${Color_Off} | jq -r .Content\n"
echo
curl -sk "$pas_base_url/AIMWebService/api/Accounts?AppID=$app2_id&Safe=$safe&UserName=$user_name" \
     --cert app.crt --key app.key | jq -r .Content
echo
echo

printf  "curl -sk \"$pas_base_url/AIMWebService/api/Accounts?AppID=${UGreen}$app3_id${Color_Off}"
printf  "&Safe=${UGreen}$safe${Color_Off}&UserName=${UGreen}$user_name${Color_Off}\" "
printf -- "--cert ${UGreen}app.crt${Color_Off} --key ${UGreen}app.key${Color_Off} | jq -r .Content\n"
echo
curl -sk "$pas_base_url/AIMWebService/api/Accounts?AppID=$app3_id&Safe=$safe&UserName=$user_name" \
     --cert app.crt --key app.key | jq -r .Content
echo
echo
