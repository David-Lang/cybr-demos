# Student Guide: Hardcoded Secret Remediation (__STUDENT__)

You do this activity on your lab VM. Start by connecting to it — don't assume
you're already on the box.

## Connect: SSH to your compute

You reach your VM over **SIA SSH** — brokered access, no inbound port or static
key. From your workstation terminal, use the **SSH link on your compute card** in
the app (the `Copy` button next to it).

Once connected, open your workspace and look around:

```bash
cd /opt/labs/__STUDENT__/hardcoded-secret-remediation
ls
```

You should see the query scripts, `secrets.yml`, and this guide.

## Goal

Take a database password out of a script and manage it in Idira, without
changing the query. You will:

1. **Expose** — run a script with a hardcoded password (the anti-pattern).
2. **Vault** — onboard that credential into Idira and authorize this VM's workload identity to read it.
3. **Secure** — retrieve it at runtime with Summon + the VM's Azure managed identity (no secret in code).
4. **Rotate** — rotate it with SRS and watch the secured script keep working while the hardcoded one breaks.
5. **Validate** — confirm the whole flow in the Secrets Manager audit.

The database is a local PostgreSQL already running on this VM. The query is the
same in both scripts; only credential handling changes.

## 1. Expose: run the hardcoded script

From your workspace directory:

```bash
cd /opt/labs/__STUDENT__/hardcoded-secret-remediation
./query_db_hardcoded.sh
```

It returns rows. Now see the problem:

```bash
cat query_db_hardcoded.sh
```

The password is right there in the file (`PGPASSWORD`). Anyone who can read the
script can read the database.

Expected rows:

```text
 id |   series_title    |   primary_setting    | lead_character  |    story_hook
----+-------------------+----------------------+-----------------+------------------
  1 | Star Trek         | USS Enterprise       | Jean Luc        | First contact
  2 | Voyager           | USS Voyager          | Kathryn Janeway | Return voyage
  3 | Deep Space        | Station Nine         | Benjamin Sisko  | Wormhole defense
  4 | Galactica         | Battlestar Galactica | William Adama   | Fleet survival
  5 | The Expanse       | Rocinante            | James Holden    | Political crisis
(5 rows)
```

## 2. Vault: onboard the credential in Idira

Sign in to idira and use Privilege Cloud. Use these **exact** names so
the pre-filled `secrets.yml` resolves without editing:

1. Create a safe named exactly:

   ```text
   __SAFE_NAME__
   ```

2. Add `Conjur Sync` as a safe member (so Secrets Manager syncs the safe), with
   `View users` and `Access without confirmation`.

3. Onboard the PostgreSQL account with these values:

   ```text
   safe:      __SAFE_NAME__
   account:   __ACCOUNT_NAME__
   platform:  PostgreSQL
   address:   __ROTATION_ADDRESS__      # connector-reachable VM address (for SRS rotation)
   username:  __DB_USERNAME__
   password:  __DB_PASSWORD__
   ```

   Note: `address` is what SRS/the Idira System connector uses to reach this VM's
   Postgres for rotation — not `localhost`. The local scripts always connect to
   `__DB_HOST__`.

4. Grant this VM's workload identity read access to the credential. In
   **Secrets Manager SaaS → Roles**, find your VM's **Azure user-assigned
   managed identity (UAMI)** — the workload identity shown on your compute card —
   and add it to the safe's **Consumers** group for `__SAFE_NAME__`.

   This is what authorizes the workload (which authenticates via `authn-azure`)
   to read the account. Without this grant Summon can authenticate but cannot
   read the secret.

## 3. Secure: retrieve at runtime with Summon

Look at the secured script and the variable map:

```bash
cat query_db_secured.sh
cat secrets.yml
```

`query_db_secured.sh` has no password; `secrets.yml` maps `PGUSER`/`PGPASSWORD`
to your vaulted account. Run it through Summon:

```bash
./run_secured_query.sh
```

Same rows — with no secret in the script. Summon authenticated with the VM's
managed identity and Idira returned the password at runtime.

If you see `CONJ00076E ... is empty or not found`, the safe/account names do not
match the values above, the account has not synced yet, or the workload has not
been granted access to the safe.

## 4. Rotate: prove the value

Rotate the vaulted credential with **SRS** (Secrets Rotation Service). SRS reaches
this VM's PostgreSQL through the Idira System connector and changes the password.

After the rotation completes:

```bash
./query_db_hardcoded.sh    # FAILS — still has the old password
./run_secured_query.sh     # WORKS — fetches the current password from Idira
```

## 5. Validate: confirm the flow in the Audit

Everything you just did is auditable. In **Secrets Manager SaaS → Audit**, filter
for your safe (`__SAFE_NAME__`) or your VM's workload identity and confirm you can
see:

- the workload **authentication** events (`authn-azure`) from this VM's UAMI,
- the **secret retrieval** (get) events for `__ACCOUNT_NAME__` — one per
  `run_secured_query.sh` run,
- the **rotation** event from SRS, followed by a successful retrieval that
  returns the *new* value.

Each entry shows who (the VM's workload identity), what (authenticate / fetch),
which secret, and when — the audit trail that a hardcoded password can never give
you.

## Runtime flow

```text
run_secured_query.sh
  -> source conjur_authn_azure.env
  -> summon reads secrets.yml
  -> summon-conjur authenticates with the Azure managed identity (authn-azure)
  -> Idira returns the authorized, current PGUSER/PGPASSWORD
  -> query_db_secured.sh runs psql with them
```

## Success criteria

- You can point to the hardcoded password in `query_db_hardcoded.sh`.
- You vaulted the credential into safe `__SAFE_NAME__` as account `__ACCOUNT_NAME__` on the PostgreSQL platform.
- You added your VM's UAMI to the safe's Consumers group in Secrets Manager SaaS.
- `./run_secured_query.sh` returns rows with no secret in the script.
- After SRS rotation, the secured script still works and the hardcoded one fails.
- The Secrets Manager audit shows your VM's workload identity authenticating and reading `__ACCOUNT_NAME__`, including after rotation.
