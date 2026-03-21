# Changelog Authoring

## When to Activate

Use for every user-facing release (libraries, CLIs, SaaS APIs). Start at 1.0.0 or first public release; maintain through the product lifetime. Pair with semantic versioning.

## Process

1. **Follow Keep a Changelog** — Sections: **Added**, **Changed**, **Deprecated**, **Removed**, **Fixed**, **Security**. Use `## [version] - YYYY-MM-DD` headings; unreleased work lives under `## [Unreleased]`.
2. **Link evidence** — Reference PRs (`#123`), issues, and ADRs. Readers should trace “why” without opening Slack.
3. **Call out migrations** — Config renames, database migrations, env var changes, CLI flag removals—put under **Changed**/**Removed** with explicit upgrade steps (`ALTER TABLE`, new default).
4. **Align with semver** — Breaking API or behavior → major; backward-compatible features → minor; fixes → patch. If you ship breaking changes, the changelog entry must scream **BREAKING** at the top of that version block.
5. **Automate where possible** — Use `release-please`, `semantic-release`, or `changesets` to aggregate conventional commits; always **human-edit** the final notes for customer impact.
6. **Proofread for users** — Replace internal ticket codes with outcomes (“Faster sync on slow networks”) when publishing externally.

## Checklist

- [ ] Unreleased section maintained during development
- [ ] Sections match Keep a Changelog style
- [ ] PRs/issues linked; migrations called out
- [ ] Semver bump matches changelog severity
- [ ] Customer-facing wording reviewed

## Tips

Keep `CHANGELOG.md` at repo root. For mobile apps, mirror key points in App Store / Play release notes—shorter, same facts. On release day, diff the changelog against the actual git tag to catch missing entries.
