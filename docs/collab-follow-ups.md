# Collaboration follow-ups (cybr-demos)

Lightweight backlog from working sessions. Review at the start of the next Cursor/collab session.

## Next session — repo / PRs

- [ ] **Refresh upstream PR branches** on `ZAG23/cybr-demos` if still open:
  - `pr/k8s-eso-reloader` — updated with `230aef4` (stale-env demo fix)
  - `pr/k8s-eso`, `pr/k8s-sidecar` — **not** rebased since `554fd8c` / `af644de`; cherry-pick or re-cut from `main` if David is still reviewing
- [ ] **David-Lang/cybr-demos:** [#28 ESO](https://github.com/David-Lang/cybr-demos/pull/28), [#29 sidecar](https://github.com/David-Lang/cybr-demos/pull/29), [#30 eso-reloader](https://github.com/David-Lang/cybr-demos/pull/30), [#31 README consolidate](https://github.com/David-Lang/cybr-demos/issues/31)
- [ ] **Local lab:** ensure `demos/tenant_vars.sh` exists (`cp demos/tenant_vars.sh.example`); after minikube demos, run `init_rancher.sh` if switching back to Rancher JWKS

## Automation idea — “post-collab” cron (design next time)

Goal: after we improve this repo together, something runs without manual remember-every-branch hygiene.

**Possible triggers**

| Trigger | When |
|--------|------|
| GitHub Actions `schedule` | Weekly (e.g. Monday 09:00) |
| `workflow_dispatch` | Manual “end of session” button |
| Local `launchd` / cron | Same machine as lab; runs `tools/session-sync.sh` |

**Possible jobs (keep small)**

1. `git fetch upstream` + report commits behind/ahead of `David-Lang/main`
2. Confirm `origin/main` pushed; list open `pr/*` branches vs `main`
3. `shellcheck` only on changed `demos/**/*.sh` since last tag or last run
4. Optional: comment template on open David PRs (“fork main at SHA …”)
5. Do **not** auto-push to `David-Lang` or merge without human approval

**Sketch**

```text
tools/session-sync.sh          # read-only report + optional push origin/main
.github/workflows/collab-hygiene.yml   # schedule + workflow_dispatch
```

**Open questions for next design session**

- Store last-synced SHA in repo (`docs/.collab-sync-state`) or GitHub Actions cache?
- Notify via GitHub Issue on fork vs. only terminal output?
- Include `secure-ai-sme` / other workspaces or cybr-demos only?

---

*Last updated: 2026-05-18 — after eso-reloader live demo + fork push `230aef4`.*
