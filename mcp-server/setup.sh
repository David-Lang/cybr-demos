#!/bin/bash

# Setup script for CyberArk Demos MCP Server

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

echo "=========================================="
echo "CyberArk Demos MCP Server Setup"
echo "=========================================="
echo ""

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    echo "Error: Node.js is not installed."
    echo ""
    echo "Please install Node.js (version 18 or higher) from:"
    echo "  https://nodejs.org/"
    echo ""
    echo "Or use a package manager:"
    echo "  macOS:   brew install node"
    echo "  Ubuntu:  sudo apt install nodejs npm"
    echo "  Windows: winget install OpenJS.NodeJS"
    echo ""
    exit 1
fi

# Check Node.js version
NODE_VERSION=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
if [ "$NODE_VERSION" -lt 18 ]; then
    echo "Warning: Node.js version 18 or higher is recommended."
    echo "Current version: $(node -v)"
    echo ""
fi

echo "Node.js version: $(node -v)"
echo "npm version: $(npm -v)"
echo ""

# Install dependencies
echo "Installing dependencies..."
npm install

echo ""
echo "=========================================="
echo "Setup completed successfully!"
echo "=========================================="
echo ""
echo "Next steps:"
echo ""
echo "1. Configure your MCP client (Claude Desktop or Zed)"
echo ""
echo "For Claude Desktop (~/.config/Claude/claude_desktop_config.json or ~/Library/Application Support/Claude/claude_desktop_config.json):"
echo ""
echo '{'
echo '  "mcpServers": {'
echo '    "cybr-demos": {'
echo '      "command": "node",'
echo '      "args": ['
echo "        \"$SCRIPT_DIR/index.js\""
echo '      ]'
echo '    }'
echo '  }'
echo '}'
echo ""
echo "For Zed (~/.config/zed/settings.json):"
echo ""
echo '{'
echo '  "context_servers": {'
echo '    "cybr-demos": {'
echo '      "command": "node",'
echo '      "args": ['
echo "        \"$SCRIPT_DIR/index.js\""
echo '      ]'
echo '    }'
echo '  }'
echo '}'
echo ""
echo "2. Restart your MCP client to load the server"
echo ""
echo "3. Test the server by asking your AI assistant to create a demo:"
echo '   "Create a new secrets_manager demo called test_demo"'
echo ""
