#!/bin/bash
set -euo pipefail

printf "\nInjected environment variables\n"
printf "SECRET1: %s\n" "${SECRET1:-}"
printf "SECRET2: %s\n" "${SECRET2:-}"
printf "SECRET3: %s\n" "${SECRET3:-}"
