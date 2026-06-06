# Changelog

All notable changes to the CyberArk Demos MCP Server will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- **`create_demo_safe` tool**: `safeName` parameter is now optional
  - When omitted, automatically generates safe name using pattern: `${LAB_ID}-{demo-name}`
  - Demo name is extracted from the demo path and normalized (lowercase, spaces and non-alphanumeric characters replaced with hyphens)
  - Example: For demo path `secrets_manager/azure_devops`, default safe name becomes `${LAB_ID}-azure-devops`
  - Example: For demo path `secrets_manager/K8s Demo`, default safe name becomes `${LAB_ID}-k8s-demo`
  - Custom safe names can still be provided to override the default

### Added

- **New environment variable**: `LAB_ID` added to `demos/tenant_vars.sh`
  - Used for generating unique safe names across different lab environments
  - Default value: `SET_LAB_ID`
  - Common values: `poc`, `lab01`, `demo`, etc.

### Tests

- Added comprehensive tests for `createDemoSafe` function
  - Test default safe name generation
  - Test custom safe name override
  - Test safe name normalization with special characters

## [1.3.0] - 2024-02-13

### Added

- **New Tool: `validate_readme`** - Validates README and markdown files against documentation guidelines
  - Checks for emojis and provides suggestions for removal
  - Returns validation score (0-100) and pass/fail status
  - Lists specific line numbers and locations of issues
  - Provides suggestions for fixing issues
  - Helps maintain professional, enterprise-ready documentation
  - No user input required - just provide file path
  - Supports any markdown file in the demos directory
  - Severity-based issue reporting (warnings, errors)
  - Detailed issue locations with line numbers and preview text

### Documentation

- Added comprehensive `validate_readme` documentation to `TOOLS.md`
- Added `DOCUMENTATION_GUIDELINES.md` with complete style guide
  - No emojis guideline with rationale and examples
  - Professional tone requirements
  - Consistent formatting standards
  - Clear structure requirements
  - Code example best practices
  - Link and reference guidelines
  - Command example standards
  - Error message documentation
  - Validation and enforcement procedures
- Updated version to 1.3.0

### Technical Details

**validate_readme Implementation:**
- Reads markdown file from demos directory
- Uses comprehensive emoji regex pattern to detect all emoji characters
- Scans line by line for emoji occurrences
- Calculates score based on issues found (max -30 for emojis)
- Returns detailed issue report with:
  - Guideline violated
  - Severity level
  - Count of occurrences
  - Specific line numbers
  - Preview of problematic content
  - List of detected emojis
- Provides actionable suggestions for fixes
- Sets passing threshold at 70/100

**Emoji Detection:**
- Covers all Unicode emoji ranges
- Detects standard emojis (😀-🙏)
- Detects symbols and pictographs (🌀-🗿)
- Detects transport and map symbols (🚀-🛿)
- Detects flags (🇦-🇿)
- Detects supplemental symbols (⚡☀)
- Returns matched emojis for each occurrence

## [1.2.0] - 2024-02-13

### Added

- **New Tool: `provision_workload`** - Provisions workloads in Secrets Manager with API key authentication
  - Automatically creates workload host identity in Conjur
  - Grants workload access to specified safe
  - Uses API key authentication (authn/api-key: true)
  - Rotates API key and returns fresh credentials
  - Saves credentials to secure file (mode 600)
  - No user input required - fully automated
  - Creates workload as `data/workloads/{workloadName}`
  - Provides usage examples for authentication and secret retrieval
  - Complements `provision_safe` - create safe first, then create workloads to access it

### Documentation

- Added comprehensive `provision_workload` documentation to `TOOLS.md`
- Added usage examples and best practices for workload provisioning
- Added security considerations for credential storage
- Updated version to 1.2.0

### Technical Details

**provision_workload Implementation:**
- Creates temporary bash script in demo's `setup/` directory
- Sources `setup_env.sh` and `conjur_functions.sh`
- Authenticates to both Identity and Conjur
- Creates Conjur policy with host and safe access grant
- Executes API call to rotate workload's API key
- Saves credentials to `.workload_credentials_{workloadName}.txt`
- Sets file permissions to 600 (owner read/write only)
- Returns workload details and credentials location

**Workload Policy Structure:**
```yaml
- !host
  id: workloads/{workloadName}
  annotations:
    authn/api-key: true
- !grant
  roles:
    - !group vault/{safeName}/delegation/consumers
  members:
    - !host workloads/{workloadName}
```

## [1.1.0] - 2024-02-13

### Added

- **New Tool: `provision_safe`** - Provisions safes in CyberArk Privilege Cloud via API
  - Automatically creates safes using environment variables from `tenant_vars.sh`
  - No user input required - fully automated
  - Options to add Conjur Sync member for Secrets Manager integration
  - Options to create test SSH accounts in the safe
  - Options to wait for Conjur synchronization
  - Executes actual API calls (unlike `create_demo_safe` which generates scripts)
  - Uses utility functions from `demos/utility/ubuntu/privilege_functions.sh`
  
- **New Tool: `create_demo_safe`** - Generates safe setup scripts
  - Creates `setup/vault/` directory structure
  - Generates `vars.env` with environment variables
  - Generates `setup.sh` orchestration script (single execution entrypoint)
  - Customizable with additional environment variables
  - Follows patterns from existing demos (e.g., `k8s`)

### Documentation

- Added comprehensive `TOOLS.md` with detailed documentation for all tools
- Added `QUICKSTART_PROVISION.md` for safe provisioning workflows
- Added `CHANGELOG.md` to track version history
- Updated tool descriptions and examples
- Added troubleshooting guides and best practices

### Changed

- Imported `child_process` and `util` modules for executing shell commands
- Enhanced error handling with detailed error messages
- Improved response formatting with structured JSON output

### Technical Details

**provision_safe Implementation:**
- Creates temporary bash script in demo's `setup/` directory
- Sources `setup_env.sh` to load utility functions
- Executes CyberArk API calls via bash functions:
  - `get_identity_token()` - OAuth authentication
  - `create_safe()` - Safe creation
  - `add_safe_admin_role()` - Admin permissions
  - `add_safe_read_member()` - Conjur Sync member
  - `create_account_ssh_user_1()` - Test account
  - `get_conjur_token()` - Conjur authentication
  - `wait_for_synchronizer()` - Sync detection
- Auto-cleanup of temporary scripts
- Returns execution output and warnings

**create_demo_safe Implementation:**
- Validates demo path existence
- Creates `setup/vault/` directory structure
- Generates executable shell scripts with proper permissions
- Supports optional features via boolean flags
- Returns list of created files

## [1.0.0] - 2024-02-01

### Added

- **Initial Release**
- **Tool: `create_demo`** - Create demo scaffolding
  - Generates README.md with documentation template
  - Generates info.yaml with metadata
  - Generates demo.sh executable script
  - Generates setup.sh executable script
  - Generates setup/configure.sh script
  - Supports four categories: credential_providers, secrets_manager, secrets_hub, utility
  - Customizable display names, descriptions, and script names

### Features

- MCP server implementation using `@modelcontextprotocol/sdk`
- Stdio transport for communication with MCP clients
- Support for Zed and Claude Desktop
- Automatic script permission setting (chmod +x)
- Standard demo structure enforcement
- Environment variable sourcing in scripts

### Documentation

- Initial README.md with setup instructions
- QUICKSTART.md for new users
- Example config files for Zed and Claude Desktop
- Test suite (test.js)

---

## Future Releases

### Planned Features

- `delete_safe` - Delete safes from Privilege Cloud
- `delete_workload` - Remove workloads from Secrets Manager
- `rotate_workload_key` - Rotate a workload's API key
- `list_workloads` - List all workloads for a demo/safe
- `provision_app_id` - Create Application IDs via API
- `provision_jwt_auth` - Create JWT authenticator for workloads
- `list_safes` - List all safes in tenant
- `get_safe_info` - Get safe details
- `create_conjur_policy` - Generate Conjur policy files
- `create_k8s_manifests` - Generate Kubernetes manifests
- `create_cleanup_script` - Generate teardown scripts
- Enhanced error recovery and retry logic
- Batch operations support
- Interactive mode for tool parameters

---

## Notes

### Breaking Changes

None in this release.

### Deprecations

None in this release.

### Security

- All API credentials sourced from environment variables
- No hardcoded secrets
- Temporary scripts automatically cleaned up
- OAuth token-based authentication (no password storage)

### Known Issues

- MCP server requires manual restart to load new tools
- `provision_safe` requires `CYBR_DEMOS_PATH` environment variable
- Conjur synchronization wait time can be several minutes
- No built-in safe deletion capability yet

### Migration Guide

For users upgrading from 1.1.0:

1. Restart your MCP client (Zed or Claude Desktop) to load new tools
2. Ensure `CYBR_DEMOS_PATH` is set in your environment
3. Configure `demos/tenant_vars.sh` with your credentials
4. Test the complete workflow:
   ```
   # Create safe
   Provision a safe for secrets_manager/test with safe name "poc-test"
   
   # Create workload
   Provision a workload for secrets_manager/test with safe name "poc-test" and workload name "test-app"
   ```

For users upgrading from 1.0.0:

1. Restart your MCP client (Zed or Claude Desktop) to load new tools
2. Ensure `CYBR_DEMOS_PATH` is set in your environment
3. Configure `demos/tenant_vars.sh` with your credentials
4. Test with a simple safe provisioning:
   ```
   Provision a safe for secrets_manager/test with safe name "poc-test"
   ```

---

[1.3.0]: https://github.com/cyberark/cybr-demos/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/cyberark/cybr-demos/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/cyberark/cybr-demos/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/cyberark/cybr-demos/releases/tag/v1.0.0