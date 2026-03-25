# Repository Instructions

## Repository orientation

- **Top-level overview and quick start:** [`README.md`](README.md)
- **VM / lab bootstrap (clone + Ubuntu `compute_init`):** [`init_cybr_demos.sh`](init_cybr_demos.sh)
- **Shared demo bootstrap:** `demos/setup_env.sh` (requires `CYBR_DEMOS_PATH` and `demos/tenant_vars.sh`)

## Demo Documentation

When creating or updating demo documentation under `demos/`, follow the guidance in:

- `demos/demo_md_guidelines.md`

Key expectation:

- Use `demo_setup.md` for setup and deployment documentation.
- Use `demo_validation.md` for post-install validation walkthroughs.
- Assume the demo is already installed.
- Focus on post-install validation.
- Explain both platform behavior and CyberArk behavior.
- Organize walkthroughs around the major integration patterns in the demo.
