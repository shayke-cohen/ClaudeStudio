# Linting and Static Standards

## When to Activate

Use when onboarding, standardizing a repo, before CI hardening, or when style drift slows reviews across Swift, TypeScript, YAML, and Markdown.

## Process

1. **Align rules** — Start from defaults (`swiftlint`, `swiftformat`, ESLint flat config, `markdownlint-cli2`). Document intentional overrides in `CONTRIBUTING.md` or config comments—not only tribal knowledge.
2. **Auto-fix pass** — Run `swiftformat .`, `swiftlint --fix` (where supported), `eslint --fix`, `prettier --write`. Commit fixes alone: `git commit -m "chore: apply formatter"` for clean blame.
3. **Gradual rollout** — For legacy code, use folder-scoped configs, `// swiftlint:disable` with issue links, or ESLint `overrides`. Prefer shrinking baselines over global disables.
4. **CI enforcement** — Add `swiftlint --strict`, `eslint --max-warnings 0`, `prettier --check` to GitHub Actions or Xcode Cloud. Fail on new violations via reviewdog or diff-based checks.
5. **Editor integration** — Enable format-on-save in VS Code/Cursor and Xcode build phases for SwiftLint to shorten feedback loops.

## Checklist

- [ ] Formatter and linter configs committed
- [ ] Auto-fix commits separated from logic changes
- [ ] CI fails on new violations
- [ ] Exceptions documented with owners/expiry
- [ ] New files inherit defaults without copy-paste disables

## Tips

Treat warnings as debt: either fix or ticket. Prefer rules that catch bugs (`no-floating-promises`, `unused_declaration`) over purely cosmetic nitpicks. Revisit config when language modes change (Swift 6 concurrency, TypeScript `strict`).
