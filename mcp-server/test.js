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

  // Final cleanup
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
