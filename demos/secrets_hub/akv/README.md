# Onboard Azure AKV (Secrets Hub)

The **Idira** / CyberArk side of a Secret Stores *app-set*. It complements the
Azure side that the **Idira Vegas** app provisions (an Azure Key Vault, demo
`db-credentials` / `ssh-credentials` secrets in it, and a standalone
rotation-demo Entra app registration).

This activity wires that AKV into CyberArk Secrets Hub:

0. **Ensure the service account is in the Secrets Hub admin role** (`Secrets
   Manager - Secrets Hub Admin`) via the CyberArk Identity API, so the Secrets
   Hub calls below don't 403. Idempotent; the service account has rights to
   modify roles.
1. **Create the App Safe** (Privilege Cloud) and add the **Secrets Hub member**
   (`SecretsHub`, source-side read access).
2. **Vault the rotation-demo app registration** as an Azure account in the safe.
   Secrets Hub rotates this credential and syncs it to the AKV. It is *not* used
   to access any resource — it only demonstrates rotation.
3. **Onboard the AKV individually as an `AZURE_AKV` secret store** (the sync
   target) using **`FEDERATED_IDENTITY`** — Secrets Hub authenticates to the
   vault via workload-identity federation using a *separate* app registration
   (`SECRETSHUB_AZURE_APP_CLIENT_ID`), **not** Cloud Connect and **not** a client
   secret.
4. **Create the sync policy** (`PAM_SAFE` filter) so the safe's secrets sync to
   the AKV.

## Files

| File         | Purpose                                                        |
|--------------|----------------------------------------------------------------|
| `setup.sh`   | Orchestrator — runs steps 1–4. Prints `__ONBOARD_AKV_OK__` on success. |
| `inputs.env` | Per-app-set inputs (safe, AKV, app-reg IDs, subscription…).    |
| `lib.sh`     | Secrets Hub + Azure-account curl/jq helpers.                   |

Tenant/service-account vars (`LAB_ID`, `TENANT_ID`, `TENANT_SUBDOMAIN`,
`CLIENT_ID`, `CLIENT_SECRET`) come from the environment / `demos/tenant_vars.sh`
via `demos/setup_env.sh`.

## Running by hand

```bash
export CYBR_DEMOS_PATH=/path/to/cybr-demos
# set tenant vars (or edit demos/tenant_vars.sh):
export LAB_ID=... TENANT_ID=... TENANT_SUBDOMAIN=... CLIENT_ID=... CLIENT_SECRET=...

# fill in the app-set specifics:
$EDITOR demos/secrets_hub/akv/inputs.env

bash demos/secrets_hub/akv/setup.sh
```

## How the app runs it (execution model)

The AKV onboarding has no VM, so — unlike the Summon workshop (Azure
run-command on a VM) — the Idira Vegas app runs this activity in a **dedicated
Kubernetes Job** in the RKE2 cluster. The Job clones cybr-demos at the
admin-configured `WORKSHOP_REPO_URL`/`REF`, injects the tenant vars and the
`inputs.env` values (from the app-set the app just provisioned) as env, and runs
`setup.sh`. The app watches the Job to completion and greps its logs for
`__ONBOARD_AKV_OK__` to mark the app-set ready/failed (mirroring the VM
`idira_setup_status` running→ready/failed model). See the lab repo's
`AGENT_PLAN.md` (Secret Stores) and `setup/k8s/` for the Job + RBAC.

## API reference

The Secrets Hub + Privilege Cloud REST calls in `lib.sh` were reverse-engineered
from the CyberArk Terraform provider (`internal/cyberark/*.go`). Base URLs:

- ISPSS auth: `https://<tenant>.id.cyberark.cloud/oauth2/platformtoken`
- Privilege Cloud: `https://<subdomain>.privilegecloud.cyberark.cloud/PasswordVault/API/...`
- Secrets Hub: `https://<subdomain>.secretshub.cyberark.cloud/api/{secret-stores,policies}`

## Known / deferred

- **`get_pcloud_source_store_id`** matches the Privilege Cloud source store by
  `type == PAM_PCLOUD | PAM_SELF_HOSTED`, falling back to the `SECRETS_SOURCE`
  behavior. Confirm the exact discriminator against a live tenant and tighten
  if needed.
- **`vault_azure_app_account`** uses `platformId: MS_TF` (the TF provider's
  Azure platform). Adjust if the target tenant onboards Azure accounts under a
  different platform id.
- Not yet built: teardown (delete policy → store → safe/account), and the
  `SECRETSHUB_AZURE_APP_CLIENT_ID` federation setup (Secrets Hub's federated app
  registration + trust) which is a tenant-level prerequisite.
