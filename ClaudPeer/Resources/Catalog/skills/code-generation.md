# Code Generation from Specs

## When to Activate

Use when translating tickets, API specs (OpenAPI), or design docs into implementation—especially multi-file features in Swift, TypeScript, or tooling scripts.

## Process

1. **Extract interfaces first** — Define function signatures, types, and error enums before bodies. For cross-process work, sketch wire shapes and validate with both producers and consumers.
2. **Small reviewable chunks** — Generate one module or vertical slice per PR (e.g. model + migration, or handler + tests). Avoid thousand-line dumps.
3. **No secrets** — Never embed API keys, tokens, or PEM blocks. Use env vars (`ANTHROPIC_API_KEY`), Keychain, or CI secrets. Placeholder values must be obviously invalid.
4. **Match conventions** — Read nearby files: naming, async style (`async/await` vs callbacks), error handling (`Result`, `throws`). Run `swiftformat .`, `swiftlint`, `eslint`, `prettier --write`.
5. **Verify** — `xcodebuild -scheme Scheme -destination 'platform=macOS' build`, `bun run build`, or project script. Fix compiler warnings in touched code.

## Checklist

- [ ] Requirements mapped to types and public entry points
- [ ] Output split into reviewable commits/PRs
- [ ] No credentials or production URLs in source
- [ ] Formatter and linter pass on changed paths
- [ ] Build/test command recorded in PR description

## Tips

Generate tests alongside production code when behavior is specified. Cross-check `Codable`/`Decodable` field names against real JSON samples. Prefer explicit `Sendable` and isolation in Swift 6 over unchecked assumptions.
