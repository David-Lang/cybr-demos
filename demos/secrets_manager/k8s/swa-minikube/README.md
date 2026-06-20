# Demo: Secure Workload Access (SWA) on Kubernetes (minikube)

> **Folder:** `demos/secrets_manager/k8s/swa-minikube/` — local minikube + official SWA release zip.
> For the separate upstream giftapp/Rancher demo, see [`../../swa_k8s/`](../../swa_k8s/).

CyberArk **Secure Workload Access (SWA)** issues SPIFFE-compliant workload identities and
integrates with Secrets Manager so a Kubernetes workload can fetch a short-lived **JWT-SVID**
and exchange it for a Conjur Cloud secret — no API keys, no long-lived service-account tokens
leaving the cluster.

End-to-end flow:

```text
Privilege Cloud Safe -> Conjur Sync -> Conjur Cloud (SaaS)        [= SWA control plane]
                                          ^                         ^
                terraform-provider-swa ───┘ (trust domain,          │ authn-jwt/secureWorkloadAccess
                                            server group, node       │ validates the JWT-SVID
                                            group, server)           │
SWA Server (in-cluster) ── node attest (k8s_psat) ──> SWA Agent (DaemonSet)
                                                          │ workload attest (k8s) + JWT-SVID
                                                          v
                                                       Workload pod ── JWT-SVID ──> Conjur Cloud -> secret
```

Two JWT authenticators are in play:

| Authenticator | Who uses it | Validates against |
|---|---|---|
| SWA Server -> control plane | the in-cluster SWA Server | the `swa_server` registration (inline `public_keys` from the cluster OIDC, since Conjur Cloud cannot reach minikube) |
| `authn-jwt/secureWorkloadAccess` | the **workload** | the trust domain's hosted JWKS (`<control-plane>/.../.well-known/jwks`) |

The trust domain JWT signing must be **RSA** (`RS256` / `RSA_2048`) — elliptic-curve signing is
not supported on the `authn-jwt` path.

## Prerequisites

- A running **minikube** cluster (`minikube start --driver=docker`) as the current kubectl context.
- `kubectl`, `helm`, `terraform`, `jq`, `curl`, `minikube` on PATH.
- The SWA release zip from the CyberArk Marketplace
  (`Secure Workload Access_1.0_*.zip`) in `~/Downloads` (or pin `SWA_RELEASE_ZIP`). ~195MB, not committed.
- Tenant credentials in `demos/tenant_vars.sh` (`TENANT_ID`, `TENANT_SUBDOMAIN`, `CLIENT_ID`, `CLIENT_SECRET`).

## Quick start

```bash
export CYBR_DEMOS_PATH=/path/to/cybr-demos
cd demos/secrets_manager/k8s/swa-minikube

cp setup/vars.env.example setup/vars.env
vi setup/vars.env                 # SAFE_NAME, trust domain, control-plane URL, release path

bash check_prereqs.sh
bash go.sh                        # full bootstrap (M1 + M2 + M3)
bash smoke.sh                       # M1 + M2 + M3 acceptance
bash ready_check.sh               # M3 readiness
bash demo.sh                      # interactive walkthrough (12 steps; step 5 auto-opens spiffe-info)

# Optional env for demo.sh:
#   SKIP_SPIFFE_INFO=1          skip Workload API inspector beat
#   SPIFFE_INFO_PORT=18080      if :8080 is taken
bash go_m1.sh && bash smoke_m1.sh   # platform only
bash go_m2.sh && bash smoke_m2.sh   # + authn-jwt
bash go_m3.sh && bash ready_check.sh # + workload + spiffe-info + acme-carrier

# Visual SVID inspector (after go.sh)
kubectl port-forward -n swa-demo svc/spiffe-info 8080:80
```

## Scripts

| Script | Purpose |
|--------|---------|
| `go.sh` | **Main entry** — full bootstrap (8 stages including spiffe-info + acme-carrier) |
| `go_m1.sh` / `go_m2.sh` / `go_m3.sh` | Incremental bootstrap by milestone |
| `smoke.sh` / `smoke_m1.sh` / `smoke_m2.sh` | Milestone acceptance checks |
| `setup.sh` | Alias for `go.sh` (after prereqs) |
| `check_prereqs.sh` | Pass/fail prerequisite triage before bootstrap |
| `ready_check.sh` | M3 pass/fail readiness before presenting |
| `demo.sh` | Interactive walkthrough (12 steps, press ENTER between steps) |
| `remove.sh` | Teardown: terraform destroy (with retry), helm, namespaces, safe |
| `setup/swa/deploy_spiffe_info.sh` | Deploy [spiffe-info](https://github.com/MattiasGees/spiffe-info) JWT/X.509 inspector UI |
| `setup/swa/deploy_acme.sh` | Deploy foreign-trust-domain acme-carrier (trust-boundary beat) |
| `setup/swa/load_release.sh` | Extract release, `minikube image load`, stage terraform provider mirror |
| `setup/swa/install_server.sh` / `install_agent.sh` | Render values + `helm upgrade --install` |
| `setup/conjur/enable_swa_authenticator.sh` | Configure + activate `authn-jwt/secureWorkloadAccess`, grant workload access |
| `setup/vault/setup.sh` | Privilege Cloud safe + account + Conjur Sync |

## Documentation

| File | Purpose |
|------|---------|
| [demo_setup.md](demo_setup.md) | Deployment, configuration, troubleshooting |
| [demo_validation.md](demo_validation.md) | Post-install validation walkthrough |
| [talktrack.md](talktrack.md) | Presenter script |
| [setup/swa/README.md](setup/swa/README.md) | Release artifacts, control-plane URL, terraform notes |

## Clean up

```bash
bash remove.sh
```

## Reference

- [Understand SPIFFE workload identities (SWA overview)](https://docs.cyberark.com/secrets-manager-saas/latest/en/content/conjurcloud/ccl-swa-overview.htm)
- [Integrate SWA with Secrets Manager JWT authentication](https://docs.cyberark.com/secrets-manager-saas/latest/en/content/operations/services/cjr-authn-jwt-swa.htm)
