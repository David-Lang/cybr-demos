# Demo Doc Authoring Guide

Use this guide when creating demo documentation under `demos/`.

The standard filenames are:

- `demo_setup.md` for deployment and setup guidance
- `demo_validation.md` for post-install walkthrough and validation guidance

## Standard Pair

Use both files when the demo has meaningful deployment and validation steps.

- `demo_setup.md`
  - deployment context
  - automation path in this repo
  - setup scripts and sequence
  - required environment and prerequisites
  - what gets installed

- `demo_validation.md`
  - post-install walkthrough
  - runtime validation
  - CyberArk behavior
  - platform behavior
  - troubleshooting

If the demo is simple, `demo_validation.md` may be enough. If the demo has a non-trivial setup path, include both.

## File Roles

Keep the file roles distinct.

`demo_setup.md` should answer:

- How is this demo deployed in this repo?
- What scripts or automation run?
- What environment variables and platform prerequisites are required?
- What gets installed or configured?
- What is specific to the lab or platform deployment path?

`demo_validation.md` should answer:

- What should the user inspect after deployment?
- What are the major use cases or integration patterns?
- What commands prove the demo is working?
- What is CyberArk doing behind the scenes?
- What controls or policy decisions affect the result?
- How does the user troubleshoot failures?

## Primary Goal

A good `demo_setup.md` should help a new user:

- understand how the demo is deployed in this repo
- understand which setup path is repo-specific versus platform-generic
- identify the scripts, variables, and prerequisites involved
- understand what infrastructure or application resources will be created
- troubleshoot setup failures before moving to validation

A good `demo_validation.md` should help a new user:

- understand what was deployed
- understand the CyberArk integration pattern being demonstrated
- understand the request, policy, retrieval, and delivery flow end to end
- validate the result with concrete commands
- compare the important patterns in the demo
- troubleshoot common failure points

## Default Assumptions

For `demo_setup.md`:

- explain the deployment path clearly
- document the setup sequence explicitly
- call out what is lab-specific
- separate deployment context from runtime validation
- explicitly state when shared environment such as `CYBR_DEMOS_PATH`, `LAB_ID`, and tenant variables are expected to already be set and ready to use
- prefer a single demo-level `setup/vars.env` as the shared configuration file for all setup scripts

For `demo_validation.md`, assume the demo is already installed.

That usually means:

- `setup.sh` has already completed
- any Helm chart or manifests have already been applied
- the user is now exploring and validating the environment

Do not make setup the focus of `demo_validation.md` unless the use case specifically requires it.

## What To Emphasize

In `demo_setup.md`, prioritize:

- deployment flow
- setup scripts and their sequence
- platform or lab context
- required variables and prerequisites
- pre-existing shared environment assumptions
- the location of the demo's common `setup/vars.env` file
- platform-specific naming constraints such as maximum safe name length
- what gets deployed
- setup troubleshooting

When checking whether a demo is ready for a test deployment, verify that the expected code and documentation changes are present in the repository copy that will actually be used for the deployment target.

In `demo_validation.md`, prioritize:

- post-install validation
- understanding how the CyberArk solution works
- user understanding of the deployed resources
- CyberArk authentication method
- authorization or access control decisions
- how secrets are delivered or consumed
- what success looks like
- how to inspect or troubleshoot failures

For Kubernetes demos, that usually means:

- namespaces
- pods
- secrets
- configmaps
- service accounts
- mounted files
- operator or controller health

For other platforms, adapt the same idea to the platform primitives.

## Recommended Structure

Most `demo_setup.md` files should follow this flow:

1. Short intro explaining the deployment path.
2. Main entry point such as `setup.sh`.
3. Deployment context for the repo or lab.
4. Required environment, variables, and prerequisites.
5. Setup stages and the scripts that run.
6. What gets deployed or configured.
7. Setup troubleshooting.

## Vars File Pattern

Prefer one common vars file per demo:

- `setup/vars.env`

Use that file as the default source of demo-specific configuration for:

- `setup.sh`
- `setup/vault/setup.sh`
- `setup/conjur/setup.sh`
- `cleanup.sh`
- any other setup or reset entrypoint for the demo

This keeps the demo configuration in one place and avoids drift between multiple `vars.env` files in subdirectories.

Only introduce additional vars files under subdirectories when there is a clear technical reason and document that exception explicitly in `demo_setup.md`.

Most `demo_validation.md` files should follow this flow:

1. Short intro explaining the purpose of the demo.
2. Starting point that assumes the environment is already deployed.
3. Short "About" section describing the CyberArk components involved.
4. Workflow section showing the request and retrieval path.
5. Quick validation that the core resources exist.
6. One section per major integration pattern or use case.
7. A comparison section if multiple patterns exist.
8. A troubleshooting section.

Keep both files practical. The user should be able to follow them live in a terminal.

## Pattern Sections

For each major pattern in `demo_validation.md`, include:

- what the pattern does
- what CyberArk component or feature is involved
- what policy, access control, or identity boundary matters
- what the user should validate
- concrete commands to validate it
- what the result proves

Examples of pattern-oriented sections:

- K8s Secrets
- Push To File
- FetchAll
- External Secrets Operator
- direct API retrieval with `curl`
- CI/CD secret injection
- workload identity authentication

## Validation Over Deployment

In `demo_validation.md`, prefer validation commands over authoring or deployment inspection.

Good examples:

- `kubectl get ...`
- `kubectl describe ...`
- `kubectl exec ...`
- `kubectl logs ...`
- reading generated files
- decoding created secrets
- checking synced resources

Avoid making the validation guide about:

- Helm install commands
- rendered manifest dumps
- long setup instructions
- resource creation mechanics the user no longer needs

It is fine to mention which manifest or template implements a pattern, but the focus should stay on validating the live result.

For `demo_setup.md`, the opposite emphasis is appropriate:

- explain the actual deployment flow in this repo
- identify setup scripts and automation boundaries
- call out whether the deployment path is Rancher, EKS, OCP, or other
- distinguish repo-specific automation from generic platform behavior

Do not turn `demo_setup.md` into a generic product overview. It should stay tied to the repo’s real deployment path.

## Explain The CyberArk Behavior

Do not stop at platform commands. Explain what CyberArk is doing.

For each pattern in `demo_validation.md`, clarify:

- how authentication happens
- what identity is used
- how CyberArk maps that identity
- what authorization or access controls are evaluated
- where the secret is delivered
- whether caching, brokering, sync, or retrieval intermediaries are involved
- whether the delivery is init, sidecar, controller, API, or sync based

The user should come away understanding both:

- what they see in the platform
- why CyberArk behaves that way

When useful, make the flow explicit with a short sequence diagram, numbered request path, or compact workflow table. Prefer a Mermaid `sequenceDiagram` when the demo has a clear request path between an application, CyberArk component, and backend service. The diagram should be relevant to the actual demo flow and help the reader understand who initiates the request, where policy is enforced, and how the secret returns to the workload. The `demos/credential_providers/agent_ubuntu/README.md` example is a good model: it explains the component role, the access controls, the required configuration, the runtime request flow, and a concrete retrieval example.

## Solution Understanding First

Treat `demo_validation.md` as a guided explanation of the working solution, not just a checklist.

Strong validation docs usually make these points obvious:

- which CyberArk component receives the request
- which identity or application context is presented
- which policies, safe permissions, or application controls allow the request
- how the secret is retrieved from CyberArk
- whether the component caches, writes, injects, or proxies the secret
- what the consuming application actually receives

If the demo includes controls such as allowed machines, OS users, file path rules, workload identity bindings, safe membership, or namespace scoping, explain how to validate those controls and what failure would look like.

## Command Guidance

Commands should be:

- short
- copy-pasteable
- directly useful
- specific to the deployed demo

Prefer commands that prove something concrete, such as:

- a secret exists
- a file was written
- a controller synced data
- a JWT is mounted
- an API call succeeds

When a variable like namespace or workload name is dynamic, source it from the demo’s env file when possible.

## Deployment Readiness Checks

Before declaring a demo ready for test deployment, validate:

- the required scripts are executable
- the expected setup and validation entrypoints exist
- the configuration files match the intended deployment values
- the latest local changes are visible in the repository copy that will be used for the test environment
- any remote lab host has been updated if it uses its own checkout of the repo

## Path Guidance

Always use relative paths in demo documentation.

Use paths like:

- `demos/secrets_manager/k8s/demo_setup.md`
- `setup/k8s/charts/poc-sm/templates/namespace.yaml`
- `setup/vars.env`

Do not use:

- absolute filesystem paths from the development machine
- paths rooted in a developer home directory
- `file:///` URLs

The docs should be portable across environments, users, and installation locations.

## Tone And Depth

Write for a technically capable user who is new to the specific demo.

The docs should be:

- practical
- concise
- validation-oriented where appropriate
- explanatory without becoming a full product manual

Avoid placeholder text, generic filler, or repeating README content unless it directly helps the walkthrough.

## What To Avoid

Avoid these common mistakes:

- spending half the validation document on setup
- describing resources without showing how to validate them
- listing commands without saying what they prove
- focusing only on manifests instead of runtime behavior
- ignoring the CyberArk authentication and delivery flow
- mixing deployment guidance and validation guidance into one unclear document

## Minimal Quality Bar

Before considering a new `demo_setup.md` complete, check that it answers:

- How is the demo deployed here?
- What script should the user run?
- What variables or tenant settings are required?
- What gets installed or configured?
- What part of the setup is platform-specific or lab-specific?
- Where should the user look if setup fails?

Before considering a new `demo_validation.md` complete, check that it answers:

- What is this demo proving?
- How does the request move through the CyberArk solution?
- What should the user validate first?
- What are the major patterns or flows?
- What does each validation command prove?
- How is CyberArk authenticating?
- What authorization or access controls are involved?
- Where do the secrets end up?
- How does the user troubleshoot a broken flow?

## Reusable Templates

These outlines are good defaults.

```md
# Demo Setup

Short description of how this demo is deployed in this repo.

## Main Entry Point

What script or command deploys the demo.

## Deployment Context

What part of the setup is repo-specific, lab-specific, or platform-specific.

## Required Environment

Variables, credentials, and prerequisites.

## Setup Flow

What scripts run and what each stage does.

## What Gets Deployed

Main resources, services, workloads, or integrations created.

## Troubleshooting Setup

What to check if deployment fails.
```

```md
# Demo Validation

Short description of the deployed demo.

## Start Here

How to identify the target environment, namespace, project, application, or service.

## About

What CyberArk components are involved and what role each one plays.

## Workflow

Show how the request moves from the application or workload to CyberArk and back.
Add a Mermaid `sequenceDiagram` when it helps explain the live flow.

## Core Validation

Commands that prove the demo is present and healthy.

## Pattern 1: <Name>

What it does.
What identity and access controls matter.
What to validate.
Commands.
What the result proves.
CyberArk behavior.

## Pattern 2: <Name>

What it does.
What identity and access controls matter.
What to validate.
Commands.
What the result proves.
CyberArk behavior.

## Compare The Patterns

Short comparison of when each pattern is useful.

## Troubleshooting

Logs, describe commands, API checks, and common failure points.
```

## Final Rule

If a user can follow `demo_setup.md` to understand deployment and `demo_validation.md` to understand runtime behavior, the documentation is doing its job.
