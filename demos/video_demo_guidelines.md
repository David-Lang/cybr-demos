# Video Demo Authoring Guide

Use this guide when creating a recorded demo outline under `demos/`.

## Purpose

The goal is to create short, credible recorded demos that educate security teams and business or technical stakeholders on how a CyberArk solution works, what problem it solves, and how it fits into their operating model.

These videos should inform evaluation, not just showcase a successful command.

They should help the audience understand:

- the business and security objective
- the pain or risk in the current state
- the CyberArk control points involved
- the runtime user experience
- the security team's control plane role

## Default Scope

Unless the use case requires otherwise, recorded demo outlines should focus on validation, not setup.

Assumptions:

- the demo is already installed
- the environment is already reachable
- the demo is shown through live runtime behavior

Do not make setup or deployment the main story unless the demo is specifically about onboarding or provisioning.

## Target Audience

Default audience:

- security teams
- technical stakeholders
- business stakeholders who need enough context to understand value and fit

These demos should educate and inform.

That means the outline should speak to:

- how the solution works
- how control is maintained
- what changes for the workload or platform owner
- why the operating model is safer or simpler

Do not assume the audience already understands CyberArk components, authenticator flows, or policy boundaries.

## Required Audience Themes

Every video demo outline should touch these themes explicitly:

- Goals
  What outcome the customer is trying to achieve.
- Pains
  What is hard, risky, manual, or slow in the current state.
- Security Posture
  What improves from a security perspective.
- Low Friction Ease of Use / Stakeholder UX
  Why the developer, platform, or application team experience is simple.
- Security Team Control Plane Enablement
  How CyberArk gives the security team centralized policy, visibility, and control.

These themes should be explained in a way that informs the audience, not treated as marketing slogans.

## Length Guidance

Keep recorded demos short and focused.

Recommended lengths:

- quick educational validation demo: 4 to 6 minutes
- focused solution walkthrough: 5 to 7 minutes

Default maximum:

- less than 7 minutes unless a user explicitly asks for a longer format

If time is tight, keep:

- the opening context
- one workflow explanation
- one or two live validation steps
- the close with stakeholder meaning

Cut:

- setup details
- long terminal output
- repeated explanation
- implementation detail that does not improve understanding

## What To Show

Prefer showing:

- `demo_validation.md`
- a relevant architecture or workflow section
- a Mermaid `sequenceDiagram` when present
- the minimum live commands needed to prove the flow works
- the output lines that prove identity, authorization, and secret delivery

Avoid showing:

- long file edits
- setup scripts unless the story is deployment-oriented
- noisy logs with no explanation
- terminal history that distracts from the use case

## Narrative Structure

Most recorded demo outlines should follow this flow:

1. Opening context and why the use case matters.
2. Goal and pain statement.
3. Security posture statement.
4. Short explanation of how the CyberArk solution works.
5. Live validation of identity, policy, and secret delivery.
6. Stakeholder impact and security team control plane value.
7. Short close.

## Validation-First Guidance

For most demos, the recorded flow should align to `demo_validation.md`.

Use the validation guide to drive:

- the order of the commands
- the explanation of the CyberArk behavior
- the success criteria
- the troubleshooting language for predictable failures

The video should show what success proves, not just that a command ran.

## Explain The CyberArk Flow

A good recorded demo should make the runtime flow easy to follow.

Clarify:

- who the workload or user is
- how authentication happens
- what identity is presented
- how CyberArk maps that identity
- what authorization or policy boundary matters
- where the secret is delivered
- what the application or workload receives

If a sequence diagram exists, use it early.

If one does not exist and the flow is important, create a short relevant diagram in the documentation first.

## Security Team And Stakeholder Framing

Keep the story understandable to both technical and non-technical stakeholders.

For security teams, emphasize:

- centralized authentication and authorization control
- reduced use of static credentials
- policy-driven access
- auditability and operational consistency

For technical stakeholders, emphasize:

- low friction adoption
- minimal code or workflow changes
- runtime simplicity
- compatibility with existing tooling and identity systems

For broader stakeholders, emphasize:

- reduced operational risk
- clearer ownership boundaries
- faster adoption without weakening controls

## Command Guidance

Commands in a video demo should be:

- short
- readable on screen
- copy-pasteable
- directly tied to the proof point

Prefer commands that prove:

- the active identity
- the configured CyberArk target
- the expected policy or mapping
- the successful secret retrieval or injection

Do not spend time on commands that do not improve the audience's understanding.

## Talk Track Guidance

The narrative should use plain language.

Good talk track characteristics:

- explains why the use case matters
- ties technical proof to stakeholder value
- explains why a step matters before running it
- calls out what success means
- connects user experience to security control

Avoid:

- reading commands without interpretation
- deep implementation detail that does not change the audience's understanding
- jargon-heavy explanation with no clear meaning

## Recommended Outline Template

```md
# <Demo Name> Video Demo Outline

Target length: <under 7 minutes>

Audience: security teams and stakeholders

Scope: validation only

## Demo Goal

One short paragraph describing the business and technical outcome.

## Audience Message

- Goal:
- Pain:
- Security posture:
- Low friction ease of use / stakeholder UX:
- Security team control plane enablement:

## Recorded Flow

### 0:00-0:45 Opening Context

Talk track:

On screen:

### 0:45-1:30 Goal, Pain, And Security Posture

Talk track:

On screen:

### 1:30-3:00 Explain The CyberArk Flow

Talk track:

On screen:

### 3:00-5:00 Live Validation

Talk track:

On screen:

### 5:00-6:15 Stakeholder Impact

Talk track:

On screen:

### 6:15-6:30 Close

Talk track:

## Presenter Notes

- keep if time gets tight
- most important proof points
- does not cover
```

## File Naming

Prefer a simple, demo-local filename such as:

- `video_demo_outline.md`

Place it in the relevant demo directory.

## Sources

When creating a video demo outline:

- use the local demo's `demo_validation.md` first
- use repo guidance under `demos/`
- prefer current `docs.cyberark.com` pages over older docs
- use CyberArk open source docs only as a last resort

## Quality Bar

Before considering a video demo outline complete, check that it:

- is clearly less than 7 minutes
- focuses on validation rather than setup
- explains how the CyberArk solution works
- educates security teams and stakeholders
- covers goals, pains, security posture, stakeholder UX, and security team control plane enablement
- shows only the commands needed to prove the story
- gives the presenter a usable talk track rather than a loose topic list
- reads cleanly if both the presenter and audience can see it
