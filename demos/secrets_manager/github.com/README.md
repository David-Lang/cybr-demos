# Demo: GitHub Actions

This demo shows GitHub Actions workflows retrieving secrets from CyberArk Secrets Manager by authenticating with a GitHub OIDC JWT (and, optionally, a workload API key) instead of long-lived static credentials. The secrets are synchronized into Secrets Manager from a Privilege Cloud safe.

Use the repo-standard docs for deployment and validation:

- `demo_setup.md`
- `demo_validation.md`

Official CyberArk references for this use case:

- [Secrets Manager authentication methods](https://docs.cyberark.com/secrets-manager-saas/latest/en/content/operations/authn/authn-lp.htm)
- [Set up JWT authentication](https://docs.cyberark.com/secrets-manager-saas/latest/en/content/operations/authn/authenticate-jwt-config.htm)

GitHub references for OIDC:

- [About security hardening with OpenID Connect](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
- [OIDC configuration endpoint](https://token.actions.githubusercontent.com/.well-known/openid-configuration)

## About

- GitHub Actions requests a short-lived OIDC JWT that carries the workflow `actor` claim.
- The `authn-jwt/github1` authenticator validates that JWT against the GitHub JWKS and issuer.
- Secrets Manager maps the `actor` claim to a Conjur host under `data/workloads/github-actor`.
- Conjur authorizes that host to read variables synchronized from the demo safe.
- The workflows in the `idira-github-actions` repo consume the result via the `cyberark/conjur-action` plugin, raw `curl`, or the Conjur Terraform provider.

## Workflow

```mermaid
sequenceDiagram
    autonumber
    participant GHA as GitHub Actions job
    participant OIDC as GitHub OIDC provider
    participant JWT as authn-jwt/github1
    participant Conjur as Conjur Policy + Variables
    participant Vault as Privilege Cloud Safe

    GHA->>OIDC: Request OIDC JWT (actor claim)
    OIDC-->>GHA: Signed JWT
    GHA->>JWT: Authenticate with JWT
    JWT->>Conjur: Map actor to Conjur host
    Conjur->>Vault: Read synced safe variables
    Vault-->>Conjur: Return account values
    Conjur-->>GHA: Authorize and return session token / values
```

## Key Files

- `setup.sh`
  Bootstrap + validation: provisions the safe, the JWT authenticator, and the workload, maps the values, configures the GitHub repository, then runs `setup/validate.sh`.
- `demo.sh`
  Runs the demo: triggers the GitHub Actions workflows on `GH_REF` (default `aardvark`) via the `gh` CLI and lists the runs.
- `setup/vars.env`
  Shared demo configuration: `SAFE_NAME`, `JWT_CLAIM_IDENTITY`, `GH_REPO`, `GH_ENVIRONMENTS`, `TRUFFLEHOG_REPOS`, `TFVAR_*` (all env-overridable).
- `setup/vault/setup.sh`
  Creates the demo safe, grants required members, and creates `account-ssh-user-1`.
- `setup/conjur/setup.sh`
  Creates and activates the `github1` JWT authenticator and the `github-actor` workload, and grants safe access.
- `setup/github/setup.sh`
  Maps `CONJUR_*` to `SM_*`, rotates the api-key credential, and configures the GitHub repo via `setup/github/init-gh-vars-secrets.sh`.
- `setup/validate.sh`
  Confirms the server side (authenticator, workload, safe delegation) and the GitHub repo (variables, secrets, environments) are in place.
- `remove.sh`
  Removes the workload and safe artifacts created by setup.

## GitHub Configuration

This demo is authoritative for both sides. `setup/github/setup.sh` maps the rendered `CONJUR_*` values to the `SM_*` names the workflows consume, provisions the api-key credential (by rotating the workload host key), and calls `setup/github/init-gh-vars-secrets.sh` to create the repository variables, secrets, and environments in `GH_REPO`. The `idira-github-actions` repo holds only the workflows, Terraform config, and docs. Requires the `gh` CLI authenticated for `GH_REPO`.
