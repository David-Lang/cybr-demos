# Domain Rules (Layer B)

Status: Draft
Scope: Rules shared by groups of tools that inherit `mcp-server/GLOBAL_CONTRACT.md`

## Domain: automation_shared_library

Purpose:
- Keep automation modular, reusable, and reviewable across labs.
- Prevent duplicated shell/API logic in individual demos.
- Standardize prerequisites and installation paths for SE reproducibility.

### B1) Outbound API Centralization

Rule:
- All outbound API calls MUST be implemented as shared functions under `demos/utility/`.
- Tool and demo scripts MUST call shared utility functions, not inline raw `curl`/HTTP logic.

Implementation guidance:
- Linux/bash functions go under `demos/utility/ubuntu/*.sh`.
- Windows/PowerShell 5 functions go under `demos/utility/powershell5/*.ps1`.
- Shared function libraries are loaded via `demos/setup_env.sh` (or platform equivalent import pattern).

Definition of outbound API call:
- Any network request from demo/tool code to CyberArk, cloud providers, SCM/CI systems, or other external services.

Allowed exception:
- Temporary diagnostic probes are allowed only during local troubleshooting and MUST NOT be committed to published lab modules.

### B2) Shared Library Contract

Rule:
- Utility functions in `demos/utility/` are the stable automation interface and SHOULD be treated as a shared library.

Required function behavior:
- Validate required arguments.
- Return consistent exit behavior (`0` success, non-zero failure).
- Avoid echoing secrets/tokens in plaintext.
- Emit actionable error messages for operators.

Change management:
- Breaking changes to utility function signatures require coordinated updates to all calling demos before merge.

### B3) CLI Dependency Installation Policy

Rule:
- Any CLI dependency required by a setup/demo script MUST have an installer script under `compute_init/`, unless the tool is available by default on:
  - Ubuntu base image used by labs, or
  - Windows Server 2019 with PowerShell 5.

Placement:
- Ubuntu installers: `compute_init/ubuntu/install_<tool>.sh`
- Windows installers: `compute_init/windows/install_<tool>.ps1`

Documentation requirement:
- Each module MUST document required CLIs and whether they are:
  - `default` (already present in baseline image), or
  - `installed` (via `compute_init` script).

Verification requirement:
- If a dependency is marked `default`, module docs SHOULD cite the expected baseline image/version.
- If availability is uncertain, treat as non-default and provide install automation.

### B4) Tool Authoring Guardrails

All new tools in this domain MUST:
- Reuse existing `demos/utility` functions when functionally equivalent behavior exists.
- Add new utility functions before adding new direct API use in tool handlers.
- Keep tool handlers focused on orchestration, validation, and response shaping.
- Keep platform-specific installation logic out of tool handlers; place it in `compute_init`.

### B5) Review Checklist (Domain Gate)

A change passes domain review only if:
- No new committed inline outbound API calls exist in setup/demo scripts outside `demos/utility`.
- New required CLI dependencies are represented in `compute_init` (or explicitly justified as default on baseline OS).
- Utility function changes include caller compatibility review.
- Documentation for prerequisites is updated in the affected module.

### B6) Dynamic File Creation and Templating

Rule:
- Any file that contains dynamic values and is created/used at runtime MUST be template-driven.
- YAML with dynamic values MUST be committed as template files and resolved in scripts before use.

Template naming convention:
- `xyzname.tmpl.filetype`
- Examples:
  - `workload.tmpl.yaml`
  - `authenticator_public_key.tmpl.yaml`
  - `values.tmpl.json`

Resolution requirement:
- Scripts MUST use the shared template resolver function (`resolve_template`) to render templates.
- Do not inline YAML generation in scripts.
- Reference implementation: `demos/secrets_manager/k8s/setup/sm/setup.sh`

Heredoc policy:
- Heredocs are allowed only for very simple non-YAML content.
- Heredocs MUST NOT be used to create YAML.

### B7) Applies To (Current)

- All Vault automation (safe/account setup, membership, policy-linked access, provisioning, and lifecycle operations)
- All Conjur / Secrets Manager automation (identity/workload setup, policy application, service activation, secret operations, and integrations)
- `provision_safe`
- `provision_workload`
- `create_demo_safe` generated scripts
- Any current or future provisioning/integration tools, generated scripts, setup scripts, and helper workflows under these domains
