#!/bin/bash
set -euo pipefail

demo_path="$CYBR_DEMOS_PATH/demos/secrets_manager/jenkins"
# shellcheck disable=SC1091
source "$demo_path/setup/vars.env" 2>/dev/null || true

state_dir="$demo_path/setup/jenkins/state"
CLOUDFLARED_PID_FILE="$state_dir/cloudflared.pid"

if [ -f "$CLOUDFLARED_PID_FILE" ]; then
  pid=$(cat "$CLOUDFLARED_PID_FILE")
  kill "$pid" 2>/dev/null || true
  rm -f "$CLOUDFLARED_PID_FILE"
fi
pkill -f "cloudflared.*127.0.0.1:${JENKINS_PORT:-8081}" 2>/dev/null || true

if [ -n "${JENKINS_CONTAINER:-}" ] && docker ps -a --format '{{.Names}}' | grep -qx "$JENKINS_CONTAINER"; then
  docker stop "$JENKINS_CONTAINER" && docker rm "$JENKINS_CONTAINER"
fi

rm -f "$demo_path/setup/.jenkins.env"

printf "Jenkins container and tunnel removed.\n"
