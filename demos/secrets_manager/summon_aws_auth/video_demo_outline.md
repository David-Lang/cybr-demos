# Summon AWS Auth Video Demo Outline

Target length: 6 minutes 15 seconds

Audience: security teams and stakeholders

Scope: validation only

Does not cover:

- `demo_setup.md`
- installation steps
- detailed policy authoring
- deployment troubleshooting outside the validation story

## Demo Goal

Show how a Linux-based workload can use AWS IAM identity to retrieve CyberArk-managed secrets at runtime through Summon, without a static Conjur API key, while keeping authentication and authorization under centralized CyberArk control.

## Audience Message

- Goal:
  Show a practical pattern for secure runtime secret retrieval using AWS IAM identity and CyberArk policy control.
- Pain:
  Many teams still rely on static credentials, local secret handling, and application-owned secret logic that is hard to govern and hard to audit.
- Security posture:
  Authentication comes from AWS IAM, authorization is enforced in CyberArk, and secrets are delivered only to the running process.
- Low friction ease of use / stakeholder UX:
  The workload team runs a normal command and consumes environment variables without building custom secret-handling code.
- Security team control plane enablement:
  Security owns the authenticator configuration, workload identity mapping, and safe delegation model centrally in CyberArk.

## Recorded Flow

### 0:00-0:40 Opening Context

Talk track:

- This video explains how the Summon AWS Auth pattern works and what it means for security teams and stakeholders.
- The focus is runtime validation, not setup.
- The main question is how a workload can use AWS IAM identity to retrieve secrets while security retains centralized control.

On screen:

- Open `demos/secrets_manager/summon_aws_auth/demo_validation.md`
- Highlight the `About` and `Workflow` sections

### 0:40-1:20 Goal, Pain, And Security Posture

Talk track:

- The goal is to remove static secret credentials from the workload and use AWS-native identity instead.
- The pain is familiar: secret sprawl, manual distribution, and unclear boundaries between application responsibility and security responsibility.
- The improved security posture comes from separating identity, authorization, and secret delivery into managed control points.

On screen:

- Show the Mermaid workflow in `demo_validation.md`
- Pause where `authn-iam` maps the AWS role and Conjur checks authorization

Key points:

- This pattern reduces reliance on long-lived credentials.
- The workload identity comes from AWS IAM, not from a manually distributed CyberArk secret.

### 1:20-2:15 Explain The CyberArk Flow

Talk track:

- Summon starts the process and `summon-conjur` performs the authentication flow.
- CyberArk validates the AWS identity, maps it to a Conjur host, and then checks whether that host is allowed to read the safe-backed variables.
- This matters because authentication and authorization are separate decisions, which gives the security team clearer control.

On screen:

- Stay on the workflow diagram
- Highlight the `Pattern 1` and `Pattern 2` sections in `demo_validation.md`

Key points:

- Authentication answers who the workload is.
- Authorization answers what that workload can read.
- Secret delivery happens only after both controls succeed.

### 2:15-3:05 Validate The Workload Identity

Talk track:

- The first validation step is to prove the workload identity.
- CyberArk can only authorize the request if the AWS identity maps to the expected Conjur host.

On screen:

```bash
cd demos/secrets_manager/summon_aws_auth
source ./conjur_authn_iam.env
env | grep -E '^(CONJUR|AUTHN_IAM|WORKLOAD_HOST_ID|AWS_)' | sort
aws sts get-caller-identity
```

Key points:

- The output shows the AWS caller identity.
- The environment shows the CyberArk authenticator target and derived workload host mapping.
- This is the identity foundation for the rest of the flow.

### 3:05-3:40 Validate The Secret Mapping

Talk track:

- The next step is to show the application-facing secret map.
- The workload does not implement custom authentication logic. It references named variables and lets Summon handle retrieval.

On screen:

```bash
cat ./secrets.yml
```

Key points:

- These are safe-backed variable paths.
- The workload consumes simple variables.
- Security controls what those paths resolve to.

### 3:40-4:55 Run The Validation Flow

Talk track:

- This command validates the flow end to end.
- It proves the identity, policy, and runtime secret delivery path together.

On screen:

```bash
./demo.sh
```

Pause on:

- AWS caller identity output
- Conjur appliance and service ID
- injected `SECRET1`, `SECRET2`, and `SECRET3`

Key points:

- `summon-conjur` authenticates with AWS IAM.
- CyberArk maps the request to the expected host and checks safe delegation.
- The synchronized values are returned only after those checks succeed.
- The running process receives environment variables at runtime rather than relying on static credentials.

### 4:55-5:45 Stakeholder Impact And Security Team Control Plane

Talk track:

- For workload and platform owners, the experience is intentionally simple.
- For security teams, the value is centralized control over authenticator configuration, identity mapping, and authorization boundaries.
- For broader stakeholders, this reduces risk without forcing application teams into a complex secret-consumption model.

On screen:

- Return to the `Pattern 1`, `Pattern 2`, and `Compare The Patterns` sections in `demo_validation.md`

Key points:

- Security governs the control plane centrally.
- The workload team keeps a low-friction runtime experience.
- The model separates identity, access, and delivery in a way that is easier to understand and govern.

### 5:45-6:15 Close

Talk track:

- This use case shows how AWS IAM identity and CyberArk policy work together to improve security posture while keeping the workload experience simple.
- That is the main takeaway for security teams and stakeholders evaluating this pattern.

## Notes

- Keeps the terminal font large and the output focused on the relevant lines.
- Does not explain setup or installation.
- Does not spend time on internal implementation detail unless it improves understanding of the control model.
- If time is tight, shortens the `secrets.yml` section and keeps the workflow explanation plus the `./demo.sh` run.
- Most important proof points:
  `aws sts get-caller-identity`, `WORKLOAD_HOST_ID`, the `secrets.yml` mapping, and the successful `./demo.sh` output.
