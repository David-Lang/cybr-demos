# Machine Identity Portfolio — Unified Workflow Demo

Single end-to-end demo covering the full CyberArk Machine Identity portfolio.

## Documentation Index

- `demo_setup.md` — How to deploy this demo
- `demo_validation.md` — Post-install walkthrough and runtime behavior
- `talk_track.md` — Presenter narrative with three delivery formats (full, abbreviated, executive)
- `setup/sai/sai_documentation_overview.md` — SAI architecture, workflows, security principles, and CyberArk docs reference
- `setup/sai/dp_tenant_preparations.md` — SAI/AI Gateway tenant prerequisites (roles, SIA MCP creation, known issues)

## Recommended Reading Order

1. `demo_setup.md`
2. `demo_validation.md`
3. `talk_track.md`

## Demo Scope

- **ISPSS Platform Authentication** — OAuth2 client_credentials
- **Conjur Cloud (Secrets Manager)** — Workload authn + secret fetch
- **Certificate Management — Three Approaches:**
  - **Conjur Cloud PKI** — Ephemeral short-lived workload certs (mTLS)
  - **VCert Python SDK** — Programmatic lifecycle: request, retrieve, renew, revoke
  - **cert-manager + CyberArk Issuer** — Kubernetes-native auto-provisioning and renewal
- **Secrets Hub** — PAM-to-cloud secret sync (AWS, Azure, GCP, HCV)
- **Secure Infrastructure Access (SIA)** — JIT SSH certificates
- **Secure Cloud Access (SCA)** — JIT cloud entitlements
- **Secure AI Agents** — Agentic identity lifecycle, AI Gateway, MCP server inventory

## Related Repositories

These sibling repos in `/Repo` complement different aspects of this demo:

| Repo | What It Adds | Relevant Steps |
|------|-------------|----------------|
| [`secure-aiagent-secrets`](../../../secure-aiagent-secrets/) | Production reference architecture — Conjur OSS JWT auth, n8n workflow automation, LLM Guard input/output scanning. Shows the implementation depth behind Step 8 with real credential sync and multi-layer LLM security. | Step 8 (SAI) |
| [`secure-ai-sme`](../../../secure-ai-sme/) | SME knowledge base — 7-layer least-privilege framework, 5-layer audit trail model, OWASP Top 10 for LLMs control mapping, competitive positioning (AWS/Azure/HashiCorp), regulatory alignment (NIST AI RMF, EU AI Act). Deepens the talk track narrative. | Step 8 (SAI), Summary |
| [`agent-orchestration`](../../../agent-orchestration/) | CrewAI multi-agent swarm (6 agents, triple-layer memory, A2A/ACP protocols). Currently has zero CyberArk integration — serves as a live example of unmanaged NHIs and a future integration target. | Gap analysis target |
| [`aws-bedrock-demo`](../../../aws-bedrock-demo/) | FinOps multi-agent on Amazon Bedrock (supervisor + specialists). Demonstrates multi-agent IAM delegation patterns. | Step 1 (ISPSS), Step 8 (SAI) |

### Deep Dive Paths

- **After Step 8 (SAI)**: Walk through `secure-aiagent-secrets` to show a working Conjur + AI agent integration with JWT-based identity, credential sync, and LLM Guard protection.
- **After Summary**: Reference `secure-ai-sme/security/least-privilege-agents.md` for the 7-layer framework and `secure-ai-sme/security/agent-audit-trail.md` for the 5-layer audit model.
- **For "why does this matter" conversations**: Use `secure-ai-sme/research/market-landscape.md` for competitive positioning and `secure-ai-sme/research/owasp-llm-control-mapping.md` for OWASP alignment.
