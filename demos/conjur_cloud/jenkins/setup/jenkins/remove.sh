#!/bin/bash
# shellcheck disable=SC2046
# shellcheck disable=SC2005
# shellcheck disable=SC2153
set -euo pipefail

jenkins_container="$JENKINS_CONTAINER"
docker stop $jenkins_container && docker rm $jenkins_container
