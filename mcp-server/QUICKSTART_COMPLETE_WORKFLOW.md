# Complete Workflow: From Demo to Workload

This guide walks you through the complete process of setting up a Secrets Manager demo from scratch, including demo creation, safe provisioning, and workload creation.

## Overview

You'll learn how to:
1. Create a demo structure
2. Provision a safe in CyberArk Privilege Cloud
3. Create workload identities with API key authentication
4. Use the credentials to access secrets

**Time to complete:** ~5-10 minutes (after initial setup)

## Prerequisites

### One-Time Setup

#### 1. Set Environment Variable

```bash
export CYBR_DEMOS_PATH="/path/to/cybr-demos"
```

Add to your shell profile to make it permanent:
```bash
echo 'export CYBR_DEMOS_PATH="/path/to/cybr-demos"' >> ~/.bashrc
source ~/.bashrc
```

#### 2. Configure Credentials

Edit `demos/tenant_vars.sh`:

```bash
# CyberArk Identity
export TENANT_ID="abc12345"
export TENANT_SUBDOMAIN="yourcompany"
export CLIENT_ID="your-client-id@cyberark.cloud.12345"
export CLIENT_SECRET="your-client-secret"
```

**How to get these values:**
1. Log in to CyberArk Identity portal
2. Go to **Applications** → Create OAuth Confidential Client
3. Copy Client ID and Client Secret
4. Subdomain is in your URL: `https://SUBDOMAIN.privilegecloud.cyberark.cloud`

#### 3. Verify Setup

```bash
source demos/tenant_vars.sh
echo $TENANT_ID
echo $CYBR_DEMOS_PATH
```

Both should print values.

#### 4. Restart MCP Client

- **Claude Desktop**: Quit (Cmd+Q) and reopen
- **Zed**: Cmd+Shift+P → "zed: reload extensions"

---

## Complete Workflow Example

Let's create a complete Secrets Manager demo for an application called "MyWebApp".

### Step 1: Create Demo Structure

**Ask your AI assistant:**

```
Create a secrets_manager demo called "mywebapp" with:
- Display name: "MyWebApp Integration"
- Description: "Demonstrates CyberArk Secrets Manager integration with a web application"
```

**What happens:**
- ✅ Directory created: `demos/secrets_manager/mywebapp/`
- ✅ Files created: README.md, info.yaml, demo.sh, setup.sh
- ✅ Setup directory created with configure.sh

**Time:** ~2 seconds

---

### Step 2: Provision the Safe

**Ask your AI assistant:**

```
Provision a safe for secrets_manager/mywebapp with:
- Safe name: "poc-mywebapp"
- Add sync member: true
- Create accounts: true
```

**What happens:**
- ✅ Safe "poc-mywebapp" created in Privilege Cloud
- ✅ Admin permissions added
- ✅ "Conjur Sync" member added
- ✅ Test SSH account created (account-ssh-user-1)

**Time:** ~15-20 seconds

**Verify in UI:**
1. Log in to CyberArk Privilege Cloud
2. Go to **Policies** → **Safes**
3. Find "poc-mywebapp"
4. Check members and accounts

---

### Step 3: Create Workload for Production

**Ask your AI assistant:**

```
Provision a workload for secrets_manager/mywebapp with:
- Safe name: "poc-mywebapp"
- Workload name: "mywebapp-prod"
```

**What happens:**
- ✅ Workload identity created: `data/workloads/mywebapp-prod`
- ✅ API key authentication enabled
- ✅ Access granted to "poc-mywebapp" safe
- ✅ API key rotated
- ✅ Credentials saved to: `demos/secrets_manager/mywebapp/setup/.workload_credentials_mywebapp-prod.txt`

**Time:** ~10-15 seconds

---

### Step 4: Create Workload for Development

**Ask your AI assistant:**

```
Provision a workload for secrets_manager/mywebapp with:
- Safe name: "poc-mywebapp"
- Workload name: "mywebapp-dev"
```

**What happens:**
- ✅ Second workload created: `data/workloads/mywebapp-dev`
- ✅ Separate API key generated
- ✅ Credentials saved to: `demos/secrets_manager/mywebapp/setup/.workload_credentials_mywebapp-dev.txt`

**Time:** ~10-15 seconds

---

### Step 5: Retrieve and Use Credentials

#### View Credentials File

```bash
cd demos/secrets_manager/mywebapp/setup
cat .workload_credentials_mywebapp-prod.txt
```

**Output:**
```
========================================
Workload Credentials
========================================
Workload Name: mywebapp-prod
Login: host/data/workloads/mywebapp-prod
API Key: 3x4mpl3k3y1a2b3c4d5e6f7g8h9i0j1k2l3m4n5o6p7q8r9s

Safe Access: poc-mywebapp
Conjur URL: https://yourcompany.secretsmgr.cyberark.cloud

========================================
Usage Example:
========================================
# Authenticate
curl -d "3x4mpl3k3y1a2b3c4d5e6f7g8h9i0j1k2l3m4n5o6p7q8r9s" \
  https://yourcompany.secretsmgr.cyberark.cloud/api/authn/conjur/host%2Fdata%2Fworkloads%2Fmywebapp-prod/authenticate

# Retrieve secret
curl -H "Authorization: Token token=\"<token>\"" \
  https://yourcompany.secretsmgr.cyberark.cloud/api/secrets/conjur/variable/data%2Fvault%2Fpoc-mywebapp%2F<account-id>%2Fusername
```

#### Test Authentication

```bash
# Set variables from credentials file
SUBDOMAIN="yourcompany"
WORKLOAD_LOGIN="host/data/workloads/mywebapp-prod"
API_KEY="<your-api-key-from-file>"

# Authenticate and get token
TOKEN=$(curl -s -d "$API_KEY" \
  "https://$SUBDOMAIN.secretsmgr.cyberark.cloud/api/authn/conjur/${WORKLOAD_LOGIN/\//%2F}/authenticate" \
  | base64 | tr -d '\r\n')

echo "Token: $TOKEN"
```

#### Retrieve a Secret

```bash
# Get username from test account
curl -H "Authorization: Token token=\"$TOKEN\"" \
  "https://$SUBDOMAIN.secretsmgr.cyberark.cloud/api/secrets/conjur/variable/data%2Fvault%2Fpoc-mywebapp%2Faccount-ssh-user-1%2Fusername"
```

**Output:**
```
ssh-user-1
```

---

## Quick Reference Commands

### Create Demo
```
Create a secrets_manager demo called "{demo_name}"
```

### Provision Safe
```
Provision a safe for secrets_manager/{demo_name} with:
- Safe name: "poc-{demo_name}"
- Add sync member: true
- Create accounts: true
```

### Provision Workload
```
Provision a workload for secrets_manager/{demo_name} with:
- Safe name: "poc-{demo_name}"
- Workload name: "{workload_name}"
```

---

## Common Patterns

### Pattern 1: Single Application

**Use Case:** One application needs access to secrets

```
# Step 1: Create demo
Create a secrets_manager demo called "api_server"

# Step 2: Create safe
Provision a safe for secrets_manager/api_server with safe name "poc-api-server" and add sync member true and create accounts true

# Step 3: Create workload
Provision a workload for secrets_manager/api_server with safe name "poc-api-server" and workload name "api-server-prod"
```

### Pattern 2: Multiple Environments

**Use Case:** Same app in dev/staging/prod

```
# Step 1: Create demo
Create a secrets_manager demo called "webapp"

# Step 2: Create safe (one per environment)
Provision a safe for secrets_manager/webapp with safe name "poc-webapp-dev" and add sync member true and create accounts true
Provision a safe for secrets_manager/webapp with safe name "poc-webapp-staging" and add sync member true and create accounts true
Provision a safe for secrets_manager/webapp with safe name "poc-webapp-prod" and add sync member true and create accounts true

# Step 3: Create workloads (one per environment)
Provision a workload for secrets_manager/webapp with safe name "poc-webapp-dev" and workload name "webapp-dev"
Provision a workload for secrets_manager/webapp with safe name "poc-webapp-staging" and workload name "webapp-staging"
Provision a workload for secrets_manager/webapp with safe name "poc-webapp-prod" and workload name "webapp-prod"
```

### Pattern 3: Microservices

**Use Case:** Multiple services sharing secrets

```
# Step 1: Create demo
Create a secrets_manager demo called "microservices"

# Step 2: Create shared safe
Provision a safe for secrets_manager/microservices with safe name "poc-microservices-shared" and add sync member true and create accounts true

# Step 3: Create workload per service
Provision a workload for secrets_manager/microservices with safe name "poc-microservices-shared" and workload name "auth-service"
Provision a workload for secrets_manager/microservices with safe name "poc-microservices-shared" and workload name "api-gateway"
Provision a workload for secrets_manager/microservices with safe name "poc-microservices-shared" and workload name "payment-service"
Provision a workload for secrets_manager/microservices with safe name "poc-microservices-shared" and workload name "notification-service"
```

### Pattern 4: CI/CD Pipeline

**Use Case:** Jenkins/Azure DevOps/GitHub Actions

```
# Step 1: Create demo
Create a secrets_manager demo called "cicd"

# Step 2: Create safe
Provision a safe for secrets_manager/cicd with safe name "poc-cicd-secrets" and add sync member true and create accounts true

# Step 3: Create workload per pipeline/job
Provision a workload for secrets_manager/cicd with safe name "poc-cicd-secrets" and workload name "deploy-prod-pipeline"
Provision a workload for secrets_manager/cicd with safe name "poc-cicd-secrets" and workload name "deploy-staging-pipeline"
Provision a workload for secrets_manager/cicd with safe name "poc-cicd-secrets" and workload name "test-pipeline"
```

---

## What You Get

After completing the workflow, you'll have:

### In CyberArk Privilege Cloud
- ✅ Safe with proper permissions
- ✅ "Conjur Sync" member for synchronization
- ✅ Test accounts with credentials

### In Secrets Manager (Conjur)
- ✅ Workload identities created
- ✅ API key authentication enabled
- ✅ Safe access granted
- ✅ Ready to retrieve secrets

### On Your System
- ✅ Demo directory structure
- ✅ Documentation files
- ✅ Setup scripts
- ✅ Secure credential files (mode 600)
- ✅ Usage examples

---

## File Structure After Completion

```
demos/secrets_manager/mywebapp/
├── README.md                                        # Documentation
├── info.yaml                                        # Metadata
├── demo.sh                                          # Demo script
├── setup.sh                                         # Setup script
└── setup/
    ├── configure.sh                                 # Configuration
    ├── .workload_credentials_mywebapp-prod.txt     # Prod credentials
    └── .workload_credentials_mywebapp-dev.txt      # Dev credentials
```

---

## Best Practices

### 1. Naming Conventions

✅ **Good:**
- Safe: `poc-myapp-prod`, `poc-jenkins-secrets`
- Workload: `myapp-prod-server`, `jenkins-deploy-job`

❌ **Bad:**
- Safe: `safe1`, `test`, `mysafe`
- Workload: `app`, `workload1`, `test`

### 2. Security

- ✅ Keep credential files in `setup/` directory
- ✅ Add `.workload_credentials_*` to `.gitignore`
- ✅ Delete credential files after distributing to applications
- ✅ Use separate workloads for different environments
- ✅ Never commit API keys to version control

### 3. Organization

- ✅ One demo per application/use case
- ✅ One safe per environment or application
- ✅ One workload per consuming service/job
- ✅ Document each workload's purpose in README

### 4. Workflow Order

Always follow this order:
1. Create demo
2. Provision safe
3. Provision workload(s)

Don't skip steps!

---

## Troubleshooting

### Error: "Demo path does not exist"

**Problem:** Trying to provision safe/workload before creating demo

**Solution:**
```
Create a secrets_manager demo called "myapp"
```

### Error: "Safe already exists"

**Problem:** Safe name is already taken

**Solution:** Use a different name like `poc-myapp-v2`

### Error: "Failed to get identity token"

**Problem:** Credentials not configured or incorrect

**Solution:**
1. Check `demos/tenant_vars.sh`
2. Verify credentials in Identity portal
3. Test: `source demos/tenant_vars.sh && echo $CLIENT_ID`

### Error: "Cannot access safe"

**Problem:** Safe doesn't exist or workload not granted access

**Solution:**
1. Verify safe exists in Privilege Cloud UI
2. Ensure "Conjur Sync" member is added
3. Wait a few minutes for synchronization

### Credentials File Not Found

**Problem:** Looking in wrong location

**Solution:**
```bash
# List all credential files
find demos -name ".workload_credentials_*" -type f
```

---

## Integration Examples

### Python Application

```python
import requests
import base64

# From credentials file
SUBDOMAIN = "yourcompany"
WORKLOAD_LOGIN = "host/data/workloads/mywebapp-prod"
API_KEY = "your-api-key"

# Authenticate
auth_url = f"https://{SUBDOMAIN}.secretsmgr.cyberark.cloud/api/authn/conjur/{WORKLOAD_LOGIN.replace('/', '%2F')}/authenticate"
response = requests.post(auth_url, data=API_KEY)
token = base64.b64encode(response.content).decode('utf-8')

# Retrieve secret
secret_url = f"https://{SUBDOMAIN}.secretsmgr.cyberark.cloud/api/secrets/conjur/variable/data%2Fvault%2Fpoc-mywebapp%2Faccount-ssh-user-1%2Fusername"
headers = {"Authorization": f"Token token=\"{token}\""}
secret = requests.get(secret_url, headers=headers).text
print(f"Secret: {secret}")
```

### Node.js Application

```javascript
const axios = require('axios');

// From credentials file
const SUBDOMAIN = 'yourcompany';
const WORKLOAD_LOGIN = 'host/data/workloads/mywebapp-prod';
const API_KEY = 'your-api-key';

async function getSecret() {
    // Authenticate
    const authUrl = `https://${SUBDOMAIN}.secretsmgr.cyberark.cloud/api/authn/conjur/${WORKLOAD_LOGIN.replace(/\//g, '%2F')}/authenticate`;
    const authResponse = await axios.post(authUrl, API_KEY);
    const token = Buffer.from(authResponse.data).toString('base64');

    // Retrieve secret
    const secretUrl = `https://${SUBDOMAIN}.secretsmgr.cyberark.cloud/api/secrets/conjur/variable/data%2Fvault%2Fpoc-mywebapp%2Faccount-ssh-user-1%2Fusername`;
    const secretResponse = await axios.get(secretUrl, {
        headers: { 'Authorization': `Token token="${token}"` }
    });
    
    console.log('Secret:', secretResponse.data);
}

getSecret();
```

### Bash Script

```bash
#!/bin/bash
# From credentials file
SUBDOMAIN="yourcompany"
WORKLOAD_LOGIN="host/data/workloads/mywebapp-prod"
API_KEY="your-api-key"

# Authenticate
TOKEN=$(curl -s -d "$API_KEY" \
  "https://$SUBDOMAIN.secretsmgr.cyberark.cloud/api/authn/conjur/${WORKLOAD_LOGIN/\//%2F}/authenticate" \
  | base64 | tr -d '\r\n')

# Retrieve secret
SECRET=$(curl -s -H "Authorization: Token token=\"$TOKEN\"" \
  "https://$SUBDOMAIN.secretsmgr.cyberark.cloud/api/secrets/conjur/variable/data%2Fvault%2Fpoc-mywebapp%2Faccount-ssh-user-1%2Fusername")

echo "Secret: $SECRET"
```

---

## Next Steps

### Learn More

- ✅ [Tool Reference](TOOLS.md) - Detailed documentation
- ✅ [Safe Provisioning Guide](QUICKSTART_PROVISION.md) - Safe-specific details
- ✅ [MCP Server README](README.md) - Overview and setup

### Advanced Topics

- Multiple safes per demo
- Custom account creation
- JWT authentication (coming soon)
- Application ID authentication (coming soon)
- Safe cleanup and rotation

### Production Deployment

Before going to production:
1. ✅ Use production-grade credentials
2. ✅ Implement proper secret rotation
3. ✅ Set up monitoring and alerting
4. ✅ Follow least-privilege principle
5. ✅ Document all workloads and their purposes
6. ✅ Implement proper error handling in applications
7. ✅ Use secure storage for credential files
8. ✅ Set up backup and disaster recovery

---

## Summary

You now know how to:
- ✅ Create demo structures
- ✅ Provision safes with proper permissions
- ✅ Create workloads with API key authentication
- ✅ Grant workloads access to safes
- ✅ Use credentials to retrieve secrets

**Total time from zero to working demo:** ~5 minutes!

**Questions?** Check the [TOOLS.md](TOOLS.md) for detailed documentation.

---

**Happy building! 🚀**

Version: 1.2.0  
Last Updated: February 13, 2024