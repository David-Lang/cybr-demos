#!/bin/bash
# Push Conjur plugin config + pipeline job into Jenkins via init.groovy.d (run on host).
set -euo pipefail

# shellcheck disable=SC1091
source "$(cd "$(dirname "$0")" && pwd)/jenkins_demo_lib.sh"
jenkins_demo_init
jenkins_load_env

container="${JENKINS_CONTAINER:-cybr-jenkins}"
init_dir="/var/jenkins_home/init.groovy.d"
port="${JENKINS_PORT:-8081}"

CONFIGURE_CONJUR_TMPL="$JENKINS_DEMO_DIR/setup/jenkins/configure_conjur.groovy.tmpl"
CONFIGURE_CONJUR_RENDERED="$JENKINS_DEMO_DIR/setup/jenkins/configure_conjur.groovy"

render_configure_conjur() {
  : "${TENANT_SUBDOMAIN:?TENANT_SUBDOMAIN required for configure_conjur.groovy render}"
  : "${CONJUR_JWT_AUTHN_ID:?CONJUR_JWT_AUTHN_ID required for configure_conjur.groovy render}"
  local audience="${CONJUR_AUDIENCE:-cyberark-conjur}"
  local appliance_url
  appliance_url="$(conjur_appliance_url)"
  sed \
    -e "s|{{APPLIANCE_URL}}|${appliance_url}|g" \
    -e "s|{{CONJUR_JWT_AUTHN_ID}}|${CONJUR_JWT_AUTHN_ID}|g" \
    -e "s|{{CONJUR_AUDIENCE}}|${audience}|g" \
    "$CONFIGURE_CONJUR_TMPL" >"$CONFIGURE_CONJUR_RENDERED"
  printf 'Rendered %s (authn-jwt/%s -> %s)\n' \
    "$CONFIGURE_CONJUR_RENDERED" "$CONJUR_JWT_AUTHN_ID" "$appliance_url"
}

if ! jenkins_container_running; then
  printf 'Jenkins container %s is not running.\n' "$container" >&2
  exit 1
fi

if ! pipeline_is_rendered; then
  bash "$JENKINS_DEMO_DIR/render_pipeline.sh"
fi

render_configure_conjur

docker exec "$container" mkdir -p "$init_dir"
docker cp "$JENKINS_PIPELINE_FILE" "${container}:/var/jenkins_home/get_secrets.groovy"
docker cp "$CONFIGURE_CONJUR_RENDERED" "${container}:${init_dir}/zzz-configure-conjur.groovy"
docker cp "$JENKINS_DEMO_DIR/setup/jenkins/create_pipeline_job.groovy" "${container}:${init_dir}/zzz-create-pipeline.groovy"

printf 'Restarting Jenkins to apply init scripts...\n'
docker restart "$container" >/dev/null

printf 'Waiting for Jenkins...'
for _ in $(seq 1 60); do
  if curl -sf "http://127.0.0.1:${port}/login" >/dev/null 2>&1; then
    echo ' ready.'
    docker exec "$container" rm -f \
      "${init_dir}/zzz-configure-conjur.groovy" \
      "${init_dir}/zzz-create-pipeline.groovy" 2>/dev/null || true
    if jenkins_automation_ready; then
      printf 'Conjur plugin and job global-credentials-demo are configured.\n'
    else
      printf '[WARN] Jenkins is up but automation checks did not all pass — run bash ready_check.sh\n'
    fi
    exit 0
  fi
  sleep 2
done
echo
printf 'Jenkins slow to start — check http://127.0.0.1:%s\n' "$port"
exit 1
