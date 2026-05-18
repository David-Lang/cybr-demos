# ESO + CyberArk Conjur Cloud — References

Sources used to build, configure, and troubleshoot this demo.

## External Secrets Operator

| Resource | URL |
|---|---|
| ESO Conjur Provider (primary reference) | https://external-secrets.io/latest/provider/conjur/ |
| ESO Conjur JWT Auth (Option 2) | https://external-secrets.io/latest/provider/conjur/#option-2-external-secret-store-with-jwt-authentication |
| ESO Installation / Helm Chart | https://external-secrets.io/latest/introduction/getting-started/ |
| ESO API — SecretStore | https://external-secrets.io/latest/api/secretstore/ |
| ESO API — ExternalSecret | https://external-secrets.io/latest/api/externalsecret/ |
| ESO GitHub Repo | https://github.com/external-secrets/external-secrets |
| Accelerator-K8s-External-Secrets (CyberArk example repo) | https://github.com/conjurdemos/Accelerator-K8s-External-Secrets |

## CyberArk Conjur Cloud

| Resource | URL |
|---|---|
| Conjur Cloud JWT Authenticator Setup | https://docs.cyberark.com/conjur-cloud/latest/en/Content/Integrations/k8s-ocp/k8s-jwt-authn.htm |
| Conjur JWT Authentication Guidelines | https://docs.cyberark.com/conjur-open-source/Latest/en/Content/Operations/Services/cjr-authn-jwt-guidelines.htm |
| Conjur Policy Reference | https://docs.cyberark.com/conjur-cloud/latest/en/Content/Operations/Policy/policy-statement-ref.htm |
| Conjur Cloud REST API | https://docs.cyberark.com/conjur-cloud/latest/en/Content/Developer/Conjur_API_v5.htm |
| Conjur Synchronizer (Privilege Cloud to Conjur) | https://docs.cyberark.com/conjur-cloud/latest/en/Content/ConjurCloud/cl_ConjurSynchronizer.htm |

## CyberArk Identity / ISPSS

| Resource | URL |
|---|---|
| ISPSS OAuth2 Client Credentials Flow | https://docs.cyberark.com/identity/latest/en/Content/Developer/Developer-idp-OAuth2-ClientCreds.htm |
| Privilege Cloud REST API — Safes | https://docs.cyberark.com/privilege-cloud-shared-services/latest/en/Content/SDK/Safes%20Web%20Services%20-%20List%20Safes.htm |
| Privilege Cloud REST API — Accounts | https://docs.cyberark.com/privilege-cloud-shared-services/latest/en/Content/SDK/Add%20Account.htm |

## Kubernetes

| Resource | URL |
|---|---|
| K8s TokenRequest API (JWT source for ESO) | https://kubernetes.io/docs/reference/kubernetes-api/authentication-resources/token-request-v1/ |
| K8s ServiceAccount Tokens | https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/ |
| K8s Secrets | https://kubernetes.io/docs/concepts/configuration/secret/ |

## Tools

| Tool | URL |
|---|---|
| k9s — Terminal UI for Kubernetes | https://k9scli.io/ |
| k9s GitHub | https://github.com/derailed/k9s |
| Helm | https://helm.sh/ |
| ShellCheck (used by this repo's CI) | https://www.shellcheck.net/ |

## Key Decisions and Lessons Learned

These came out of the actual build session and are documented here for future reference.

**CLIENT_ID login suffix matters.** The CyberArk Identity service account login suffix must exactly match the tenant subdomain. `conjurinstaller@zach-lab` works; `conjurinstaller@zachlab` returns `access_denied`. The hyphen matters.

**CLIENT_SECRET with special characters in bash.** Complex passwords containing `}`, `&`, `^`, etc. break `${VAR:-default}` parameter expansion. Use an `if/else` block with single-quoted direct assignment instead.

**Conjur Sync must be a safe member before policy loading.** The `delegation/consumers` group for a safe only exists in Conjur after the Conjur Synchronizer (DAPService) has been added as a member of the safe in Privilege Cloud and completed its sync cycle.

**identity-path must match the host's policy branch.** The JWT authenticator variable `conjur/authn-jwt/zg-eso/identity-path` is prepended to the JWT `sub` claim to resolve the Conjur host. If the host is defined at `data/poc-workloads/...`, the identity-path must be `data/poc-workloads` — not `data/k8s/eso` or any other path.

**ESO webhook needs time to start.** After Helm install, the webhook and cert-controller pods must be fully ready before applying SecretStore resources. Use `kubectl rollout status` to gate on readiness.
