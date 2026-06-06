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

## Use A Lab For Demo Work

Use `cybr-lab-output` to get the jumpbox SSH command, then run demo-specific setup and validation commands on the lab host.

Example pattern:

```bash
cybr-lab-output
ssh -i "$SSH_KEY_PATH" ubuntu@<jumpbox-ip>
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
