#!/bin/bash
# Alias for the SWA demo bootstrap. See go.sh.
set -euo pipefail
demo_path="$(cd "$(dirname "$0")" && pwd)"
exec bash "$demo_path/go.sh" "$@"
