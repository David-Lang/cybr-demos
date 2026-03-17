import { access, chmod, unlink, writeFile } from "fs/promises";
import path from "path";
import { exec } from "child_process";
import { promisify } from "util";
import { getDemosBaseDir, getRepoRoot } from "../lib/repo-paths.js";
import { parseBoolean, requireOption } from "../lib/options.js";

const execAsync = promisify(exec);

const REQUIRED_AUTOMATION_ENV_VARS = [
  "CYBR_DEMOS_PATH",
  "INSTALLER_USR",
  "CLIENT_SECRET",
  "CLIENT_ID",
  "TENANT_SUBDOMAIN",
  "LAB_ID",
  "TENANT_ID",
  "INSTALLER_PWD",
];

export async function runProvisionSafe(options) {
  const demoPath = requireOption(options, "demo-path");
  const safeName = requireOption(options, "safe-name");
  const fullDemoPath = path.join(getDemosBaseDir(), demoPath);

  try {
    await access(fullDemoPath);
  } catch {
    throw new Error(`Demo path does not exist: ${demoPath}`);
  }

  const addSyncMember = parseBoolean(
    options["add-sync-member"],
    "add-sync-member",
  );
  const createAccounts = parseBoolean(
    options["create-accounts"],
    "create-accounts",
  );
  const setupConjur = parseBoolean(options["setup-conjur"], "setup-conjur");
  const scriptPath = path.join(fullDemoPath, "setup", ".provision_safe_temp.sh");

  const provisionScript = `#!/bin/bash
set -euo pipefail

source "$CYBR_DEMOS_PATH/demos/setup_env.sh"

required_vars=(${REQUIRED_AUTOMATION_ENV_VARS.join(" ")})
for var_name in "\${required_vars[@]}"; do
  if [ -z "\${!var_name:-}" ]; then
    printf "ERROR: Required environment variable is not set: %s\\n" "$var_name" >&2
    exit 1
  fi
done

printf "\\n========================================\\n"
printf "Provisioning Safe: ${safeName}\\n"
printf "========================================\\n"

isp_id=$TENANT_ID
isp_subdomain=$TENANT_SUBDOMAIN
client_id=$CLIENT_ID
client_secret=$CLIENT_SECRET
safe_name="${safeName}"

printf "\\nAuthenticating to Identity...\\n"
identity_token=$(get_identity_token "$isp_id" "$client_id" "$client_secret")

if [ -z "$identity_token" ]; then
  printf "ERROR: Failed to get identity token\\n" >&2
  exit 1
fi

printf "✓ Authentication successful\\n"

printf "\\nCreating safe: $safe_name...\\n"
create_safe "$isp_subdomain" "$identity_token" "$safe_name"
printf "✓ Safe created\\n"

printf "\\nAdding admin role...\\n"
add_safe_admin_role "$isp_subdomain" "$identity_token" "$safe_name" "Privilege Cloud Administrators"
printf "✓ Admin role added\\n"

${
  addSyncMember
    ? `
printf "\\nAdding Conjur Sync member...\\n"
add_safe_read_member "$isp_subdomain" "$identity_token" "$safe_name" "Conjur Sync"
printf "✓ Conjur Sync member added\\n"
`
    : ""
}

${
  createAccounts
    ? `
printf "\\nCreating test account...\\n"
create_account_ssh_user_1 "$isp_subdomain" "$identity_token" "$safe_name"
printf "✓ Test account created\\n"
`
    : ""
}

${
  setupConjur
    ? `
printf "\\nSetting up Conjur synchronization...\\n"
conjur_token=$(get_conjur_token "$isp_subdomain" "$identity_token")
printf "Waiting for synchronizer (*/$safe_name/delegation/consumers)...\\n"
wait_for_synchronizer "$isp_subdomain" "$conjur_token" "$safe_name"
printf "✓ Conjur synchronization complete\\n"
`
    : ""
}

printf "\\n========================================\\n"
printf "Safe provisioning completed successfully!\\n"
printf "========================================\\n"
printf "\\nSafe Name: $safe_name\\n"
printf "Demo Path: ${demoPath}\\n"
`;

  try {
    await writeFile(scriptPath, provisionScript, "utf8");
    await chmod(scriptPath, 0o755);

    const { stdout, stderr } = await execAsync(scriptPath, {
      cwd: fullDemoPath,
      env: {
        ...process.env,
        CYBR_DEMOS_PATH: process.env.CYBR_DEMOS_PATH || getRepoRoot(),
      },
    });

    await unlink(scriptPath).catch(() => {});

    return {
      safeName,
      demoPath,
      output: stdout,
      warnings: stderr || undefined,
    };
  } catch (error) {
    await unlink(scriptPath).catch(() => {});
    throw new Error(
      `Failed to provision safe: ${error.message}\n${error.stderr || ""}`,
    );
  }
}
