# State Management

## When to Activate

Use when client app state grows beyond a few screens: server caches, wizards, real-time updates, or duplicated sources of truth. Apply when bugs trace to stale props, race conditions, or untraceable updates.

## Process

1. **Local state by default**: Keep UI-only state (`useState`, `useReducer`, component refs) colocated until multiple distant subtrees need the same data or persistence.
2. **Normalize remote data**: Store entities by id in a flat map (e.g. `{ users: { [id]: User } }`) and keep lists as id arrays. Avoid nesting duplicate copies of the same record.
3. **Model async explicitly**: Use status unions: `idle | loading | success | error` with timestamps or request ids to ignore stale responses. Never overload `null` alone as “loading.”
4. **Derive, don’t duplicate**: Compute filtered lists, counts, and flags with selectors (`reselect`, `computed` in Pinia) or memoized hooks—not stored fields that can drift.
5. **Named, traceable actions**: Prefer event-style action creators (Redux) or named store methods (Zustand `set` with action names in devtools middleware). Enable **Redux DevTools** or **Vue DevTools** / **Pinia** inspector in development.
6. **Choose the tool**: **Redux Toolkit** for large teams and time-travel debugging; **Zustand** or **Jotai** for minimal boilerplate; **Pinia** as the standard for Vue 3; avoid global store for truly local UI.

## Checklist

- [ ] Remote entities normalized by id
- [ ] Async operations have explicit status + error handling
- [ ] No stored values that can be derived from source state
- [ ] Updates go through named actions or store methods
- [ ] Devtools enabled in dev builds

## Tips

For **Zustand**, use `subscribeWithSelector` or middleware for cross-cutting concerns. For **Redux**, colocate slices with feature folders and export typed hooks from a single module.
