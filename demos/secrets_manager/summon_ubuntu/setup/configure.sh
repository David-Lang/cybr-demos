#!/bin/bash

echo "Configuring Conjur environment variables..."
echo ""

# Prompt for values or use defaults
read -p "Enter CONJUR_APPLIANCE_URL (default: https://your-conjur-instance.com): " appliance
appliance=${appliance:-https://your-conjur-instance.com}

read -p "Enter CONJUR_ACCOUNT (default: your-account): " account
account=${account:-your-account}

read -p "Enter CONJUR_AUTHN_LOGIN (default: your-username): " login
login=${login:-your-username}

read -p "Enter CONJUR_AUTHN_API_KEY (default: your-api-key): " apikey
apikey=${apikey:-your-api-key}

# Set for current session
export CONJUR_APPLIANCE_URL="$appliance"
export CONJUR_ACCOUNT="$account"
export CONJUR_AUTHN_LOGIN="$login"
export CONJUR_AUTHN_API_KEY="$apikey"

# Persist to ~/.bashrc
BASHRC="$HOME/.bashrc"

# Remove old entries if they exist
sed -i '/^export CONJUR_APPLIANCE_URL=/d' "$BASHRC" 2>/dev/null || true
sed -i '/^export CONJUR_ACCOUNT=/d' "$BASHRC" 2>/dev/null || true
sed -i '/^export CONJUR_AUTHN_LOGIN=/d' "$BASHRC" 2>/dev/null || true
sed -i '/^export CONJUR_AUTHN_API_KEY=/d' "$BASHRC" 2>/dev/null || true

# Add new entries
echo "" >> "$BASHRC"
echo "# Conjur configuration" >> "$BASHRC"
echo "export CONJUR_APPLIANCE_URL=\"$appliance\"" >> "$BASHRC"
echo "export CONJUR_ACCOUNT=\"$account\"" >> "$BASHRC"
echo "export CONJUR_AUTHN_LOGIN=\"$login\"" >> "$BASHRC"
echo "export CONJUR_AUTHN_API_KEY=\"$apikey\"" >> "$BASHRC"

echo ""
echo "Environment variables configured successfully!"
echo "CONJUR_APPLIANCE_URL: $appliance"
echo "CONJUR_ACCOUNT: $account"
echo "CONJUR_AUTHN_LOGIN: $login"
echo "CONJUR_AUTHN_API_KEY: ****"
echo ""
echo "These variables have been saved to $BASHRC"
echo "They will be available in new shell sessions."
echo "To use them now, run: source ~/.bashrc"
