# Type Safety

## When to Activate

Use when modeling domains in Swift or TypeScript, crossing JSON/process boundaries, or eliminating classes of bugs via the type system.

## Process

1. **Unrepresentable invalid states** — Prefer `struct Loaded { let data: Data }` over `var isLoaded` flags. Use enums with associated values instead of parallel optionals.
2. **Unions over booleans** — Replace `isAgent` + `isUser` with `enum Role { case user, agent }`. Encode exhaustive switches; let the compiler flag new cases.
3. **Narrow at boundaries** — Parse external JSON into validated types (`Decodable` + failable init, `zod`/`valibot` in TS). Do not leak `Any`/`unknown` deep into the core.
4. **Avoid unsafe casts** — Replace `as!` / `as unknown as` with `guard let`, `switch`, or typed adapters. Document unavoidable escapes with `// SAFETY:` and tests.
5. **Generics for reuse** — Factor shared algorithms with constraints (`Collection`, `Sendable`). Avoid over-abstracting; two copies can be clearer than one opaque generic.

## Checklist

- [ ] Optional explosion replaced with enums where practical
- [ ] External input validated at module boundaries
- [ ] No silent force-unwraps/casts in production paths
- [ ] Switches updated when enums grow (compiler helps)
- [ ] Concurrency annotations (`Sendable`, `@MainActor`) accurate

## Tips

Enable `strict` in TS; treat Swift 6 concurrency errors as design feedback. Use `nonisolated`/`@preconcurrency` sparingly and document lifetimes. Property wrappers are for repetition, not hiding invalid states.
