# Summon Azure Auth Demo Plan

This file tracks the buildout for `demos/secrets_manager/summon_azure_auth`.

## Objective

Create a repo-standard Secrets Manager demo based on `summon_aws_auth` that runs on an Ubuntu VM in Azure. The demo uses Summon and `summon-conjur` to retrieve safe-backed secrets by authenticating with Azure managed identity through `authn-azure`, not a Conjur API key.

## Assumptions

- The demo runs on an Ubuntu VM hosted in Azure.
- The VM has a user-assigned managed identity attached.
- The CyberArk tenant may not already have an `authn-azure` service configured.
- Setup creates/configures `authn-azure/<service-id>` when needed.
- The authenticator uses the `apps` group convention.
- Cleanup removes demo workload and safe resources, but leaves the Azure authenticator service in place.

## Progress

- [x] Create `summon_azure_auth` directory from the AWS-auth demo pattern.
- [x] Add this progress plan.
- [x] Add Azure authenticator service policy using `provider-uri` and `apps`.
- [x] Add Azure workload policy with managed identity annotations.
- [x] Adapt setup orchestration and vault setup paths.
- [x] Adapt runtime demo script for Azure metadata and Summon cloud auth.
- [x] Discover Azure tenant, subscription, resource group, and identity metadata from IMDS where possible.
- [x] Adapt cleanup to preserve `authn-azure/<service-id>`.
- [x] Update README, setup, and validation documentation.
- [x] Run syntax checks locally.
- [ ] Test end-to-end in a fresh Azure Ubuntu lab.
  - In progress (2026-07-07, idira-vegas `faa3`, driven from the app's "Summon"
    action). `setup.sh` (authn-azure + workload + platform validation) passes;
    blocked past `db_setup.sh` until the docker fix below; full green not yet
    confirmed.
- [x] Record lab-specific fixes discovered during test.
  - **IMDS 400 / no managed identity:** the provisioning app now attaches a
    per-VM user-assigned identity, and the `Microsoft.ManagedIdentity` resource
    provider must be registered on the subscription (one-time, control plane).
  - **`usermod: user 'ubuntu' does not exist`:** `compute_init/ubuntu/
    install_docker.sh` hardcoded the `ubuntu` user; Azure VMs use `azureuser`.
    Made the docker-group user portable (`DOCKER_GROUP_USER` → `$SUDO_USER` →
    first of azureuser/ubuntu, skip if none) and set `DEBIAN_FRONTEND=
    noninteractive` for the no-TTY run-command context.

## New Lab Test Checklist

- Fill `setup/vars.env` with `AZURE_CLIENT_ID` if the VM has multiple managed identities.
- Fill `AZURE_USER_ASSIGNED_IDENTITY_NAME` only if setup cannot discover it from the managed identity token.
- Confirm the VM can obtain an Azure managed identity token from IMDS.
- Run `bash setup.sh`.
- Run `source ./conjur_authn_azure.env`.
- Run `bash demo.sh`.
- Confirm the hardcoded query returns rows, and (post-vault) the secured query returns the same rows.

## Known Test Risks

- A VM with multiple user-assigned identities may require `AZURE_CLIENT_ID` in `setup/vars.env`.
- If `summon-conjur` cannot select the intended managed identity from metadata, set `SUMMON_AZURE_FETCH_TOKEN="true"` to pass a short-lived IMDS token explicitly through `CONJUR_AUTHN_JWT_TOKEN`.
- CyberArk safe synchronization can lag; setup waits for the safe delegation group, but a slow tenant may still need a retry.

---

# Workshop Delivery on the Provisioned VM

Runbook + design for the per-student workshop: the `idira-vegas-lab` app
provisions one Azure VM per student, the admin/privileged lab setup runs
automatically as part of that provisioning, and the student follows an
app-rendered, click-through Guide (with completion tracking) to run the
hardcoded-vs-secured activity on their own VM.

## Decisions (locked)

- **One VM per student, deployed from the app.** Isolation is per VM; no shared
  `/opt/labs/studentN` fan-out.
- **Deployment does infra enablement only; the student does the vaulting.** At
  provisioning the control plane stands up the local Postgres (with an initial
  cred defined in the setup script), installs Summon + tooling, configures
  `authn-azure` + the workload identity, and makes the VM Postgres reachable by
  the Idira System connector. It does **not** onboard/vault the DB credential.
- **Vaulting the DB credential is a student action.** Signed in with their idira
  user, the student manually onboards (vaults) the Postgres credential during
  the activity — that is the lesson, not a pre-baked state. (Requires splitting
  account onboarding out of the deploy-time `setup.sh`; see Step C+D.)
- **Rotation uses SRS (Secrets Rotation Service), not CPM.** After vaulting, the
  cred is rotated by SRS via the **Idira System connector**. For SRS to reach
  it, the VM Postgres must be **port-accessible to the connector** (line-of-sight
  to 5432 + `pg_hba` allowing the connector + a rotation-capable account) — set
  up at deployment, exercised in the activity.
- **Activity is fully VM-resident; its database is local to the VM.** The SQL
  the student queries runs on the VM (local Postgres), not a remote/Azure SQL,
  and no DB is shared across VMs. It is **not** localhost-only — it binds so the
  Idira System connector can reach it for rotation.
- **Guide is rendered server-side by the app from a local Markdown copy.**
  goldmark renders Markdown → HTML and bluemonday sanitizes it; the client just
  injects the HTML. Content comes from the initial `cybr-demos` clone only — no
  per-view GitHub or CDN traffic, and **no browser Markdown library**.
- **Steps are discovered from the Markdown by convention** (no hand-kept
  manifest). Each top-level `##` heading is a step: its slug is the step id, its
  heading text is the title, document order is step order. The app parses this
  to build the step list.
- **Two views from one guide file:** the **sidebar** Guide pane feeds the
  activity one step at a time (stepper: Next/Prev, mark-complete, resume,
  percent complete); the **main panel** shows the full rendered guide.
- **Optional per-step verify hook.** A step may declare a readiness check by
  convention; the app runs it (e.g. managed identity present, `authn-azure`
  ready) and marks the step verified. Steps without a hook are manual
  click-to-complete.
- **Progress persists in the app's Postgres** (on the EC2 app host), keyed by
  user + guide + step — distinct from the activity's VM-local DB.

## Topology and Roles

- **Per-student VM.** Ubuntu VM in Azure with a user-assigned managed identity +
  SIA SSH, provisioned by the app. `CYBR_DEMOS_PATH=/opt/cybr-demos`.
- **Control plane (privileged, at deploy).** Clones `cybr-demos`, injects tenant
  creds, runs `setup.sh`, and generates the student's workspace — all during
  provisioning. Creds are never left on the VM in student-readable form.
- **Student (credential-less).** Uses the app UI, follows the Guide, SSHes to
  their VM, and runs the hardcoded vs secured query. The secured path
  authenticates via the VM's managed identity through `authn-azure`.

## Step A: Clone (initial, once per plane)

Two one-time clones; nothing re-hits GitHub afterward:

1. **Per-student VM** (at provisioning): clone `cybr-demos` to `/opt/cybr-demos`
   via cloud-init/custom-data (or a control-plane post-provision SSH step), then
   run Steps C+D. Pin a tag/branch for reproducible workshops.
2. **App host (once):** the guide Markdown must be readable by the app process,
   which runs in the RKE2 pod on the EC2 — **not** on the student VM. Deliver it
   via the initial `cybr-demos` clone/sync on the EC2 and **hostPath-mount** the
   guide dir into the app pod read-only (preferred: update by re-pull, no image
   rebuild), or bake the guide into the app image at build. Either way the app
   serves it locally with no runtime GitHub calls.

## Step B: Credentials

Two planes, kept separate:

1. **Privileged setup creds — control plane only, at deploy.** `TENANT_ID`,
   `TENANT_SUBDOMAIN`, `CLIENT_ID`, `CLIENT_SECRET` (a CyberArk Identity OAuth2
   **confidential client** that can manage Privilege Cloud safes/accounts +
   Conjur policies), sourced from `demos/setup_env.sh`. Injected by the
   provisioning path (transiently via SSH env or a root-only file removed after
   setup); **never** written to a student-readable path and **never** committed.
2. **Student runtime — no secrets in code.** After vaulting, the secured query
   uses the VM's Azure managed identity via `authn-azure`; `conjur_authn_azure.env`
   and `secrets.yml` hold only IDs/URLs.
3. **DB credential — starts in the initial script, then gets vaulted.** Setup
   stands up Postgres with an initial cred that the hardcoded query script
   exposes on purpose. During the activity the student vaults that cred (via
   their idira login); thereafter the secured path fetches it — and its rotated
   values — via Summon, with nothing in code.

Because it's one VM per student, isolation is by VM ownership: harden the VM's
SSH (SIA scoped to the owning student) rather than relying on `/opt/labs` perms.

## Step C+D: Deployment enablement (admin, no vaulting)

Run by the control plane during provisioning, not by the student. Deployment
enables everything the student will *use*, but deliberately stops short of
vaulting the DB credential (that's the student's job in Step E).

```bash
export CYBR_DEMOS_PATH=/opt/cybr-demos
cd /opt/cybr-demos/demos/secrets_manager/summon_azure_auth
# setup/vars.env: SAFE_NAME (<=28 chars), AUTHN_AZURE_SERVICE_ID; Azure IDs auto-
# discovered from IMDS. Tenant creds provided transiently by the control plane.
bash setup.sh                     # authn-azure + workload identity + safe (access) + conjur_authn_azure.env
bash activity/db_setup.sh         # local Postgres container w/ INITIAL cred; port-accessible to the connector
STUDENT_COUNT=1 bash activity/setup_activity.sh   # -> /opt/labs/student1/hardcoded-secret-remediation
```

**Required rework of `setup.sh` for this arc:** today it also onboards the DB
account (`setup/vault/setup.sh` → `create_account_ssh_user_1`). Split that out so
deployment does **not** vault the credential — deploy only sets up `authn-azure`,
the workload identity, and a safe the student can write to; the student onboards
the account in Step E. Also register/ensure the Idira System connector has port
access to this VM's Postgres so SRS can rotate later.

Result: the VM boots with a running local Postgres (initial cred in the
hardcoded script), Summon + tooling installed, `authn-azure` ready, the safe
present, and the connector reachable — but the credential is **not yet vaulted**.

## Step E: Student activity (guided) — expose → vault → secure → rotate

The student's hands-on arc, walked through by the app Guide (they sign in with
their idira user):

1. **Expose.** Run the hardcoded query — the DB password is inline in the script
   (the anti-pattern):
   ```bash
   cd /opt/labs/student1/hardcoded-secret-remediation
   ./query_db_hardcoded.sh
   ```
2. **Vault.** Signed in to idira, manually onboard the Postgres credential into
   the safe (the learning step — done in the CyberArk UI, not scripted).
3. **Secure.** Retrieve the cred at runtime via Summon + managed identity — no
   secret in code:
   ```bash
   ./run_secured_query.sh
   ```
4. **Rotate.** Rotate the vaulted cred with **SRS**; SRS reaches the VM Postgres
   through the **Idira System connector**. The payoff: the secured script keeps
   working (it fetches the new value) while the still-hardcoded script now fails
   against the rotated password.

Teaching moment: a hardcoded secret is exposed and brittle; a vaulted,
rotation-managed secret is retrieved at runtime and survives rotation.

## Credential Lifecycle & Rotation (SRS + Idira System connector)

- **Rotation engine: SRS (Secrets Rotation Service), not CPM.** SRS rotates the
  vaulted Postgres credential and updates the value the secured path reads.
- **Reachability: the Idira System connector needs port access to the VM
  Postgres.** SRS connects through the connector to `postgres:5432` on the VM to
  change the password, so at deploy `db_setup.sh` / provisioning must ensure:
  - Postgres binds on an address the connector can reach (VM private IP, not
    localhost-only); `listen_addresses` set accordingly.
  - `pg_hba.conf` allows the connector's source with password auth.
  - the VM firewall / NSG / SIA-network opens 5432 to the connector only.
  - a rotation-capable account exists (the account changes its own password, or
    a reconcile account with `ALTER ROLE` rights).
- **Set up at deploy, exercised in the activity.** The port-accessible Postgres
  + rotation account are configured at provisioning; the student triggers the
  actual rotation in Step E.

Open questions: is the Idira System connector the same one used for SIA SSH, or
a separate connector for DB rotation? the exact SRS target onboarding; how the
connector's source range is expressed in `pg_hba`; and the rotation-account
model (self-rotate vs reconcile).

## Guide Integration (app "Guide" side pane)

**Status: IMPLEMENTED (Slices 1–3, 2026-07-07, `gardenia`, deployed to `faa3`).**
The design below is the original target; the shipped version differs in a few
deliberate ways (see `idira-vegas-lab/PLAN.md` → GUI layout rework → Guide
feature for the app-side detail):
- **One endpoint, VM-sourced:** `GET /api/guide/{vm}/{activity}` reads the VM's
  *rendered* `student_guide.md` via Azure run-command and caches it per
  `vm|activity` (not a `GUIDE_DIR` hostPath mount; no separate step/full/verify
  endpoints). Returns full HTML + parsed steps in one payload.
- **Completion = localStorage**, per `vm|activity|step` — not Postgres.
- **Checkbox stepper, no auto-progress, no verify** (verify hooks deferred; the
  `<!-- verify: -->` convention is not yet consumed).
- **Full guide** is its own Views toggle (`fullguide` → `#view-guide`), separate
  from the stepper panel, which has Activity + Compute selectors.
- Steps derived from `##` headings; commands = fenced blocks (Copy buttons).
- Depends on the multi-region layout rework (now DONE).

Original design (target reference):


Target: the side-rail **Guide** tab (`data-panel="guide"` in
`idira-vegas-lab/app/static/index.html`), today a placeholder. **Design:**

**Content & step discovery (by convention).**
- Author the guide as Markdown in this repo under `activity/guide/` (one file
  per guide, e.g. `summon-azure.md`).
- The app derives steps by parsing structure — each top-level `##` heading is a
  step; step id = GitHub-style slug of the heading, title = heading text, order
  = document order. No separate manifest to maintain.
- Optional per-step **verify hook** declared inline by convention, e.g. an HTML
  comment directly under the heading: `<!-- verify: managed-identity -->` or
  `<!-- verify: authn-azure -->`. The app maps the token to a readiness check.
- Content is trusted-but-templated (the app injects the student's SIA SSH
  string / VM name before rendering); bluemonday sanitizes the final HTML.

**Delivery.** The initial `cybr-demos` clone on the EC2 provides the file;
hostPath-mount `activity/guide/` into the app pod read-only (update by re-pull,
no rebuild) or bake at build. No runtime network calls.

**App endpoints (`idira-vegas-lab` repo; Go + goldmark + bluemonday):**
- `GET /api/guide` — parse the active lab's guide file; return ordered steps
  (id, title, order, and a `verify` token when present) plus overall metadata.
  Reads from `GUIDE_DIR` (default the mounted path).
- `GET /api/guide/step/{id}` — server-rendered, sanitized HTML for one step
  (sidebar stepper).
- `GET /api/guide/full` — sanitized HTML for the whole guide (main panel).
- `GET`/`POST /api/guide/progress` — per-student step completion, persisted in
  Postgres (user id + guide id + step id); in-memory fallback if the DB is off.
- `POST /api/guide/verify/{token}` — run the step's readiness check (reuse the
  app's existing inspect/status probes: managed identity detected, `authn-azure`
  ready, secret retrievable) and return pass/fail; on pass, auto-complete the
  step.

**UI wiring (`index.html` Guide panel):**
- Sidebar Guide pane = **stepper**: renders one step's HTML at a time, Next/Prev,
  "Mark complete" (or auto-complete on verify pass), overall percent, and
  resumes at the last incomplete step on reload.
- A step carrying a `verify` token shows a **Verify** button that calls
  `/api/guide/verify/{token}`; a green check on success.
- A "View full guide" action swaps the **main panel** to the full rendered
  guide (`/api/guide/full`) — consistent with how Status/Routes take over the
  main area today.
- Rendering just sets `innerHTML` with the server-sanitized HTML (the pattern
  the app already uses), so **no client Markdown library** is vendored.
- **Depends on the app's multi-region layout rework** (multi-select toolbar +
  toolbar/left/main/right areas) so the sidebar step, the full guide, and chat
  can be shown together — tracked in `idira-vegas-lab/PLAN.md` (Immediate Next
  Work → GUI layout rework).

## Open Questions

- Guide selection: how the app maps a provisioned lab to its guide file — a
  config var (`GUIDE_FILE`), a lab-type tag, or the demo's `info.yaml`.
- Verify-token vocabulary: finalize the check tokens (e.g. `managed-identity`,
  `authn-azure`, `secret-read`) and map each to an existing app probe.
- Heading-convention edge cases: non-unique `##` headings (slug collisions) and
  whether `###` are sub-steps or in-step content.
- Completion trigger: is a step complete on Next, on explicit mark, or only on
  verify-pass when a hook is present?
- Agent assistance: the reworked AgentCore agent (idira secrets assistant, MCP
  deep-wiki over `cybr-demos` + Summon (`cyberark/summon` + `summon-conjur`) via
  the Idira AI Broker — see `idira-vegas-lab/PLAN.md`) can help students complete
  steps and could back the per-step verify hooks; define how the Guide and agent
  hand off.

## Workshop Checklist / TODO

- [ ] Provisioning: clone `cybr-demos` to the VM (cloud-init/custom-data or
      control-plane SSH); pin a ref.
- [ ] Rework `setup.sh`: split DB-account onboarding out so deploy sets up only
      authn-azure + workload identity + safe (student vaults in Step E).
- [ ] `activity/db_setup.sh`: stand up a local Postgres container with an
      INITIAL cred; bind + `pg_hba` + rotation account so it's port-accessible
      to the Idira System connector.
- [ ] Provisioning: register/ensure the Idira System connector can reach the VM
      Postgres:5432; open the port to the connector only.
- [ ] Rework activity scripts/templates MSSQL→Postgres (`psql`): hardcoded,
      secured, `secrets.yml`, `SQL_QUERY` default, and the SQL client install.
- [ ] Provisioning: run `setup.sh` + `db_setup.sh` +
      `STUDENT_COUNT=1 activity/setup_activity.sh` with control-plane creds;
      keep `CLIENT_SECRET` transient and never student-readable.
- [ ] Confirm `demos/setup_env.sh` takes creds from the (control-plane) env.
- [ ] Author guide Markdown under `activity/guide/` (`##`-per-step + optional
      `<!-- verify: <token> -->`) covering expose → vault → secure → rotate.
- [x] App: deliver guide to the pod — **done (differently):** read the VM's
      rendered `student_guide.md` via Azure run-command, cached per
      `vm|activity` (no hostPath mount / bake).
- [x] App (Go): add goldmark + bluemonday; guide endpoint — **done:** single
      `GET /api/guide/{vm}/{activity}` (full HTML + parsed steps). Progress is
      localStorage (not Postgres); no `/step`, `/full`, or `/verify` endpoints.
- [x] App: Guide-panel stepper (sidebar) + full-guide main-panel view;
      completion tracking + percent — **done** (checkbox completion in
      localStorage; Copy buttons per code block; Connect/SSH first step).
      **Deferred:** resume-at-last-incomplete, Verify buttons for hooked steps.
- [ ] Define SRS target onboarding + rotation-account model; connector source in
      `pg_hba`; whether the SIA connector doubles as the DB connector.
- [ ] Map verify tokens to existing readiness probes; finalize the token set.
- [ ] Decide guide-selection mechanism (config var / lab-type / info.yaml).
- [ ] End-to-end dry run: provision VM → enablement → student expose → vault →
      secure → rotate (SRS via connector) → hardcoded breaks, secured survives →
      completion tracked to 100%.
- [ ] End-to-end dry run: provision VM → auto setup → student follows Guide →
      hardcoded vs secured run → completion tracked to 100%.
