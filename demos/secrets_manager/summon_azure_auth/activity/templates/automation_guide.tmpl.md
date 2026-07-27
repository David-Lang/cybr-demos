# Activity Guide (Automated): Hardcoded Secret Remediation (__STUDENT__)

This is the **automated ("answer key")** path: review the problem, see the
insecure starting state, click **Solve** to have the setup done for you, then
confirm the credential is retrieved securely and gets rotated. Solve is
idempotent (safe to click more than once). For the hands-on version, use the
**Summon — Manual** guide.

## 1. Review the problem

A database password is **hardcoded** in a script on your VM — the anti-pattern.
Hardcoded secrets leak (anyone who can read the file can read the database),
rarely get rotated, and aren't attributable to a specific workload.

**Goal:** take the secret out of the code and manage it centrally in Idira, so
the app fetches the *current* credential at runtime using the VM's own **workload
identity** (no secret on disk) — and the credential can be **rotated** without
changing or breaking the app.

In this automated path, **Solve** performs steps 4–6 for you; the other steps you
run yourself to see the before/after.

## 2. Connect: SSH to your compute

You reach your VM over **SIA SSH** — brokered access, no inbound port or static
key. From your workstation terminal, use the **SSH link on your compute card** in
the app (the `Copy` button next to it). Then open your workspace:

```bash
cd /opt/labs/__STUDENT__/hardcoded-secret-remediation
ls
```

> **Already installed on this compute** (by the deployment enablement): **Summon**
> and its **`summon-conjur`** provider, plus the local PostgreSQL and the
> `authn-azure` configuration. New to Summon? See **Learning → What Is Summon?**
> in the Guide panel (switch the kind selector to *Idira Lab*).

## 3. Expose: see the hardcoded anti-pattern

Run the insecure baseline and look at the script:

```bash
./run_hardcoded_query.sh
cat query_db_hardcoded.sh
```

It returns rows — but the password (`PGPASSWORD`) is right there in the file.
Anyone who can read the script can read the database. The secured query does
**not** work yet, because nothing has been vaulted:

```bash
./run_secured_query.sh     # expected to FAIL until you Solve
```

## 4. Create the workload

> **This step is automated by Solve.**

> **Click Solve now.** On your compute card's **Summon — Automated** row, click
> **Solve** and wait for the row to show **Solved**. Solve performs steps 4–6
> automatically; those steps below explain what it did.

Solve creates a **workload** in Secrets Manager that maps to this VM's Azure
managed identity (its Azure ID). **authn-azure** is Idira Secrets Manager's Azure
authenticator: it validates the VM's Azure managed-identity token and maps it to a
registered workload, so the workload proves what it is with no stored secret. The
workload is the record `authn-azure` maps the VM's managed-identity token to when
it authenticates — without it, `authn-azure` can validate the token but has no
workload to map it to.

## 5. Vault the credential

> **This step is automated by Solve.**

Solve creates a safe named exactly `__SAFE_NAME__` (it matches your compute's
name, so yours differs from everyone else's), adds **Conjur Sync** so Secrets
Manager syncs with the safe, and onboards the PostgreSQL account `__ACCOUNT_NAME__`:

```text
safe:      __SAFE_NAME__
account:   __ACCOUNT_NAME__
platform:  PostgreSQL
address:   __ROTATION_ADDRESS__      # connector-reachable VM address (for SRS rotation)
username:  __DB_USERNAME__
password:  __DB_PASSWORD__
```

`address` is the connector-reachable host SRS (the Idira System connector) uses to
rotate this VM's Postgres. Syncing a safe automatically creates a **Consumers**
delegation group for it, used in the next step.

## 6. Grant the workload access to the safe

> **This step is automated by Solve.**

Solve adds this VM's **workload** to the safe's **Consumers** group, authorizing
it to **read the vaulted database credential**. It's the workload — not the Azure
identity directly — that becomes a safe consumer; the workload maps to the VM's
Azure ID from step 4.

After Solve, the vaulted secret identifiers that `secrets.yml` references resolve:

```text
data/vault/__SAFE_NAME__/__ACCOUNT_NAME__/username
data/vault/__SAFE_NAME__/__ACCOUNT_NAME__/password
```

## 7. Secure: retrieve at runtime with Summon

Run the secured query again — Summon authenticates with the VM's managed identity
and **retrieves the PostgreSQL database credential** for `__DB_USERNAME__` from
Idira at runtime — the vaulted secret
`data/vault/__SAFE_NAME__/__ACCOUNT_NAME__/password` (and its `/username`) — with
no secret in code:

```bash
./run_secured_query.sh
```

It returns the **same rows** as the hardcoded query in step 3, but with no secret
in the script. That's the point: same result, credential handled securely. If it
reports `CONJ00076E ... is empty or not found`, the account may still be syncing —
wait a moment and re-run.

## 8. Rotate

Solve also **queues a rotation** with **SRS** (Secrets Rotation Service) as its
last step. SRS, via the Idira System connector, changes the password on this VM's
Postgres — expect roughly a **~1 minute queue time** before it runs. Once it
completes, validate both paths:

**Hardcoded (now fails)** — the baked-in password is stale after rotation:

```bash
./run_hardcoded_query.sh
```

**Secured (still works)** — Summon fetches the current credential from Idira:

```bash
./run_secured_query.sh
```

You can queue another rotation on demand with **SRS**, or from **Privilege Cloud**
(the account → Change).

## 9. Validate

Open **Idira → Audit and Reports** (the top-level space in the Idira menu) and set
the **Service Name** filter to **Secrets Manager** to scope the log to workload
activity. Filter further by your safe `__SAFE_NAME__`, the account
`__ACCOUNT_NAME__`, or your VM's workload, and confirm:

- **Authentication** — the workload authenticating via **authn-azure** (its Azure
  managed-identity token, validated by Secrets Manager).
- **Secret retrieval** — a fetch of `__ACCOUNT_NAME__`. Solve runs one secured
  query automatically before it rotates, so a retrieval is already logged; each
  `./run_secured_query.sh` you run adds another.
- **Rotation** — the credential change queued by SRS, followed by a successful
  retrieval of the *new* value.

Each entry shows who (the VM's workload), what (authenticate / retrieve / rotate),
which secret, and when — the audit trail a hardcoded password can never give you.

---

**Reset** (not a step): clicking **Reset** re-runs `activity/reset.sh` on the VM,
which idempotently returns you to a clean student-start — it deletes the account
`__ACCOUNT_NAME__`, the safe `__SAFE_NAME__`, and the per-VM workload record
(no-ops if already gone). Run **Solve** again afterward to rebuild the state.
