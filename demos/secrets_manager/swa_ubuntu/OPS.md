---
title: "SWA Ubuntu — Operations Guide"
doc_type: ops
---

# SWA Ubuntu — Operations Guide

Practical knowledge for running, debugging, and re-running this demo. Read this before
touching the setup scripts or when something breaks.

---

## Setup Order

```
# On the jumpbox VM — credentials must be in the environment
export CYBR_DEMOS_PATH=/opt/cybr-demos
export SWA_MODE=real

cd $CYBR_DEMOS_PATH/demos/secrets_manager/swa_ubuntu

bash setup/swa/register_control_plane.sh   # Terraform: creates SWA control plane in Conjur
bash setup.sh                               # Conjur policies + JWT auth + installs SWA server + agent
bash demo.sh                                # Run the demo
```

**Required environment variables** (set in the VM login shell):

| Variable | Example | Source |
|---|---|---|
| `CYBR_DEMOS_PATH` | `/opt/cybr-demos` | Set manually |
| `LAB_ID` | `dcnl-pci-df71` | Set by lab provisioner |
| `TENANT_ID` | `abe4736` | CyberArk tenant |
| `TENANT_SUBDOMAIN` | `poc-cdn-isp` | CyberArk tenant |
| `CLIENT_ID` | `svc@example.com` | ISP service account |
| `CLIENT_SECRET` | `...` | ISP service account |
| `SWA_MODE` | `real` | Set manually |

---

## Tearing Down a Lab

**Always run deregister before deleting the lab VM.** The SWA Terraform provider does not
fully clean up Conjur resources on destroy, so orphaned authenticators will block the next
registration if you reuse the same resource names.

```bash
cd $CYBR_DEMOS_PATH/demos/secrets_manager/swa_ubuntu
bash setup/swa/deregister_control_plane.sh
```

Then delete the lab.

---

## Known Issues

### 1. Conjur resources are not cleaned up on `terraform destroy` (SWA provider bug)

**Symptom:** `register_control_plane.sh` fails with:
```
Error: API returned status 409: conjur_resource_already_exists
```

**Cause:** The SWA Terraform provider leaves Conjur JWT authenticators behind when
destroying a server or trust domain. The next registration attempt collides with the
orphaned resource.

**Automatic prevention:** `vars.env` scopes all resource names to `LAB_ID` by default:
```
SWA_RESOURCE_PREFIX=swa-<LAB_ID>
SWA_TRUST_DOMAIN_NAME=swa-<LAB_ID>.workloads.local
SWA_NODE_GROUP_NAME=swa-<LAB_ID>-nodes
```
Each lab gets unique names, so collisions only happen if the same lab is re-registered
without running `deregister_control_plane.sh` first.

**Fix if you hit it:**
```bash
bash setup/swa/deregister_control_plane.sh
bash setup/swa/register_control_plane.sh
```
If deregister also fails, manually delete the trust domain from the CyberArk admin
console under Secrets Manager → Secure Workload Access.

---

### 2. `swa_server` does not support in-place Terraform updates

**Symptom:** `register_control_plane.sh` fails with:
```
Error: Update Not Supported — Servers cannot be updated. Delete and recreate the resource instead.
```

**Cause:** The SWA Terraform provider rejects any update to an existing `swa_server`
resource (e.g., changing the auth subject). The resource must be destroyed and recreated.

**Automatic fix:** `register_control_plane.sh` detects this error and automatically
retries with `-replace=swa_server.demo`. No manual action needed.

---

### 3. ISP token `sub` claim is a UUID, not the `CLIENT_ID` email

**Symptom:** `swa-server` starts but immediately fails with:
```
conjur authentication failed: status 401
```

**Cause:** The Conjur JWT authenticator for the SWA Server validates the `sub` claim in
the ISP token. The `sub` is a UUID (e.g., `c60588c1-b0a9-4277-8171-010333ed9b06`),
but `CLIENT_ID` is the email/username used to obtain the token. Terraform must receive
the UUID as `client_subject`, not the email.

**Automatic fix:** `register_control_plane.sh` decodes the `sub` claim from the ISP token
at step 1 and passes it to Terraform as `client_subject`. This happens automatically.

If you see the UUID in the registration output:
```
[1/5] Authenticating to Conjur...
      ISP token sub: c60588c1-b0a9-4277-8171-010333ed9b06
```
it is working correctly.

---

### 4. ISP token TTL (~15 min) is shorter than the default refresh interval

**Symptom:** `swa-server` runs fine for ~15 minutes then starts failing with 401 in a loop.

**Cause:** ISP tokens from `grant_type=client_credentials` expire in approximately
15 minutes. The `swa-token-refresh` systemd timer must run more frequently than the TTL.

**Fix already applied:** `install_server.sh` sets:
- `OnBootSec=1min` — first refresh 1 minute after boot
- `OnUnitActiveSec=10min` — refresh every 10 minutes thereafter

If you see the server failing with 401 after previously working, check the timer:
```bash
sudo systemctl status swa-token-refresh.timer
sudo journalctl -u swa-token-refresh -n 10
```
And manually trigger a refresh:
```bash
sudo systemctl start swa-token-refresh.service
sudo systemctl restart swa-server
```

---

### 5. Special characters in `CLIENT_SECRET` are mangled in systemd unit files

**Symptom:** Token refresh timer runs but produces an invalid token; password contains
`\`, `%`, `<`, `>`, `|`, `(`, `)` or similar.

**Cause:** systemd silently drops unknown backslash escape sequences (e.g., `\p → p`)
when parsing `ExecStart=` values in unit files. This corrupts passwords with backslashes.

**Fix already applied:** `install_server.sh` writes credentials to `/etc/swa/refresh.env`
(mode `0600`) and loads them via `EnvironmentFile=`. systemd never parses the credential
values — they are expanded by the shell at runtime.

---

### 6. `setup.sh` must be run after `register_control_plane.sh`

`setup.sh` sources `setup/swa/swa_registered.env` (written by `register_control_plane.sh`)
to get `SWA_OIDC_ISSUER`. If that file doesn't exist and `SWA_MODE=real`, `setup.sh` exits
with an error.

Running order is always:
1. `register_control_plane.sh`
2. `setup.sh`

---

## Checking SWA Server Health

```bash
# Service status
sudo systemctl status swa-server
sudo journalctl -u swa-server -n 30 --no-pager

# Token freshness (should show exp > now)
sudo cat /etc/swa/token | cut -d. -f2 | tr '_-' '/+' | \
  awk '{n=length($0)%4; if(n==2) print $0"=="; else if(n==3) print $0"="; else print $0}' | \
  base64 -d | python3 -c 'import sys,json,datetime; d=json.load(sys.stdin); print("sub:", d["sub"]); print("exp:", datetime.datetime.utcfromtimestamp(d["exp"]))'

# Manual auth test (should return HTTP 200 with a Conjur token)
TOKEN=$(sudo cat /etc/swa/token)
LOGIN_URL=$(grep SWA_SERVER_LOGIN_URL /opt/cybr-demos/demos/secrets_manager/swa_ubuntu/setup/swa/swa_registered.env | cut -d= -f2- | tr -d '"' | base64 -d)
curl -s -o /dev/null -w "%{http_code}" -X POST "$LOGIN_URL" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "jwt=$TOKEN"
```

## Checking SWA Agent Health

```bash
sudo systemctl status swa-agent
sudo journalctl -u swa-agent -n 30 --no-pager
ls -la /run/swa-agent/api.sock   # must exist when agent is running
/opt/swa/bin/swa-agent api fetch jwt --audience conjur
```
