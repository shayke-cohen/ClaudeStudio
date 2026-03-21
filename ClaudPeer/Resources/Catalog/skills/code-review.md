# Code Review

## When to Activate

Use before approving a PR, after your own substantial change before merge, or when onboarding to unfamiliar code. Applies to Swift, TypeScript, SQL, and infrastructure-as-code.

## Process

1. **Read the intent** — PR description, linked issue, and diff stats; note risk areas (auth, persistence, concurrency).
2. **Correctness** — Trace main paths: inputs, state transitions, error returns. Check edge cases (empty, max size, concurrent access). For data access, look for N+1 (loops calling the DB/API per item) and missing transactions.
3. **Security** — Search for string concatenation into queries, shell, HTML, or log templates (`executeRaw`, `os.system`, innerHTML). Verify auth checks on every mutating route, not only UI. Confirm secrets are not in repo: `git log -p -S 'api_key'`, scan for `.env` commits, use `gitleaks` or `trufflehog` where allowed.
4. **Performance** — Hot paths: allocation in loops, synchronous I/O on the main thread (`@MainActor`), unbounded caches, missing pagination.
5. **Style & consistency** — Match project formatters: `swiftformat`, `swiftlint`, `eslint --fix`, `prettier`. Prefer existing patterns over new abstractions.
6. **Tests** — New behavior needs tests; bugfixes need regression tests. Run `swift test`, `bun test`, or CI workflow locally when feasible.
7. **Comment** — Be specific: file, function, line range, impact, suggestion. Separate must-fix from nit.

## Checklist

- [ ] Behavior matches spec; failure modes are explicit
- [ ] No injection vectors; authz enforced server-side
- [ ] No secrets or tokens in code or logs
- [ ] No obvious N+1 or unbounded queries
- [ ] Concurrency and threading assumptions are safe
- [ ] Tests cover new paths and critical regressions
- [ ] Linter/formatter clean; CI would pass

## Tips

Prefer questions over accusations: “What happens if X is nil?” Summarize approval criteria. If you lack context, request a short design note rather than guessing. Time-box nits; file follow-up issues for large refactors.
