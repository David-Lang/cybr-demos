# Bruno API Demo Setup

This demo deploys the `poc-sm-saas-bruno` "ALM API Key Auth" collection against a live
Secrets Manager tenant and prepares it to run from both the Bruno CLI and GUI.

## Main Entry Point

```bash
cd "$CYBR_DEMOS_PATH/demos/secrets_manager/bruno_api"
./setup.sh
```

`setup.sh`:

1. Ensures the Bruno CLI (`bru`) is installed (`compute_init/ubuntu/install_bru.sh`).
2. Clones the Bruno collection (`BRUNO_REPO`, default `David-Lang/poc-sm-saas-bruno`) into
   the git-ignored `.collection/`.
3. Generates a git-ignored Bruno environment (`environments/cybr.secret.bru`) from the tenant
   service creds.
4. Runs the **Setup App** section with `bru run` (creates ISP roles, safe + accounts,
   workload, RBAC, and rotates the workload API key).
5. Captures the workload API key (using the service/root token) and stores it in the
   Bruno env so the Demo App can authenticate as the workload.

To reset before another attempt (removes the workload policy, safe + accounts, and the
ISP `<app>-admins` role):

```bash
./remove.sh
```

## Deployment Context

This is a control-plane + API demo. The "workload" is the Bruno request context
authenticating as the application's machine identity. The Setup App section is driven by
the service account; the Demo App section runs as the workload.

## Required Environment

Prerequisites:

- Linux/macOS with `bash`, `curl`, `jq`, `git`, and the GitHub CLI (`gh`, authenticated
  to clone `BRUNO_REPO`).
- Node.js + the Bruno CLI (`@usebruno/cli`) — installed by `setup.sh` if missing.
- `CYBR_DEMOS_PATH` exported; tenant vars via `demos/setup_env.sh` (`tenant_vars.sh` or
  environment): `LAB_ID`, `TENANT_ID`, `TENANT_SUBDOMAIN`, `CLIENT_ID`, `CLIENT_SECRET`.
- The service account must have System Administrator + Conjur Cloud Admin rights.

Inputs (env-overridable):

- `UseCaseAlmAppName` — application name (default `poc-alm-app`).
- `BRUNO_REPO` — collection repo to clone (default `David-Lang/poc-sm-saas-bruno`).

The Bruno environment is generated, not committed. Real service creds live only in the
git-ignored `.collection/collection/environments/cybr.secret.bru`.

## What Gets Deployed

CyberArk-side (via the Setup App section):

- ISP roles for the app admins and service user
- Privilege Cloud safe `data/vault/<app>` with sample accounts
- Secrets Manager workload `data/<app>/<app>-workload` (+ rotated API key)
- RBAC grants for the workload to the safe

Local artifacts (git-ignored):

- `.collection/` (cloned collection)
- `.collection/collection/environments/cybr.secret.bru` (generated env + captured key)

## Troubleshooting Setup

- If `gh repo clone` fails, confirm `gh auth status` and access to `BRUNO_REPO`.
- If `bru` install fails, install Node.js 20+ and `npm install -g @usebruno/cli` manually.
- If the workload key capture fails, confirm the service account has Conjur Cloud Admin
  rights and that the Setup App section created the workload.
- Re-running `setup.sh` may show "already exists" errors from the create steps; these are
  non-fatal (the key is re-captured each run).
