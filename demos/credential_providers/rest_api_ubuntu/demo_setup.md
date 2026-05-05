# Demo Setup

This demo configures a CyberArk Central Credential Provider (CCP) REST API example for Ubuntu-based validation. The setup creates a Safe, stores one credential, creates three CyberArk application IDs, and configures different CCP application authentication controls for each AppID.

## Main Entry Point

Run setup from the demo directory through the top-level wrapper:

```bash
./setup.sh
```

The wrapper changes into `demos/credential_providers/rest_api_ubuntu` and runs:

```bash
./setup/setup.sh
```

## Deployment Context

This setup assumes CCP is already installed and reachable through the `PAS_BASE_URL` value from the shared lab configuration. The repo automation configures the CyberArk objects used by the demo; it does not install the CCP server.

The generated client certificate files are written to the demo directory:

```text
app.crt
app.key
app.pfx
cert_serial_number
```

Install or trust the generated certificate chain on the CCP server as required by the CCP IIS client certificate configuration before validating certificate-based requests.

## Required Environment

The shared environment must already be configured:

- `CYBR_DEMOS_PATH` points at this repository.
- `demos/tenant_vars.sh` contains tenant and API client values.
- `demos/setup_env.sh` can source the shared utility functions.
- `PAS_BASE_URL` points at the CCP REST endpoint host.
- `curl`, `jq`, and `openssl` are available.

Demo-specific values live in:

```text
setup/vars.env
```

That file defines the Safe name, the three AppIDs, and the certificate issuer and SAN values used by the certificate attribute example.

## Setup Flow

`setup/setup.sh` runs these stages:

1. Sources `demos/setup_env.sh` and `setup/vars.env`.
2. Generates a self-signed client certificate with a DNS SAN and URI SAN.
3. Records the certificate serial number in `cert_serial_number`.
4. Creates the Safe from `SAFE_NAME`.
5. Adds the `Privilege Cloud Administrators` role as a Safe administrator.
6. Creates one credential in the Safe for `ssh-user-1`.
7. Creates three CCP application IDs:
   - `CCP_APP1_ID` for allowed machine authentication.
   - `CCP_APP2_ID` for certificate serial number authentication.
   - `CCP_APP3_ID` for certificate attribute authentication using Issuer and SAN.
8. Adds each application as a read member of the Safe.

## What Gets Configured

The demo configures these CyberArk controls:

- Safe authorization: each AppID receives read access to the Safe.
- Allowed machine authentication: the first AppID is restricted to the setup host public IP.
- Certificate serial authentication: the second AppID is tied to the generated certificate serial number.
- Certificate attribute authentication: the third AppID uses `certificateattr` with the configured Issuer and Subject Alternative Name values.

The certificate attribute example is the renewal-friendly pattern. If the certificate is renewed with the same issuer and SAN values, the CyberArk AppID authentication rule does not need to change.

## Troubleshooting Setup

If setup fails, check these items first:

- `CYBR_DEMOS_PATH` points to the repo copy where this demo exists.
- `demos/tenant_vars.sh` has valid tenant, client ID, and client secret values.
- `PAS_BASE_URL` points to the CCP base URL.
- The setup host can reach Privilege Cloud APIs and `https://checkip.amazonaws.com/`.
- `setup/vars.env` has a Safe name that meets tenant naming rules.
- The CCP server trusts the generated client certificate or its issuing CA before certificate validation.
