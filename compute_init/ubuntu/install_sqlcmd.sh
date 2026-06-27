#!/usr/bin/env bash
set -euo pipefail

SQLCMD_BIN="${SQLCMD_BIN:-sqlcmd}"

usage() {
  cat <<EOF
Usage: $(basename "$0")

Installs Microsoft sqlcmd for Ubuntu.

This script installs Microsoft's mssql-tools18 package and links sqlcmd to
/usr/local/bin/sqlcmd.

Environment:
  SQLCMD_BIN   Command or path to check before installing. Default: sqlcmd.
EOF
}

resolve_sqlcmd() {
  local candidate

  if command -v "$SQLCMD_BIN" >/dev/null 2>&1; then
    command -v "$SQLCMD_BIN"
    return 0
  fi

  for candidate in /usr/local/bin/sqlcmd /opt/mssql-tools18/bin/sqlcmd /opt/mssql-tools/bin/sqlcmd; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

run_privileged() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    echo "Installing sqlcmd requires root privileges or sudo." >&2
    return 1
  fi
}

run_privileged_accept_eula() {
  if [[ "$(id -u)" -eq 0 ]]; then
    env ACCEPT_EULA=Y "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo env ACCEPT_EULA=Y "$@"
  else
    echo "Installing sqlcmd requires root privileges or sudo." >&2
    return 1
  fi
}

configure_sqlcmd_path() {
  local sqlcmd_path="$1"
  local sqlcmd_dir
  local tmp_profile

  sqlcmd_dir="$(dirname "$sqlcmd_path")"

  run_privileged ln -sf "$sqlcmd_path" /usr/local/bin/sqlcmd
  run_privileged install -d -m 0755 /etc/profile.d

  tmp_profile="$(mktemp)"
  cat >"$tmp_profile" <<EOF
case ":\$PATH:" in
  *:${sqlcmd_dir}:*) ;;
  *) export PATH="${sqlcmd_dir}:\$PATH" ;;
esac
EOF
  run_privileged install -m 0644 "$tmp_profile" /etc/profile.d/sqlcmd.sh
  rm -f "$tmp_profile"
}

is_ubuntu() {
  [[ -r /etc/os-release ]] &&
    . /etc/os-release &&
    [[ "${ID:-}" == "ubuntu" ]]
}

install_sqlcmd_ubuntu() {
  local version_id
  local repo_deb

  if ! command -v apt-get >/dev/null 2>&1; then
    echo "Ubuntu install path requires apt-get." >&2
    return 1
  fi

  # shellcheck disable=SC1091
  . /etc/os-release
  version_id="${VERSION_ID:-}"
  if [[ -z "$version_id" ]]; then
    echo "Could not determine Ubuntu VERSION_ID from /etc/os-release." >&2
    return 1
  fi

  echo "Installing sqlcmd for Ubuntu ${version_id} using mssql-tools18..."
  run_privileged apt-get update
  run_privileged apt-get install -y ca-certificates curl

  repo_deb="$(mktemp)"
  curl -fsSL "https://packages.microsoft.com/config/ubuntu/${version_id}/packages-microsoft-prod.deb" -o "$repo_deb"
  run_privileged dpkg -i "$repo_deb"
  rm -f "$repo_deb"

  run_privileged apt-get update
  run_privileged_accept_eula apt-get install -y msodbcsql18 mssql-tools18 unixodbc-dev
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if sqlcmd_path="$(resolve_sqlcmd)"; then
  configure_sqlcmd_path "$sqlcmd_path"
  echo "SQL client already installed: $sqlcmd_path"
  echo "SQL client command linked: /usr/local/bin/sqlcmd"
  exit 0
fi

if ! is_ubuntu; then
  cat >&2 <<EOF
Automatic sqlcmd installation is supported only for Ubuntu.
Install sqlcmd manually for this environment, or set SQLCMD_BIN=/path/to/sqlcmd
if it is already installed.
EOF
  exit 1
fi

install_sqlcmd_ubuntu

if sqlcmd_path="$(resolve_sqlcmd)"; then
  configure_sqlcmd_path "$sqlcmd_path"
  echo "SQL client installed: $sqlcmd_path"
  echo "SQL client command linked: /usr/local/bin/sqlcmd"
else
  echo "sqlcmd installation completed, but sqlcmd was not found." >&2
  echo "Set SQLCMD_BIN=/opt/mssql-tools18/bin/sqlcmd if needed." >&2
  exit 1
fi
