#!/bin/bash
set -euo pipefail

get_identity_token() {
  # $1 isp_id, $2 client_id, $3 client_secret
  if [ $# -ne 3 ]; then
      echo "Usage: get_identity_token client_id, client_secret, isp_id"
      return 1
  fi

  curl --silent --location "https://$1.id.cyberark.cloud/oauth2/platformtoken" \
  --header 'X-IDAP-NATIVE-CLIENT: true' \
  --header 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode 'grant_type=client_credentials' \
  --data-urlencode "client_id=$2" \
  --data-urlencode "client_secret=$3" | jq -r .access_token
}
