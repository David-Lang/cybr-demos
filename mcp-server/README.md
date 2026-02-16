# CyberArk Demos MCP Server

Model Context Protocol (MCP) server for managing the CyberArk demos project. This server provides AI assistants with tools to create and manage demo scaffolding automatically.

## 🚀 Quick Start

**New to this?** Check out [QUICKSTART.md](QUICKSTART.md) for step-by-step setup instructions!

## Overview

This MCP server gives AI assistants (like Claude or Zed) the ability to:
- Create new demos with proper scaffolding
- Generate consistent documentation templates
- Set up standard directory structures
- Create executable scripts with proper permissions

## Features

### create_demo Tool

Creates a new demo with standard scaffolding files:

- **README.md** - Documentation template with sections for About, Prerequisites, Setup, Running, Configuration, Workflow, and Examples
- **info.yaml** - Demo metadata (Category, Name, Docs URL, Script names, Enabled/Setup status)
- **demo.sh** - Executable demo script with boilerplate
- **setup.sh** - Executable setup script with boilerplate
- **setup/configure.sh** - Executable configuration script

All scripts are automatically:
- Made executable (`chmod +x`)
- Include shebang (`#!/bin/bash`)
- Source common environment variables
- Include error handling (`set -e`)
- Have descriptive headers

## Installation

### Prerequisites

- Node.js 18 or higher
- npm (comes with Node.js)
- An MCP client: [Zed](https://zed.dev/) or [Claude Desktop](https://claude.ai/desktop)

### Steps

1. **Install Node.js** (if not already installed):
   ```bash
   # macOS
   brew install node
   
   # Ubuntu/Debian
   sudo apt install nodejs npm
   
   # Windows
   winget install OpenJS.NodeJS
   ```

2. **Run setup script**:
   ```bash
   cd mcp-server
   ./setup.sh
   ```

3. **Configure your MCP client** (see Configuration section below)

4. **Restart your client** to load the MCP server

## Configuration

### Zed

Edit `~/.config/zed/settings.json` (macOS/Linux) or `%APPDATA%\Zed\settings.json` (Windows):

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

### Claude Desktop

Edit the config file:
- **macOS**: `~/Library/Application Support/Claude/claude_desktop_config.json`
- **Windows**: `%APPDATA%\Claude\claude_desktop_config.json`

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

**Important:** Use absolute paths! Get yours with:
```bash
cd /path/to/cybr-demos/mcp-server && pwd
```

Example config files are provided:
- [claude_desktop_config.example.json](claude_desktop_config.example.json)
- [zed_settings.example.json](zed_settings.example.json)

## Usage

Once configured, ask your AI assistant to create demos:

### Basic Examples

```
Create a new secrets_manager demo called "AWS Lambda Integration"
```

```
Create a credential_providers demo named "PSM for SSH"
```

### Advanced Examples

```
Create a secrets_hub demo called "Azure Key Vault Sync" with:
- Display name: "Azure Key Vault Synchronization"
- Description: "Demonstrates bidirectional sync between Secrets Hub and Azure Key Vault"
- Category label: "Secrets Hub"
```

### Tool Parameters

**Required:**
- `category` - Demo category (see Categories section)
- `name` - Demo name (converted to lowercase with underscores for directory)

**Optional:**
- `displayName` - Display name in README and info.yaml (defaults to name)
- `categoryLabel` - Custom category label for info.yaml (defaults to category)
- `description` - Description for README About section
- `docs` - Documentation URL (defaults to CyberArk docs portal)
- `demoScript` - Demo script filename (defaults to "demo.sh")
- `setupScript` - Setup script filename (defaults to "setup.sh")

## Categories

- **`credential_providers`** - CyberArk Credential Providers (CCP, CP Agent, etc.)
- **`secrets_manager`** - Conjur/Secrets Manager integrations (K8s, Jenkins, etc.)
- **`secrets_hub`** - Secrets Hub integrations (AWS, Azure, HashiCorp, etc.)
- **`utility`** - Utility demos and helper tools

## Project Structure

Created demos follow this structure:

```
demos/{category}/{demo_name}/
├── README.md              # Documentation
├── info.yaml             # Metadata
├── demo.sh               # Demo execution script (executable)
├── setup.sh              # Setup script (executable)
└── setup/
    └── configure.sh      # Configuration script (executable)
```

### Generated README Template

Each README includes:
- **About** - Description of the demo
- **Prerequisites** - Required setup/dependencies
- **Setup** - Installation instructions
- **Running the Demo** - How to execute
- **Configuration** - Configuration details
- **Workflow** - Architecture/sequence diagrams
- **Example** - Sample commands and output

### Generated info.yaml

```yaml
Category: "Conjur Cloud"
Name: "EKS K8s"
Docs: "https://docs.cyberark.com/portal/latest/en/docs.htm"
DemoScript: "demo.sh"
SetupScript: "setup.sh"
Enabled: false
IsSetup: false
```

### Generated Scripts

All scripts include:
- Proper shebang (`#!/bin/bash`)
- Error handling (`set -e`)
- Environment variable sourcing (tenant_vars.sh)
- Descriptive headers and comments
- Echo statements for user feedback
- Executable permissions

## Development

### Running Locally

```bash
npm start
```

The server communicates via stdio using the Model Context Protocol.

### Testing

Test the create_demo function:

```bash
node -e "
const { createDemo } = require('./index.js');
createDemo('utility', 'test_demo', {
  displayName: 'Test Demo',
  description: 'A test demo'
}).then(console.log);
"
```

### Modifying Templates

Edit `index.js` and modify the template strings in the `createDemo` function:
- `infoYaml` - info.yaml template
- `readme` - README.md template
- `demoScript` - demo.sh template
- `setupScript` - setup.sh template
- `configureScript` - setup/configure.sh template

## Troubleshooting

### Server Not Loading

1. **Check Node.js installation:**
   ```bash
   node -v  # Should be 18+
   npm -v
   ```

2. **Verify config path is absolute:**
   ```bash
   cd mcp-server && pwd
   # Use this full path in your config
   ```

3. **Check client logs:**
   - Zed: `~/Library/Logs/Zed/Zed.log` (macOS)
   - Claude: Check Console/Developer Tools

### Permission Issues

```bash
chmod +x setup.sh
chmod +x index.js
```

### Demo Already Exists

The server prevents overwriting existing demos. Delete or rename the existing demo first.

## Architecture

```
┌─────────────────┐
│   MCP Client    │
│ (Zed/Claude)    │
└────────┬────────┘
         │ stdio
         │ MCP Protocol
┌────────▼────────┐
│   MCP Server    │
│   (Node.js)     │
└────────┬────────┘
         │ filesystem
┌────────▼────────┐
│  demos/         │
│  ├─ category1/  │
│  └─ category2/  │
└─────────────────┘
```

## Resources

- [Model Context Protocol Spec](https://modelcontextprotocol.io/)
- [MCP SDK Documentation](https://github.com/modelcontextprotocol/typescript-sdk)
- [CyberArk Documentation](https://docs.cyberark.com/)

## License

MIT

## Contributing

To add new tools:

1. Add tool definition in `ListToolsRequestSchema` handler
2. Implement tool logic in `CallToolRequestSchema` handler
3. Update README with tool documentation
4. Test with MCP client

## Support

For issues or questions:
1. Check [QUICKSTART.md](QUICKSTART.md)
2. Review this README
3. Check MCP client logs
4. Verify Node.js version and paths

---

**Built with ❤️ for the CyberArk Demos Project**