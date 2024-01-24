#!/bin/bash
set -euo pipefail

curl -sSL https://raw.githubusercontent.com/cyberark/summon-conjur/main/install.sh | bash
curl -sSL https://raw.githubusercontent.com/cyberark/summon/main/install.sh | bash
