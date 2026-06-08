# SWA release artifacts + control-plane notes

This folder stages the **Secure Workload Access** release (helm charts, container images,
terraform provider) and registers the SWA control-plane objects in Conjur Cloud.

## What `load_release.sh` does

1. Finds the release zip (`SWA_RELEASE_ZIP`, else newest `Secure Workload Access*.zip` in `SWA_RELEASE_DIR`).
2. Extracts `swa-release-v1.0.0.tgz` into `release/` (gitignored, ~195MB).
3. `minikube image load`s the arch-matched images:
   - `swa-server:1.0.0-<arch>` and `swa-agent:1.0.0-<arch>` (`arm64v8` on Apple Silicon, `amd64` on Intel/EKS).
4. Copies the matching `terraform-provider-swa` binary into a local filesystem mirror and writes
   `.terraformrc` so `terraform init` resolves the provider offline.

## What `register.sh` does

Runs `terraform apply` (config in `terraform/`) to create:

- `swa_trust_domain` — RSA JWT signing (required by the `authn-jwt` integration).
- `swa_server_group` — `k8s_psat` node attestation; allow-lists `<SWA_NAMESPACE>/<SWA_AGENT_SA>`.
- `swa_node_group` — `kubernetes` workload type; SPIFFE template
  `spiffe://{{ .trustdomain }}/{{ .nodegroup }}/ns/{{ .k8s.ns }}/sa/{{ .k8s.sa }}`.
- `swa_server` — the in-cluster server's registration; uses inline `public_keys` (cluster OIDC JWKS,
  since Conjur Cloud cannot reach minikube). Its `authn_id` output feeds the swa-server helm chart.

The provider authenticates with `CONJUR_APPLIANCE_URL` + `CONJUR_AUTHN_TOKEN` (set by the script).

## Values verified against a live tenant (v1.0)

These were confirmed end-to-end on a real tenant; all are configurable in `setup/vars.env`:

- `SWA_CONTROL_PLANE_URL` — the SWA control-plane base URL the **server** registers with.
  Defaults to `https://<subdomain>.secretsmgr.cyberark.cloud` (confirmed correct).
- **Trust domain issuer / JWKS** used by `authn-jwt/secureWorkloadAccess` to validate workload
  JWT-SVIDs:
  - issuer:  `https://<subdomain>.secretsmgr.cyberark.cloud/api/swa/trust-domains/<trust-domain>`
  - JWKS:    that URL + `/.well-known/jwks`
  - OIDC discovery (`.../.well-known/openid-configuration`) works at the issuer URL, so
    `enable_swa_authenticator.sh` auto-discovers both; override with `SWA_TD_JWKS_URI` /
    `SWA_TD_ISSUER` only if discovery is blocked.
- `cluster_issuer` — minikube defaults to `https://kubernetes.default.svc.cluster.local`;
  `register.sh` reads the live `iss` claim when the server SA already exists.

### v1.0 gotchas already handled in the scripts

- **Server-group SA allow-list uses `namespace:serviceaccount`** (colon), not a slash. The provider
  example shows a slash, but node attestation only matches the colon form.
- **The provider's `CONJUR_AUTHN_TOKEN` must be the decoded JSON token.** `get_conjur_token` returns
  base64; `register.sh` base64-decodes it before exporting.
- **`swa-agent api fetch jwt -s` takes a plain socket path** (`/run/swa/public/api.sock`), not a
  `unix://` URI — the client prepends the scheme itself.
- **`swa_node_group.workload_configuration` is a nested attribute** (`= { ... }`), not a block.
