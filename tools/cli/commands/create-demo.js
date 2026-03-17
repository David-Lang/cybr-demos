import { mkdir, access, writeFile, chmod, readFile } from "fs/promises";
import path from "path";
import {
  getRepoRoot,
  getDemosBaseDir,
  getTemplatesBaseDir,
} from "../lib/repo-paths.js";
import { renderTemplate } from "../lib/templates.js";
import { requireOption } from "../lib/options.js";

const CATEGORIES = new Set([
  "credential_providers",
  "secrets_manager",
  "secrets_hub",
  "utility",
]);

function normalizeDemoDir(name) {
  return name.toLowerCase().replace(/\s+/g, "_");
}

async function loadTemplate(name) {
  const templatePath = path.join(getTemplatesBaseDir(), "demo", name);
  return readFile(templatePath, "utf8");
}

export async function runCreateDemo(options) {
  const category = requireOption(options, "category");
  const name = requireOption(options, "name");

  if (!CATEGORIES.has(category)) {
    throw new Error(`Invalid category: ${category}`);
  }

  const displayName = options["display-name"] || name;
  const demoDir = normalizeDemoDir(name);
  const demoPath = path.join(getDemosBaseDir(), category, demoDir);

  try {
    await access(demoPath);
    throw new Error(`Demo already exists at: ${demoPath}`);
  } catch (error) {
    if (error.code !== "ENOENT") {
      throw error;
    }
  }

  const setupPath = path.join(demoPath, "setup");
  await mkdir(setupPath, { recursive: true });

  const templateValues = {
    CATEGORY: category,
    CATEGORY_LABEL: options["category-label"] || category,
    DEMO_NAME: name,
    DEMO_DIR: demoDir,
    DISPLAY_NAME: displayName,
    DESCRIPTION: options.description || "Description of this demo.",
    DOCS: options.docs || "https://docs.cyberark.com/portal/latest/en/docs.htm",
    DEMO_SCRIPT: options["demo-script"] || "demo.sh",
    SETUP_SCRIPT: options["setup-script"] || "setup.sh",
  };

  const files = [
    ["info.yaml", "info.yaml.tmpl", false],
    ["README.md", "README.md.tmpl", false],
    [templateValues.DEMO_SCRIPT, "demo.sh.tmpl", true],
    [templateValues.SETUP_SCRIPT, "setup.sh.tmpl", true],
    ["setup/configure.sh", "configure.sh.tmpl", true],
  ];

  for (const [relativeTarget, templateName, executable] of files) {
    const template = await loadTemplate(templateName);
    const content = renderTemplate(template, templateValues);
    const targetPath = path.join(demoPath, relativeTarget);
    await writeFile(targetPath, content, "utf8");
    if (executable) {
      await chmod(targetPath, 0o755);
    }
  }

  return {
    repoRoot: getRepoRoot(),
    path: demoPath,
    files: files.map(([relativeTarget]) => relativeTarget),
  };
}
