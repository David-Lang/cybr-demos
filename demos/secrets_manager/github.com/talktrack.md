# Talk Track: GitHub Actions OIDC + CyberArk Secrets Manager

**Demo runtime:** ~12 minutes | **Script:** `bash demo.sh` from `demos/secrets_manager/github.com`

---

## Opening (~1 min)

> What we're going to walk through is how GitHub Actions can retrieve secrets from CyberArk without ever storing a credential. No static API keys, no service account passwords checked into repo settings. The workflow authenticates using its own OIDC identity — the same token GitHub already issues to every running workflow — and CyberArk decides whether to trust it based on policy.

**On screen:** Intro banner — OIDC flow summary.

*[Press ENTER]*

---

## Step 1: Local Demo Inputs (~1 min)

> Before anything runs, we configure three things: the Safe name in CyberArk Privilege Cloud, the GitHub repository and workflow that will authenticate, and the tenant subdomain. These aren't secrets — they're identity claims. The repository and workflow values have to match exactly what GitHub puts in the OIDC token at runtime. If they don't match, Conjur rejects the request. That's the first layer of control.

**On screen:** `SAFE_NAME`, `GITHUB_REPOSITORY`, `GITHUB_WORKFLOW`, `TENANT_SUBDOMAIN` from `vars.env`.

**Key message:** Identity is declared, not embedded. Any mismatch = immediate rejection.

*[Press ENTER]*

---

## Step 2: Conjur JWT Service Definition (~2 min)

> This is the authenticator definition in Conjur — policy-as-code. A few things to call out:
>
> **jwks-uri** points at GitHub's public signing keys. Conjur uses these to verify the JWT signature — it never trusts the token blindly.
>
> **token-app-property** is set to `workflow`. That means the workflow name becomes the primary identity segment — the thing Conjur maps to a host.
>
> **enforced-claims** requires both `workflow` and `repository` in every token. If a JWT arrives without both of those claims, it's rejected before Conjur even looks up the host. This follows the CyberArk Secrets Manager SaaS integration guide exactly.
>
> **apps group** — any host that needs to authenticate through this service has to be granted into this group. No grant, no access. It's explicit.

**On screen:** `jwt_service_github.yaml` policy file displayed via `sed`.

**Key message:** `enforced-claims: workflow,repository` — dual-claim lockdown per CyberArk SaaS guidance.

*[Press ENTER]*

---

## Step 3: Workload Identity Policy (~2 min)

> Now the workload itself. This host lives under `data/github-apps` and is annotated with two things: the repository and the workflow. At authentication time, Conjur checks these annotations against the actual JWT claims. Both have to match.
>
> The Safe access grant is separate — it connects this host to `vault/poc-github/delegation/consumers`, which is the group the Conjur Synchronizer creates when it syncs with Privilege Cloud. So the authorization chain is: GitHub OIDC proves identity, Conjur maps it to this host, and the host's group membership determines which secrets it can read.
>
> All of this is version-controlled. You can diff it, review it, audit it.

**On screen:** `workload1.tmpl.yaml` template, then rendered preview with actual values.

**Key message:** Authorization is policy-as-code. Separate identity from authorization.

*[Press ENTER]*

---

## Step 4: GitHub Variables to Configure (~1 min)

> These are the repository-level variables the workflow reads at runtime. No secrets here — just pointers: where is Conjur, what account, which authenticator ID, and which Conjur variable paths map to the secret values.
>
> The actual secret never leaves CyberArk until the workflow authenticates and is authorized to retrieve it.

**On screen:** `settings_variables.tmpl.env` template → resolved values.

**Key message:** Variables are pointers, not credentials.

*[Press ENTER]*

---

## Step 5: Choose Workflow Pattern (~1 min)

> We have three workflow patterns available. The recommended one is the **JWT plugin** — it's the CyberArk-maintained GitHub Action (`cyberark/conjur-action`). It handles the OIDC token exchange and secret fetch in a single step. The direct flow does the same thing with raw API calls if you need full control. And the API key flow is there for comparison — it's the legacy pattern we're moving away from.

**On screen:** `ls` showing three workflow YAML files.

**Key message:** JWT plugin = recommended path. API key = what we're migrating from.

*[Press ENTER]*

---

## Step 6: Live GitHub Dispatch (~2 min)

> Now we go live. We're setting the repository variables using `gh` — this is the same thing as going into Settings > Variables in the GitHub UI, just scripted.
>
> Then we dispatch the workflow. Watch what happens...

*[Workflow runs and completes]*

> Fifteen seconds. The workflow requested an OIDC token from GitHub, presented it to Conjur, Conjur validated the signature against GitHub's JWKS, checked the `workflow` and `repository` claims against the host annotations, confirmed the host is in the `apps` group and the `delegation/consumers` group, and returned the secrets. The workflow used them and they're masked in the logs — GitHub auto-redacts any value registered as a secret.
>
> No credential was stored anywhere in GitHub. If we revoke the host or remove it from the consumers group, the next run fails immediately.

**On screen:** `gh variable set` commands, `gh workflow run`, `gh run watch` with live status.

**Key message:** End-to-end in ~15 seconds. Revocation is instant — remove grant, next run fails.

---

## Step 7: CyberArk Tenant Verification (~2 min)

> This step proves the tenant state is real. We authenticate to CyberArk Privilege Cloud, confirm the account exists in the Safe, then authenticate to Conjur separately and retrieve the same secret paths the workflow just used. This isn't a mock — it's the same API endpoints, same authorization chain.
>
> The password is masked by default because this is a live credential. We can reveal it to prove it's real, but the point is: the plumbing works end to end.

**On screen:** Live API calls — identity token, Conjur session token, account lookup, secret retrieval.

**Key message:** Real tenant, real secrets, same variable paths as the workflow.

---

## Step 8: Key Value Recap (~1 min)

> So what did we just show?
>
> **No credential sprawl.** The GitHub workflow never had a static secret. The OIDC token is short-lived and scoped to the run.
>
> **Policy-based access.** Adding a new workflow means adding a new host with the right annotations and granting it into the right groups. Removing access means removing the grant. It's auditable and reviewable.
>
> **CyberArk stays central.** Identity management, secret storage, rotation, audit — all in one platform. GitHub is a consumer, not a credential store.
>
> **Developer experience is preserved.** The workflow YAML is four lines. Developers don't need to know how Conjur works — they reference variable paths and the action handles the rest.

---

## Authentication Chain (Reference)

| # | Stage | What Happens |
|---|-------|--------------|
| 1 | GitHub OIDC | Issues short-lived JWT with `workflow` + `repository` claims |
| 2 | Conjur JWT authn | Validates signature via JWKS, checks enforced claims |
| 3 | Host lookup | Maps `token-app-property` (workflow) under `identity-path` (data/github-apps) |
| 4 | Annotation check | Confirms `repository` and `workflow` annotations match JWT |
| 5 | Group auth | Host must be in `conjur/authn-jwt/github/apps` group |
| 6 | Secret access | Host must be in `vault/<safe>/delegation/consumers` group |
| 7 | Secret returned | Conjur returns variable value; GitHub masks it in logs |

---

## Objection Handling

| Question | Answer |
|----------|--------|
| What if someone forks the repo? | The `repository` claim changes to the fork path. Conjur rejects it — the annotation won't match. |
| Can a different workflow in the same repo access the secrets? | No. The `workflow` claim is enforced. Only the specific workflow named in the host annotation can authenticate. |
| What about branch protection? | You can add `ref` or `environment` as additional enforced claims to restrict to specific branches or GitHub environments. |
| How does rotation work? | CyberArk rotates the credential in Privilege Cloud. The Conjur Synchronizer picks up the new value. The workflow gets the current secret on next run — no config change needed. |
| Why not just use GitHub encrypted secrets? | GitHub secrets are static, don't rotate, and have no centralized audit. CyberArk gives you rotation, RBAC, and a single pane for all platforms. |

---

## Security Reminder

This demo uses live tenant credentials. After lab use:
- Rotate the service account used in `tenant_vars.sh`
- Clear terminal scrollback to remove leaked tokens or API keys
- The host API key printed during `setup.sh` is unused at runtime (JWT auth), but should still be treated as sensitive
