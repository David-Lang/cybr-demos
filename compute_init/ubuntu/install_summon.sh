#!/bin/bash
set -euo pipefail

curl -sSL https://raw.githubusercontent.com/cyberark/summon-conjur/main/install.sh | sudo bash
curl -sSL https://raw.githubusercontent.com/cyberark/summon/main/install.sh | sudo bash
