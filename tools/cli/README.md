# CyberArk Demos CLI

This CLI is the implementation layer behind the MCP server.

## Purpose

- Keep demo scaffolding and execution logic out of `mcp-server/index.js`
- Provide a stable repo-native interface for humans, MCP clients, and future CI jobs
- Make templates, command behavior, and JSON responses testable without running the MCP transport

## Current Commands

- `create-demo`
- `create-demo-safe`
- `provision-safe`
- `provision-workload`
- `validate-readme`

## Usage

Run from the repo root:

```bash
node tools/cli/cybr-demos.js --help
```

Examples:

```bash
node tools/cli/cybr-demos.js create-demo \
  --category secrets_manager \
  --name summon_aws_auth \
  --json
```

```bash
node tools/cli/cybr-demos.js validate-readme \
  --file-path demo_md_guidelines.md \
  --json
```

## JSON Contract

All commands support `--json`.

Success shape:

```json
{
  "success": true,
  "command": "create-demo",
  "data": {},
  "warnings": [],
  "errors": []
}
```

Failure shape:

```json
{
  "success": false,
  "command": "create-demo",
  "data": {},
  "warnings": [],
  "errors": [
    {
      "code": "CLI_ERROR",
      "message": "..."
    }
  ]
}
```

## Repo Conventions

- Use template files under `tools/templates/`
- Keep demo-specific config in shared `setup/vars.env`
- Treat the CLI as the source of truth for command behavior
- Keep `mcp-server/` as a thin adapter that shells out to the CLI

## Smoke Test

Run:

```bash
cd tools/cli
npm run smoke
```

The smoke test validates the CLI JSON contract and basic template-backed generation using a temporary repo root.
