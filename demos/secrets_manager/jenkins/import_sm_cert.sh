#!/bin/bash
# Import Secrets Manager TLS cert into Jenkins container Java trust store (run on host).
set -euo pipefail

# shellcheck disable=SC1091
source "$(cd "$(dirname "$0")" && pwd)/jenkins_demo_lib.sh"
jenkins_load_env

container="${JENKINS_CONTAINER:-cybr-jenkins}"
conjur_fqdn="${TENANT_SUBDOMAIN}.secretsmgr.cyberark.cloud"

if ! jenkins_container_running; then
  printf 'Jenkins container %s is not running.\n' "$container" >&2
  exit 1
fi

printf 'Importing %s cert into %s (as root)...\n' "$conjur_fqdn" "$container"

docker exec -u root "$container" bash -c "
set -euo pipefail
conjur_fqdn=\"${conjur_fqdn}\"
pem_file=/tmp/conjur-sm-import.pem
rm -f \"\${pem_file}\" /tmp/\${conjur_fqdn}.pem 2>/dev/null || true
openssl s_client -showcerts -connect \"\${conjur_fqdn}:443\" </dev/null 2>/dev/null \
  | sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' > \"\${pem_file}\"
keytool -delete -alias \"\${conjur_fqdn}\" \
  -keystore /opt/java/openjdk/lib/security/cacerts \
  -storepass changeit -noprompt 2>/dev/null || true
keytool -importcert -alias \"\${conjur_fqdn}\" \
  -keystore /opt/java/openjdk/lib/security/cacerts \
  -file \"\${pem_file}\" -storepass changeit -noprompt
rm -f \"\${pem_file}\"
"

printf 'Restarting Jenkins...\n'
docker restart "$container" >/dev/null
printf 'Done. Wait ~30s, then open http://127.0.0.1:%s\n' "${JENKINS_PORT:-8081}"
