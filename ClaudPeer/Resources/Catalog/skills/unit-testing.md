# Unit Testing

## When to Activate

Use for pure functions, parsers, state machines, and small components where isolation and speed matter—default tier before integration tests.

## Process

1. **Test via public API** — Prefer module `internal`/`public` entry points tests can import. Avoid `@testable` hacks unless necessary; document why.
2. **Mock edges only** — Fake clock, network, filesystem. Keep core logic real. In Swift, inject protocols; in TS, stub `fetch` with `msw` only at HTTP boundary tests.
3. **One theme per test** — Name reads as a spec: `decoding_invalidUUID_throws`. Avoid asserting ten unrelated things; split cases.
4. **Factories and fixtures** — Centralize builders (`makeConversation()`, `makeAgentConfig()`) to reduce duplication and keep valid defaults obvious.
5. **Determinism** — Freeze time (`Date.init` injection), fix seeds, avoid real sleep. Run `swift test --parallel`, `bun test` with `--randomize` when supported.

## Checklist

- [ ] Tests run in milliseconds per case on average
- [ ] No network or real disk unless explicitly tagged
- [ ] Failures point to a single behavior
- [ ] Data builders keep models consistent
- [ ] Flakes investigated before merging

## Tips

Assert on outcomes, not call counts, unless testing a collaborator contract. Use table-driven tests for input matrices. Snapshot only stable text; avoid brittle UI snapshots at unit tier.
