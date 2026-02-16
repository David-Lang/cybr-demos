#!/usr/bin/env node

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import * as fs from "fs/promises";
import * as path from "path";
import { fileURLToPath } from "url";
import { exec } from "child_process";
import { promisify } from "util";
import { randomUUID } from "crypto";

const execAsync = promisify(exec);

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Base directory for demos - go up one level from mcp-server to cybr-demos
const DEMOS_BASE_DIR = path.resolve(__dirname, "..", "demos");
const CONTRACT_VERSION = "global/v1";
const MUTATING_TOOLS = new Set([
  "create_demo",
  "create_demo_safe",
  "provision_safe",
  "provision_workload",
]);

// Available categories
const CATEGORIES = [
  "credential_providers",
  "secrets_manager",
  "secrets_hub",
  "utility",
];
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

/**
 * Create a new demo with standard scaffolding
 */
async function createDemo(category, name, options = {}) {
  // Validate category
  if (!CATEGORIES.includes(category)) {
    throw new Error(
      `Invalid category: ${category}. Must be one of: ${CATEGORIES.join(", ")}`,
    );
  }

  // Sanitize demo name (replace spaces with underscores, lowercase)
  const demoDir = name.toLowerCase().replace(/\s+/g, "_");
  const demoPath = path.join(DEMOS_BASE_DIR, category, demoDir);

  // Check if demo already exists
  try {
    await fs.access(demoPath);
    throw new Error(`Demo already exists at: ${demoPath}`);
  } catch (err) {
    if (err.code !== "ENOENT") throw err;
  }

  // Create demo directory
  await fs.mkdir(demoPath, { recursive: true });

  // Create setup directory
  const setupPath = path.join(demoPath, "setup");
  await fs.mkdir(setupPath, { recursive: true });

  // Create info.yaml
  const infoYaml = `Category: "${options.categoryLabel || category}"
Name: "${options.displayName || name}"
Docs: "${options.docs || "https://docs.cyberark.com/portal/latest/en/docs.htm"}"
DemoScript: "${options.demoScript || "demo.sh"}"
SetupScript: "${options.setupScript || "setup.sh"}"
Enabled: false
IsSetup: false
`;
  await fs.writeFile(path.join(demoPath, "info.yaml"), infoYaml);

  // Create README.md
  const readme = `# Demo: ${options.displayName || name}

## About

${options.description || "Description of this demo."}

## Prerequisites

- List prerequisites here

## Setup

Run the setup script:

\`\`\`bash
./setup.sh
\`\`\`

## Running the Demo

\`\`\`bash
./demo.sh
\`\`\`

## Configuration

Describe any configuration needed here.

## Workflow

Describe the workflow or architecture here.

## Example

Provide example commands or outputs here.
`;
  await fs.writeFile(path.join(demoPath, "README.md"), readme);

  // Create demo.sh
  const demoScript = `#!/bin/bash

# Demo: ${options.displayName || name}
# Category: ${category}

set -e

# Source common environment variables if available
if [ -f "../../tenant_vars.sh" ]; then
    source ../../tenant_vars.sh
fi

echo "=========================================="
echo "Demo: ${options.displayName || name}"
echo "=========================================="
echo ""

# Add your demo commands here

echo ""
echo "Demo completed!"
`;
  await fs.writeFile(path.join(demoPath, "demo.sh"), demoScript);
  await fs.chmod(path.join(demoPath, "demo.sh"), 0o755);

  // Create setup.sh
  const setupScript = `#!/bin/bash

# Setup script for: ${options.displayName || name}
# Category: ${category}

set -e

SCRIPT_DIR="$( cd "$( dirname "\${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

echo "=========================================="
echo "Setup: ${options.displayName || name}"
echo "=========================================="
echo ""

# Source common environment variables if available
if [ -f "../../tenant_vars.sh" ]; then
    source ../../tenant_vars.sh
fi

# Add your setup commands here

echo ""
echo "Setup completed successfully!"
`;
  await fs.writeFile(path.join(demoPath, "setup.sh"), setupScript);
  await fs.chmod(path.join(demoPath, "setup.sh"), 0o755);

  // Create setup/configure.sh
  const configureScript = `#!/bin/bash

# Configuration script for: ${options.displayName || name}

set -e

echo "Configuring ${options.displayName || name}..."

# Add configuration commands here

echo "Configuration completed!"
`;
  await fs.writeFile(path.join(setupPath, "configure.sh"), configureScript);
  await fs.chmod(path.join(setupPath, "configure.sh"), 0o755);

  return {
    success: true,
    path: demoPath,
    files: [
      "info.yaml",
      "README.md",
      "demo.sh",
      "setup.sh",
      "setup/configure.sh",
    ],
  };
}

/**
 * Create demo safe setup scaffolding for CyberArk Privilege Cloud
 */
async function createDemoSafe(demoPath, safeName, options = {}) {
  // Validate demo path exists
  try {
    await fs.access(demoPath);
  } catch (err) {
    throw new Error(`Demo path does not exist: ${demoPath}`);
  }

  // Generate default safe name if not provided
  if (!safeName) {
    // Extract demo name from path (last directory component)
    const demoName = path.basename(demoPath);
    // Normalize: replace spaces and non-alphanumeric chars with hyphens
    const normalizedName = demoName
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "");
    safeName = `\${LAB_ID}-${normalizedName}`;
  }

  // Create setup/vault directory
  const vaultPath = path.join(demoPath, "setup", "vault");
  await fs.mkdir(vaultPath, { recursive: true });

  // Create vars.env
  const varsEnv = `# CyberArk Vault
SAFE_NAME="${safeName}"

${options.additionalVars || "# Add additional environment variables here"}
`;
  await fs.writeFile(path.join(vaultPath, "vars.env"), varsEnv);

  // Create setup.sh
  const setupScript = `#!/bin/bash
# shellcheck disable=SC2059
set -euo pipefail

demo_path="${options.demoPathVar || "$CYBR_DEMOS_PATH/demos/secrets_manager/" + path.basename(demoPath)}"
# Set environment variables using .env file
# -a means that every bash variable would become an environment variable
# Using '+' rather than '-' causes the option to be turned off
set -a
source "$CYBR_DEMOS_PATH/demos/setup_env.sh"
source "$demo_path/setup/vault/vars.env"
set +a

required_vars=(${REQUIRED_AUTOMATION_ENV_VARS.join(" ")})
for var_name in "\${required_vars[@]}"; do
  if [ -z "\${!var_name:-}" ]; then
    printf "ERROR: Required environment variable is not set: %s\\n" "$var_name" >&2
    exit 1
  fi
done

printf "\\nSetting local vars from Env"
isp_id=$TENANT_ID
isp_subdomain=$TENANT_SUBDOMAIN
client_id=$CLIENT_ID
client_secret=$CLIENT_SECRET
safe_name=$SAFE_NAME

identity_token=$(get_identity_token "$isp_id" "$client_id" "$client_secret")
printf "\\n\\nidentity_token: \\n$identity_token\\n"

create_safe "$isp_subdomain" "$identity_token" "$safe_name"
add_safe_admin_role "$isp_subdomain" "$identity_token" "$safe_name" "Privilege Cloud Administrators"
${options.addSyncMember || demoPath.includes(`${path.sep}secrets_manager${path.sep}`) ? 'add_safe_read_member "$isp_subdomain" "$identity_token" "$safe_name" "Conjur Sync"' : ""}

${options.createAccount ? 'create_account_ssh_user_1 "$isp_subdomain" "$identity_token" "$safe_name"' : ""}

${
  options.setupConjur
    ? `
conjur_token=$(get_conjur_token "$isp_subdomain" "$identity_token")
printf "\\n\\nconjur_token: \\n$conjur_token\\n"
printf "Waiting for synchronizer (*/$safe_name/delegation/consumers)\\n"
wait_for_synchronizer "$isp_subdomain" "$conjur_token" "$safe_name"
`
    : ""
}

printf "\\n\\nSafe setup completed successfully!\\n"
`;
  await fs.writeFile(path.join(vaultPath, "setup.sh"), setupScript);
  await fs.chmod(path.join(vaultPath, "setup.sh"), 0o755);

  // setup.sh is the single execution entrypoint (vars.env feeds into it)

  return {
    success: true,
    path: vaultPath,
    files: ["vars.env", "setup.sh"],
  };
}

/**
 * Provision a safe in CyberArk Privilege Cloud and create accounts
 * Uses environment variables from tenant_vars.sh
 */
async function provisionSafe(demoPath, safeName, options = {}) {
  // Validate demo path exists
  const fullDemoPath = path.join(DEMOS_BASE_DIR, demoPath);
  try {
    await fs.access(fullDemoPath);
  } catch (err) {
    throw new Error(`Demo path does not exist: ${demoPath}`);
  }

  // Create a temporary script to run the provisioning
  const scriptPath = path.join(
    fullDemoPath,
    "setup",
    ".provision_safe_temp.sh",
  );

  const provisionScript = `#!/bin/bash
set -euo pipefail

# Source environment and utility functions
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

# Get environment variables
isp_id=$TENANT_ID
isp_subdomain=$TENANT_SUBDOMAIN
client_id=$CLIENT_ID
client_secret=$CLIENT_SECRET
safe_name="${safeName}"

# Authenticate and get token
printf "\\nAuthenticating to Identity...\\n"
identity_token=$(get_identity_token "$isp_id" "$client_id" "$client_secret")

if [ -z "$identity_token" ]; then
  printf "ERROR: Failed to get identity token\\n" >&2
  exit 1
fi

printf "✓ Authentication successful\\n"

# Create safe
printf "\\nCreating safe: $safe_name...\\n"
create_safe "$isp_subdomain" "$identity_token" "$safe_name"
printf "✓ Safe created\\n"

# Add admin role
printf "\\nAdding admin role...\\n"
add_safe_admin_role "$isp_subdomain" "$identity_token" "$safe_name" "Privilege Cloud Administrators"
printf "✓ Admin role added\\n"

${
  options.addSyncMember
    ? `
# Add Conjur Sync member
printf "\\nAdding Conjur Sync member...\\n"
add_safe_read_member "$isp_subdomain" "$identity_token" "$safe_name" "Conjur Sync"
printf "✓ Conjur Sync member added\\n"
`
    : ""
}

${
  options.createAccounts
    ? `
# Create test account
printf "\\nCreating test account...\\n"
create_account_ssh_user_1 "$isp_subdomain" "$identity_token" "$safe_name"
printf "✓ Test account created\\n"
`
    : ""
}

${
  options.setupConjur
    ? `
# Setup Conjur synchronization
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
    // Write the temporary script
    await fs.writeFile(scriptPath, provisionScript);
    await fs.chmod(scriptPath, 0o755);

    // Execute the script
    const { stdout, stderr } = await execAsync(scriptPath, {
      cwd: fullDemoPath,
      env: {
        ...process.env,
        CYBR_DEMOS_PATH: path.resolve(DEMOS_BASE_DIR, ".."),
      },
    });

    // Clean up temporary script
    await fs.unlink(scriptPath).catch(() => {});

    return {
      success: true,
      safeName: safeName,
      demoPath: demoPath,
      output: stdout,
      warnings: stderr || undefined,
    };
  } catch (error) {
    // Clean up temporary script on error
    await fs.unlink(scriptPath).catch(() => {});

    throw new Error(
      `Failed to provision safe: ${error.message}\n${error.stderr || ""}`,
    );
  }
}

/**
 * Provision a Secrets Manager workload with API key authentication
 * Creates the workload policy and grants it access to the specified safe
 */
async function provisionWorkload(
  demoPath,
  safeName,
  workloadName,
  options = {},
) {
  // Validate demo path exists
  const fullDemoPath = path.join(DEMOS_BASE_DIR, demoPath);
  try {
    await fs.access(fullDemoPath);
  } catch (err) {
    throw new Error(`Demo path does not exist: ${demoPath}`);
  }

  // Create a temporary script to run the provisioning
  const scriptPath = path.join(
    fullDemoPath,
    "setup",
    ".provision_workload_temp.sh",
  );

  // URL encode the workload name for API calls
  const workloadIdEncoded = `data%2Fworkloads%2F${workloadName}`;
  const workloadId = `data/workloads/${workloadName}`;

  const provisionScript = `#!/bin/bash
set -euo pipefail

# Source environment and utility functions
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

# Get environment variables
isp_id=$TENANT_ID
isp_subdomain=$TENANT_SUBDOMAIN
client_id=$CLIENT_ID
client_secret=$CLIENT_SECRET
safe_name="${safeName}"
workload_name="${workloadName}"

# Authenticate and get tokens
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

# Create workload policy
printf "\\nCreating workload policy...\\n"

workload_policy="
# Workload identity with API key authentication
- !host
  id: workloads/${workloadName}
  annotations:
    authn/api-key: true

# Grant access to the safe
- !grant
  roles:
    - !group vault/${safeName}/delegation/consumers
  members:
    - !host workloads/${workloadName}
"

apply_conjur_policy "$isp_subdomain" "$conjur_token" "data" "$workload_policy"
printf "✓ Workload policy created\\n"

# Rotate API key to get a fresh one
printf "\\nRotating API key for workload...\\n"
api_key=$(curl --silent --request PUT --data "" \\
  --location "https://$isp_subdomain.secretsmgr.cyberark.cloud/api/authn/conjur/api_key?role=host:${workloadIdEncoded}" \\
  --header "Authorization: Token token=\\"$conjur_token\\"")

if [ -z "$api_key" ]; then
  printf "ERROR: Failed to rotate API key\\n" >&2
  exit 1
fi

printf "✓ API key rotated\\n"

# Save credentials to file
credentials_file="$CYBR_DEMOS_PATH/demos/$demoPath/setup/.workload_credentials_${workloadName}.txt"
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
    // Write the temporary script
    await fs.writeFile(scriptPath, provisionScript);
    await fs.chmod(scriptPath, 0o755);

    // Execute the script
    const { stdout, stderr } = await execAsync(scriptPath, {
      cwd: fullDemoPath,
      env: {
        ...process.env,
        CYBR_DEMOS_PATH: path.resolve(DEMOS_BASE_DIR, ".."),
      },
    });

    // Clean up temporary script
    await fs.unlink(scriptPath).catch(() => {});

    return {
      success: true,
      workloadName: workloadName,
      safeName: safeName,
      demoPath: demoPath,
      output: stdout,
      warnings: stderr || undefined,
    };
  } catch (error) {
    // Clean up temporary script on error
    await fs.unlink(scriptPath).catch(() => {});

    throw new Error(
      `Failed to provision workload: ${error.message}\n${error.stderr || ""}`,
    );
  }
}

/**
 * Validate README/markdown files against documentation guidelines
 */
async function validateReadme(filePath) {
  // Resolve the full file path
  const fullFilePath = path.join(DEMOS_BASE_DIR, filePath);

  try {
    await fs.access(fullFilePath);
  } catch (err) {
    throw new Error(`File does not exist: ${filePath}`);
  }

  // Read the file content
  const content = await fs.readFile(fullFilePath, "utf-8");

  // Initialize validation results
  const issues = [];
  const suggestions = [];
  let score = 100;

  // Guideline 1: No emojis
  const emojiRegex =
    /[\u{1F600}-\u{1F64F}\u{1F300}-\u{1F5FF}\u{1F680}-\u{1F6FF}\u{1F1E0}-\u{1F1FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}\u{1F900}-\u{1F9FF}\u{1FA00}-\u{1FA6F}\u{1FA70}-\u{1FAFF}\u{231A}-\u{231B}\u{23E9}-\u{23EC}\u{23F0}\u{23F3}\u{25FD}-\u{25FE}\u{2614}-\u{2615}\u{2648}-\u{2653}\u{267F}\u{2693}\u{26A1}\u{26AA}-\u{26AB}\u{26BD}-\u{26BE}\u{26C4}-\u{26C5}\u{26CE}\u{26D4}\u{26EA}\u{26F2}-\u{26F3}\u{26F5}\u{26FA}\u{26FD}\u{2705}\u{270A}-\u{270B}\u{2728}\u{274C}\u{274E}\u{2753}-\u{2755}\u{2757}\u{2795}-\u{2797}\u{27B0}\u{27BF}\u{2B1B}-\u{2B1C}\u{2B50}\u{2B55}]/gu;

  const lines = content.split("\n");
  const emojiMatches = [];

  lines.forEach((line, index) => {
    const matches = line.match(emojiRegex);
    if (matches) {
      emojiMatches.push({
        line: index + 1,
        content: line.trim(),
        emojis: matches,
      });
    }
  });

  if (emojiMatches.length > 0) {
    score -= Math.min(30, emojiMatches.length * 5);
    issues.push({
      guideline: "No Emojis",
      severity: "warning",
      count: emojiMatches.length,
      message: `Found ${emojiMatches.length} line(s) containing emojis`,
      locations: emojiMatches.map((m) => ({
        line: m.line,
        preview:
          m.content.substring(0, 80) + (m.content.length > 80 ? "..." : ""),
        emojis: m.emojis.join(", "),
      })),
    });
    suggestions.push(
      "Remove emojis from documentation. Use descriptive text instead.",
    );
  }

  // Calculate pass/fail
  const passed = score >= 70;

  return {
    success: true,
    filePath: filePath,
    passed: passed,
    score: score,
    issues: issues,
    suggestions: suggestions,
    summary: {
      totalIssues: issues.length,
      guidelinesChecked: 1,
      guidelinesPassed: issues.length === 0 ? 1 : 0,
    },
  };
}

function createRequestEnvelope(toolName, rawArgs = {}) {
  const isEnvelope =
    rawArgs && typeof rawArgs === "object" && rawArgs.params !== undefined;

  const requestId =
    (isEnvelope ? rawArgs.request_id : rawArgs.request_id) || randomUUID();

  const caller = isEnvelope
    ? rawArgs.caller || { type: "agent", id: "mcp-client" }
    : rawArgs.caller || { type: "agent", id: "mcp-client" };

  const labContext = isEnvelope
    ? rawArgs.lab_context || {
        solution_format: "saas",
        environment: "demo",
      }
    : rawArgs.lab_context || {
        solution_format: "saas",
        environment: "demo",
      };

  const params = isEnvelope ? rawArgs.params || {} : { ...rawArgs };
  delete params.request_id;
  delete params.contract_version;
  delete params.idempotency_key;
  delete params.dry_run;
  delete params.caller;
  delete params.lab_context;
  delete params.params;

  return {
    request_id: requestId,
    tool_name: toolName,
    contract_version: CONTRACT_VERSION,
    idempotency_key: isEnvelope
      ? (rawArgs.idempotency_key ?? null)
      : (rawArgs.idempotency_key ?? null),
    dry_run: isEnvelope ? Boolean(rawArgs.dry_run) : Boolean(rawArgs.dry_run),
    caller,
    lab_context: labContext,
    params,
  };
}

function redactString(input) {
  let count = 0;
  let value = input;
  value = value.replace(/(API Key:\s*)([^\s]+)/gi, (_match, prefix) => {
    count += 1;
    return `${prefix}***REDACTED***`;
  });

  value = value.replace(
    /(client_secret[=:]\s*)([^\s]+)/gi,
    (_match, prefix) => {
      count += 1;
      return `${prefix}***REDACTED***`;
    },
  );

  value = value.replace(/(access_token[=:]\s*)([^\s]+)/gi, (_match, prefix) => {
    count += 1;
    return `${prefix}***REDACTED***`;
  });

  value = value.replace(
    /(Authorization:\s*Token token="?)([^"\s]+)("?)/gi,
    (_match, prefix, _token, suffix) => {
      count += 1;
      return `${prefix}***REDACTED***${suffix}`;
    },
  );

  value = value.replace(
    /(Bearer\s+)([A-Za-z0-9\-._~+/]+=*)/gi,
    (_match, prefix) => {
      count += 1;
      return `${prefix}***REDACTED***`;
    },
  );

  value = value.replace(
    /(eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)/g,
    () => {
      count += 1;
      return "***REDACTED***";
    },
  );

  return { value, count };
}

function redactValue(value, keyHint = "") {
  const sensitiveKeyPattern =
    /(secret|token|password|api[_-]?key|private[_-]?key)/i;

  if (typeof value === "string") {
    const { value: redacted, count } = redactString(value);
    return { value: redacted, count };
  }

  if (
    value !== null &&
    typeof value === "object" &&
    !Array.isArray(value) &&
    sensitiveKeyPattern.test(keyHint)
  ) {
    return { value: "***REDACTED***", count: 1 };
  }

  if (Array.isArray(value)) {
    let count = 0;
    const redacted = value.map((item) => {
      const result = redactValue(item, keyHint);
      count += result.count;
      return result.value;
    });
    return { value: redacted, count };
  }

  if (value !== null && typeof value === "object") {
    let count = 0;
    const redacted = {};
    for (const [key, objectValue] of Object.entries(value)) {
      if (sensitiveKeyPattern.test(key)) {
        redacted[key] = "***REDACTED***";
        count += 1;
        continue;
      }
      const result = redactValue(objectValue, key);
      redacted[key] = result.value;
      count += result.count;
    }
    return { value: redacted, count };
  }

  if (sensitiveKeyPattern.test(keyHint) && value != null) {
    return { value: "***REDACTED***", count: 1 };
  }

  return { value, count: 0 };
}

function mapErrorToContract(error) {
  const message = error?.message || "Unknown error";
  const lowered = message.toLowerCase();

  let code = "INTERNAL_ERROR";
  let category = "INTERNAL";
  let retryable = false;
  let http_status = 500;
  let remediation = "Check logs and retry. If persistent, escalate.";

  if (lowered.includes("invalid") || lowered.includes("required")) {
    code = "VALIDATION_FAILED";
    category = "VALIDATION";
    http_status = 400;
    remediation = "Verify required parameters and allowed values.";
  } else if (
    lowered.includes("does not exist") ||
    lowered.includes("not found")
  ) {
    code = "RESOURCE_NOT_FOUND";
    category = "NOT_FOUND";
    http_status = 404;
    remediation = "Confirm the resource path or identifier exists.";
  } else if (
    lowered.includes("already exists") ||
    lowered.includes("conflict")
  ) {
    code = "RESOURCE_CONFLICT";
    category = "CONFLICT";
    http_status = 409;
    remediation =
      "Use a unique name or idempotency key, or target an existing resource.";
  } else if (
    lowered.includes("permission") ||
    lowered.includes("forbidden") ||
    lowered.includes("denied")
  ) {
    code = "PERMISSION_DENIED";
    category = "PERMISSION";
    http_status = 403;
    remediation = "Verify caller permissions and required role assignments.";
  } else if (lowered.includes("auth") || lowered.includes("token")) {
    code = "AUTH_FAILED";
    category = "AUTH";
    http_status = 401;
    remediation = "Validate tenant credentials and token acquisition.";
  } else if (lowered.includes("rate limit") || lowered.includes("429")) {
    code = "RATE_LIMITED";
    category = "RATE_LIMIT";
    retryable = true;
    http_status = 429;
    remediation = "Retry with backoff.";
  } else if (
    lowered.includes("timeout") ||
    lowered.includes("econnreset") ||
    lowered.includes("enotfound") ||
    lowered.includes("eai_again")
  ) {
    code = "DEPENDENCY_UNAVAILABLE";
    category = "DEPENDENCY";
    retryable = true;
    http_status = 503;
    remediation = "Retry after dependency health is restored.";
  }

  return {
    code,
    message,
    category,
    retryable,
    http_status,
    details: {},
    remediation,
  };
}

function buildContractResponse({
  status,
  requestEnvelope,
  durationMs,
  result = {},
  warnings = [],
  errors = [],
}) {
  const redactedResult = redactValue(result);
  const redactedWarnings = redactValue(warnings);
  const redactedErrors = redactValue(errors);
  const redactionCount =
    redactedResult.count + redactedWarnings.count + redactedErrors.count;

  return {
    status,
    request_id: requestEnvelope.request_id,
    tool_name: requestEnvelope.tool_name,
    contract_version: CONTRACT_VERSION,
    duration_ms: durationMs,
    result: redactedResult.value,
    warnings: redactedWarnings.value,
    errors: redactedErrors.value,
    meta: {
      timestamp_utc: new Date().toISOString(),
      redactions_applied: redactionCount,
      next_cursor: null,
    },
  };
}

async function executeWithContract(toolName, rawArgs, executor) {
  const startedAt = Date.now();
  const requestEnvelope = createRequestEnvelope(toolName, rawArgs || {});
  const warnings = [];
  const isMutating = MUTATING_TOOLS.has(toolName);

  if (isMutating && !requestEnvelope.idempotency_key) {
    warnings.push({
      code: "MISSING_IDEMPOTENCY_KEY",
      message:
        "Mutating operation called without idempotency_key; replay safety is reduced.",
    });
  }

  if (isMutating && requestEnvelope.dry_run) {
    const response = buildContractResponse({
      status: "ok",
      requestEnvelope,
      durationMs: Date.now() - startedAt,
      result: {
        dry_run: true,
        executed: false,
        normalized_params: requestEnvelope.params,
      },
      warnings,
      errors: [],
    });

    return {
      content: [{ type: "text", text: JSON.stringify(response, null, 2) }],
    };
  }

  try {
    const result = await executor(requestEnvelope.params, requestEnvelope);
    const response = buildContractResponse({
      status: "ok",
      requestEnvelope,
      durationMs: Date.now() - startedAt,
      result,
      warnings,
      errors: [],
    });

    return {
      content: [{ type: "text", text: JSON.stringify(response, null, 2) }],
    };
  } catch (error) {
    const mapped = mapErrorToContract(error);
    const response = buildContractResponse({
      status: "error",
      requestEnvelope,
      durationMs: Date.now() - startedAt,
      result: {},
      warnings,
      errors: [mapped],
    });

    return {
      content: [{ type: "text", text: JSON.stringify(response, null, 2) }],
      isError: true,
    };
  }
}

// Create MCP server
const server = new Server(
  {
    name: "cybr-demos-mcp-server",
    version: "1.0.0",
  },
  {
    capabilities: {
      tools: {},
    },
  },
);

// List available tools
server.setRequestHandler(ListToolsRequestSchema, async () => {
  return {
    tools: [
      {
        name: "create_demo",
        description:
          "Create a new demo with standard scaffolding files (README.md, info.yaml, demo.sh, setup.sh, and setup directory). The demo will be created in the appropriate category directory under demos/.",
        inputSchema: {
          type: "object",
          properties: {
            category: {
              type: "string",
              enum: CATEGORIES,
              description: `Category for the demo. Must be one of: ${CATEGORIES.join(", ")}`,
            },
            name: {
              type: "string",
              description:
                "Name of the demo (will be converted to lowercase with underscores for directory name)",
            },
            displayName: {
              type: "string",
              description:
                "Display name for the demo (used in README and info.yaml). Optional, defaults to name.",
            },
            categoryLabel: {
              type: "string",
              description:
                "Custom category label for info.yaml. Optional, defaults to category.",
            },
            description: {
              type: "string",
              description:
                "Description of the demo for README. Optional, uses placeholder if not provided.",
            },
            docs: {
              type: "string",
              description:
                "Documentation URL. Optional, defaults to CyberArk docs portal.",
            },
            demoScript: {
              type: "string",
              description:
                'Name of the demo script file. Optional, defaults to "demo.sh".',
            },
            setupScript: {
              type: "string",
              description:
                'Name of the setup script file. Optional, defaults to "setup.sh".',
            },
          },
          required: ["category", "name"],
        },
      },
      {
        name: "create_demo_safe",
        description:
          "Create scaffolding for CyberArk Privilege Cloud safe setup. This creates a setup/vault directory with scripts to create and configure a safe using the CyberArk APIs. Requires an existing demo directory.",
        inputSchema: {
          type: "object",
          properties: {
            demoPath: {
              type: "string",
              description:
                "Path to the demo directory (relative to demos/ base directory, e.g., 'secrets_manager/azure_devops')",
            },
            safeName: {
              type: "string",
              description:
                "Name of the safe to create in CyberArk Privilege Cloud. Optional, defaults to '$LAB_ID-{demo-name}' where demo name is normalized (spaces and non-alphanumeric chars replaced with hyphens).",
            },
            addSyncMember: {
              type: "boolean",
              description:
                "Add 'Conjur Sync' user as a read member to the safe. Optional, defaults to false.",
            },
            createAccount: {
              type: "boolean",
              description:
                "Include account creation in the setup script. Optional, defaults to false.",
            },
            setupConjur: {
              type: "boolean",
              description:
                "Include Conjur synchronizer setup in the script. Optional, defaults to false.",
            },

            additionalVars: {
              type: "string",
              description:
                "Additional environment variables to include in vars.env. Optional.",
            },
          },
          required: ["demoPath"],
        },
      },
      {
        name: "provision_safe",
        description:
          "Provision a safe in CyberArk Privilege Cloud and optionally create accounts. This tool executes the actual API calls using environment variables from tenant_vars.sh. No user input required - uses system environment variables automatically.",
        inputSchema: {
          type: "object",
          properties: {
            demoPath: {
              type: "string",
              description:
                "Path to the demo directory (relative to demos/ base directory, e.g., 'secrets_manager/azure_devops')",
            },
            safeName: {
              type: "string",
              description:
                "Name of the safe to create in CyberArk Privilege Cloud (e.g., 'poc-azure-devops')",
            },
            addSyncMember: {
              type: "boolean",
              description:
                "Add 'Conjur Sync' user as a read member to the safe. Required for Secrets Manager/Hub integration. Defaults to false.",
            },
            createAccounts: {
              type: "boolean",
              description:
                "Create test SSH account (account-ssh-user-1) in the safe. Defaults to false.",
            },
            setupConjur: {
              type: "boolean",
              description:
                "Setup Conjur synchronization and wait for synchronizer. Requires addSyncMember to be true. Defaults to false.",
            },
          },
          required: ["demoPath", "safeName"],
        },
      },
      {
        name: "provision_workload",
        description:
          "Provision a Secrets Manager workload with API key authentication and grant it access to a safe. This tool creates the workload policy in Conjur, rotates the API key, and saves the credentials. No user input required - uses system environment variables automatically.",
        inputSchema: {
          type: "object",
          properties: {
            demoPath: {
              type: "string",
              description:
                "Path to the demo directory (relative to demos/ base directory, e.g., 'secrets_manager/azure_devops')",
            },
            safeName: {
              type: "string",
              description:
                "Name of the safe to grant access to (e.g., 'poc-azure-devops'). Safe must already exist.",
            },
            workloadName: {
              type: "string",
              description:
                "Name/identifier for the workload (e.g., 'azure-devops-pipeline', 'jenkins-job-1'). Will be created as 'data/workloads/{workloadName}'",
            },
          },
          required: ["demoPath", "safeName", "workloadName"],
        },
      },
      {
        name: "validate_readme",
        description:
          "Validate README and markdown files against documentation guidelines. Checks for common issues like emojis, formatting problems, and documentation standards. Returns validation results with suggestions for improvements.",
        inputSchema: {
          type: "object",
          properties: {
            filePath: {
              type: "string",
              description:
                "Path to the markdown file relative to demos/ base directory (e.g., 'secrets_manager/azure_devops/README.md')",
            },
          },
          required: ["filePath"],
        },
      },
    ],
  };
});

// Handle tool calls
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const toolName = request.params.name;
  const args = request.params.arguments || {};

  if (toolName === "create_demo") {
    return executeWithContract(toolName, args, async (params) => {
      const { category, name, ...options } = params;
      return createDemo(category, name, options);
    });
  }

  if (toolName === "create_demo_safe") {
    return executeWithContract(toolName, args, async (params) => {
      const { demoPath, safeName, ...options } = params;
      const fullDemoPath = path.join(DEMOS_BASE_DIR, demoPath);
      return createDemoSafe(fullDemoPath, safeName, options);
    });
  }

  if (toolName === "provision_safe") {
    return executeWithContract(toolName, args, async (params) => {
      const { demoPath, safeName, ...options } = params;
      return provisionSafe(demoPath, safeName, options);
    });
  }

  if (toolName === "provision_workload") {
    return executeWithContract(toolName, args, async (params) => {
      const { demoPath, safeName, workloadName, ...options } = params;
      return provisionWorkload(demoPath, safeName, workloadName, options);
    });
  }

  if (toolName === "validate_readme") {
    return executeWithContract(toolName, args, async (params) => {
      const { filePath } = params;
      return validateReadme(filePath);
    });
  }

  throw new Error(`Unknown tool: ${toolName}`);
});

// Start the server
async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("CyberArk Demos MCP Server running on stdio");
}

main().catch((error) => {
  console.error("Server error:", error);
  process.exit(1);
});
