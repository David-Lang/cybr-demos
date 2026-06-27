# CyberArk Lab Tooling

This is an optional way to create disposable CyberArk lab infrastructure for demo setup and validation. Use it when you need a fresh lab and do not already have suitable infrastructure available.

The shared `cybr-lab-*` commands live outside this repo and can be used from any workspace. They trigger a configured infrastructure workflow, download the resulting CloudFormation outputs, and make those outputs easy to inspect.

## One-Time Setup

Install the lab tooling from the `spin_cfn` checkout:

```bash
cd /path/to/spin_cfn
./install.sh
```

Make sure `~/bin` is on your `PATH`:

```bash
export PATH="$HOME/bin:$PATH"
```

Then edit your local config:

```bash
vi ~/.cybr-labs/config.env
```

The config file is intentionally outside this repo and should not be committed. It should define:

```bash
LAB_CFN_REPO=owner/repo
LAB_CFN_WORKFLOW=workflow-file.yml
LAB_CFN_BRANCH=your-branch
LAB_CFN_ENVIRONMENT=your-environment
LAB_ARTIFACTS_DIR=$HOME/.cybr-labs/artifacts
SSH_KEY_PATH=$HOME/.ssh/your-keypair.pem
```

Use `spin_cfn/config.example.env` as the template.

## Spin A New Lab

Use the defaults from `~/.cybr-labs/config.env`:

```bash
cybr-lab-spin
```

Or pass workflow inputs explicitly:

```bash
cybr-lab-spin <branch> <environment>
```

The command waits for the workflow to finish and downloads CloudFormation outputs to the configured artifacts directory.

## Get Connection Details

Show the latest lab:

```bash
cybr-lab-output
```

Show a specific lab:

```bash
cybr-lab-output <lab-id>
```

The output includes the lab ID, host addresses, and reusable connection commands derived from the CloudFormation outputs.

## Connect To A Lab

Use `cybr-lab-output` to get the host, then SSH:

```bash
cybr-lab-output
ssh -i "$SSH_KEY_PATH" ubuntu@<lab-host>
```

## Lab Environment Variables

Tenant credentials and the lab ID are injected into every login shell via `/etc/profile.d/cyberark.sh`. The file is written by cloud-init at instance launch and contains:

```bash
LAB_ID=...               # unique ID for this lab (used in safe names, namespaces, etc.)
TENANT_ID=...            # CyberArk ISP tenant GUID
TENANT_SUBDOMAIN=...     # subdomain of *.id.cyberark.cloud
CLIENT_ID=...            # ISP service account username
CLIENT_SECRET=...        # ISP service account password
INSTALLER_USR=...        # ISP installer user
INSTALLER_PWD=...        # ISP installer password
```

**Interactive session** — variables load automatically when you SSH normally:

```bash
ssh -i "$SSH_KEY_PATH" ubuntu@<lab-host>
echo $LAB_ID   # available immediately
```

**Non-interactive / scripted commands** — a plain `ssh host "cmd"` does not source `/etc/profile.d/`. Use a login shell explicitly:

```bash
ssh -i "$SSH_KEY_PATH" ubuntu@<lab-host> "bash -lc 'echo \$LAB_ID'"
```

Or when piping a longer script:

```bash
ssh -i "$SSH_KEY_PATH" ubuntu@<lab-host> bash -lc << 'EOF'
cd /opt/cybr-demos/demos/secrets_manager/swa_k8s
bash setup.sh --aws
EOF
```

## Use A Lab For Demo Work

Use `cybr-lab-output` to get the host, SSH with a login shell so the tenant vars are loaded, then run demo setup:

```bash
ssh -i "$SSH_KEY_PATH" ubuntu@<lab-host>
cd /opt/cybr-demos/demos/<category>/<demo>
bash setup.sh
bash validate.sh
```

Keep generated lab artifacts outside this repo. Record reusable instructions in demo docs, not one-off lab IDs, public IPs, hostnames, or local paths.

## Artifact Location

By default, lab outputs are stored outside project repos:

```text
~/.cybr-labs/artifacts/<lab-id>/
```

Keep generated lab artifacts out of application repos. If a project needs to reference a lab, record only the lab ID or use `cybr-lab-output` at runtime.
