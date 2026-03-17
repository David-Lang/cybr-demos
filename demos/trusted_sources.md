# Trusted Sources for LLM-Assisted Coding

Use this file as the default source policy when using an LLM to write, update, or explain code and documentation in `demos/`.

## Purpose

The goal is to keep generated changes aligned with:

- CyberArk product behavior
- this repository's real implementation patterns
- official platform and vendor integration guidance

Prefer sources that are current, authoritative, and specific to the task being implemented.

## Source Priority

Use sources in this order:

1. This repository
2. Official CyberArk documentation
3. Official product documentation for the integrated platform or vendor
4. Official source repositories for the relevant tool or SDK
5. Trusted standards or maintainer-authored references
6. Community content only when official sources do not answer the question

## Approved Source Types

### 1. Repository Sources

Use local repo content first to match the existing implementation style and automation model.

Trusted repo sources include:

- existing demos under `demos/`
- shared utilities under `demos/utility/`
- setup entry points such as `setup.sh`, `demo.sh`, and `setup/` scripts
- repo guidance such as `demos/demo_md_guidelines.md`
- `AGENTS.md` instructions and skill guidance when present

Use these sources to determine:

- file layout
- naming conventions
- setup sequence
- environment variable patterns
- policy template structure
- documentation style

### 2. Official CyberArk Sources

Use official CyberArk documentation for product behavior, APIs, authenticators, and integration requirements.

Preferred sources:

- CyberArk documentation portal
- CyberArk GitHub repositories
- CyberArk-maintained example repos
- official product pages for Summon, Conjur, Secrets Manager, Credential Providers, and Secrets Hub

Use these sources for:

- authenticator behavior
- policy model and examples
- API usage
- client and provider configuration
- setup prerequisites
- supported integration patterns

### 3. Official Vendor Documentation

When the demo integrates with another platform, use that platform's official docs.

Examples:

- AWS documentation
- GitHub documentation
- GitLab documentation
- Jenkins documentation
- Kubernetes documentation
- HashiCorp documentation
- Microsoft documentation

Use these sources for:

- identity and auth behavior
- CLI syntax
- environment requirements
- role or permission definitions
- service-specific configuration

### 4. Official Source Repositories

Use the official source repository when implementation details are clearer in code, examples, release notes, or install scripts than in the product docs.

Examples:

- `cyberark/summon`
- `cyberark/summon-conjur`
- official Terraform providers
- official SDK repositories

Prefer:

- README files
- versioned examples
- installation scripts
- tagged releases
- maintainer-authored docs in the repo

## Trusted URL List

Use this section to maintain a concrete allowlist of URLs and domains that are approved for LLM-assisted coding and documentation work.

Add task-specific URLs here as needed. Prefer stable product docs, official repositories, and official vendor references.

### CyberArk

- Add trusted CyberArk URLs here
- Example: `https://cyberark.github.io/summon/`
- Example: `https://github.com/cyberark/summon`
- Example: `https://github.com/cyberark/summon-conjur`
- Example: `https://github.com/conjurdemos`

### AWS

- Add trusted AWS URLs here
- Example: `https://docs.aws.amazon.com/`
- Example: `https://aws.amazon.com/blogs/`

### Kubernetes

- Add trusted Kubernetes URLs here
- Example: `https://kubernetes.io/docs/`

### GitHub

- Add trusted GitHub URLs here
- Example: `https://docs.github.com/`

### GitLab

- Add trusted GitLab URLs here
- Example: `https://docs.gitlab.com/`

### Jenkins

- Add trusted Jenkins URLs here
- Example: `https://www.jenkins.io/doc/`

### HashiCorp

- Add trusted HashiCorp URLs here
- Example: `https://developer.hashicorp.com/`

### Microsoft

- Add trusted Microsoft URLs here
- Example: `https://learn.microsoft.com/`

### Repository-Local References

- Add repo-local paths here when a file should be treated as a primary source
- Example: `demos/demo_md_guidelines.md`
- Example: `demos/setup_env.sh`
- Example: `demos/secrets_manager/`

## Sources to Avoid or Treat as Low Trust

Do not rely on these as primary sources:

- random blogs
- SEO content farms
- AI-generated articles
- reposted docs on third-party sites
- outdated Stack Overflow answers
- copied snippets without provenance
- unofficial forks unless the task explicitly targets that fork

Community sources may help when debugging edge cases, but they should not define the implementation unless the official source is missing and the limitation is stated clearly.

## Usage Rules for LLM-Assisted Coding

When using an LLM for coding or documentation:

- cite or name the source category used for key decisions
- prefer primary sources over summaries
- verify time-sensitive details before implementing
- do not invent API fields, CLI flags, environment variables, or policy structure
- match repo patterns when the repo already has a working example
- call out uncertainty when the source is incomplete

## Recommended Workflow

For new demo work:

1. Inspect similar demos in this repo.
2. Read repo guidance files that define documentation or setup expectations.
3. Confirm product-specific behavior in official CyberArk docs.
4. Confirm platform-specific behavior in the official vendor docs.
5. Use official source repos for concrete examples if the docs are thin.
6. Only then write or update code and documentation.

## Task-Specific Guidance

### Demo Documentation

When writing `demo_setup.md` or `demo_validation.md`, prefer:

- repo setup scripts
- repo validation commands
- CyberArk product docs
- official platform docs for commands and runtime behavior

### Shell Scripts and Setup Automation

Prefer:

- existing repo scripts
- official install docs
- official CLI references
- maintainer install scripts from official repos

### Policy Templates and Authenticator Configuration

Prefer:

- existing repo policy examples
- official CyberArk policy and authenticator docs
- official CyberArk examples from maintained repositories

### Cloud Identity Integrations

Prefer:

- official cloud provider docs for IAM, roles, OIDC, STS, and trust policies
- official CyberArk docs for how those identities map into CyberArk

## Decision Rule

If two sources conflict:

- prefer the more official source
- prefer the more specific source
- prefer the source that matches the deployed product version or integration model
- prefer the repo's existing pattern when multiple valid implementations exist

## Minimum Standard

Before accepting LLM-generated output for this repo, verify that it is grounded in at least:

- one repo source
- one official product or vendor source when behavior depends on an external system

If that standard is not met, treat the output as a draft and validate it before merging or running it.
