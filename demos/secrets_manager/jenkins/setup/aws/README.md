# AWS lab VM checklist (Jenkins demo)

Manual steps when provisioning a new EC2 host for `DEPLOY_PROFILE=aws`. No Terraform in this folder for v1.

## Instance

- AMI: Ubuntu 22.04 LTS
- Size: t3.medium or larger
- Storage: 30 GB+

## Security group

| Port | Source | Purpose |
|------|--------|---------|
| 22 | Your IP | SSH |
| 8081 | Your IP | Jenkins UI (default `JENKINS_PORT`) |
| 8081 | Optional: CyberArk SaaS egress | Only required if you opt out of public-keys mode (see below) |

`finish_setup.sh` runs in **public-keys mode** by default — it mirrors the Jenkins plugin's live JWKS into the Conjur `public-keys` variable and PATCH-deletes `jwks-uri`, so Conjur Cloud verifies JWT signatures locally and does **not** need inbound reach back to your EC2 host. The 8081-from-CyberArk-SaaS rule is only needed if you intentionally switch the authenticator to fetch JWKS over the internet.

If you do opt into `jwks-uri` mode and JWT auth fails with a JWKS timeout, verify Conjur Cloud can reach `http://<public-dns>:8081/jwtauth/conjur-jwk-set`.

## Bootstrap

```bash
sudo apt-get update && sudo apt-get install -y docker.io git curl jq
sudo usermod -aG docker "$USER"
# log out and back in

export CYBR_DEMOS_PATH=$HOME/cybr-demos
git clone <your-fork-or-upstream> "$CYBR_DEMOS_PATH"
cd "$CYBR_DEMOS_PATH/demos/secrets_manager/jenkins"
cp setup/vars.env.example setup/vars.env
# edit SAFE_NAME, ensure DEPLOY_PROFILE=aws
cp "$CYBR_DEMOS_PATH/demos/tenant_vars.local.sh.example" \
   "$CYBR_DEMOS_PATH/demos/tenant_vars.local.sh"
# fill in TENANT_ID, TENANT_SUBDOMAIN, CLIENT_ID, CLIENT_SECRET
bash check_prereqs.sh
bash go.sh
bash ready_check.sh
```

## Post-setup

Follow `demo_validation.md` for Jenkins plugin configuration and pipeline run.

## Teardown

```bash
bash remove.sh
# optional: terminate EC2 instance
```
