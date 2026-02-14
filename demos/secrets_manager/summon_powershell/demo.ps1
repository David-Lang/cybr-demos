#!/usr/bin/env pwsh
# PowerShell version of the summon demo

# Set strict mode for better error handling
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

./setEnvVars.ps1

# Validate required vars
Write-Host "--- Variables Used ---"
Write-Host "CONJUR_APPLIANCE_URL=$env:CONJUR_APPLIANCE_URL"
Write-Host "CONJUR_ACCOUNT=$env:CONJUR_ACCOUNT"
Write-Host "CONJUR_AUTHN_LOGIN=$env:CONJUR_AUTHN_LOGIN"
Write-Host "CONJUR_AUTHN_API_KEY=$env:CONJUR_AUTHN_API_KEY"

# Check if required environment variables are set
if (-not $env:CONJUR_APPLIANCE_URL) {
    throw "CONJUR_APPLIANCE_URL environment variable is not set"
}
if (-not $env:CONJUR_ACCOUNT) {
    throw "CONJUR_ACCOUNT environment variable is not set"
}
if (-not $env:CONJUR_AUTHN_LOGIN) {
    throw "CONJUR_AUTHN_LOGIN environment variable is not set"
}
if (-not $env:CONJUR_AUTHN_API_KEY) {
    throw "CONJUR_AUTHN_API_KEY environment variable is not set"
}

# Use summon with summon-conjur provider to run the PowerShell consumer script
& summon -p summon-conjur.exe pwsh consumer.ps1
