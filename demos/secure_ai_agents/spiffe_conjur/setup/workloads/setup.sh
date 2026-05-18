#!/bin/bash
# setup/workloads/setup.sh
#
# Stage 2: deploy the BEFORE pod (vulnerable-agent) and the AFTER pod
# (attested-agent). The attested-agent manifest is templated -- envsubst
# fills in the trust domain and Conjur Cloud URL from setup/vars.env.

# shellcheck disable=SC1091
set -euo pipefail

if [ -z "${CYBR_DEMOS_PATH:-}" ]; then
  CYBR_DEMOS_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
  export CYBR_DEMOS_PATH
fi

demo_path="$CYBR_DEMOS_PATH/demos/secure_ai_agents/spiffe_conjur"

set -a
source "$CYBR_DEMOS_PATH/demos/setup_env.sh"
source "$demo_path/setup/vars.env"
set +a

stage_dir="$demo_path/setup/workloads"
kctx() { kubectl --context "$MINIKUBE_PROFILE" "$@"; }

if ! command -v envsubst >/dev/null 2>&1; then
  printf "[FAIL] envsubst not found (install gettext: brew install gettext / apt install gettext)\n" >&2
  exit 1
fi

printf "\n[INFO] Workloads: applying BEFORE pod (vulnerable-agent)\n"
kctx apply -f "$stage_dir/manifests/00-vulnerable-agent.yaml"

printf "\n[INFO] Workloads: rendering attested-agent manifest from template\n"
rendered="$stage_dir/manifests/40-attested-agent.rendered.yaml"
# `set -a` (above) already exports vars.env values — envsubst inherits them.
# The single-quoted argument is envsubst's variable allowlist syntax, NOT a shell expansion.
# shellcheck disable=SC2016
envsubst '${ATTESTED_AGENT_NAME} ${ATTESTED_AGENT_SA} ${WORKLOADS_NAMESPACE} ${TRUST_DOMAIN} ${TENANT_SUBDOMAIN} ${CONJUR_AUTHN_SERVICE_ID} ${CONJUR_SECRET_VARIABLE} ${SPIRE_TOOLS_IMAGE}' \
  < "$stage_dir/manifests/40-attested-agent.yaml.tpl" \
  > "$rendered"

printf "[INFO] Workloads: applying AFTER pod (attested-agent)\n"
kctx apply -f "$rendered"

printf "\n[INFO] Workloads: stage complete\n"
printf "[INFO] Workloads:   BEFORE -> kubectl get pod -n %s vulnerable-agent\n" "$VULNERABLE_NAMESPACE"
printf "[INFO] Workloads:   AFTER  -> kubectl get pod -n %s %s\n" "$WORKLOADS_NAMESPACE" "$ATTESTED_AGENT_NAME"
