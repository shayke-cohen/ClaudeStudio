# Dependency Audit

## When to Activate

Use before major releases, after security incidents, when adopting a new library, or on a quarterly hygiene cadence for SwiftPM, npm/bun, CocoaPods, or Gradle.

## Process

1. **Inventory** — Export lockfiles: `Package.resolved`, `bun.lockb` / `package-lock.json`, `Gemfile.lock`. List direct vs transitive deps.
2. **CVEs and advisories** — Run `bun audit`, `npm audit`, `swift package show-dependencies` plus GitHub Dependabot or OSV-Scanner (`osv-scanner -r .`). Triage by reachable code and severity.
3. **Maintenance signals** — Check last release date, open issues/PRs, bus factor, and whether the repo archived. Prefer deps with semver discipline and changelog.
4. **Licenses** — Use `license-checker` (npm), `swift package dump-package` for SPM metadata, or `fossa`/`FOSSA` CI. Flag GPL/AGPL in proprietary products early.
5. **Upgrade plan** — Batch patch/minor upgrades; isolate majors. Order: security patches first, then tooling, then feature bumps. Run full test suite and smoke after each batch (`bun test`, `xcodebuild`).

## Checklist

- [ ] Direct and critical transitive deps reviewed
- [ ] Known CVEs addressed or explicitly accepted with ticket
- [ ] License policy compliance documented
- [ ] Upgrade PRs scoped and reversible
- [ ] Post-upgrade regression tests executed

## Tips

Pin versions in apps; use ranges cautiously in libraries. Prefer well-audited stacks (e.g. `undici` vs obscure HTTP clients). If a dep is unmaintained, budget time to fork, replace, or vendor minimally.
