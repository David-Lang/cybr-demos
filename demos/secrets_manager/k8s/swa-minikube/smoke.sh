#!/usr/bin/env bash
# Run all milestone smoke checks in order (M1 platform → M2 authn → M3 workload).
set -uo pipefail

demo_path="$(cd "$(dirname "$0")" && pwd)"
rc=0

for script in smoke_m1.sh smoke_m2.sh ready_check.sh; do
  bash "$demo_path/$script" || rc=1
done

[[ $rc -eq 0 ]] && printf '========== ALL SMOKE PASS ==========\n\n' \
               || printf '========== SMOKE FAILED — see [FAIL] above ==========\n\n'
exit $rc
