# `demo.md` Authoring Guide

Use this guide when creating a new `demo.md` for any demo under `demos/`.

The purpose of a `demo.md` file is to help a user understand and validate a deployed demo. It should explain what to look at after install, how the CyberArk functionality works, and how to confirm the expected behavior in the target platform.

## Primary Goal

A good `demo.md` should help a new user:

- understand what was deployed
- understand the CyberArk integration pattern being demonstrated
- validate the result with concrete commands
- compare the important patterns in the demo
- troubleshoot common failure points

## Default Assumption

Assume the demo is already installed.

That usually means:

- `setup.sh` has already completed
- any Helm chart or manifests have already been applied
- the user is now exploring and validating the environment

Do not make setup the focus unless the use case specifically requires it.

## What To Emphasize

Prioritize these topics:

- post-install validation
- user understanding of the deployed resources
- CyberArk authentication method
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
- operator/controller health

For other platforms, adapt the same idea to the platform primitives.

## Recommended Structure

Most `demo.md` files should follow this flow:

1. Short intro explaining the purpose of the demo.
2. Starting point that assumes the environment is already deployed.
3. Quick validation that the core resources exist.
4. One section per major integration pattern or use case.
5. A comparison section if multiple patterns exist.
6. A troubleshooting section.

Keep the structure practical. The user should be able to walk through it live in a terminal.

## Pattern Sections

For each major pattern, include:

- what the pattern does
- what CyberArk component or feature is involved
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

Prefer validation commands over authoring or deployment inspection.

Good examples:

- `kubectl get ...`
- `kubectl describe ...`
- `kubectl exec ...`
- `kubectl logs ...`
- reading generated files
- decoding created secrets
- checking synced resources

Avoid making the guide about:

- Helm install commands
- rendered manifest dumps
- long setup instructions
- resource creation mechanics the user no longer needs

It is fine to mention which manifest or template implements a pattern, but the focus should stay on validating the live result.

## Explain The CyberArk Behavior

Do not stop at platform commands. Explain what CyberArk is doing.

For each pattern, clarify:

- how authentication happens
- what identity is used
- how CyberArk maps that identity
- where the secret is delivered
- whether the delivery is init, sidecar, controller, API, or sync based

The user should come away understanding both:

- what they see in the platform
- why CyberArk behaves that way

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

## Tone And Depth

Write for a technically capable user who is new to the specific demo.

The guide should be:

- practical
- concise
- validation-oriented
- explanatory without becoming a full product manual

Avoid placeholder text, generic filler, or repeating README content unless it directly helps the walkthrough.

## What To Avoid

Avoid these common mistakes:

- spending half the document on setup
- describing resources without showing how to validate them
- listing commands without saying what they prove
- focusing only on manifests instead of runtime behavior
- ignoring the CyberArk authentication and delivery flow
- mixing too many goals into one section

## Minimal Quality Bar

Before considering a new `demo.md` complete, check that it answers:

- What is this demo proving?
- What should the user validate first?
- What are the major patterns or flows?
- What does each validation command prove?
- How is CyberArk authenticating?
- Where do the secrets end up?
- How does the user troubleshoot a broken flow?

## Reusable Template

This outline is a good default:

```md
# Demo Walkthrough

Short description of the deployed demo.

## Start Here

How to identify the target environment, namespace, project, application, or service.

## Core Validation

Commands that prove the demo is present and healthy.

## Pattern 1: <Name>

What it does.
What to validate.
Commands.
What the result proves.
CyberArk behavior.

## Pattern 2: <Name>

What it does.
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

If a user can follow the `demo.md` after install and clearly understand both the platform behavior and the CyberArk behavior, the file is doing its job.
