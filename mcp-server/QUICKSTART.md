# Quickstart Guide

## New Feature: Automatic Safe Name Generation

The `create_demo_safe` tool now automatically generates safe names using your `LAB_ID` environment variable!

### Default Behavior

When you don't specify a `safeName`, the tool will automatically generate one using the pattern:
```
${LAB_ID}-{demo-name}
```

Where:
- `LAB_ID` is your lab environment identifier (set in `demos/tenant_vars.sh`)
- `demo-name` is extracted from your demo path and normalized (lowercase, spaces and non-alphanumeric chars → hyphens)

### Examples

| Demo Path | Generated Safe Name |
|-----------|---------------------|
| `secrets_manager/azure_devops` | `${LAB_ID}-azure-devops` |
| `secrets_manager/k8s` | `${LAB_ID}-k8s` |
| `secrets_hub/aws_secrets_manager` | `${LAB_ID}-aws-secrets-manager` |

### Setup

1. Set your `LAB_ID` in `demos/tenant_vars.sh`:
   ```bash
   export LAB_ID="poc"  # or "lab01", "demo", etc.
   ```

2. Create a demo safe without specifying the name:
   ```
   Create a demo safe for secrets_manager/azure_devops
   ```
   
   This will use `${LAB_ID}-azure-devops` as the safe name.

3. Or override with a custom name:
   ```
   Create a demo safe for secrets_manager/azure_devops with safe name "my-custom-safe"
   ```

---

# Quickstart Guide

Get the CyberArk Demos MCP Server up and running in minutes!

## Prerequisites

- Node.js 18 or higher
- npm (comes with Node.js)
- An MCP-compatible client (Claude Desktop or Zed)

## Installation

### Step 1: Install Node.js

If you don't have Node.js installed:

**macOS (using Homebrew):**
```bash
brew install node
```

**macOS/Linux (using nvm - recommended):**
```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
nvm install 20
nvm use 20
```

**Windows:**
- Download from https://nodejs.org/
- Or use: `winget install OpenJS.NodeJS`

### Step 2: Run Setup

Navigate to the mcp-server directory and run the setup script:

```bash
cd mcp-server
./setup.sh
```

This will install all required dependencies.

### Step 3: Configure Your Client

#### For Zed (Recommended)

1. Open Zed
2. Press `Cmd+Shift+P` (macOS) or `Ctrl+Shift+P` (Windows/Linux)
3. Type "zed: open settings" and press Enter
4. Add this configuration to your `settings.json`:

```json
{
  "context_servers": {
    "cybr-demos": {
      "command": "node",
      "args": [
        "/absolute/path/to/cybr-demos/mcp-server/index.js"
      ]
    }
  }
}
```

**Important:** Replace `/absolute/path/to/cybr-demos` with your actual project path!

You can get the absolute path by running:
```bash
cd cybr-demos/mcp-server
pwd
```

#### For Claude Desktop

1. Open the config file:
   - **macOS:** `~/Library/Application Support/Claude/claude_desktop_config.json`
   - **Windows:** `%APPDATA%\Claude\claude_desktop_config.json`

2. Add this configuration:

```json
{
  "mcpServers": {
    "cybr-demos": {
      "command": "node",
      "args": [
        "/absolute/path/to/cybr-demos/mcp-server/index.js"
      ]
    }
  }
}
```

### Step 4: Restart Your Client

Restart Zed or Claude Desktop to load the MCP server.

### Step 5: Test It!

In Zed's AI assistant or Claude Desktop, try:

```
Create a new secrets_manager demo called "test demo"
```

The MCP server will create a new demo with all the scaffolding files!

## What Gets Created

When you create a demo, the following structure is generated:

```
demos/{category}/{demo_name}/
├── README.md              # Documentation template
├── info.yaml             # Metadata (Category, Name, Docs, etc.)
├── demo.sh               # Executable demo script
├── setup.sh              # Executable setup script
└── setup/
    └── configure.sh      # Executable configuration script
```

All scripts are automatically made executable.

## Usage Examples

### Basic Demo Creation

```
Create a secrets_manager demo named "AWS Lambda"
```

### Demo with Custom Options

```
Create a secrets_hub demo called "HashiCorp Vault Integration" with description "Demonstrates integration between CyberArk Secrets Hub and HashiCorp Vault for secrets synchronization"
```

### Available Categories

- `credential_providers` - CCP, CP Agent demos
- `secrets_manager` - Conjur/Secrets Manager integrations
- `secrets_hub` - Secrets Hub integrations
- `utility` - Utility demos and tools

## Troubleshooting

### "Node.js is not installed"

Run the setup script to see installation instructions:
```bash
./setup.sh
```

### MCP Server Not Showing in Client

1. Check that the path in your config is absolute and correct
2. Make sure you restarted the client after adding the config
3. Check the client's logs for errors

**Zed logs location:**
- macOS: `~/Library/Logs/Zed/Zed.log`
- Linux: `~/.local/share/zed/logs/`
- Windows: `%APPDATA%\Zed\logs\`

### Permission Denied

Make sure the setup script is executable:
```bash
chmod +x setup.sh
```

## Next Steps

- Read the full [README.md](README.md) for detailed documentation
- Explore existing demos in the `demos/` directory
- Customize the templates in `index.js` to match your team's conventions

## Getting Help

If you encounter issues:
1. Check the troubleshooting section above
2. Review the MCP server logs
3. Verify your Node.js version: `node -v` (should be 18+)
4. Ensure all paths in config files are absolute paths

Happy demo building!
