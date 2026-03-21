# Test-Driven Development

## When to Activate

Use for new logic with clear inputs/outputs, bugfixes, or refactors where behavior must stay pinned—especially in shared libraries and protocols.

## Process

1. **Red** — Write one failing test that expresses desired behavior. Use the public API; name the test for the scenario (`test_sendsMessageWhenSessionReady`). Run: `swift test --filter MyTests`, `bun test path/to/file.test.ts`.
2. **Green** — Implement the smallest change that makes the test pass. No speculative features.
3. **Refactor** — Clean up with tests green; extract helpers, rename for clarity. Do not add behavior in this step.
4. **Repeat** — Next scenario or edge case. Keep cycles under minutes when possible.
5. **Harden** — Ensure tests are fast (no real network unless integration tier), deterministic (fixed clocks, seeded RNG), and readable (given/when/then structure).

## Checklist

- [ ] Test failed before implementation existed
- [ ] Each cycle adds one behavior slice
- [ ] Tests avoid asserting private internals
- [ ] Suite remains fast enough for frequent runs
- [ ] Flaky tests fixed or quarantined with issue link

## Tips

Use test doubles only at system edges (clock, network, filesystem). Prefer fakes over deep mocks. When TDD feels heavy, spike then rewrite with tests. Pair TDD with CI: `swift test` / `bun test` on every push.
