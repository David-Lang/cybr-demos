#!/bin/bash
set -euo pipefail

branch="main"
rm -rf /home/ubuntu/cybr-demos
git clone https://github.com/David-Lang/cybr-demos.git \
  --branch $branch --depth 1 --single-branch

cybr-demos/compute_init/ubuntu/setup.sh
cybr-demos/demos/utility/overwrite_vars.env.sh
