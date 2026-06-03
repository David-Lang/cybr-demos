# Student Guide: Hardcoded Secret Remediation

Your instructor will assign you a workspace like:

```bash
cd /opt/labs/student1/hardcoded-secret-remediation
```

Use the `student_guide.md` inside your assigned workspace for your exact CyberArk safe and account paths.

## Goal

You will compare two scripts that run the same Azure SQL query:

- `query_db_hardcoded.sh` has database connection secrets in the script.
- `query_db_secured.sh` has no hardcoded secrets and receives them at runtime.

The SQL query remains inline in both scripts. The remediation is about secret handling, not query logic.

## Activity Steps

1. Run the hardcoded script.

   ```bash
   ./query_db_hardcoded.sh
   ```

2. Inspect the hardcoded values.

   ```bash
   sed -n '1,80p' query_db_hardcoded.sh
   ```

3. Inspect the secured script.

   ```bash
   sed -n '1,120p' query_db_secured.sh
   ```

4. Inspect the CyberArk variable map.

   ```bash
   cat secrets.yml
   ```

5. Inspect the Summon wrapper.

   ```bash
   sed -n '1,120p' run_secured_query.sh
   ```

6. Run the secured script.

   ```bash
   ./run_secured_query.sh
   ```

## Runtime Flow

```text
run_secured_query.sh
  -> source conjur_authn_azure.env
  -> summon reads secrets.yml
  -> summon-conjur authenticates with Azure managed identity
  -> CyberArk returns authorized safe-backed values
  -> query_db_secured.sh receives environment variables
  -> sqlcmd runs the inline SQL query
```

## Success Criteria

- You can identify the hardcoded secrets in `query_db_hardcoded.sh`.
- You can explain why `query_db_secured.sh` does not contain those secrets.
- You can point to where Summon is called.
- You can explain which values come from CyberArk and which value is normal configuration.
