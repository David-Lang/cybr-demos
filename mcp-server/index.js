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
import { execFile } from "child_process";
import { promisify } from "util";
import { randomUUID } from "crypto";

const execFileAsync = promisify(execFile);

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Base directory for demos - go up one level from mcp-server to cybr-demos
const DEMOS_BASE_DIR = path.resolve(__dirname, "..", "demos");
const CLI_ENTRYPOINT = path.resolve(
  __dirname,
  "..",
  "tools",
  "cli",
  "cybr-demos.js",
);
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
async function createDemoViaCli(category, name, options = {}) {
  return runCliCommand("create-demo", {
    category,
    name,
    displayName: options.displayName,
    categoryLabel: options.categoryLabel,
    description: options.description,
    docs: options.docs,
    demoScript: options.demoScript,
    setupScript: options.setupScript,
  });
}

async function createDemoSafeViaCli(demoPath, safeName, options = {}) {
  return runCliCommand("create-demo-safe", {
    demoPath,
    safeName,
    addSyncMember: options.addSyncMember,
    createAccount: options.createAccount,
    setupConjur: options.setupConjur,
    additionalVars: options.additionalVars,
  });
}

async function provisionSafeViaCli(demoPath, safeName, options = {}) {
  return runCliCommand("provision-safe", {
    demoPath,
    safeName,
    addSyncMember: options.addSyncMember,
    createAccounts: options.createAccounts,
    setupConjur: options.setupConjur,
  });
}

async function provisionWorkloadViaCli(
  demoPath,
  safeName,
  workloadName,
  options = {},
) {
  return runCliCommand("provision-workload", {
    demoPath,
    safeName,
    workloadName,
    ...options,
  });
}

async function validateReadmeViaCli(filePath) {
  return runCliCommand("validate-readme", {
    filePath,
  });
}

async function runCliCommand(command, options = {}) {
  const cliArgs = [CLI_ENTRYPOINT, command];

  const optionMap = [
    ["category", "--category"],
    ["name", "--name"],
    ["displayName", "--display-name"],
    ["categoryLabel", "--category-label"],
    ["description", "--description"],
    ["docs", "--docs"],
    ["demoScript", "--demo-script"],
    ["setupScript", "--setup-script"],
    ["demoPath", "--demo-path"],
    ["safeName", "--safe-name"],
    ["addSyncMember", "--add-sync-member"],
    ["createAccount", "--create-account"],
    ["createAccounts", "--create-accounts"],
    ["setupConjur", "--setup-conjur"],
    ["additionalVars", "--additional-vars"],
    ["workloadName", "--workload-name"],
    ["filePath", "--file-path"],
  ];

  for (const [inputKey, cliFlag] of optionMap) {
    if (options[inputKey] !== undefined) {
      cliArgs.push(cliFlag, String(options[inputKey]));
    }
  }

  cliArgs.push("--json");

  const { stdout, stderr } = await execFileAsync(process.execPath, cliArgs, {
    cwd: path.resolve(__dirname, ".."),
    env: process.env,
  });

  if (stderr && stderr.trim()) {
    console.error(stderr.trim());
  }

  let parsed;
  try {
    parsed = JSON.parse(stdout);
  } catch (error) {
    throw new Error(`Failed to parse CLI output: ${error.message}`);
  }

  if (!parsed.success) {
    const firstError = parsed.errors?.[0]?.message || "CLI command failed";
    throw new Error(firstError);
  }

  return parsed.data;
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
      return createDemoViaCli(category, name, options);
    });
  }

  if (toolName === "create_demo_safe") {
    return executeWithContract(toolName, args, async (params) => {
      const { demoPath, safeName, ...options } = params;
      return createDemoSafeViaCli(demoPath, safeName, options);
    });
  }

  if (toolName === "provision_safe") {
    return executeWithContract(toolName, args, async (params) => {
      const { demoPath, safeName, ...options } = params;
      return provisionSafeViaCli(demoPath, safeName, options);
    });
  }

  if (toolName === "provision_workload") {
    return executeWithContract(toolName, args, async (params) => {
      const { demoPath, safeName, workloadName, ...options } = params;
      return provisionWorkloadViaCli(demoPath, safeName, workloadName, options);
    });
  }

  if (toolName === "validate_readme") {
    return executeWithContract(toolName, args, async (params) => {
      const { filePath } = params;
      return validateReadmeViaCli(filePath);
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
