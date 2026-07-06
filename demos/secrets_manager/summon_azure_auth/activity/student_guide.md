# Student Guide (reference)

The authoritative, ready-to-run guide is generated per student at:

```text
/opt/labs/<student>/hardcoded-secret-remediation/student_guide.md
```

It is rendered from `templates/student_guide.md.tmpl` with your safe/account
names and connection details filled in. Use that copy on the VM.

## What the activity covers

A VM-local PostgreSQL and two scripts that run the same query with `psql`. The
arc is **expose → vault → secure → rotate**:

1. **Expose** — `./query_db_hardcoded.sh` runs with the password inline in the script.
2. **Vault** — signed in to idira, create the safe (named after the VM) and onboard
   the Postgres account (`postgres-appuser`, platform `PostgreSQL`) with the initial
   credential. Add `Conjur Sync` to the safe.
3. **Secure** — `./run_secured_query.sh` returns the same rows with no secret in the
   script; Summon fetches the credential at runtime using the VM's Azure managed
   identity (`authn-azure`).
4. **Rotate** — rotate the vaulted credential with SRS (through the Idira System
   connector). The secured script keeps working; the hardcoded one fails.

The workload's read access to the safe is granted by the control plane
(`setup/conjur/grant_consumers.sh`) after the safe syncs.
