# Hardcoded Secret Remediation - __STUDENT__

This activity removes a hardcoded database password from a script without
changing the SQL query — you vault it in CyberArk and retrieve it at runtime.

The database is a local PostgreSQL already running on this VM. The scripts use
`psql`; the only thing that changes between them is how the password is handled.

## Files

- `query_db_hardcoded.sh` — starting script with the password inline (anti-pattern).
- `query_db_secured.sh` — no secret; reads `PGUSER`/`PGPASSWORD` from the environment.
- `run_hardcoded_query.sh` — runs `query_db_hardcoded.sh` (the insecure baseline).
- `run_secured_query.sh` — runs `query_db_secured.sh` under Summon (the secured path).
- `secrets.yml` — maps `PGUSER`/`PGPASSWORD` to your vaulted CyberArk account (pre-filled; do not edit).
- `student_guide.md` — step-by-step guide (expose → vault → secure → rotate).
- `conjur_authn_azure.env` — Azure authenticator runtime config for this VM.

## Activity (short form)

```bash
./run_hardcoded_query.sh    # 1. Expose: works, but the password is in the file
cat query_db_hardcoded.sh   #    see the hardcoded PGPASSWORD
# 2. Vault the credential in CyberArk (see student_guide.md)
./run_secured_query.sh      # 3. Secure: same result, no secret in the script
# 4. Rotate with SRS, then rerun both — hardcoded fails, secured still works
```

## Expected result

Both scripts return the same rows from `example_table`. The secured version has
no server, username, or password in the file — Summon injects the current
credential at runtime using the VM's Azure managed identity.
