# Talk track: Jenkins + Secrets Manager JWT (~30 minutes)

**Before the room:** `bash go.sh` → `bash finish_setup.sh` → `bash ready_check.sh`  
**In the room:** `bash demo.sh`  
**Presenter browser:** http://127.0.0.1:8081/job/global-credentials-demo/

> If anything looks off (build 401s, "Authentication failed. Cannot get token from Conjur"): `bash finish_setup.sh`. It's idempotent, takes ~15s, and re-binds every link in the JWT chain. Its closing log line `End-to-end verified: secrets retrieved via Conjur JWT auth` is the ground truth `ready_check.sh` is implicitly trusting.

This talk track assumes the demo is configured for **Edge mode** (`CONJUR_AUTH_TARGET=edge`, `JWT_TRUST_MODE=jwks-uri`) — the setup currently deployed. A short cloud-mode variant lives at the end if the audience needs the simpler story first.

## Minute-by-minute

| Time | Phase | Action |
|------|-------|--------|
| 0:00–2:00 | Opening | The problem with static credentials in CI; the JWT-based identity model that fixes it |
| 2:00–6:00 | `demo.sh` 1–3 | Architecture toggles, both containers (Jenkins + Edge), JWT auth path |
| 6:00–9:00 | `demo.sh` 4–5 | Workload identity, the five Conjur policy files |
| 9:00–13:00 | `demo.sh` 6–7 | Live JWT trust chain; pipeline preview |
| 13:00–18:00 | UI verify | Manage Jenkins → System: appliance URL is Edge, not SaaS; Build Now |
| 18:00–24:00 | Rotation | Privilege Cloud password change → SaaS → Edge (MQTT push) → next build |
| 24:00–30:00 | Close + Q&A | Customer takeaway: where this fits, what it replaces |

---

## Opening (2 min)

"Every Jenkins shop has the same problem: pipelines need credentials. SSH keys, cloud creds, registry tokens, database passwords. Today those usually live in Jenkins's static credential store, in `Jenkinsfile`s, or in environment variables on the agent. They leak. They don't rotate. They outlive the people who set them up.

What you're going to see is the same Jenkins pipeline, but every credential is fetched at run time from CyberArk Secrets Manager, scoped per-job by Conjur policy, and authenticated with a JWT minted at build time. No static API key lives anywhere in Jenkins."

If the room asks where Edge fits: "Conjur Cloud Edge is a CyberArk-managed container we run on the same Docker host as Jenkins. It replicates policy and secrets from Conjur Cloud SaaS over an outbound-only TLS connection. Edge handles the JWT validation and serves secrets locally — so the auth + secret-read path never leaves this host. That's why customers with restricted egress, latency-sensitive build farms, or regulated boundaries pick this pattern."

---

## Terminal — `bash demo.sh` (10–12 min)

Press ENTER through steps 1–7. The script narrates the architecture for you. Emphasize:

- **Step 1** — show the **Architecture toggles** block. `CONJUR_AUTH_TARGET=edge` is the headline. The plugin appliance URL is `https://host.docker.internal:443/api` — call it out: "that's a Docker-internal hostname. The auth path never leaves this host."
- **Step 2** — `docker ps` shows `cybr-jenkins` AND `cybr_conjur_edge` side-by-side. Then the script greps `docker logs` for replication lines — point at "Replicated 21 secrets, 10 workloads, 9 authenticators". Say: "this is Edge picking up the policy I wrote in the SaaS console, automatically".
- **Step 3** — `authn-jwt/jenkins` is the Conjur authenticator. The plugin signs a short-lived JWT in memory, sends it here, gets back a Conjur access token. The token's lifetime is minutes — there is no long-lived secret to steal.
- **Step 4** — `jenkins_full_name = GlobalCredentials` means the **pipeline job IS a Conjur identity**. No shared service account; folder-scoped pipelines map to dedicated host policy automatically.
- **Step 5** — five policy files, all small and declarative:
  `authenticator_consumers`, `jwt_service_jenkins`, `workload1`, `jenkins_apps_vault_grant`, `jenkins_jwt_apps_grant`. Pull any one out and the build immediately stops retrieving secrets. Policy is the only way in.
- **Step 6** — the trust chain. Edge HTTP-GETs `http://host.docker.internal:8081/jwtauth/conjur-jwk-set` to learn Jenkins's signing keys, verifies the JWT against them, looks up the workload host, issues a Conjur token. **Show the cert subject:** `CN=host.docker.internal` — Edge generated this itself on first start.
- **Step 7** — `conjurSecretCredential` in the pipeline. Maps a Conjur variable path to an env var name (`SSH_UNAME`, `SSH_PWD`). Plugin resolves at build time, masks in console, drops on step exit.

If `go.sh` already ran (it has, in this lab): step 8 is **verify**, not greenfield install.

---

## Jenkins UI (5 min)

1. **Manage Jenkins → System → CyberArk Secrets Manager Conjur Configuration**  
   Point at **Appliance URL = `https://host.docker.internal:443/api`**.  
   "This is the line. We're talking to a container on this host, not the public CyberArk SaaS endpoint."
2. **JWT Token Claims** — `jenkins_full_name: GlobalCredentials`. Show that this is the entire identity surface.
3. **`global-credentials-demo` → Build Now**.
4. **Console Output** — point at the masked `SSH_UNAME` / `SSH_PWD`. The plugin auto-redacts.
5. **Workspace `demo.txt`** — same secrets written to a file in the workspace, also masked in the log when the file is `cat`'d.

If anyone asks "is the cert validated?" — yes. The cert was imported into Jenkins's Java truststore by `setup/edge/import_edge_cert.sh`. CN/SAN both include `host.docker.internal`, which is what the plugin connects to.

---

## Rotation (5 min)

`demo.sh` step 10:

1. Change `account-ssh-user-1` password in Privilege Cloud (the safe `SAFE_NAME` points at).
2. The script polls Conjur Cloud SaaS until the new value lands.
3. Edge picks up the change near-instantly via its MQTT subscription to SaaS — no polling, no restart.
4. Build Now in Jenkins → console shows the new masked value.

**Say:** "Rotation starts in the Privileged Account Manager. Conjur Sync replicates to Conjur Cloud. Conjur Cloud pushes to every connected Edge over MQTT. The next pipeline run gets the new value automatically. There is no Jenkins restart, no human in the loop, no static credential to update in any pipeline config."

---

## Close (2 min)

What we showed:

- Two containers on one Docker host: Jenkins + Conjur Cloud Edge
- Edge replicating policy + secrets from Conjur Cloud SaaS over outbound-only TLS
- A Jenkins build authenticating with a short-lived JWT against Edge — never the public internet
- A pipeline retrieving credentials at run time, masked in the build log
- Live rotation: change a password in Privilege Cloud, the next build uses the new value

What this replaces in a typical Jenkins environment:

- Static credentials in `Jenkinsfile` or Jenkins's built-in credential store
- Service-account passwords / API keys hand-rotated on a quarterly cadence
- Secrets baked into Docker images or environment variables on agents
- "I'll just put it in a vault and grant Jenkins read access" — same idea, but with audit + per-job scoping + automatic rotation

---

## Cloud-mode variant (if needed)

If the audience wants to see the simpler "Jenkins → SaaS directly" path before the Edge story, flip `setup/vars.env`:

```bash
CONJUR_AUTH_TARGET="cloud"
JWT_TRUST_MODE="public-keys"

bash configure_jenkins.sh
bash finish_setup.sh
```

In cloud mode, the Conjur Secrets plugin's appliance URL points at `https://<tenant>.secretsmgr.cyberark.cloud/api`, and Conjur Cloud SaaS validates JWT signatures using a JWKS that `finish_setup.sh` mirrors into the `public-keys` authenticator variable. Same pipeline, same identity, same policy — just no Edge in the path.

Same `bash demo.sh` works — the script auto-detects the toggle and tells the cloud story instead.

---

## Backup commands

```bash
bash finish_setup.sh   # idempotent rebind — fix 401s, JWKS rotation, "was working yesterday"
bash ready_check.sh
bash setup/edge/setup.sh   # if Edge container died and you need to bring it back up
bash go.sh                 # last resort: full bootstrap (~3 min)
open http://127.0.0.1:8081/job/global-credentials-demo/
```
