import path from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const defaultRepoRoot = path.resolve(__dirname, "..", "..", "..");

export function getRepoRoot() {
  return process.env.CYBR_DEMOS_REPO_ROOT || defaultRepoRoot;
}

export function getDemosBaseDir() {
  return path.join(getRepoRoot(), "demos");
}

export function getTemplatesBaseDir() {
  return path.join(getRepoRoot(), "tools", "templates");
}
