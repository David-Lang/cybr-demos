#!/usr/bin/env bash
# Lab Identifier
# Used for generating unique safe names across lab environments
export LAB_ID="${LAB_ID:-SET_LAB_ID}"

# ISP Tenant Info
# If TENANT_ID is set, use it. Otherwise, use a placeholder.
export TENANT_ID="${TENANT_ID:-SET_TENANT_ID}"
export TENANT_SUBDOMAIN="${TENANT_SUBDOMAIN:-SET_TENANT_SUBDOMAIN}"

# ISP Service Account User
export CLIENT_ID="${CLIENT_ID:-SET_CLIENT_ID}"
export CLIENT_SECRET="${CLIENT_SECRET:-SET_CLIENT_SECRET}"

# ISP Service Account Installer User
export INSTALLER_USR="${INSTALLER_USR:-SET_INSTALLER_USR}"
export INSTALLER_PWD="${INSTALLER_PWD:-SET_INSTALLER_PWD}"
