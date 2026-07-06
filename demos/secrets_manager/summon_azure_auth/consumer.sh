#!/bin/bash
set -euo pipefail

# Proves Summon injected the vaulted credential into this process. The password
# is shown as presence/length, not printed, so it does not leak into logs.
printf "\nInjected environment variables (from CyberArk via Summon)\n"
printf "PGUSER:     %s\n" "${PGUSER:-<empty>}"
if [ -n "${PGPASSWORD:-}" ]; then
  printf "PGPASSWORD: present (%s chars)\n" "${#PGPASSWORD}"
else
  printf "PGPASSWORD: <empty>\n"
fi
