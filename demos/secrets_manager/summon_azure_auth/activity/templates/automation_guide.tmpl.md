# Activity Guide (Automated): Hardcoded Secret Remediation (__STUDENT__)

This is the **answer key**. Clicking **Solve** runs `activity/solve.sh` on your
lab VM, which performs the vault + grant steps for you — so you can inspect the
finished state and run the secured query without doing the manual onboarding.

Solve is idempotent (safe to click more than once) and it **does not rotate** the
credential. Rotation stays a live, manual capstone (see below).

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

## What Solve did

`activity/solve.sh` performed the student's vault + grant steps in Idira:

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
./query_db_hardcoded.sh
cat query_db_hardcoded.sh
```

The hardcoded script has the password (`PGPASSWORD`) right in the file — anyone
who can read the script can read the database. The secured script has no secret.

If `run_secured_query.sh` reports `CONJ00076E ... is empty or not found`, the
account may still be syncing; wait a moment and re-run.

## Rotation (NOT performed by automation)

> **Callout:** Solve does **not** rotate the credential. Rotation is the
> live/manual capstone you drive yourself.

Rotate the vaulted credential with **SRS** (Secrets Rotation Service). SRS
reaches this VM's PostgreSQL through the Idira System connector (using the stored
`address` `__ROTATION_ADDRESS__`) and changes the password. After it completes:

```bash
./query_db_hardcoded.sh    # FAILS — still has the old password
./run_secured_query.sh     # WORKS — fetches the current password from Idira
```

Verify in **Secrets Manager SaaS → Audit**: filter for your safe
(`__SAFE_NAME__`) or your VM's workload identity and confirm the workload
`authn-azure` authentication events, the secret retrievals for `__ACCOUNT_NAME__`,
and the SRS **rotation** event followed by a successful retrieval of the *new*
value.

## Reset

Clicking **Reset** re-runs `activity/reset.sh` on the VM, which idempotently
returns you to a clean student-start: it deletes the account `__ACCOUNT_NAME__`
and the safe `__SAFE_NAME__` (no-ops if already gone) and leaves `authn-azure`
and the Conjur workload policy in place. Run Solve again afterward to rebuild the
finished state.
