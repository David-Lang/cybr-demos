# Demo: Jenkins + CyberArk Secrets Manager (JWT)

Jenkins pipelines retrieve secrets from CyberArk Secrets Manager using the [Conjur Secrets plugin](https://plugins.jenkins.io/conjur-credentials/) and JWT authentication (`authn-jwt`), with credentials synced from a Privilege Cloud safe.

End-to-end flow:

```text
Privilege Cloud Safe -> Conjur Sync -> Conjur Cloud (SaaS) -> Jenkins Conjur plugin
                                                              -> JWT auth (authn-jwt)
                                                              -> conjurSecretCredential
                                                              -> masked env vars in build
```

Two architectures supported, switchable via two env vars in `setup/vars.env`:

| Path | `CONJUR_AUTH_TARGET` | `JWT_TRUST_MODE` | Story |
|------|----------------------|------------------|-------|
| **Default (cloud)** | `cloud` | `public-keys` | Jenkins authenticates directly against Conjur Cloud SaaS. Conjur verifies JWT signatures locally using a JWKS we mirror into the `public-keys` variable. Works on a laptop with no inbound network. |
| **Edge** | `edge` | `jwks-uri` | Jenkins authenticates against a local Conjur Cloud Edge container running on the same Docker host. Edge replicates policy + secrets from Conjur Cloud. Edge fetches Jenkins's JWKS over the Docker network (`host.docker.internal`) — no public hostname required. |

## Quick start

```bash
export CYBR_DEMOS_PATH=/path/to/cybr-demos
cd demos/secrets_manager/jenkins

cp setup/vars.env.example setup/vars.env
vi setup/vars.env                    # SAFE_NAME, DEPLOY_PROFILE (aws|local)

cp "$CYBR_DEMOS_PATH/demos/tenant_vars.local.sh.example" \
   "$CYBR_DEMOS_PATH/demos/tenant_vars.local.sh"
vi "$CYBR_DEMOS_PATH/demos/tenant_vars.local.sh"   # TENANT_ID, CLIENT_ID, CLIENT_SECRET

bash check_prereqs.sh
bash go.sh                           # full bootstrap (recommended)
bash ready_check.sh                  # confirm ready
bash demo.sh                         # interactive presenter walkthrough (~30 min)
```

**Presenter URL:** http://127.0.0.1:8081/job/global-credentials-demo/  
**JWT signature trust:** default mode is **public-keys** — `finish_setup.sh` mirrors the live Jenkins JWKS into the Conjur `public-keys` variable, so Conjur Cloud does **not** need inbound network reach back to Jenkins. `JENKINS_JWKS_URI` (in `setup/.jenkins.env`) is only required if you opt out and switch the authenticator to `jwks-uri` mode.

## Edge mode quickstart

To switch the demo to authenticate against a local Conjur Cloud Edge:

```bash
# 1. Download Edge from CyberArk Marketplace and load it
sudo docker load -i ~/Downloads/conjur-edge_*.tar.gz

# 2. Generate an install script in Secrets Manager UI -> Edges -> Install new Edge
#    Set: COMMON_NAME=host.docker.internal, SAN=127.0.0.1,localhost
#    Save the generated 'docker run' as setup/edge/install.sh (gitignored)

# 3. Flip the toggles in setup/vars.env
#    CONJUR_AUTH_TARGET="edge"
#    JWT_TRUST_MODE="jwks-uri"

# 4. Bring it up (works whether or not the cloud demo was already running)
bash setup/edge/setup.sh
bash configure_jenkins.sh
bash finish_setup.sh
```

Full Edge bring-up walkthrough: [setup/edge/README.md](setup/edge/README.md).

## Scripts

| Script | Purpose |
|--------|---------|
| `go.sh` | **Main entry** — Jenkins, TLS, vault, Conjur policy, plugin, pipeline job |
| `setup.sh` | Alias for `go.sh` (after prereqs) |
| `demo.sh` | Interactive walkthrough (~25-30 min with UI). Mode-aware: tells the Edge story when `CONJUR_AUTH_TARGET=edge`. |
| `ready_check.sh` | Pass/fail readiness before presenting |
| `finish_setup.sh` | **Idempotent rebind** — re-applies Conjur policies, syncs JWKS, recreates Jenkins credentials, pushes pipeline, runs sanity build. Use after Jenkins restart, JWKS rotation, or any "it was working yesterday" moment. |
| `configure_jenkins.sh` | Plugin JWT config + `global-credentials-demo` job (restarts Jenkins) |
| `import_sm_cert.sh` | Import SM TLS cert into Jenkins Java truststore |
| `render_pipeline.sh` | Render `get_secrets.groovy` from template |
| `remove.sh` | Teardown Conjur policy, safe, Jenkins container |

## Documentation

| File | Purpose |
|------|---------|
| [demo_setup.md](demo_setup.md) | Deployment, profiles, troubleshooting |
| [demo_validation.md](demo_validation.md) | Post-setup validation |
| [talktrack.md](talktrack.md) | 30-minute presenter script |
| [setup/edge/README.md](setup/edge/README.md) | Conjur Cloud Edge bring-up |
| [setup/aws/README.md](setup/aws/README.md) | EC2 lab checklist |

## Clean up

```bash
bash remove.sh
```

## Reference

- [CyberArk Jenkins integration](https://docs.cyberark.com/secrets-manager-saas/latest/en/content/integrations/jenkins.htm)
- [Conjur Cloud Edge install docs](https://docs.cyberark.com/secrets-manager-saas/latest/en/content/conjurcloud/edge/ccl-edge-install.htm)
