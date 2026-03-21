# Dependency Scanning: SBOM and Vulnerability Management

## When to Activate

Use when setting up CI, onboarding a new language stack, or after security asks for continuous supply-chain visibility.

## Process

1. **Generate SBOMs.** Export CycloneDX or SPDX from package managers: `syft packages dir:. -o cyclonedx-json`, `npm sbom`, Gradle **Syft/Trivy** plugins. Store artifacts per build SHA.
2. **Scan in CI.** Run **Snyk test**, **Trivy fs .**, or **Grype** `grype dir:.` on every main-branch build; fail on critical CVEs with fixed versions available.
3. **Transitive risk review.** For unresolved criticals, trace the dependency chain (`npm ls`, `gradle dependencies`) and evaluate exploitability (network reachable? dev-only?).
4. **Upgrade with tests.** Bump minors/patches in a branch; run unit/integration suites; watch for breaking API changes in lockfile diffs.
5. **Dependabot/GitHub integration.** Enable **Dependabot** security + version updates; group ecosystem updates to reduce noise; require human review for major bumps.
6. **License obligations.** Attach license scan (e.g., **FOSSA**, **license-checker**) to SBOM; block copyleft in distributed artifacts if policy forbids.

## Checklist

- [ ] SBOM artifact attached to each release
- [ ] Scanner runs on PR and default branch
- [ ] Policy for severities and SLA to patch
- [ ] Transitive issues triaged with notes
- [ ] License report aligned with legal policy

## Tips

Pin base images and scan containers: `trivy image myapp:tag`. Correlate findings to CWE for richer dashboards; dedupe across duplicate lockfile paths in monorepos.
