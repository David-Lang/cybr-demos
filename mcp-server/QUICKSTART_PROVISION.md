# Quick Start: Provisioning Safes with MCP

This guide shows you how to use the `provision_safe` MCP tool to automatically create safes in CyberArk Privilege Cloud.

## What is provision_safe?

The `provision_safe` tool is an MCP server capability that allows you to create safes and accounts in CyberArk Privilege Cloud directly through your AI assistant (Claude or Zed). **No manual steps required** - just ask and it provisions!

## Prerequisites

### 1. Environment Setup

Ensure `CYBR_DEMOS_PATH` is set:

```bash
export CYBR_DEMOS_PATH="/path/to/cybr-demos"
```

Add to your `~/.bashrc` or `~/.zshrc` to make it permanent.

### 2. Configure Tenant Credentials

Edit `demos/tenant_vars.sh` with your CyberArk Privilege Cloud credentials:

```bash
# CyberArk Identity
export TENANT_ID="abc12345"
export TENANT_SUBDOMAIN="yourcompany"
export CLIENT_ID="your-client-id@cyberark.cloud.12345"
export CLIENT_SECRET="your-client-secret"
```

**How to get these values:**
1. Log in to your CyberArk Identity portal
2. Go to **Applications** → Create or select an OAuth app
3. Copy the Client ID and Client Secret
4. Your subdomain is in your URL: `https://SUBDOMAIN.privilegecloud.cyberark.cloud`
5. Your tenant ID is in your Identity URL

### 3. Test Your Setup

```bash
source demos/tenant_vars.sh
echo $TENANT_ID
echo $TENANT_SUBDOMAIN
```

If these print your values, you're ready!

## Usage Examples

### Example 1: Basic Safe Creation

**Ask your AI assistant:**

```
Provision a safe for secrets_manager/azure_devops with safe name "poc-azure-devops"
```

**What happens:**
- ✅ Safe "poc-azure-devops" is created
- ✅ Admin permissions added
- ⏱️ Takes ~5-10 seconds

---

### Example 2: Safe with Conjur Sync

**For Secrets Manager or Secrets Hub demos:**

```
Provision a safe for secrets_manager/k8s with safe name "poc-k8s-secrets" and add sync member true
```

**What happens:**
- ✅ Safe "poc-k8s-secrets" is created
- ✅ Admin permissions added
- ✅ "Conjur Sync" user added with read permissions
- ⏱️ Takes ~10-15 seconds

---

### Example 3: Complete Setup with Accounts

**For demos that need test data:**

```
Provision a safe for secrets_manager/jenkins with:
- Safe name: "poc-jenkins-demo"
- Add sync member: true
- Create accounts: true
```

**What happens:**
- ✅ Safe "poc-jenkins-demo" is created
- ✅ Admin permissions added
- ✅ "Conjur Sync" user added
- ✅ Test SSH account created (ssh-user-1)
- ⏱️ Takes ~15-20 seconds

---

### Example 4: Full Conjur Integration

**For end-to-end Secrets Manager setup:**

```
Provision a safe for secrets_manager/k8s with:
- Safe name: "poc-k8s-complete"
- Add sync member: true
- Create accounts: true
- Setup Conjur: true
```

**What happens:**
- ✅ Safe "poc-k8s-complete" is created
- ✅ Admin permissions added
- ✅ "Conjur Sync" user added
- ✅ Test SSH account created
- ✅ Waits for Conjur synchronizer to detect the safe
- ⏱️ Takes ~2-5 minutes (synchronizer wait time)

---

## Quick Reference

### Parameter Cheat Sheet

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `demoPath` | string | **required** | Demo directory path (e.g., `secrets_manager/k8s`) |
| `safeName` | string | **required** | Safe name (e.g., `poc-k8s-secrets`) |
| `addSyncMember` | boolean | `false` | Add Conjur Sync user for SM/SH integration |
| `createAccounts` | boolean | `false` | Create test SSH account in safe |
| `setupConjur` | boolean | `false` | Wait for Conjur synchronization |

### Common Patterns

#### Pattern 1: Simple Testing
```
demoPath: "secrets_manager/test"
safeName: "poc-test"
```

#### Pattern 2: Secrets Manager Demo
```
demoPath: "secrets_manager/k8s"
safeName: "poc-k8s-secrets"
addSyncMember: true
createAccounts: true
```

#### Pattern 3: Credential Provider Demo
```
demoPath: "credential_providers/ccp"
safeName: "poc-ccp-accounts"
createAccounts: true
```

## Troubleshooting

### Error: "Failed to get identity token"

**Problem:** Cannot authenticate to CyberArk Identity

**Solution:**
1. Check credentials in `demos/tenant_vars.sh`
2. Verify network connectivity
3. Test manually:
   ```bash
   source demos/tenant_vars.sh
   source demos/setup_env.sh
   get_identity_token "$TENANT_ID" "$CLIENT_ID" "$CLIENT_SECRET"
   ```

---

### Error: "Demo path does not exist"

**Problem:** The demo directory hasn't been created yet

**Solution:**
1. Create the demo first:
   ```
   Create a secrets_manager demo called "azure_devops"
   ```
2. Then provision the safe

---

### Error: "Safe already exists"

**Problem:** A safe with that name already exists

**Solution:**
- Use a different name: `poc-azure-devops-v2`
- Or delete the existing safe first

---

### Error: "CYBR_DEMOS_PATH: unbound variable"

**Problem:** Environment variable not set

**Solution:**
```bash
export CYBR_DEMOS_PATH="/path/to/cybr-demos"
source demos/tenant_vars.sh
```

---

## Complete Workflow Example

Here's a complete workflow from start to finish:

### Step 1: Create the Demo Structure
```
Create a secrets_manager demo called "my_app"
```

### Step 2: Provision the Safe
```
Provision a safe for secrets_manager/my_app with:
- Safe name: "poc-my-app"
- Add sync member: true
- Create accounts: true
```

### Step 3: Verify in UI
1. Log in to CyberArk Privilege Cloud
2. Go to **Policies** → **Safes**
3. Find "poc-my-app"
4. Check members and accounts

### Step 4: Use in Your Demo
The safe is now ready! You can:
- Configure your application to retrieve secrets
- Set up Secrets Manager policies
- Test credential retrieval

---

## Tips & Best Practices

### 1. Safe Naming Convention
✅ **Good:** `poc-k8s-secrets`, `poc-jenkins-demo`, `poc-test-app`  
❌ **Bad:** `mysafe`, `test123`, `safe`

**Why:** Descriptive names make it clear what the safe is for

### 2. Use addSyncMember for Secrets Manager
For ANY Secrets Manager or Secrets Hub demo:
```
addSyncMember: true
```

### 3. Create Accounts When You Need Test Data
If your demo needs to retrieve secrets:
```
createAccounts: true
```

### 4. Only Use setupConjur When Needed
The `setupConjur` option adds several minutes. Only use when:
- You need immediate synchronization
- Your demo script depends on Conjur detection

Otherwise, Conjur will sync automatically in the background.

### 5. Check Output for Errors
Always review the output:
```
✓ Authentication successful
✓ Safe created
✓ Admin role added
```

Look for checkmarks! If something failed, you'll see error messages.

---

## Advanced Usage

### Batch Provisioning

Create multiple safes in sequence:

```
Provision these safes:
1. For secrets_manager/k8s with name "poc-k8s" and add sync member true
2. For secrets_manager/jenkins with name "poc-jenkins" and add sync member true
3. For credential_providers/ccp with name "poc-ccp" and create accounts true
```

### Environment-Specific Safes

Use naming to separate environments:

```
- poc-k8s-dev
- poc-k8s-staging
- poc-k8s-prod
```

---

## What Gets Created?

### In CyberArk Privilege Cloud:

1. **Safe**
   - Name: As specified (e.g., `poc-azure-devops`)
   - Auto-purge: Enabled
   - OLAC: Enabled

2. **Members**
   - "Privilege Cloud Administrators" (full permissions)
   - "Conjur Sync" (read-only, if requested)

3. **Accounts** (if requested)
   - Name: `account-ssh-user-1`
   - Username: `ssh-user-1`
   - Platform: UnixSSH
   - Address: 196.168.0.1
   - Secret: SuperSecret1!

### On Your System:

- Temporary script in `demos/{category}/{demo}/setup/` (auto-deleted)
- Execution output displayed in chat

---

## Cleanup

### Deleting Safes

Currently, safe deletion must be done manually:

1. **Via UI:**
   - CyberArk Privilege Cloud → Policies → Safes
   - Select safe → Delete

2. **Via API:** (coming soon as MCP tool)
   ```bash
   # Manual script
   source demos/setup_env.sh
   delete_safe "$TENANT_SUBDOMAIN" "$identity_token" "poc-test-safe"
   ```

---

## Next Steps

- ✅ Learn about [create_demo](TOOLS.md#create_demo) - Create demo scaffolding
- ✅ Learn about [create_demo_safe](TOOLS.md#create_demo_safe) - Generate safe scripts
- ✅ Read the [full tools documentation](TOOLS.md)
- ✅ Check out [existing demos](../demos/) for examples

---

## Support

If you encounter issues:

1. Check this guide's troubleshooting section
2. Review [TOOLS.md](TOOLS.md) for detailed documentation
3. Verify your environment setup
4. Check CyberArk Privilege Cloud audit logs

---

**Happy provisioning! 🚀**