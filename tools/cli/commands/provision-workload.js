import { access, chmod, unlink, writeFile } from "fs/promises";
import path from "path";
import { exec } from "child_process";
import { promisify } from "util";
import { getDemosBaseDir, getRepoRoot } from "../lib/repo-paths.js";
import { requireOption } from "../lib/options.js";

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

export async function runProvisionWorkload(options) {
  const demoPath = requireOption(options, "demo-path");
  const safeName = requireOption(options, "safe-name");
  const workloadName = requireOption(options, "workload-name");
  const fullDemoPath = path.join(getDemosBaseDir(), demoPath);

  try {
    await access(fullDemoPath);
  } catch {
    throw new Error(`Demo path does not exist: ${demoPath}`);
  }

  const scriptPath = path.join(
    fullDemoPath,
    "setup",
    ".provision_workload_temp.sh",
  );
  const workloadIdEncoded = `data%2Fworkloads%2F${workloadName}`;
  const workloadId = `data/workloads/${workloadName}`;

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
printf "Provisioning Workload: ${workloadName}\\n"
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

printf "\\nAuthenticating to Conjur...\\n"
conjur_token=$(get_conjur_token "$isp_subdomain" "$identity_token")
if [ -z "$conjur_token" ]; then
  printf "ERROR: Failed to get Conjur token\\n" >&2
  exit 1
fi
printf "✓ Conjur authentication successful\\n"

printf "\\nCreating workload policy...\\n"

workload_policy="
- !host
  id: workloads/${workloadName}
  annotations:
    authn/api-key: true

- !grant
  roles:
    - !group vault/${safeName}/delegation/consumers
  members:
    - !host workloads/${workloadName}
"

apply_conjur_policy "$isp_subdomain" "$conjur_token" "data" "$workload_policy"
printf "✓ Workload policy created\\n"

printf "\\nRotating API key for workload...\\n"
api_key=$(curl --silent --request PUT --data "" \\
  --location "https://$isp_subdomain.secretsmgr.cyberark.cloud/api/authn/conjur/api_key?role=host:${workloadIdEncoded}" \\
  --header "Authorization: Token token=\\"$conjur_token\\"")

if [ -z "$api_key" ]; then
  printf "ERROR: Failed to rotate API key\\n" >&2
  exit 1
fi

printf "✓ API key rotated\\n"

credentials_file="$CYBR_DEMOS_PATH/demos/${demoPath}/setup/.workload_credentials_${workloadName}.txt"
printf "\\nSaving credentials to file...\\n"
cat > "$credentials_file" << EOF
========================================
Workload Credentials
========================================
Workload Name: ${workloadName}
Login: host/${workloadId}
API Key: $api_key

Safe Access: ${safeName}
Conjur URL: https://$isp_subdomain.secretsmgr.cyberark.cloud

========================================
Usage Example:
========================================
# Authenticate
curl -d "$api_key" \\
  https://$isp_subdomain.secretsmgr.cyberark.cloud/api/authn/conjur/host%2F${workloadIdEncoded}/authenticate

# Retrieve secret
curl -H "Authorization: Token token=\\"<token>\\"" \\
  https://$isp_subdomain.secretsmgr.cyberark.cloud/api/secrets/conjur/variable/data%2Fvault%2F${safeName}%2F<account-id>%2Fusername
EOF

chmod 600 "$credentials_file"
printf "✓ Credentials saved to: $credentials_file\\n"

printf "\\n========================================\\n"
printf "Workload provisioning completed successfully!\\n"
printf "========================================\\n"
printf "\\nWorkload Name: ${workloadName}\\n"
printf "Login: host/${workloadId}\\n"
printf "Safe Access: ${safeName}\\n"
printf "Credentials File: $credentials_file\\n"
printf "\\nIMPORTANT: Store the API key securely!\\n"
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
      workloadName,
      safeName,
      demoPath,
      output: stdout,
      warnings: stderr || undefined,
    };
  } catch (error) {
    await unlink(scriptPath).catch(() => {});
    throw new Error(
      `Failed to provision workload: ${error.message}\n${error.stderr || ""}`,
    );
  }
}
