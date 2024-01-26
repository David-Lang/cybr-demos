#!/bin/bash
set -euo pipefail

branch="main"
rm -rf /home/ubuntu/cybr-demos
git clone https://github.com/David-Lang/cybr-demos.git \
  --branch $branch --depth 1 --single-branch

"$CYBR_DEMOS_PATH"/demos/utility/reset_cybr_demos.sh
