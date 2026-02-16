# Documentation Guidelines

This document defines the standards and best practices for documentation in the CyberArk Demos project.

## Purpose

These guidelines ensure that all documentation is:
- Professional and enterprise-ready
- Consistent across all demos
- Accessible to all users
- Easy to maintain and update
- Compatible with various platforms and tools

## Guidelines

### 1. No Emojis

**Rule:** Do not use emojis in documentation.

**Rationale:**
- Emojis may not render consistently across platforms
- Enterprise documentation should maintain a professional tone
- Some documentation systems and email clients don't support emojis
- Text descriptions are more searchable and accessible
- Screen readers may not properly interpret emojis

**Examples:**

❌ **Incorrect:**
```markdown
## 🚀 Quick Start
✅ Feature is enabled
❌ Not supported
```

✅ **Correct:**
```markdown
## Quick Start
- Feature is enabled
- Not supported
```

**Common Replacements:**

| Emoji | Replacement Text |
|-------|-----------------|
| 🚀 | Quick Start, Launch, Deploy |
| ✅ | Yes, Enabled, Supported, Success |
| ❌ | No, Disabled, Not supported, Failed |
| ⚠️ | Warning:, Note:, Caution: |
| 📝 | Note:, Documentation |
| 🔧 | Configuration, Setup, Settings |
| 🎯 | Goal, Objective, Target |
| 💡 | Tip:, Hint:, Recommendation: |
| 🐛 | Bug, Issue, Problem |
| 🎉 | Success, Complete, Done |
| 📋 | List, Steps, Checklist |
| 📁 | Files, Directory, Folder |
| 🔒 | Security, Secure, Protected |
| 🌐 | Network, Web, Internet |
| 💻 | System, Computer, Server |

### 2. Professional Tone

**Rule:** Maintain a professional, technical tone throughout documentation.

**Guidelines:**
- Use clear, precise language
- Avoid casual expressions and slang
- Write in complete sentences
- Use proper technical terminology
- Be concise but thorough

**Examples:**

❌ **Too Casual:**
```markdown
This is super cool! Just run the script and boom, you're done!
```

✅ **Professional:**
```markdown
This feature provides automated configuration. Run the script to complete the setup.
```

### 3. Consistent Formatting

**Rule:** Use consistent formatting throughout all documentation.

**Headers:**
- Use ATX-style headers (# ## ###)
- Start with a single # for the main title
- Don't skip heading levels

**Code Blocks:**
- Always specify the language for syntax highlighting
- Use consistent indentation (2 or 4 spaces)
- Include comments for complex examples

**Lists:**
- Use `-` for unordered lists
- Use `1.` for ordered lists
- Be consistent within a document

**Examples:**

✅ **Good:**
```markdown
## Installation

### Prerequisites

1. Node.js 18 or higher
2. npm package manager
3. Git

### Steps

Follow these steps to install:

```bash
# Clone the repository
git clone https://github.com/example/repo.git

# Install dependencies
npm install
```
```

### 4. Clear Structure

**Rule:** Every README should have a consistent structure.

**Required Sections:**
1. Title
2. About/Overview
3. Prerequisites
4. Installation/Setup
5. Usage
6. Configuration (if applicable)
7. Examples
8. Troubleshooting (if applicable)

**Example Structure:**

```markdown
# Demo: Application Name

## About

Brief description of what this demo demonstrates.

## Prerequisites

- List required software
- List required credentials
- List required knowledge

## Setup

Instructions for setting up the demo.

## Usage

Instructions for running the demo.

## Configuration

Configuration options and environment variables.

## Examples

Concrete examples with expected output.

## Troubleshooting

Common issues and solutions.
```

### 5. Code Examples

**Rule:** All code examples must be properly formatted and tested.

**Guidelines:**
- Use proper syntax highlighting
- Include comments for complex sections
- Show expected output when relevant
- Use realistic examples (not foo/bar)
- Ensure examples are copy-pasteable

**Examples:**

✅ **Good:**
```markdown
### Authentication Example

```bash
# Set your credentials
export CLIENT_ID="your-client-id"
export CLIENT_SECRET="your-client-secret"

# Authenticate to the service
curl -X POST https://api.example.com/auth \
  -H "Content-Type: application/json" \
  -d '{"client_id":"'$CLIENT_ID'","client_secret":"'$CLIENT_SECRET'"}'
```

Expected output:
```json
{
  "access_token": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
  "expires_in": 3600
}
```
```

### 6. Links and References

**Rule:** Use descriptive link text and verify all links are valid.

**Guidelines:**
- Don't use "click here" as link text
- Use relative paths for internal links
- Include link descriptions
- Verify external links are current

**Examples:**

❌ **Poor:**
```markdown
Click [here](https://docs.example.com) for more info.
```

✅ **Good:**
```markdown
For detailed API documentation, see the [CyberArk API Reference](https://docs.cyberark.com/api).
```

### 7. Command Examples

**Rule:** Command examples should be complete and runnable.

**Guidelines:**
- Show the full command
- Include all required parameters
- Use environment variables for sensitive data
- Show expected output
- Include error handling examples

**Examples:**

✅ **Good:**
```markdown
### Running the Setup Script

```bash
cd demos/secrets_manager/myapp
./setup.sh
```

Expected output:
```
========================================
Setup: MyApp Integration
========================================

Authenticating to Identity...
✓ Authentication successful

Creating safe...
✓ Safe created successfully

Setup completed successfully!
```

If you encounter authentication errors:
```bash
# Verify your credentials
source ../../tenant_vars.sh
echo $TENANT_ID
```
```

### 8. File Paths

**Rule:** Use consistent path notation throughout documentation.

**Guidelines:**
- Use relative paths from project root
- Use forward slashes (even for Windows)
- Use backticks for inline paths
- Show directory structure when helpful

**Examples:**

✅ **Good:**
```markdown
The configuration file is located at `demos/tenant_vars.sh`.

Project structure:
```
demos/
├── secrets_manager/
│   ├── jenkins/
│   │   ├── README.md
│   │   └── setup.sh
│   └── k8s/
│       ├── README.md
│       └── setup.sh
└── tenant_vars.sh
```
```

### 9. Tables

**Rule:** Use tables for structured data comparison.

**Guidelines:**
- Include header row
- Align columns consistently
- Keep tables simple and readable
- Don't use tables for lists

**Examples:**

✅ **Good:**
```markdown
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| client_id | string | Yes | OAuth client identifier |
| client_secret | string | Yes | OAuth client secret |
| tenant_id | string | Yes | CyberArk tenant identifier |
```

### 10. Error Messages

**Rule:** Document common errors and their solutions.

**Guidelines:**
- Show the actual error message
- Explain the cause
- Provide step-by-step solution
- Include verification steps

**Examples:**

✅ **Good:**
```markdown
### Troubleshooting

#### Error: "Failed to get identity token"

**Symptom:**
```
ERROR: Failed to get identity token
Connection timeout
```

**Cause:** Invalid credentials or network connectivity issue

**Solution:**
1. Verify credentials in `demos/tenant_vars.sh`:
   ```bash
   source demos/tenant_vars.sh
   echo $CLIENT_ID
   echo $TENANT_ID
   ```

2. Test network connectivity:
   ```bash
   curl -v https://$TENANT_ID.id.cyberark.cloud
   ```

3. Verify credentials in CyberArk Identity portal

4. Re-run the setup script
```

## Validation

Use the `validate_readme` MCP tool to check compliance:

```
Validate secrets_manager/myapp/README.md
```

The tool checks:
- Emoji usage
- More guidelines coming soon

## Best Practices

### Writing Style

1. **Be Concise**: Get to the point quickly
2. **Be Specific**: Use concrete examples
3. **Be Accurate**: Test all commands and examples
4. **Be Complete**: Include all necessary information
5. **Be Consistent**: Follow these guidelines throughout

### Maintenance

1. **Review Regularly**: Check documentation for accuracy
2. **Update Examples**: Keep examples current with code changes
3. **Fix Broken Links**: Verify links periodically
4. **Version Information**: Include version numbers when relevant
5. **Date Updates**: Note when documentation was last updated

### Accessibility

1. **Descriptive Text**: Use text instead of symbols
2. **Alt Text**: Provide descriptions for images
3. **Clear Language**: Write for non-native English speakers
4. **Logical Flow**: Organize content logically
5. **Semantic Markup**: Use proper heading hierarchy

## Examples

### Good README Example

```markdown
# Demo: Jenkins Integration

## About

This demo demonstrates how to integrate CyberArk Secrets Manager with Jenkins for secure credential retrieval in CI/CD pipelines.

## Prerequisites

- Jenkins server version 2.346 or higher
- CyberArk Secrets Manager tenant
- Network access from Jenkins to CyberArk cloud services

Required credentials:
- CyberArk tenant ID
- OAuth client ID and secret
- Jenkins admin access

## Setup

### Step 1: Configure CyberArk Credentials

Edit the tenant variables file:

```bash
cd /path/to/cybr-demos
nano demos/tenant_vars.sh
```

Add your credentials:

```bash
export TENANT_ID="abc12345"
export TENANT_SUBDOMAIN="yourcompany"
export CLIENT_ID="your-client-id"
export CLIENT_SECRET="your-client-secret"
```

### Step 2: Run Setup Script

```bash
cd demos/secrets_manager/jenkins
./setup.sh
```

The script will:
1. Create a safe in CyberArk Privilege Cloud
2. Configure Secrets Manager authenticator
3. Create workload identities
4. Generate Jenkins configuration

Expected output:
```
========================================
Setup: Jenkins Integration
========================================

Creating safe: poc-jenkins
Success: Safe created

Configuring authenticator: jenkins1
Success: Authenticator configured

Setup completed successfully!
```

## Usage

### Configure Jenkins Plugin

1. Log in to Jenkins as administrator
2. Navigate to Manage Jenkins > Manage Plugins
3. Install the CyberArk Conjur Secrets Plugin
4. Configure the plugin with the credentials from the setup

### Retrieve Secrets in Pipeline

Example Jenkinsfile:

```groovy
pipeline {
    agent any
    
    environment {
        DB_PASSWORD = conjur(
            credentialsId: 'conjur',
            account: 'conjur',
            variable: 'data/vault/poc-jenkins/db-password'
        )
    }
    
    stages {
        stage('Deploy') {
            steps {
                sh 'echo "Deploying with secure credentials"'
                // Use $DB_PASSWORD in your deployment
            }
        }
    }
}
```

## Configuration

### Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| TENANT_ID | CyberArk tenant identifier | abc12345 |
| TENANT_SUBDOMAIN | Tenant subdomain | yourcompany |
| CLIENT_ID | OAuth client ID | client@cyberark.cloud.123 |
| CLIENT_SECRET | OAuth client secret | (sensitive) |

### Jenkins Plugin Settings

Configure in Manage Jenkins > Configure System > CyberArk Conjur:

- Appliance URL: `https://yourcompany.secretsmgr.cyberark.cloud`
- Account: `conjur`
- Authenticator: `authn-jwt/jenkins1`

## Troubleshooting

### Error: "Unable to authenticate to Conjur"

**Cause:** Invalid credentials or network connectivity issue

**Solution:**
1. Verify credentials are correctly set in Jenkins
2. Check network connectivity:
   ```bash
   curl -v https://yourcompany.secretsmgr.cyberark.cloud
   ```
3. Verify the authenticator is enabled in Secrets Manager

### Error: "Secret not found"

**Cause:** Secret path is incorrect or workload doesn't have access

**Solution:**
1. Verify the secret exists:
   ```bash
   # List secrets in safe
   curl -H "Authorization: Bearer $TOKEN" \
     https://yourcompany.secretsmgr.cyberark.cloud/api/secrets?safe=poc-jenkins
   ```
2. Check workload has access to the safe
3. Verify the secret path matches the Conjur variable path

## References

- [Jenkins Plugin Documentation](https://plugins.jenkins.io/conjur-credentials/)
- [CyberArk Secrets Manager Documentation](https://docs.cyberark.com/secrets-manager-saas/)
- [JWT Authenticator Configuration](https://docs.cyberark.com/secrets-manager-saas/latest/en/content/integrations/jenkins.htm)

---

Last Updated: February 2024
```

## Enforcement

These guidelines are enforced through:

1. **Automated Validation**: Use `validate_readme` tool before committing
2. **Code Review**: Reviewers check compliance during PR review
3. **Continuous Improvement**: Guidelines updated based on feedback

## Feedback

To suggest improvements to these guidelines:
1. Review the current guidelines
2. Propose specific changes with rationale
3. Submit feedback through appropriate channels

---

**Version:** 1.0.0  
**Last Updated:** February 13, 2024