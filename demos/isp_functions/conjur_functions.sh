#!/bin/bash
set -euo pipefail

get_conjur_token(){
  # $1 isp_subdomain, $2 identity_token
  if [ $# -ne 2 ]; then
      echo "Usage: get_conjur_token isp_subdomain identity_token"
      return 1
  fi

  curl --silent --location "https://$1.secretsmgr.cyberark.cloud/api/authn-oidc/cyberark/conjur/authenticate" \
  --header 'Accept-Encoding: base64' \
  --header 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode "id_token=$2"
}

apply_conjur_policy(){
  # $1 isp_subdomain, $2 conjur_token, $3 branch, $4 policy
  if [ $# -ne 4 ]; then
      echo "Usage: isp_subdomain conjur_token apply_conjur_policy branch policy "
      return 1
  fi

  curl --silent --location "https://$1.secretsmgr.cyberark.cloud/api/policies/conjur/policy/$3" \
  --header "Authorization: Token token=\"$2\"" \
  --header 'Content-Type: text/plain' \
  --data "$4"
}

apply_conjur_secret(){
  # $1 isp_subdomain, $2 conjur_token, $3 id, 4$ value
  if [ $# -ne 4 ]; then
      echo "Usage: apply_conjur_secret isp_subdomain conjur_token id value"
      return 1
  fi

  curl --silent --location "https://$1.secretsmgr.cyberark.cloud/api/secrets/conjur/variable/$3" \
  --header "Authorization: Token token=\"$2\"" \
  --header 'Content-Type: text/plain' \
  --data "$4"
}

activate_conjur_service(){
  # $1 isp_subdomain, $2 conjur_token, $3 service_id
  if [ $# -ne 3 ]; then
      echo "Usage: activate_conjur_service isp_subdomain conjur_token service_id"
      return 1
  fi

  curl --silent --request PATCH --location "https://$1.secretsmgr.cyberark.cloud/api/$3/conjur" \
  --header 'X-Request-Id: <string>' \
  --header "Authorization: Token token=\"$2\"" \
  --header 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode 'enabled=true'
}

get_conjur_groups(){
  # $1 isp_subdomain, $2 conjur_token
  if [ $# -ne 2 ]; then
      echo "Usage: get_conjur_groups isp_subdomain conjur_token"
      return 1
  fi
  curl --silent --location "https://$1.secretsmgr.cyberark.cloud/api/resources?kind=group" \
  --header "Authorization: Token token=\"$2\""
}

wait_for_synchronizer() {
  # $1 isp_subdomain, $2 conjur_token, $3 safe_name
  if [ $# -ne 3 ]; then
    echo "Usage: wait_for_synchronizer isp_subdomain conjur_token safe_name"
    return 1
  fi

  while [[ "$(get_conjur_groups "$1" "$2" | grep "/$3"/delegation/consumers)" == "" ]]; do
    echo -n "."
    sleep 2
  done
}
