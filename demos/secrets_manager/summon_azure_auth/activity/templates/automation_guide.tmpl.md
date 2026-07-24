# Activity Guide (Automated): Hardcoded Secret Remediation (__STUDENT__)

This is the **answer key**. Clicking **Solve** runs `activity/solve.sh` on your
lab VM, which performs the vault + grant steps for you — so you can inspect the
finished state and run the secured query without doing the manual onboarding.

Solve is idempotent (safe to click more than once). It also **queues a rotation**
of the vaulted credential at the end (see below).

## Connect: SSH to your compute

Same as the manual activity. You reach your VM over **SIA SSH** — brokered
access, no inbound port or static key. From your workstation terminal, use the
**SSH link on your compute card** in the app (the `Copy` button next to it).

Once connected, open your workspace:

```bash
cd /opt/labs/__STUDENT__/hardcoded-secret-remediation
ls
```

You should see the query scripts, `secrets.yml`, and this guide.

> **Already installed on this compute** (by the deployment enablement): **Summon**
> and its **`summon-conjur`** provider, plus the local PostgreSQL and the
> `authn-azure` configuration. This is a mention, not a step — Solve and the
> secured query rely on them being present.

## What Solve did

`activity/solve.sh` performed the student's vault + grant steps in Idira:

0. **Workload** — registered this VM's Azure managed identity as an
   `authn-azure` workload record (before vaulting), so `authn-azure` has a
   workload to map the VM's managed-identity token to.
1. **Safe** — created a safe named exactly `__SAFE_NAME__` (matches your
   compute's name, so yours differs from everyone else's).
2. **Conjur Sync member** — added **Conjur Sync** to the safe so Secrets Manager
   syncs it into Conjur.
3. **Account** — onboarded the PostgreSQL account `__ACCOUNT_NAME__` exposing
   `username` + `password`:

   ```text
   safe:      __SAFE_NAME__
   account:   __ACCOUNT_NAME__
   platform:  PostgreSQL
   address:   __ROTATION_ADDRESS__      # connector-reachable VM address (for SRS rotation)
   username:  __DB_USERNAME__
   password:  __DB_PASSWORD__
   ```

   `address` is what SRS/the Idira System connector uses to reach this VM's
   Postgres for rotation — not `localhost`. The local scripts always connect to
   `__DB_HOST__`.
4. **Consumers grant** — added this VM's Azure user-assigned managed identity
   (UAMI) to the safe's **Consumers** group, authorizing the workload (which
   authenticates via `authn-azure`) to read the account.

The vaulted paths that `secrets.yml` references now resolve:
`data/vault/__SAFE_NAME__/__ACCOUNT_NAME__/{username,password}`.

## Verify

From your workspace directory, run the secured query — it retrieves the password
at runtime with Summon + the VM's managed identity (no secret in code):

```bash
./run_secured_query.sh
```

It returns rows. Now look at the anti-pattern it replaces:

```bash
./run_hardcoded_query.sh
cat query_db_hardcoded.sh
```

The hardcoded script has the password (`PGPASSWORD`) right in the file — anyone
who can read the script can read the database. The secured script has no secret.

If `run_secured_query.sh` reports `CONJ00076E ... is empty or not found`, the
account may still be syncing; wait a moment and re-run.

## Rotation (queued by automation)

> **Callout:** Solve onboards the account with automatic secrets management
> enabled and **queues a CPM rotation** as its last step. The CPM/Idira System
> connector performs the change asynchronously (it reaches this VM's Postgres
> using the stored `address` `__ROTATION_ADDRESS__`), so it may take a moment.

Once the rotation completes:

```bash
./run_hardcoded_query.sh    # FAILS — still has the old password
./run_secured_query.sh     # WORKS — fetches the current password from Idira
```

You can also queue another rotation yourself from **Secrets Manager SaaS** (the
account → Change), or rotate on demand with **SRS**.

Verify in **Secrets Manager SaaS → Audit**: filter for your safe
(`__SAFE_NAME__`) or your VM's workload identity and confirm the workload
`authn-azure` authentication events, the secret retrievals for `__ACCOUNT_NAME__`,
and the **rotation** event followed by a successful retrieval of the *new*
value.

## Reset

Clicking **Reset** re-runs `activity/reset.sh` on the VM, which idempotently
returns you to a clean student-start: it deletes the account `__ACCOUNT_NAME__`,
the safe `__SAFE_NAME__`, and the per-VM `authn-azure` workload record (no-ops if
already gone), and leaves the authn-azure service enablement in place. Run Solve
again afterward to rebuild the finished state.
