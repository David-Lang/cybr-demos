# Activity Guide (Automated): Hardcoded Secret Remediation (__STUDENT__)

This is the **automated ("answer key")** path. You first see the insecure
starting state on your VM, then click **Solve** to have the vault + grant steps
done for you, then confirm the credential is now retrieved securely. Solve is
idempotent (safe to click more than once) and also **queues a rotation** at the
end.

## Connect: SSH to your compute

You reach your VM over **SIA SSH** — brokered access, no inbound port or static
key. From your workstation terminal, use the **SSH link on your compute card** in
the app (the `Copy` button next to it).

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
>
> New to Summon? See the **What Is Summon?** guide under **Learning** (switch the
> Guide panel's kind selector to *Idira Lab*).

## 1. Expose: see the starting state (do this BEFORE Solve)

Confirm the insecure baseline first, so you can see what Solve changes. Run the
hardcoded query and look at the script:

```bash
./run_hardcoded_query.sh
cat query_db_hardcoded.sh
```

It returns rows — but the password (`PGPASSWORD`) is right there in the file.
Anyone who can read the script can read the database.

Now try the secured query. It **fails** at this point, because nothing has been
vaulted yet and the workload has no access:

```bash
./run_secured_query.sh     # expected to FAIL until you click Solve
```

## 2. Solve: click Solve on your compute card

In the app, on your compute card's **Summon — Automated** row, click **Solve**.
This runs `activity/solve.sh` on the VM and performs the manual onboarding for
you (idempotent). Wait for the row to show **Solved**.

Solve performs the student's vault + grant steps in Idira:

0. **Workload** — creates a **workload** in Secrets Manager that maps to this
   VM's Azure managed identity (its Azure ID). This is the record `authn-azure`
   maps the VM's managed-identity token to.
1. **Safe** — creates a safe named exactly `__SAFE_NAME__` (matches your
   compute's name, so yours differs from everyone else's).
2. **Conjur Sync member** — adds **Conjur Sync** to the safe so Secrets Manager
   syncs with the safe. (Syncing a safe automatically creates a **Consumers**
   delegation group for it, which makes it easy to grant workloads access to the
   safe.)
3. **Account** — onboards the PostgreSQL account `__ACCOUNT_NAME__` exposing
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
4. **Grant workload access to the safe** — adds this VM's **workload** to the
   safe's **Consumers** group, authorizing it to read the account. The workload
   maps to the VM's Azure ID (step 0); it's the workload — not the Azure identity
   directly — that becomes a safe consumer.

After Solve, the vaulted paths that `secrets.yml` references resolve:
`data/vault/__SAFE_NAME__/__ACCOUNT_NAME__/{username,password}`.

## 3. Verify: the secured query now works

Run the secured query again — this time it retrieves the password at runtime with
Summon + the VM's managed identity (no secret in code):

```bash
./run_secured_query.sh
```

It returns the **same rows** as the hardcoded query in step 1 — but with no
secret in the script. That is the whole point: same result, credential handled
securely.

If `run_secured_query.sh` reports `CONJ00076E ... is empty or not found`, the
account may still be syncing; wait a moment and re-run.

## 4. Rotation (queued by Solve)

> **Callout:** Solve onboards the account with automatic secrets management
> enabled and **queues an SRS rotation** as its last step. SRS (the Secrets
> Rotation Service), via the Idira System connector, performs the change
> asynchronously (it reaches this VM's Postgres using the stored `address`
> `__ROTATION_ADDRESS__`), so it may take a moment.

Once the rotation completes:

```bash
./run_hardcoded_query.sh    # FAILS — still has the old password
./run_secured_query.sh     # WORKS — fetches the current password from Idira
```

You can also queue another rotation yourself from **Privilege Cloud** (the
account → Change), or rotate on demand with **SRS**.

Verify in **Secrets Manager SaaS → Audit**: filter for your safe
(`__SAFE_NAME__`) or your VM's workload identity and confirm the workload
`authn-azure` authentication events, the secret retrievals for `__ACCOUNT_NAME__`,
and the **rotation** event followed by a successful retrieval of the *new*
value.

## 5. Reset

Clicking **Reset** re-runs `activity/reset.sh` on the VM, which idempotently
returns you to a clean student-start: it deletes the account `__ACCOUNT_NAME__`,
the safe `__SAFE_NAME__`, and the per-VM `authn-azure` workload record (no-ops if
already gone), and leaves the authn-azure service enablement in place. Run Solve
again afterward to rebuild the finished state.
