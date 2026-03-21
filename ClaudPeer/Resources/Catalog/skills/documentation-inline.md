# Inline Documentation

## When to Activate

Use when code encodes non-obvious tradeoffs, public APIs ship to other teams, or concurrency and error contracts need to survive refactors.

## Process

1. **Explain why, not what** — Skip restating the next three lines. Document rationale: rejected alternatives, performance assumptions, security constraints.
2. **Invariants and caveats** — Note preconditions (`caller must hop to main`), ordering (`must register before start`), and thread-safety. Use `///` in Swift for public symbols; TSDoc `/** */` for exported TS.
3. **Errors** — List thrown/failure cases for non-trivial functions. Link to user-visible error codes when relevant.
4. **Examples for complex APIs** — Short usage snippet in doc comments for configuration objects and DSLs—kept in sync via doctest or snapshot review.
5. **Keep it local** — Place comments at the decision point; avoid orphan essays. Delete outdated notes when behavior changes.

## Checklist

- [ ] Public API has summary + parameters + throws/errors
- [ ] Non-obvious algorithms cite references or tickets
- [ ] Concurrency expectations stated explicitly
- [ ] Examples compile or are clearly pseudo with label
- [ ] Stale comments removed in the same PR as code changes

## Tips

Prefer clearer names over comments for simple cases. Use `TODO(username, #issue)` with owners. For SwiftUI, document binding contracts rather than visual layout. Run `swift-docc` or `typedoc` occasionally to catch broken references.
