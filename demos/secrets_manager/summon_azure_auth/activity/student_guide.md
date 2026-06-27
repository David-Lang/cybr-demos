# Student Guide: Hardcoded Secret Remediation

Your instructor will assign you a workspace like:

```bash
cd /opt/labs/student1/hardcoded-secret-remediation
```

Use the `student_guide.md` inside your assigned workspace for your exact files and secret paths.

## Goal

You will compare two scripts that run the same Azure SQL query:

- `query_db_hardcoded.sh` has database connection secrets in the script.
- `query_db_secured.sh` has no hardcoded secrets and receives them at runtime.
- `run_secured_query.sh` uses Summon to fetch secrets from CyberArk Secrets Manager.

The SQL query remains inline in both scripts. The remediation is about secret handling, not query logic.

## Idira Tenant Setup

Complete these steps in the Idira tenant before the final secured run. You will use both Privilege Cloud and Secrets Manager.

1. Locate the current SQL account in Privilege Cloud.

   Open the assigned student safe and find the Microsoft SQL Server account for this activity. Record the account address, username, and password. Use the database name provided by the instructor for `SQL_DATABASE`.

2. Add the current SQL values to the hardcoded script for the starting state.

   Update `SQL_SERVER`, `SQL_DATABASE`, `SQL_USERNAME`, and `SQL_PASSWORD` in `query_db_hardcoded.sh`. This is intentionally insecure and creates the starting point for the remediation.

3. Add the `Conjur Sync` user to the student safe.

   In Privilege Cloud, open the student safe, add `Conjur Sync` as a safe member, and grant the required sync permissions. Include `View users` and `Access without confirmation`.

4. Grant the workload identity access to the student safe.

   In Secrets Manager, find the workload identity for the Azure user-assigned managed identity, or UMAI, used by this lab VM.

   Add that workload identity to the student safe's consumers group or equivalent safe access policy. Grant it permission to read the SQL account variables for `address`, `username`, and `password`.

5. In Secrets Manager, copy the variable paths for the SQL account `address`, `username`, and `password` properties.

## Ubuntu Activity Steps

1. Open your assigned workspace and inspect the files:

   ```bash
   cd /opt/labs/student1/hardcoded-secret-remediation
   ll
   ```

2. Update and inspect the hardcoded script:

   ```bash
   vi query_db_hardcoded.sh
   ```

   Enter the current `SQL_SERVER`, `SQL_DATABASE`, `SQL_USERNAME`, and `SQL_PASSWORD` values.

3. Run the hardcoded script:

   ```bash
   ./query_db_hardcoded.sh
   ```

   It should return five rows from `dbo.ExampleTable`.

4. Run the secured script directly:

   ```bash
   ./query_db_secured.sh
   ```

   This should fail because Summon has not injected `SQL_SERVER`, `SQL_USERNAME`, or `SQL_PASSWORD`.

5. Run the Summon wrapper before fixing `secrets.yml`:

   ```bash
   ./run_secured_query.sh
   ```

   If placeholder paths are still present, Summon should report that `data/vault/set_safe/set_account/address` is empty or not found.

6. Update `secrets.yml` with the actual Secrets Manager paths:

   ```bash
   vi secrets.yml
   ```

   Example:

   ```yaml
   SQL_SERVER: !var data/vault/<student-safe>/<sql-account>/address
   SQL_USERNAME: !var data/vault/<student-safe>/<sql-account>/username
   SQL_PASSWORD: !var data/vault/<student-safe>/<sql-account>/password
   ```

7. Run the secured script through Summon again:

   ```bash
   ./run_secured_query.sh
   ```

   If the safe, account, property path, or UMAI permissions are still wrong, Summon may report that the specific variable path is empty or not found.

8. Run the secured script again after fixing the path or permissions:

   ```bash
   ./run_secured_query.sh
   ```

   It should return the same five rows as the hardcoded script.

## Bonus: Rotation Test

After the secured script works, use Privilege Cloud to rotate the SQL account password, then rerun both scripts from Ubuntu.

1. In Privilege Cloud, open the student safe and locate the SQL account used in `secrets.yml`.
2. Rotate or change the account password in Privilege Cloud.
3. Wait for the account to show the rotation completed successfully.
4. Return to the Ubuntu workspace:

   ```bash
   cd /opt/labs/student1/hardcoded-secret-remediation
   ```

5. Rerun the hardcoded script:

   ```bash
   ./query_db_hardcoded.sh
   ```

   The hardcoded script should fail because it still contains the old password.

6. Rerun the secured script through Summon:

   ```bash
   ./run_secured_query.sh
   ```

   The secured script should still return rows because Summon retrieves the current value from CyberArk at runtime.

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
- You can update `secrets.yml` with the correct Secrets Manager paths.
- You can explain why `query_db_secured.sh` fails without Summon.
- You can explain why the UMAI needs safe access before Summon can retrieve secrets.
- Bonus: You can rotate the SQL password in Privilege Cloud and show that the hardcoded script fails while the secured script still works.
