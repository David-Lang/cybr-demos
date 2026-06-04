# Demo Setup

Deploy Jenkins with Docker and configure CyberArk Secrets Manager (Conjur Cloud) JWT authentication for the [Conjur Secrets Jenkins plugin](https://plugins.jenkins.io/conjur-credentials/).

## Main Entry Point

```bash
export CYBR_DEMOS_PATH=/path/to/cybr-demos
cd demos/secrets_manager/jenkins

cp setup/vars.env.example setup/vars.env
vi setup/vars.env

cp "$CYBR_DEMOS_PATH/demos/tenant_vars.local.sh.example" \
   "$CYBR_DEMOS_PATH/demos/tenant_vars.local.sh"
vi "$CYBR_DEMOS_PATH/demos/tenant_vars.local.sh"

bash check_prereqs.sh
bash go.sh
bash ready_check.sh
```

`go.sh` runs, in order:

1. `setup/jenkins/setup.sh` — Docker Jenkins + public JWKS URL (EC2 or cloudflared)
2. `render_pipeline.sh` — `get_secrets.groovy` for your `SAFE_NAME`
3. `import_sm_cert.sh` — Secrets Manager TLS into Java truststore
4. `setup/vault/setup.sh` — Privilege Cloud safe, account, synchronizer wait
5. `setup/conjur/setup.sh` — JWT authenticator policy, workload host, grants, Conjur variables
6. *(Edge mode only)* `setup/edge/setup.sh` — bring up `cybr-conjur-edge`, wait for replication, import its TLS cert into Jenkins
7. `configure_jenkins.sh` — Conjur plugin JWT config + pipeline job `global-credentials-demo` (restarts Jenkins)
8. `finish_setup.sh` — finalizes JWT auth wiring (see below)

`setup.sh` is an alias for `go.sh` (same full bootstrap).

Teardown:

```bash
bash remove.sh
```

## The `finish_setup.sh` Step

The last step of `go.sh`, and the script to re-run any time auth breaks.
Idempotent. Takes ~15s. What it does:

1. Re-applies workload host + grant policies (`workload1`, `jenkins_apps_vault_grant`, `jenkins_jwt_apps_grant`)
2. Adds a `public-keys` variable to the authenticator policy if missing
3. Sets `issuer` / `audience` / `token-app-property` / `identity-path` to known-good values
4. Forces the Conjur Jenkins plugin to mint a JWT (so it generates its in-memory signing key)
5. Mirrors that key's JWKS into Conjur's `public-keys` variable
6. PATCH-deletes the `jwks-uri` variable so Conjur ignores any stale tunnel URL and uses `public-keys` instead
7. Creates Jenkins-side `ConjurSecretCredentialsImpl` entries (one per Conjur variable the pipeline references) via Jenkins script console — **no Jenkins restart**
8. Pushes the rendered pipeline script into the `global-credentials-demo` job via Jenkins script console — **no Jenkins restart**
9. Verifies `/api/authn-jwt/<id>/conjur/status` returns 200
10. Triggers one sanity build and reports masked secret lengths

Required env (defaults shown):

```bash
JENKINS_ADMIN_USER=admin           # set if you changed the wizard admin
JENKINS_ADMIN_PASSWORD=admin
SKIP_BUILD=0                       # set to 1 to skip the verification build
RUN_BASE_SETUP=0                   # set to 1 to also run vault + conjur base setup first
```

When to run it:

- After `go.sh` (it runs there automatically)
- After **any Jenkins restart** (the plugin rotates its in-memory JWKS key on restart)
- After the SaaS UI authenticator page replaces a Conjur variable
- When the demo "was working yesterday" but the build is now 401-ing

## Deployment Context

The demo supports two orthogonal axes:

- `DEPLOY_PROFILE` — where Jenkins lives (`aws` lab VM or `local` laptop)
- `CONJUR_AUTH_TARGET` — where the Conjur API lives (`cloud` SaaS or local `edge` container)
- `JWT_TRUST_MODE` — how Conjur validates Jenkins JWT signatures (`public-keys` mirrored or `jwks-uri` fetched)

Default for the laptop story is `local` + `cloud` + `public-keys`. Default for the Edge story is `local` + `edge` + `jwks-uri`.

| Profile | `DEPLOY_PROFILE` | Presenter UI | JWKS reachability needs |
|---------|------------------|--------------|-------------------------|
| AWS lab VM, cloud target | `aws` | `http://<ec2-dns>:8081` | None (public-keys) — or inbound 8081 from CyberArk SaaS if you opt into `jwks-uri` |
| Local laptop, cloud target | `local` | `http://127.0.0.1:8081` | None (public-keys, default) |
| Local laptop, Edge target | `local` | `http://127.0.0.1:8081` | None — Edge resolves Jenkins via `host.docker.internal` |

In **public-keys mode** (`JWT_TRUST_MODE=public-keys`, the default for the cloud target):

- Conjur Cloud does **not** need inbound reach back to Jenkins
- The local laptop profile does not require `cloudflared`
- Trade-off: every Jenkins restart rotates the plugin's in-memory key, so you must re-run `finish_setup.sh` to re-sync. Build failures with `Authentication failed. Cannot get token from Conjur` are almost always a stale `public-keys` variable.

In **Edge mode** (`CONJUR_AUTH_TARGET=edge` + `JWT_TRUST_MODE=jwks-uri`):

- A `cybr-conjur-edge` container runs on the same Docker host as Jenkins
- Plugin's appliance URL flips from the SaaS endpoint to `https://host.docker.internal/api`
- Conjur policy stores `jwks-uri = http://host.docker.internal:8081/jwtauth/conjur-jwk-set`
- Edge replicates policy + secrets from Conjur Cloud, validates Jenkins's JWT locally, and serves the secret
- Trade-off: Edge bring-up requires manual SaaS UI work (creating the Edge instance, downloading an 8-min install token). See `setup/edge/README.md`.

See `setup/aws/README.md` for the EC2 checklist, `setup/edge/README.md` for Edge bring-up.

## Required Environment

| Source | Variables |
|--------|-----------|
| `demos/tenant_vars.local.sh` | `TENANT_ID`, `TENANT_SUBDOMAIN`, `CLIENT_ID`, `CLIENT_SECRET` |
| `demos/tenant_vars.sh` | `LAB_ID`, `TENANT_SUBDOMAIN` defaults |
| `setup/vars.env` | `SAFE_NAME`, `DEPLOY_PROFILE`, `JWT_CLAIM_IDENTITY`, `JENKINS_PORT`, … |

| Variable | Purpose |
|----------|---------|
| `SAFE_NAME` | Privilege Cloud safe → `data/vault/<SAFE_NAME>/...` (the safe must already exist and be on a Conjur Sync policy). |
| `DEPLOY_PROFILE` | `aws` or `local` |
| `JWT_CLAIM_IDENTITY` | `jenkins_full_name` claim (default `GlobalCredentials`) |
| `CONJUR_JWT_AUTHN_ID` | Authenticator id (default `jenkins1`). Drives `conjur/authn-jwt/<id>` policy branch and the plugin's `authWebServiceId`. |
| `CONJUR_AUDIENCE` | JWT `aud` value (default `cyberark-conjur`). **Must match the value Conjur is configured to require** — see Troubleshooting. |
| `CONJUR_AUTH_TARGET` | `cloud` (default) or `edge`. Controls where the Jenkins plugin sends authn-jwt requests. |
| `JWT_TRUST_MODE` | `public-keys` (default) or `jwks-uri`. Controls how Conjur validates Jenkins's JWT signatures. |
| `JWKS_URL_OVERRIDE` | Optional. URL Conjur uses to fetch JWKS in `jwks-uri` mode. Defaults to `JENKINS_JWKS_URI` for cloud target, or `http://host.docker.internal:8081/jwtauth/conjur-jwk-set` for edge target. |
| `EDGE_*` | Edge container settings (`EDGE_CONTAINER`, `EDGE_HOST`, `EDGE_PORT`, `EDGE_HEALTH_PORT`, `EDGE_DATA_DIR`, `EDGE_INSTALL_SCRIPT`). See `setup/edge/README.md`. |

Generated (do not edit):

- `setup/.jenkins.env` — `JENKINS_LOCAL_URL`, `JENKINS_PUBLIC_URL`, `JENKINS_ISSUER`, `JENKINS_JWKS_URI`

## Troubleshooting Setup

| Symptom | Check |
|---------|--------|
| Missing `tenant_vars.local.sh` | `cp demos/tenant_vars.local.sh.example demos/tenant_vars.local.sh` |
| Identity token failed | `TENANT_ID` from `https://<id>.id.cyberark.cloud`; VPN |
| `CLIENT_ID` access_denied | Suffix must match tenant (`@zach-lab`, not `@zachlab`) |
| `cloudflared` not installed (local profile) | Not needed in default `public-keys` mode — `finish_setup.sh` mirrors JWKS into Conjur and deletes `jwks-uri`. The tunnel is only needed if you switch `JWT_TRUST_MODE=jwks-uri` AND `CONJUR_AUTH_TARGET=cloud`. For Edge mode, no tunnel ever. |
| Synchronizer timeout | Unique `SAFE_NAME`; Conjur Sync on safe |
| Plugin/job missing | `bash configure_jenkins.sh && bash finish_setup.sh` |
| Build fails with `Authentication failed. Cannot get token from Conjur` | Almost always: stale JWKS in Conjur (Jenkins restarted → key rotated) **or** the JWT `iss` / `aud` claims don't match the Conjur variables. Fix: `bash finish_setup.sh`. |
| Conjur `/api/authn-jwt/<id>/conjur/status` returns 500 `CONJ00037E Missing value for resource: ...audience` | The SaaS UI marks audience "optional" but Conjur requires it. `finish_setup.sh` always sets it to `cyberark-conjur` (override via `CONJUR_AUDIENCE`). |
| Conjur silently rejects JWT (HTTP 401 empty body) despite kid/issuer matching | Check `iss` exact-string match including trailing slash. The Jenkins plugin emits `iss=<root URL with no trailing slash>`. `finish_setup.sh` sets the Conjur issuer variable from `JENKINS_LOCAL_URL` (no slash). |
| `withCredentials` reports empty `$SSH_UNAME` / `$SSH_PWD` | The `credentialsId` must be the **full Conjur variable path with slashes**, e.g. `data/vault/<SAFE>/account-ssh-user-1/username` — not a dashed alias. The pipeline template does this correctly; if you edited it, re-run `render_pipeline.sh`. |

After `bash ready_check.sh` passes, continue with `demo_validation.md` and `bash demo.sh`.
