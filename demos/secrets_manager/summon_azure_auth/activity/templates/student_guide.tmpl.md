# Activity Guide: Hardcoded Secret Remediation (__STUDENT__)

You do this activity on your lab VM, performing each step yourself. For the
hands-off version, use the **Summon — Automated** guide, where **Solve** does the
setup steps for you.

## 1. Review the problem

A database password is **hardcoded** in a script on your VM — the anti-pattern.
Hardcoded secrets leak (anyone who can read the file can read the database),
rarely get rotated, and aren't attributable to a specific workload.

**Goal:** take the secret out of the code and manage it centrally in Idira, so
the app fetches the *current* credential at runtime using the VM's own **workload
identity** (no secret on disk) — and the credential can be **rotated** without
changing or breaking the app.

In this manual path, **you perform each step yourself.**

## 2. Connect: SSH to your compute

You reach your VM over **SIA SSH** — brokered access, no inbound port or static
key. From your workstation terminal, use the **SSH link on your compute card** in
the app (the `Copy` button next to it). Then open your workspace:

```bash
cd /opt/labs/__STUDENT__/hardcoded-secret-remediation
ls
```

You should see the query scripts, `secrets.yml`, and this guide.

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
Anyone who can read the script can read the database.

Expected rows:

```text
 id |          series_title          |   primary_setting    | lead_character  |    story_hook
----+--------------------------------+----------------------+-----------------+------------------
  1 | Star Trek: The Next Generation | USS Enterprise       | Jean Luc        | First contact
  2 | Star Trek: Voyager             | USS Voyager          | Kathryn Janeway | Return voyage
  3 | Star Trek: Deep Space Nine     | Station Nine         | Benjamin Sisko  | Wormhole defense
  4 | Battlestar Galactica           | Battlestar Galactica | William Adama   | Fleet survival
  5 | The Expanse                    | Rocinante            | James Holden    | Political crisis
(5 rows)
```

## 4. Create the workload

Sign in to **Idira** ([open the portal](__IDIRA_PORTAL_URL__)) and open **Secrets
Manager**. Create a **workload** that authenticates via **authn-azure** (service
`azure-1`) and set its annotations to match this VM's Azure identity — the
`subscription-id`, `resource-group`, and `user-assigned-identity` (the UAMI name
shown on your compute card).

This is the record that maps the VM's managed-identity token to a workload;
without it `authn-azure` can validate the token but has no workload to map it to.

## 5. Vault the credential

In **Privilege Cloud**, use these **exact** names so the pre-filled `secrets.yml`
resolves without editing:

1. Create a safe named exactly `__SAFE_NAME__` (it matches your compute's name, so
   yours differs from everyone else's).
2. Add **Conjur Sync** (found under **System Components**) as a safe member so
   Secrets Manager syncs with the safe. Grant it:
   - **Access:** Use accounts, Retrieve accounts, List accounts
   - **Workflow:** Access Safe without confirmation

   Syncing the safe automatically creates a **Consumers** delegation group for it,
   which you use in step 6.
3. Onboard the PostgreSQL account with these values:

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

## 6. Grant the workload access to the safe

Add the **workload** you created in step 4 to the safe's **Consumers** group for
`__SAFE_NAME__`.

It's the **workload** (not the UAMI directly) that becomes a safe consumer: the
UAMI is what the workload maps to via `authn-azure`, and the workload is what
Conjur authorizes. Without this grant Summon can authenticate but cannot read the
secret.

## 7. Secure: retrieve at runtime with Summon

Look at the secured script and the variable map, then run it through Summon:

```bash
cat query_db_secured.sh
cat secrets.yml
./run_secured_query.sh
```

Same rows as step 3 — with no secret in the script. Summon authenticated with the
VM's managed identity and Idira returned the password at runtime. If you see
`CONJ00076E ... is empty or not found`, the account hasn't synced yet or the
workload isn't granted — recheck steps 5–6 and retry.

## 8. Rotate

Rotate the vaulted credential **on demand with SRS** (Secrets Rotation Service).
SRS reaches this VM's Postgres through the Idira System connector (using the
stored `address` `__ROTATION_ADDRESS__`) and changes the password — expect roughly
a **~1 minute queue time** before it runs. Once it completes:

```bash
./run_hardcoded_query.sh    # FAILS — still has the old password
./run_secured_query.sh     # WORKS — fetches the current password from Idira
```

## 9. Validate

In **Secrets Manager → Audit**, filter for your safe (`__SAFE_NAME__`) or your
VM's workload and confirm: the workload `authn-azure` **authentication** events,
the **secret retrievals** for `__ACCOUNT_NAME__` (one per `run_secured_query.sh`),
and the **rotation** event followed by a successful retrieval of the *new* value.

Each entry shows who (the VM's workload), what (authenticate / fetch / rotate),
which secret, and when — the audit trail a hardcoded password can never give you.

---

**Reset** (not a step): if you want to start over, the compute card's **Reset**
action returns the activity to a clean student-start (deletes the account, safe,
and workload record).
