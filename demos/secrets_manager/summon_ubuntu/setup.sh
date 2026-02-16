#!/bin/bash

# Setup script for: Summon Ubuntu
# Category: secrets_manager

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

echo "=========================================="
echo "Setup: Summon Ubuntu"
echo "=========================================="
echo ""

echo "Installing Summon and summon-conjur provider..."
bash ./setup/setup.sh

echo ""
echo "Local install complete."
echo ""
echo "Run one of these provisioning flows:"
echo ""
echo "Flow A (MCP tools):"
echo "  1) mcp__cybr-demos__provision_safe"
echo "     demoPath=secrets_manager/summon_ubuntu"
echo "     safeName=<your safe name>"
echo "     addSyncMember=true createAccounts=true setupConjur=true"
echo "  2) mcp__cybr-demos__provision_workload"
echo "     demoPath=secrets_manager/summon_ubuntu"
echo "     safeName=<same safe name>"
echo "     workloadName=summon-ubuntu"
echo ""
echo "Flow B (scripted Conjur workload setup):"
echo "  1) bash ./setup/vault/setup.sh"
echo "  2) bash ./setup/conjur/setup.sh"
echo ""
echo "Then source ./conjur_credentials.env and run ./demo.sh"

echo ""
echo "Setup completed successfully!"
