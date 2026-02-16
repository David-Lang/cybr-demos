# Global Tool Contract v1

Status: Draft (adopt for all MCP tools in this repo)
Scope: Layer A rules that apply to every tool call
Audience: Tool authors, reviewers, and MCP orchestrators

## 1) Purpose

This contract defines non-negotiable behavior for all tools to support:
- Stable and repeatable labs
- Demonstrates automation in non-production environments
- Clarity of operations is more important than speed
- Is easy to understand and learn from

All tool-specific contracts (Layer C) inherit this contract.

## 2) Contract Inheritance

All tools MUST follow:
1. Layer A: this global contract
2. Layer B: domain contract in `mcp-server/DOMAIN_RULES.md` (if applicable, e.g. automation shared library, AWS, K8s, Vault)
3. Layer C: tool-specific contract

When rules conflict, apply precedence in this order: A > B > C.

## 3) Canonical Request Envelope

Every tool invocation MUST be normalized to the following shape before execution.

```json
{
  "request_id": "uuid-or-stable-id",
  "tool_name": "string",
  "contract_version": "global/v1",
  "idempotency_key": "string-or-null",
  "dry_run": false,
  "caller": {
    "type": "user|service|agent",
    "id": "string"
  },
  "lab_context": {
    "solution_format": "saas|self_hosted",
    "environment": "dev|test|demo|prod"
  },
  "params": {}
}
```

Rules:
- `request_id`, `tool_name`, `contract_version`, `caller`, `params` are required.
- `dry_run` defaults to `false`.
- Mutating tools SHOULD require `idempotency_key`.
- Unknown top-level fields MUST be ignored or rejected consistently per tool definition.

## 4) Canonical Response Envelope

Every tool response MUST use this shape.

```json
{
  "status": "ok|partial|error",
  "request_id": "string",
  "tool_name": "string",
  "contract_version": "global/v1",
  "duration_ms": 0,
  "result": {},
  "warnings": [],
  "errors": [],
  "meta": {
    "timestamp_utc": "2026-02-16T00:00:00Z",
    "redactions_applied": 0,
    "next_cursor": null
  }
}
```

Rules:
- `status=ok` means operation completed fully.
- `status=partial` means useful work completed with degraded or incomplete outcomes.
- `status=error` means requested operation failed.
- `errors` MUST be non-empty when `status=error`.

## 5) Determinism and Idempotency

- Tools MUST normalize inputs deterministically (e.g., trim whitespace, canonical path handling).
- Repeated calls with same normalized input and same idempotency context MUST not create duplicate side effects.
- Mutating operations MUST be replay-safe where supported by backend APIs.
- If idempotency cannot be guaranteed, tool MUST return typed error `IDEMPOTENCY_UNSUPPORTED`.

## 6) Typed Error Model

Each error MUST conform to:

```json
{
  "code": "VALIDATION_FAILED",
  "message": "Human-readable summary",
  "category": "VALIDATION|AUTH|PERMISSION|NOT_FOUND|CONFLICT|RATE_LIMIT|DEPENDENCY|INTERNAL|SAFETY_BLOCKED",
  "retryable": false,
  "http_status": 400,
  "details": {},
  "remediation": "Actionable next step"
}
```

Required global codes:
- `VALIDATION_FAILED`
- `AUTH_FAILED`
- `PERMISSION_DENIED`
- `RESOURCE_NOT_FOUND`
- `RESOURCE_CONFLICT`
- `RATE_LIMITED`
- `DEPENDENCY_UNAVAILABLE`
- `INTERNAL_ERROR`
- `SAFETY_BLOCKED`
- `IDEMPOTENCY_UNSUPPORTED`

## 7) Retry, Timeout, and Partial Failure

- Each tool MUST define a default timeout and expose it in Layer C docs.
- Automatic retries are allowed only when `retryable=true`.
- Use bounded exponential backoff for transient failures.
- Partial failures MUST return `status=partial` and include itemized failures in `warnings` or `errors`.

## 8) Logging and Redaction

Never log or return in clear text:
- Access tokens
- API keys
- Passwords
- Private keys
- Secret values

Redaction standard:
- Replace sensitive values with `***REDACTED***`.
- `meta.redactions_applied` MUST reflect count of replacements.

Audit minimum fields for every call:
- `timestamp_utc`
- `request_id`
- `caller.id`
- `tool_name`
- `target` (if applicable)
- `status`

## 9) Auth and Permission Boundaries

- Tools MUST execute with least privilege.
- No implicit escalation.
- Any privileged mode MUST be explicit and policy-gated.
- Destructive actions MUST require explicit confirmation semantics in Layer C.

## 10) Safety Constraints (Hard Stops)

Tools MUST NOT:
- Exfiltrate secrets or credentials
- Disable security controls silently
- Perform destructive actions against protected environments without explicit guardrails
- Use ambiguous target resolution (must resolve a single, explicit target)

High-risk mutating tools SHOULD support:
- `dry_run=true` preview
- Preflight checks before execution

## 11) Resource Naming, Filtering, and Paging

Naming:
- Resource IDs SHOULD use lowercase alphanumeric plus `-` or `_` unless backend requires otherwise.
- Inputs MUST be normalized and validated against tool/domain rules.

Filtering:
- Shared selectors SHOULD use a consistent pattern: `name`, `tags`, `created_after`, `limit`, `cursor`.

Paging:
- List operations MUST return stable ordering.
- Responses with additional records MUST set `meta.next_cursor`.

## 12) Output Conventions

- JSON-first, machine-readable responses.
- Timestamps MUST be ISO-8601 UTC.
- Field names MUST be stable and documented.
- Human-readable summaries MAY be included but MUST NOT replace structured fields.

## 13) Versioning and Compatibility

- This document uses version tag `global/v1`.
- Breaking changes require `global/v2`.
- Non-breaking additions increment minor revision in changelog, not the major contract tag.
- Every tool response MUST include `contract_version`.

## 14) Validation Checklist (Definition of Done for New Tools)

Before a tool is considered complete, verify:
- Request envelope normalized and validated
- Response envelope conforms to Section 4
- Errors mapped to Section 6 schema
- Redaction enforced for logs and outputs
- Idempotency strategy documented
- Safety constraints satisfied
- Timeout/retry behavior documented
- Paging/filtering (if list tool) documented
- Documentation scope rule in Section 17 is satisfied

## 15) Implementation Notes for This Repo

To enforce this contract in `mcp-server`:
- Add a single call wrapper that applies request/response envelopes for all tools.
- Add centralized error mapping utility.
- Add centralized redaction utility for logs and tool output.
- Add contract tests that every tool must pass.

Recommended files:
- `mcp-server/src/contract/global-contract.js`
- `mcp-server/src/contract/error-map.js`
- `mcp-server/src/contract/redaction.js`
- `mcp-server/test/contract/*.test.js`

## 16) Charter Alignment

This contract is designed to support the lab charter by prioritizing:
- Stability of published labs over ad hoc flexibility
- Modular and extensible tooling
- Minimal required inputs with standardized integration points
- Safe, secure, and auditable automation
- Contributor-friendly and SE-accessible workflows

## 17) MCP Documentation Scope Boundary (Hard Rule)

MCP tool contracts, MCP tool usage notes, and MCP-specific operational guidance in markdown/readme files are only allowed under `mcp-server/`.

Repository-wide requirements:
- Files outside `mcp-server/` MUST NOT reference MCP tools, MCP contracts, or MCP workflow notes.
- Demo/module docs under `demos/` MUST describe demo behavior using local scripts and platform capabilities only.
- If MCP guidance is needed for a demo, it MUST be documented in `mcp-server/` and linked from MCP-owned docs only.

Compliance guidance:
- Treat MCP as an internal orchestration layer, not a public dependency of demos.
- During review, any MCP references found outside `mcp-server/` MUST be removed before merge.
