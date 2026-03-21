# Continuous Integration Pipeline

## When to Activate

When setting up a new repo, when PR feedback is slow, or when flaky builds erode trust — optimize for fast, deterministic feedback before merge.

## Process

1. **Split fast vs slow** — PR workflow: format, lint, typecheck, unit tests (minutes). Nightly or merge queue: integration, e2e, security scans.
2. **Cache dependencies** — **GitHub Actions**: `actions/cache` for npm/pnpm/bun store, Gradle, or Docker layers. **GitLab CI**: `cache:` paths keyed on lockfiles.
3. **Reproduce locally** — Document `act` for Actions or `gitlab-runner exec docker` so devs mirror CI. Same Node/Java version via `.nvmrc` / **asdf** / **SDKMAN** in workflow.
4. **Artifact integrity** — Sign containers (**cosign**), SBOMs (**syft**), or binaries where policy requires; store attestations in OCI registry or GH artifacts.
5. **Gate merges** — Require status checks; use merge queues (**GitHub** merge group) or **GitLab** merge trains for serial integration of green heads.
6. **Fail loudly** — Surface junit XML (`pytest --junitxml=report.xml`, Playwright reporter) in UI; annotate PRs with coverage deltas if useful.
7. **Secrets in CI** — Use OIDC to cloud roles instead of long-lived tokens when possible (`aws-actions/configure-aws-credentials` with `role-to-assume`).

## Checklist

- [ ] Fast path completes under team SLA
- [ ] Dependency and build caches configured
- [ ] Local reproduction steps documented
- [ ] Required checks enforced on default branch
- [ ] Secrets scoped via OIDC or vault, not plaintext

## Tips

Matrix-test OS/runtime only where value justifies cost. Use path filters to skip irrelevant jobs. Pin action versions (`actions/checkout@v4`) to reduce supply-chain surprises.
