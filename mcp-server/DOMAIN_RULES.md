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

### B8) Demo Vars File Pattern

Rule:
- Demo-specific configuration SHOULD default to one shared file at `setup/vars.env`.
- Setup, cleanup, and validation entrypoints SHOULD all read the same demo-level vars file.

Required behavior:
- Avoid creating separate `vars.env` files under `setup/vault/`, `setup/conjur/`, or other subdirectories unless there is a documented technical reason.
- If a tool generates safe or workload scaffolding, it SHOULD write demo configuration into `setup/vars.env` instead of introducing multiple independent vars files.

Purpose:
- Prevent configuration drift between setup stages.
- Keep operator edits in one predictable location.

### B9) Remote Deployment Testability

Rule:
- Generated setup and test entrypoints SHOULD be safe for non-interactive remote execution.

Required behavior:
- Do not assume an interactive shell.
- If the lab environment relies on a standard profile script such as `/etc/profile.d/cyberark.sh`, entrypoints SHOULD source it explicitly when present.
- Demos intended for remote validation SHOULD prefer a top-level `test_runner.sh` and `cleanup.sh`.

Deployment-readiness expectation:
- Before declaring a demo ready for remote test deployment, verify the target repo copy actually contains the latest changes.
- File presence alone is not sufficient; the expected content or commit state must be visible on the deployment target.

### B10) Runtime Template Resolution

Rule:
- Files with runtime-dependent values MUST be committed as templates and resolved before use.

Required behavior:
- Summon variable maps with dynamic safe names or lab identifiers SHOULD be committed as template files such as `secrets.tmpl.yml`.
- Setup scripts SHOULD render the runtime file, for example `secrets.yml`, from the template before the demo executes.
- Demo scripts SHOULD consume the resolved file and MUST NOT rely on implicit shell expansion inside committed YAML.

### B11) Deployment Validation Scripts

Rule:
- Validation scripts SHOULD verify actual success, not only command execution.

Required behavior:
- `test_runner.sh` SHOULD fail if injected secrets are empty.
- Setup scripts SHOULD verify that critical Conjur resources actually exist after policy application.
- Cleanup scripts SHOULD target the same canonical identity path used by setup and runtime configuration.
