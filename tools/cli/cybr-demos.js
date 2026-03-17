#!/usr/bin/env node

import { runCreateDemo } from "./commands/create-demo.js";
import { runCreateDemoSafe } from "./commands/create-demo-safe.js";
import { runProvisionSafe } from "./commands/provision-safe.js";
import { runProvisionWorkload } from "./commands/provision-workload.js";
import { runValidateReadme } from "./commands/validate-readme.js";
import { printJson, printText } from "./lib/json-output.js";

function parseArgs(argv) {
  const [command, ...rest] = argv;
  const options = {};
  let json = false;

  for (let i = 0; i < rest.length; i += 1) {
    const token = rest[i];
    if (token === "--json") {
      json = true;
      continue;
    }
    if (!token.startsWith("--")) {
      throw new Error(`Unexpected argument: ${token}`);
    }
    const key = token.slice(2);
    const value = rest[i + 1];
    if (!value || value.startsWith("--")) {
      throw new Error(`Missing value for --${key}`);
    }
    options[key] = value;
    i += 1;
  }

  return { command, options, json };
}

function usage() {
  return `Usage:
  cybr-demos create-demo --category <category> --name <name> [options] [--json]
  cybr-demos create-demo-safe --demo-path <path> [options] [--json]
  cybr-demos provision-safe --demo-path <path> --safe-name <name> [options] [--json]
  cybr-demos provision-workload --demo-path <path> --safe-name <name> --workload-name <name> [--json]
  cybr-demos validate-readme --file-path <path> [--json]

Options:
  --category <value>
  --name <value>
  --display-name <value>
  --category-label <value>
  --description <value>
  --docs <value>
  --demo-script <value>
  --setup-script <value>
  --demo-path <value>
  --safe-name <value>
  --add-sync-member <true|false>
  --create-account <true|false>
  --create-accounts <true|false>
  --setup-conjur <true|false>
  --additional-vars <value>
  --workload-name <value>
  --file-path <value>
  --json
`;
}

function formatTextResult(command, result) {
  if (command === "create-demo" || command === "create-demo-safe") {
    return `Created demo assets at ${result.path}`;
  }
  if (command === "provision-safe") {
    return `Provisioned safe ${result.safeName} for ${result.demoPath}`;
  }
  if (command === "provision-workload") {
    return `Provisioned workload ${result.workloadName} for ${result.demoPath}`;
  }
  return `Validated ${result.filePath} with score ${result.score}`;
}

async function main() {
  try {
    const { command, options, json } = parseArgs(process.argv.slice(2));

    if (!command || command === "--help" || command === "help") {
      printText(usage());
      process.exit(0);
    }

    if (
      ![
        "create-demo",
        "create-demo-safe",
        "provision-safe",
        "provision-workload",
        "validate-readme",
      ].includes(command)
    ) {
      throw new Error(`Unsupported command: ${command}`);
    }

    let result;
    if (command === "create-demo") {
      result = await runCreateDemo(options);
    } else if (command === "create-demo-safe") {
      result = await runCreateDemoSafe(options);
    } else if (command === "provision-safe") {
      result = await runProvisionSafe(options);
    } else if (command === "provision-workload") {
      result = await runProvisionWorkload(options);
    } else {
      result = await runValidateReadme(options);
    }

    if (json) {
      printJson({
        success: true,
        command,
        data: result,
        warnings: [],
        errors: [],
      });
      return;
    }

    printText(formatTextResult(command, result));
  } catch (error) {
    const wantsJson = process.argv.includes("--json");
    if (wantsJson) {
      printJson({
        success: false,
        command: process.argv[2] || null,
        data: {},
        warnings: [],
        errors: [
          {
            code: "CLI_ERROR",
            message: error.message,
          },
        ],
      });
      process.exit(1);
    }

    printText(`ERROR: ${error.message}`);
    process.exit(1);
  }
}

await main();
