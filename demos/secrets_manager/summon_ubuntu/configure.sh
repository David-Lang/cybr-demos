#!/bin/bash
set -euo pipefail

# Configure Conjur environment variables
# This script sets up the required environment variables for Summon to connect to Conjur

echo "Configuring Conjur environment variables..."

read_with_default() {
  local prompt="$1"
  local default_value="$2"
  local value
  read -r -p "$prompt (default: $default_value): " value
  printf "%s" "${value:-$default_value}"
}

upsert_export() {
  local profile_file="$1"
  local var_name="$2"
  local var_value="$3"

  touch "$profile_file"
  sed -i.bak "/^export ${var_name}=/d" "$profile_file"
  rm -f "${profile_file}.bak"
  printf "export %s=\"%s\"\n" "$var_name" "$var_value" >> "$profile_file"
}

appliance=$(read_with_default "Enter CONJUR_APPLIANCE_URL" "https://your-conjur-instance.com")
account=$(read_with_default "Enter CONJUR_ACCOUNT" "your-account")
login=$(read_with_default "Enter CONJUR_AUTHN_LOGIN" "your-username")
apikey=$(read_with_default "Enter CONJUR_AUTHN_API_KEY" "your-api-key")

# Set environment variables for current session
export CONJUR_APPLIANCE_URL="$appliance"
export CONJUR_ACCOUNT="$account"
export CONJUR_AUTHN_LOGIN="$login"
export CONJUR_AUTHN_API_KEY="$apikey"

# Persist environment variables to user scope
PROFILE_FILE="$HOME/.bashrc"
upsert_export "$PROFILE_FILE" "CONJUR_APPLIANCE_URL" "$appliance"
upsert_export "$PROFILE_FILE" "CONJUR_ACCOUNT" "$account"
upsert_export "$PROFILE_FILE" "CONJUR_AUTHN_LOGIN" "$login"
upsert_export "$PROFILE_FILE" "CONJUR_AUTHN_API_KEY" "$apikey"

echo ""
echo "Environment variables configured successfully!"
echo "CONJUR_APPLIANCE_URL: $appliance"
echo "CONJUR_ACCOUNT: $account"
echo "CONJUR_AUTHN_LOGIN: $login"
echo "CONJUR_AUTHN_API_KEY: ****"
echo ""
echo "These variables have been saved to your user profile ($PROFILE_FILE)."
echo "They will be available in new shell sessions."
