# Continuous Deployment & Promotion

## When to Activate

When automating releases beyond CI, reducing manual deploy errors, or tightening the path from staging to production with safety rails.

## Process

1. **Promotion pipeline** — Staging deploy on merge to `main`; production on tagged release or manual approval gate in **GitHub Actions** (`environment: production` with required reviewers) or **GitLab** protected environments.
2. **Human gates** — Use approval steps for prod; keep staging fully automatic to catch integration issues early.
3. **Feature flags** — Ship dark via **LaunchDarkly**, **Unleash**, or config flags; decouple deploy from user exposure. Default off; instrument metrics per flag.
4. **Backward-compatible migrations** — Expand → migrate data → contract (two-phase schema changes). Avoid destructive DDL before old code stops reading columns.
5. **Canary metrics** — Route small % traffic (mesh, ingress split, or flag); watch error rate, latency, saturation vs baseline for fixed window before full promote.
6. **Rollback** — One command: `helm rollback`, `kubectl rollout undo`, or redeploy previous image tag. Verify database migrations roll forward-only or have documented down scripts.
7. **Release notes** — Auto-generate from conventional commits or curated changelog; link to tickets and runbooks.

## Checklist

- [ ] Staging automatic; production gated appropriately
- [ ] Flags separate release from activation
- [ ] Migrations safe across old/new code overlap
- [ ] Canary or blue/green with clear abort criteria
- [ ] Rollback rehearsed; release notes published

## Tips

Tag immutable artifacts (`registry/app:1.4.2`); never reuse tags. Store deployment parameters in Git (Helm values) not tribal knowledge. After incidents, tighten gates before adding more automation.
