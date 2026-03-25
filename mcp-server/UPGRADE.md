# Upgrade Guide: MCP Server v1.1.0

This guide will help you upgrade to MCP Server v1.1.0 with the new `provision_safe` tool.

## What's New in v1.1.0

🎉 **New Tool: `provision_safe`** - Automatically provision safes in CyberArk Privilege Cloud via API!

### New Capabilities

- ✅ Create safes directly from your AI assistant
- ✅ Add Conjur Sync members automatically
- ✅ Create test accounts
- ✅ Wait for Conjur synchronization
- ✅ No manual steps required!

Also includes:
- ✅ `create_demo_safe` - Generate safe setup scripts
- ✅ Comprehensive documentation
- ✅ Quick start guides

## Prerequisites for Upgrade

### 1. Verify Node.js Version

```bash
node -v
# Should be v18.0.0 or higher
```

If you need to upgrade Node.js:

```bash
# macOS
brew upgrade node

# Ubuntu/Debian
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

# Windows
winget upgrade OpenJS.NodeJS
```

### 2. Backup Current Configuration

Before upgrading, save your current MCP client configuration:

**For Claude Desktop:**
```bash
cp ~/Library/Application\ Support/Claude/claude_desktop_config.json \
   ~/Library/Application\ Support/Claude/claude_desktop_config.json.backup
```

**For Zed:**
```bash
cp ~/.config/zed/settings.json ~/.config/zed/settings.json.backup
```

## Upgrade Steps

### Step 1: Pull Latest Changes

```bash
cd /path/to/cybr-demos
git pull origin main
# or
git pull origin core-demos
```

### Step 2: Install Dependencies

The new tool doesn't require additional npm packages, but verify your installation:

```bash
cd mcp-server
npm install
```

### Step 3: Set Environment Variable

Add to your shell profile (`~/.bashrc`, `~/.zshrc`, or `~/.profile`):

```bash
export CYBR_DEMOS_PATH="/full/path/to/cybr-demos"
```

Then reload:
```bash
source ~/.bashrc  # or ~/.zshrc
```

Verify:
```bash
echo $CYBR_DEMOS_PATH
# Should print: /full/path/to/cybr-demos
```

### Step 4: Configure CyberArk Credentials

Edit `demos/tenant_vars.sh`:

```bash
cd /path/to/cybr-demos
nano demos/tenant_vars.sh
```

Add your credentials:

```bash
# CyberArk Identity
export TENANT_ID="abc12345"
export TENANT_SUBDOMAIN="yourcompany"
export CLIENT_ID="your-client-id@cyberark.cloud.12345"
export CLIENT_SECRET="your-client-secret"
```

**Where to find these:**
1. Log in to CyberArk Identity Portal
2. Navigate to **Applications**
3. Create or select an OAuth Confidential Client
4. Copy Client ID and Secret
5. Your subdomain is in your Privilege Cloud URL: `https://SUBDOMAIN.privilegecloud.cyberark.cloud`

### Step 5: Test Your Setup

```bash
source demos/tenant_vars.sh
echo $TENANT_ID
echo $TENANT_SUBDOMAIN
echo $CLIENT_ID
```

All should print your values (not empty).

### Step 6: Restart MCP Client

**Claude Desktop:**
1. Fully quit Claude Desktop (Cmd+Q on macOS)
2. Reopen Claude Desktop
3. The new tools will be available

**Zed:**
1. Open Command Palette (Cmd+Shift+P)
2. Type: "zed: reload extensions"
3. Press Enter

OR simply quit and restart Zed.

### Step 7: Verify Tools Are Available

In your AI assistant, ask:

```
What MCP tools do you have available?
```

You should see:
- ✅ `create_demo`
- ✅ `create_demo_safe` (NEW!)
- ✅ `provision_safe` (NEW!)

## Testing the New Tool

### Quick Test

Try creating a test safe:

```
Provision a safe for secrets_manager/test with safe name "poc-upgrade-test"
```

Expected output:
```
========================================
Provisioning Safe: poc-upgrade-test
========================================

Authenticating to Identity...
✓ Authentication successful

Creating safe: poc-upgrade-test...
✓ Safe created

Adding admin role...
✓ Admin role added

========================================
Safe provisioning completed successfully!
========================================
```

### Verify in UI

1. Log in to CyberArk Privilege Cloud
2. Go to **Policies** → **Safes**
3. Find "poc-upgrade-test"
4. Verify it exists with admin permissions

### Clean Up Test Safe

```
Delete safe "poc-upgrade-test" from CyberArk UI
```

(Note: Safe deletion via API will be added in a future release)

## Troubleshooting Upgrade Issues

### Issue: Tool Not Available After Restart

**Symptoms:**
```
No tool named provision_safe exists
```

**Solution:**
1. Verify MCP server is running:
   ```bash
   cd cybr-demos/mcp-server
   node index.js
   # Should output: CyberArk Demos MCP Server running on stdio
   # Press Ctrl+C to stop
   ```

2. Check MCP client configuration has correct path
3. Try starting a **new conversation** (tools may not load in existing ones)
4. Fully restart your MCP client

### Issue: Authentication Errors

**Symptoms:**
```
ERROR: Failed to get identity token
```

**Solution:**
1. Verify credentials in `demos/tenant_vars.sh`
2. Test manually:
   ```bash
   source demos/tenant_vars.sh
   source demos/setup_env.sh
   get_identity_token "$TENANT_ID" "$CLIENT_ID" "$CLIENT_SECRET"
   ```
3. Check network connectivity to CyberArk cloud
4. Verify OAuth client is active in Identity portal

### Issue: CYBR_DEMOS_PATH Not Set

**Symptoms:**
```
CYBR_DEMOS_PATH: unbound variable
```

**Solution:**
1. Add to shell profile:
   ```bash
   echo 'export CYBR_DEMOS_PATH="/path/to/cybr-demos"' >> ~/.bashrc
   source ~/.bashrc
   ```

2. Verify:
   ```bash
   echo $CYBR_DEMOS_PATH
   ```

3. Restart MCP client after setting

### Issue: Demo Path Not Found

**Symptoms:**
```
Demo path does not exist: secrets_manager/azure_devops
```

**Solution:**
Create the demo first:
```
Create a secrets_manager demo called "azure_devops"
```

Then provision the safe.

### Issue: Safe Already Exists

**Symptoms:**
```
Failed to provision safe: Safe already exists
```

**Solution:**
Either:
1. Use a different safe name: `poc-azure-devops-v2`
2. Delete the existing safe from Privilege Cloud UI
3. Check if safe was created in previous attempt

## Rolling Back

If you need to roll back to v1.0.0:

### Step 1: Checkout Previous Version

```bash
cd /path/to/cybr-demos
git checkout v1.0.0
```

### Step 2: Restore Backup Configuration

**Claude Desktop:**
```bash
cp ~/Library/Application\ Support/Claude/claude_desktop_config.json.backup \
   ~/Library/Application\ Support/Claude/claude_desktop_config.json
```

**Zed:**
```bash
cp ~/.config/zed/settings.json.backup ~/.config/zed/settings.json
```

### Step 3: Restart MCP Client

Quit and restart your MCP client.

## What Changed Under the Hood

### Code Changes

**mcp-server/index.js:**
- Added `child_process` and `util` imports
- New function: `provisionSafe()`
- New function: `createDemoSafe()`
- New tool handlers in `ListToolsRequestSchema`
- New tool handlers in `CallToolRequestSchema`

### New Files

- `mcp-server/TOOLS.md` - Comprehensive tool documentation
- `mcp-server/QUICKSTART_PROVISION.md` - Provisioning guide
- `mcp-server/CHANGELOG.md` - Version history
- `mcp-server/SUMMARY.md` - Feature summary
- `mcp-server/UPGRADE.md` - This file

### API Dependencies

The new `provision_safe` tool depends on utility functions in:
- `demos/setup_env.sh`
- `demos/utility/ubuntu/identity_functions.sh`
- `demos/utility/ubuntu/privilege_functions.sh`
- `demos/utility/ubuntu/conjur_functions.sh`

These should already exist in your repo.

## Migration Checklist

Use this checklist to track your upgrade:

- [ ] Backed up MCP client configuration
- [ ] Pulled latest code changes
- [ ] Verified Node.js version (18+)
- [ ] Set `CYBR_DEMOS_PATH` environment variable
- [ ] Configured credentials in `demos/tenant_vars.sh`
- [ ] Tested credential sourcing
- [ ] Restarted MCP client
- [ ] Verified new tools are available
- [ ] Tested safe provisioning
- [ ] Verified safe in Privilege Cloud UI
- [ ] Cleaned up test safe
- [ ] Read documentation (TOOLS.md, QUICKSTART_PROVISION.md)

## Getting Help

If you encounter issues during upgrade:

1. ✅ Check this upgrade guide's troubleshooting section
2. ✅ Review [TOOLS.md](TOOLS.md) for detailed tool documentation
3. ✅ Read [QUICKSTART_PROVISION.md](QUICKSTART_PROVISION.md) for usage examples
4. ✅ Check [CHANGELOG.md](CHANGELOG.md) for all changes
5. ✅ Verify environment setup and credentials
6. ✅ Check MCP client logs for errors

## Post-Upgrade Next Steps

Now that you're upgraded:

### 1. Explore the New Tool

Try provisioning safes for your existing demos:

```
Provision a safe for secrets_manager/k8s with:
- Safe name: "poc-k8s-test"
- Add sync member: true
- Create accounts: true
```

### 2. Update Your Workflows

Replace manual safe creation steps with the new tool:

**Before (Manual):**
1. Log in to Privilege Cloud UI
2. Navigate to Safes
3. Click "Create Safe"
4. Fill in form
5. Add members manually
6. Create accounts manually

**After (Automated):**
1. Ask AI to provision safe
2. Done!

### 3. Create Safe Setup Scripts

For demos that need repeatable setup:

```
Create a demo safe for secrets_manager/my_demo with:
- Safe name: "poc-my-demo"
- Create accounts script: true
```

This generates scripts you can commit to your repo.

### 4. Share with Your Team

The new tools make onboarding easier! Team members can:
- Clone the repo
- Configure their credentials
- Provision safes instantly

## Feedback

We'd love to hear about your experience with v1.1.0!

- 💡 Feature requests
- 🐛 Bug reports  
- 📝 Documentation improvements
- ✨ Success stories

## What's Next?

Future releases may include:

- `delete_safe` - Delete safes via API
- `provision_app_id` - Create Application IDs
- `list_safes` - List all safes
- `create_conjur_policy` - Generate policies
- `create_k8s_manifests` - Generate K8s configs

Stay tuned!

---

**Happy upgrading! 🚀**

Version: 1.1.0  
Last Updated: February 13, 2024