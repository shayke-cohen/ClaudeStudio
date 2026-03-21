# Safe Refactoring

## When to Activate

Use when structure blocks change, names lie, duplication causes drift, or modules are tangled—without changing user-visible behavior.

## Process

1. **Establish a safety net** — Run existing tests; add characterization tests around the behavior you will move (`swift test`, `bun test`). Prefer tests against public APIs.
2. **One mechanical step at a time** — Extract function, rename with IDE refactoring, move file. Commit after each green build. Avoid mixing refactors with feature work in the same commit.
3. **Preserve contracts** — Watch wire formats (JSON keys, WebSocket payloads), Swift `Codable` field names, database columns, and URL paths. If serialization crosses processes, update both sides in lockstep (`SidecarProtocol.swift` ↔ `types.ts`).
4. **API breakage** — Mark deprecated entry points; grep for callers before deleting. For SPM or internal modules, consider `@available` or version bumps.
5. **Verify** — Full test suite plus a smoke path (launch app, critical CLI). Compare snapshots or golden outputs only if already in use.

## Checklist

- [ ] Tests green before and after each step
- [ ] No behavior change intended; diff is mechanical
- [ ] Serialization and public API compatibility checked
- [ ] No drive-by feature edits in the same branch
- [ ] Dead code removed or ticketed separately

## Tips

Use “prepare” commits: e.g. rename file only, then change contents. Prefer compiler and type errors over comments for enforcing new structure. When unsure, spike in a throwaway branch, then replay clean commits.
