# Configure Conjur environment variables
# This script sets up the required environment variables for Summon to connect to Conjur

Write-Host "Configuring Conjur environment variables..."

# Prompt for values or use defaults
$appliance = Read-Host "Enter CONJUR_APPLIANCE_URL (default: https://your-conjur-instance.com)"
if ([string]::IsNullOrWhiteSpace($appliance)) {
    $appliance = "https://your-conjur-instance.com"
}

$account = Read-Host "Enter CONJUR_ACCOUNT (default: your-account)"
if ([string]::IsNullOrWhiteSpace($account)) {
    $account = "your-account"
}

$login = Read-Host "Enter CONJUR_AUTHN_LOGIN (default: your-username)"
if ([string]::IsNullOrWhiteSpace($login)) {
    $login = "your-username"
}

$apiKey = Read-Host "Enter CONJUR_AUTHN_API_KEY (default: your-api-key)"
if ([string]::IsNullOrWhiteSpace($apiKey)) {
    $apiKey = "your-api-key"
}

# Set environment variables for current session
$env:CONJUR_APPLIANCE_URL = $appliance
$env:CONJUR_ACCOUNT = $account
$env:CONJUR_AUTHN_LOGIN = $login
$env:CONJUR_AUTHN_API_KEY = $apiKey

# Persist environment variables to user scope
[System.Environment]::SetEnvironmentVariable("CONJUR_APPLIANCE_URL", $appliance, "User")
[System.Environment]::SetEnvironmentVariable("CONJUR_ACCOUNT", $account, "User")
[System.Environment]::SetEnvironmentVariable("CONJUR_AUTHN_LOGIN", $login, "User")
[System.Environment]::SetEnvironmentVariable("CONJUR_AUTHN_API_KEY", $apiKey, "User")

Write-Host ""
Write-Host "Environment variables configured successfully!"
Write-Host "CONJUR_APPLIANCE_URL: $appliance"
Write-Host "CONJUR_ACCOUNT: $account"
Write-Host "CONJUR_AUTHN_LOGIN: $login"
Write-Host "CONJUR_AUTHN_API_KEY: ****"
Write-Host ""
Write-Host "These variables have been saved to your user profile."
Write-Host "They will be available in new PowerShell sessions."
