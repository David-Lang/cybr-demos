import { access, chmod, mkdir, readFile, writeFile } from "fs/promises";
import path from "path";
import { getDemosBaseDir, getTemplatesBaseDir } from "../lib/repo-paths.js";
import { renderTemplate } from "../lib/templates.js";
import { parseBoolean, requireOption } from "../lib/options.js";

function normalizeDemoName(demoPath) {
  return path
    .basename(demoPath)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}

async function loadTemplate(name) {
  const templatePath = path.join(getTemplatesBaseDir(), "safe", name);
  return readFile(templatePath, "utf8");
}

export async function runCreateDemoSafe(options) {
  const demoPath = requireOption(options, "demo-path");
  const fullDemoPath = path.join(getDemosBaseDir(), demoPath);

  try {
    await access(fullDemoPath);
  } catch {
    throw new Error(`Demo path does not exist: ${demoPath}`);
  }

  const normalizedName = normalizeDemoName(demoPath);
  const safeName = options["safe-name"] || `\${LAB_ID}-${normalizedName}`;
  const addSyncMember =
    options["add-sync-member"] === undefined
      ? demoPath.startsWith("secrets_manager/")
      : parseBoolean(options["add-sync-member"], "add-sync-member");
  const createAccount = parseBoolean(
    options["create-account"],
    "create-account",
  );
  const setupConjur = parseBoolean(options["setup-conjur"], "setup-conjur");
  const additionalVars =
    options["additional-vars"] || "# Add additional environment variables here";

  const setupDir = path.join(fullDemoPath, "setup");
  const vaultDir = path.join(setupDir, "vault");
  await mkdir(vaultDir, { recursive: true });

  const varsTemplate = await loadTemplate("vars.env.tmpl");
  const varsContent = renderTemplate(varsTemplate, {
    SAFE_NAME: safeName,
    ADDITIONAL_VARS: additionalVars,
  });
  const varsPath = path.join(setupDir, "vars.env");
  await writeFile(varsPath, varsContent, "utf8");

  const setupTemplate = await loadTemplate("vault.setup.sh.tmpl");
  const setupContent = renderTemplate(setupTemplate, {
    ADD_SYNC_MEMBER_BLOCK: addSyncMember
      ? 'add_safe_read_member "$isp_subdomain" "$identity_token" "$safe_name" "Conjur Sync"'
      : "",
    CREATE_ACCOUNT_BLOCK: createAccount
      ? 'create_account_ssh_user_1 "$isp_subdomain" "$identity_token" "$safe_name"'
      : "",
    SETUP_CONJUR_BLOCK: setupConjur
      ? [
          'conjur_token=$(get_conjur_token "$isp_subdomain" "$identity_token")',
          'printf "Waiting for synchronizer (vault/%s/delegation/consumers)\\n" "$safe_name"',
          'wait_for_synchronizer "$isp_subdomain" "$conjur_token" "$safe_name"',
        ].join("\n")
      : "",
  });
  const setupPath = path.join(vaultDir, "setup.sh");
  await writeFile(setupPath, setupContent, "utf8");
  await chmod(setupPath, 0o755);

  return {
    path: setupDir,
    files: ["vars.env", "vault/setup.sh"],
    safeName,
  };
}
