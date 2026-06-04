#!/bin/bash
# Shell into the Jenkins container (debugging only).
# For TLS import use: bash import_sm_cert.sh
set -euo pipefail

# shellcheck disable=SC1091
source "$(cd "$(dirname "$0")" && pwd)/jenkins_demo_lib.sh"
jenkins_load_env 2>/dev/null || true
container="${JENKINS_CONTAINER:-cybr-jenkins}"

docker exec -it "$container" bash
