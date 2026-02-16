#!/usr/bin/env node

/**
 * Test script for CyberArk Demos MCP Server
 *
 * This script tests the create_demo functionality without requiring
 * an MCP client. It creates a test demo and then cleans it up.
 */

import * as fs from "fs/promises";
import * as path from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const DEMOS_BASE_DIR = path.resolve(__dirname, "..", "demos");
const TEST_CATEGORY = "utility";
const TEST_DEMO_NAME = "mcp_test_demo";

async function createDemo(category, name, options = {}) {
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

  return {
    success: true,
    path: vaultPath,
    files: ["vars.env", "setup.sh"],
  };
}

async function cleanupTestDemo() {
  const demoPath = path.join(DEMOS_BASE_DIR, TEST_CATEGORY, TEST_DEMO_NAME);
  try {
    await fs.rm(demoPath, { recursive: true, force: true });
    console.log(`✓ Cleaned up test demo at: ${demoPath}`);
  } catch (err) {
    console.error(`✗ Error cleaning up test demo: ${err.message}`);
  }
}

async function runTests() {
  console.log("========================================");
  console.log("CyberArk Demos MCP Server Test Suite");
  console.log("========================================");
  console.log("");

  let testsPassed = 0;
  let testsFailed = 0;

  // Test 1: Create demo with minimal options
  console.log("Test 1: Create demo with minimal options");
  try {
    const result = await createDemo(TEST_CATEGORY, TEST_DEMO_NAME);

    if (result.success) {
      console.log(`✓ Demo created successfully at: ${result.path}`);
      console.log(`✓ Files created: ${result.files.join(", ")}`);

      // Verify files exist
      for (const file of result.files) {
        const filePath = path.join(result.path, file);
        await fs.access(filePath);
        console.log(`  ✓ ${file} exists`);
      }

      // Verify scripts are executable
      const demoSh = path.join(result.path, "demo.sh");
      const setupSh = path.join(result.path, "setup.sh");
      const configureSh = path.join(result.path, "setup/configure.sh");

      const demoStat = await fs.stat(demoSh);
      const setupStat = await fs.stat(setupSh);
      const configureStat = await fs.stat(configureSh);

      if ((demoStat.mode & 0o111) !== 0) {
        console.log("  ✓ demo.sh is executable");
      } else {
        throw new Error("demo.sh is not executable");
      }

      if ((setupStat.mode & 0o111) !== 0) {
        console.log("  ✓ setup.sh is executable");
      } else {
        throw new Error("setup.sh is not executable");
      }

      if ((configureStat.mode & 0o111) !== 0) {
        console.log("  ✓ setup/configure.sh is executable");
      } else {
        throw new Error("setup/configure.sh is not executable");
      }

      testsPassed++;
    } else {
      throw new Error("Demo creation returned success: false");
    }
  } catch (err) {
    console.error(`✗ Test failed: ${err.message}`);
    testsFailed++;
  }
  console.log("");

  // Test 2: Verify duplicate detection
  console.log("Test 2: Verify duplicate detection");
  try {
    await createDemo(TEST_CATEGORY, TEST_DEMO_NAME);
    console.error("✗ Test failed: Should have thrown error for duplicate demo");
    testsFailed++;
  } catch (err) {
    if (err.message.includes("already exists")) {
      console.log("✓ Duplicate detection working correctly");
      testsPassed++;
    } else {
      console.error(`✗ Test failed with unexpected error: ${err.message}`);
      testsFailed++;
    }
  }
  console.log("");

  // Cleanup
  console.log("Cleanup:");
  await cleanupTestDemo();
  console.log("");

  // Test 3: Create demo with all options
  console.log("Test 3: Create demo with custom options");
  try {
    const result = await createDemo(TEST_CATEGORY, TEST_DEMO_NAME, {
      displayName: "MCP Test Demo",
      categoryLabel: "Utility Tools",
      description: "A comprehensive test demo for the MCP server",
      docs: "https://example.com/docs",
      demoScript: "run_demo.sh",
      setupScript: "install.sh",
    });

    if (result.success) {
      console.log("✓ Demo with custom options created successfully");

      // Verify custom info.yaml content
      const infoPath = path.join(result.path, "info.yaml");
      const infoContent = await fs.readFile(infoPath, "utf-8");

      if (infoContent.includes('Name: "MCP Test Demo"')) {
        console.log("  ✓ Custom displayName in info.yaml");
      } else {
        throw new Error("Custom displayName not found in info.yaml");
      }

      if (infoContent.includes('Category: "Utility Tools"')) {
        console.log("  ✓ Custom categoryLabel in info.yaml");
      } else {
        throw new Error("Custom categoryLabel not found in info.yaml");
      }

      if (infoContent.includes('Docs: "https://example.com/docs"')) {
        console.log("  ✓ Custom docs URL in info.yaml");
      } else {
        throw new Error("Custom docs URL not found in info.yaml");
      }

      testsPassed++;
    } else {
      throw new Error("Demo creation returned success: false");
    }
  } catch (err) {
    console.error(`✗ Test failed: ${err.message}`);
    testsFailed++;
  }
  console.log("");

  // Cleanup after test 3
  console.log("Cleanup after test 3:");
  await cleanupTestDemo();
  console.log("");

  // Test 4: Create demo safe with default safe name
  console.log("Test 4: Create demo safe with default safe name");
  try {
    // First create the demo
    await createDemo(TEST_CATEGORY, TEST_DEMO_NAME);
    const demoPath = path.join(DEMOS_BASE_DIR, TEST_CATEGORY, TEST_DEMO_NAME);
    const result = await createDemoSafe(demoPath);

    if (result.success) {
      console.log("✓ Demo safe created successfully");
      console.log(`  Path: ${result.path}`);
      console.log(`  Files: ${result.files.join(", ")}`);

      // Verify vars.env contains default safe name pattern
      const varsEnvPath = path.join(result.path, "vars.env");
      const varsContent = await fs.readFile(varsEnvPath, "utf-8");

      if (varsContent.includes('SAFE_NAME="${LAB_ID}-mcp-test-demo"')) {
        console.log(
          "  ✓ vars.env contains default safe name: ${LAB_ID}-mcp-test-demo",
        );
      } else {
        throw new Error(
          `Default safe name pattern not found in vars.env. Content: ${varsContent}`,
        );
      }

      // Verify setup.sh exists and is executable
      const setupShPath = path.join(result.path, "setup.sh");
      const setupStat = await fs.stat(setupShPath);
      if ((setupStat.mode & 0o111) !== 0) {
        console.log("  ✓ setup.sh is executable");
      } else {
        throw new Error("setup.sh is not executable");
      }

      testsPassed++;
    } else {
      throw new Error("Demo safe creation returned success: false");
    }
  } catch (err) {
    console.error(`✗ Test failed: ${err.message}`);
    testsFailed++;
  }
  console.log("");

  // Test 5: Create demo safe with custom safe name (demo already exists from test 4)
  console.log("Test 5: Create demo safe with custom safe name");
  try {
    const demoPath = path.join(DEMOS_BASE_DIR, TEST_CATEGORY, TEST_DEMO_NAME);
    // Delete existing vault directory first
    const vaultPath = path.join(demoPath, "setup", "vault");
    try {
      await fs.rm(vaultPath, { recursive: true, force: true });
    } catch (err) {
      // Ignore if doesn't exist
    }
    const result = await createDemoSafe(demoPath, "custom-safe-name");

    if (result.success) {
      console.log("✓ Demo safe created with custom name");

      // Verify vars.env contains custom safe name
      const varsEnvPath = path.join(result.path, "vars.env");
      const varsContent = await fs.readFile(varsEnvPath, "utf-8");

      if (varsContent.includes('SAFE_NAME="custom-safe-name"')) {
        console.log("  ✓ vars.env contains custom safe name: custom-safe-name");
      } else {
        throw new Error("Custom safe name not found in vars.env");
      }

      testsPassed++;
    } else {
      throw new Error("Demo safe creation returned success: false");
    }
  } catch (err) {
    console.error(`✗ Test failed: ${err.message}`);
    testsFailed++;
  }
  console.log("");

  // Test 6: Verify safe name normalization
  console.log("Test 6: Verify safe name normalization");
  try {
    // Create a temporary demo with special characters in name
    const specialDemoName = "Test Demo@123 Special!";
    const specialDemoDir = specialDemoName.toLowerCase().replace(/\s+/g, "_");
    const specialDemoPath = path.join(
      DEMOS_BASE_DIR,
      TEST_CATEGORY,
      specialDemoDir,
    );

    await fs.mkdir(specialDemoPath, { recursive: true });
    await fs.mkdir(path.join(specialDemoPath, "setup"), { recursive: true });

    const result = await createDemoSafe(specialDemoPath);

    if (result.success) {
      const varsEnvPath = path.join(result.path, "vars.env");
      const varsContent = await fs.readFile(varsEnvPath, "utf-8");

      // Expected normalized name: test_demo-123_special (underscores from directory name, other chars to hyphens)
      if (varsContent.includes('SAFE_NAME="${LAB_ID}-test-demo-123-special"')) {
        console.log(
          "  ✓ Safe name normalized correctly: ${LAB_ID}-test-demo-123-special",
        );
        testsPassed++;
      } else {
        throw new Error(`Normalization failed. Content: ${varsContent}`);
      }
    } else {
      throw new Error("Demo safe creation returned success: false");
    }

    // Cleanup special demo
    await fs.rm(specialDemoPath, { recursive: true, force: true });
    console.log("  ✓ Cleaned up special test demo");
  } catch (err) {
    console.error(`✗ Test failed: ${err.message}`);
    testsFailed++;
  }
  console.log("");

  // Final cleanup after all tests
  console.log("Final cleanup:");
  await cleanupTestDemo();
  console.log("");

  // Summary
  console.log("========================================");
  console.log("Test Summary");
  console.log("========================================");
  console.log(`Tests passed: ${testsPassed}`);
  console.log(`Tests failed: ${testsFailed}`);
  console.log("");

  if (testsFailed === 0) {
    console.log("✓ All tests passed!");
    process.exit(0);
  } else {
    console.log("✗ Some tests failed");
    process.exit(1);
  }
}

// Run tests
runTests().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
