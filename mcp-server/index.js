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

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Base directory for demos - go up one level from mcp-server to cybr-demos
const DEMOS_BASE_DIR = path.resolve(__dirname, "..", "demos");

// Available categories
const CATEGORIES = [
  "credential_providers",
  "secrets_manager",
  "secrets_hub",
  "utility",
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
${options.addSyncMember ? 'add_safe_read_member "$isp_subdomain" "$identity_token" "$safe_name" "Conjur Sync"' : ""}

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

  // Create create_safe.sh
  const createSafeScript = `#!/bin/bash
set -euo pipefail

source "$CYBR_DEMOS_PATH/demos/setup_env.sh"

isp_id=$TENANT_ID
isp_subdomain=$TENANT_SUBDOMAIN
client_id=$CLIENT_ID
client_secret=$CLIENT_SECRET
safe_name="${safeName}"

identity_token=$(get_identity_token "$isp_id" "$client_id" "$client_secret")

echo "Creating safe: $safe_name"
create_safe "$isp_subdomain" "$identity_token" "$safe_name"
add_safe_admin_role "$isp_subdomain" "$identity_token" "$safe_name" "Privilege Cloud Administrators"

echo "Safe created successfully!"
`;
  await fs.writeFile(path.join(vaultPath, "create_safe.sh"), createSafeScript);
  await fs.chmod(path.join(vaultPath, "create_safe.sh"), 0o755);

  // Optionally create create_accounts.sh
  if (options.createAccountsScript) {
    const createAccountsScript = `#!/bin/bash
set -euo pipefail

source "$CYBR_DEMOS_PATH/demos/setup_env.sh"

isp_id=$TENANT_ID
isp_subdomain=$TENANT_SUBDOMAIN
client_id=$CLIENT_ID
client_secret=$CLIENT_SECRET
safe_name="${safeName}"

identity_token=$(get_identity_token "$isp_id" "$client_id" "$client_secret")

echo "Creating accounts in safe: $safe_name"
create_account_ssh_user_1 "$isp_subdomain" "$identity_token" "$safe_name"

echo "Accounts created successfully!"
`;
    await fs.writeFile(
      path.join(vaultPath, "create_accounts.sh"),
      createAccountsScript,
    );
    await fs.chmod(path.join(vaultPath, "create_accounts.sh"), 0o755);
  }

  return {
    success: true,
    path: vaultPath,
    files: [
      "vars.env",
      "setup.sh",
      "create_safe.sh",
      ...(options.createAccountsScript ? ["create_accounts.sh"] : []),
    ],
  };
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
                "Name of the safe to create in CyberArk Privilege Cloud",
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
            createAccountsScript: {
              type: "boolean",
              description:
                "Create a separate create_accounts.sh script. Optional, defaults to false.",
            },
            additionalVars: {
              type: "string",
              description:
                "Additional environment variables to include in vars.env. Optional.",
            },
          },
          required: ["demoPath", "safeName"],
        },
      },
    ],
  };
});

// Handle tool calls
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  if (request.params.name === "create_demo") {
    const { category, name, ...options } = request.params.arguments;

    try {
      const result = await createDemo(category, name, options);

      return {
        content: [
          {
            type: "text",
            text: JSON.stringify(result, null, 2),
          },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text",
            text: JSON.stringify(
              {
                success: false,
                error: error.message,
              },
              null,
              2,
            ),
          },
        ],
        isError: true,
      };
    }
  }

  if (request.params.name === "create_demo_safe") {
    const { demoPath, safeName, ...options } = request.params.arguments;

    try {
      // Resolve the full demo path
      const fullDemoPath = path.join(DEMOS_BASE_DIR, demoPath);
      const result = await createDemoSafe(fullDemoPath, safeName, options);

      return {
        content: [
          {
            type: "text",
            text: JSON.stringify(result, null, 2),
          },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text",
            text: JSON.stringify(
              {
                success: false,
                error: error.message,
              },
              null,
              2,
            ),
          },
        ],
        isError: true,
      };
    }
  }

  throw new Error(`Unknown tool: ${request.params.name}`);
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
