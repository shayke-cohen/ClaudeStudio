# Regression Suite Curation

## When to Activate

Use when CI runtime grows, flaky tests erode trust, or automated coverage no longer maps to user-visible value. The goal is a lean suite that protects core journeys without drowning every PR in redundant checks.

## Process

1. **Prioritize by real breakages** — Mine incident postmortems, hotfix commits, and support tickets. For each recurring failure class, add one automated test that would have failed first (often API or contract level, not only UI).
2. **Deduplicate** — If two cases always fail together, merge them or keep the higher-signal test. One canonical assertion per behavior reduces maintenance and noise.
3. **Budget runtime** — Target fast PR feedback: lint, types, unit, then a **smoke** e2e slice under a team SLA (for example 10–15 minutes). Move heavy suites to nightly or pre-release using **GitHub Actions** `schedule` / `workflow_dispatch` or **GitLab CI** child pipelines.
4. **Fail fast** — Order jobs from cheapest to expensive. Examples: `pnpm lint && pnpm test:unit` before `playwright test --grep @smoke`. Use `pytest -x` or split shards only after quick gates pass.
5. **Flake hygiene weekly** — Track retries in CI metrics; quarantine persistently flaky tests in a separate job until fixed — do not mask with unbounded retries on the default branch.
6. **Prune with features** — When product behavior is removed, delete obsolete tests the same sprint. When behavior is added, require at least one test that encodes the new acceptance criteria.
7. **Tag and select** — Mark tests `@smoke`, `@nightly`, `@quarantine` so local and PR runs stay predictable: `npx playwright test --grep @smoke`.

## Checklist

- [ ] Tests trace to incidents, risks, or acceptance criteria
- [ ] Redundant or overlapping cases removed or merged
- [ ] Default pipeline stays within agreed duration budget
- [ ] Ordering fails fast on cheap checks
- [ ] Flakes tracked; quarantine path exists
- [ ] Tags used for selective execution

## Tips

Prefer stable **API-level** regression for business rules; reserve **Playwright** / **Cypress** for critical paths users actually click. Parallelize with isolated data (`--workers=4`) and avoid shared mutable accounts. Review suite composition quarterly like product inventory.
