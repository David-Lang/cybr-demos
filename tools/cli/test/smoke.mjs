import assert from "node:assert/strict";
import { mkdtemp, mkdir, cp, readFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { fileURLToPath } from "node:url";

const execFileAsync = promisify(execFile);
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, "..", "..", "..");
const cliEntrypoint = path.join(repoRoot, "tools", "cli", "cybr-demos.js");

async function runCli(args, extraEnv = {}) {
  try {
    const { stdout } = await execFileAsync(
      process.execPath,
      [cliEntrypoint, ...args],
      {
        cwd: repoRoot,
        env: {
          ...process.env,
          ...extraEnv,
        },
      },
    );
    return JSON.parse(stdout);
  } catch (error) {
    if (error.stdout) {
      return JSON.parse(error.stdout);
    }
    throw error;
  }
}

async function main() {
  const tempRoot = await mkdtemp(path.join(os.tmpdir(), "cybr-demos-cli-"));

  await mkdir(
    path.join(tempRoot, "demos", "secrets_manager", "sample_demo", "setup"),
    {
      recursive: true,
    },
  );
  await cp(
    path.join(repoRoot, "tools", "templates"),
    path.join(tempRoot, "tools", "templates"),
    {
      recursive: true,
    },
  );

  const env = {
    CYBR_DEMOS_REPO_ROOT: tempRoot,
  };

  const createDemoResult = await runCli(
    ["create-demo", "--category", "utility", "--name", "Sample Demo", "--json"],
    env,
  );
  assert.equal(createDemoResult.success, true);
  assert.equal(createDemoResult.command, "create-demo");
  assert.ok(
    createDemoResult.data.files.includes("README.md"),
    "create-demo should report generated files",
  );

  const createSafeResult = await runCli(
    [
      "create-demo-safe",
      "--demo-path",
      "secrets_manager/sample_demo",
      "--safe-name",
      "test-safe",
      "--add-sync-member",
      "true",
      "--create-account",
      "true",
      "--setup-conjur",
      "true",
      "--additional-vars",
      'AWS_REGION="us-east-1"',
      "--json",
    ],
    env,
  );
  assert.equal(createSafeResult.success, true);
  assert.equal(createSafeResult.command, "create-demo-safe");
  assert.deepEqual(createSafeResult.data.files, ["vars.env", "vault/setup.sh"]);

  const varsEnv = await readFile(
    path.join(
      tempRoot,
      "demos",
      "secrets_manager",
      "sample_demo",
      "setup",
      "vars.env",
    ),
    "utf8",
  );
  assert.match(varsEnv, /SAFE_NAME="test-safe"/);
  assert.match(varsEnv, /AWS_REGION="us-east-1"/);

  const validateResult = await runCli(
    ["validate-readme", "--file-path", "demo_md_guidelines.md", "--json"],
    {
      CYBR_DEMOS_REPO_ROOT: path.join(repoRoot),
    },
  );
  assert.equal(validateResult.success, true);
  assert.equal(validateResult.command, "validate-readme");
  assert.equal(validateResult.data.passed, true);

  const provisionError = await runCli(["provision-safe", "--json"], env);
  assert.equal(provisionError.success, false);
  assert.equal(provisionError.errors[0].code, "CLI_ERROR");

  process.stdout.write("CLI smoke test passed\n");
}

main().catch((error) => {
  process.stderr.write(`${error.stack || error.message}\n`);
  process.exit(1);
});
