#!/bin/bash
set -euo pipefail

# Validate required vars
echo "--- Variables Used ---"
echo CONJUR_APPLIANCE_URL="$CONJUR_APPLIANCE_URL"
echo CONJUR_ACCOUNT="$CONJUR_ACCOUNT"
echo CONJUR_AUTHN_LOGIN="$CONJUR_AUTHN_LOGIN"
echo CONJUR_AUTHN_API_KEY="$CONJUR_AUTHN_API_KEY"

summon -p summon-conjur bash consumer.sh