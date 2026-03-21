# React Patterns (Hooks, Composition, Performance)

## When to Activate

When building new features, reviewing PRs, or fixing unnecessary re-renders — keep components predictable and maintainable.

## Process

1. **Composition over inheritance** — Prefer children, render props, or small specialized components over deep class hierarchies. Wrap cross-cutting concerns in layout/route shells.
2. **State placement** — Keep state as close as usage as possible; lift only when multiple children need it. Split large contexts or use selectors to avoid wide re-renders.
3. **Effects with correct deps** — List every value read inside `useEffect`; use `useCallback`/`useMemo` only when a child is `React.memo` and profiling shows benefit. Avoid empty deps unless truly mount-once.
4. **Memoization discipline** — Profile with **React DevTools** Profiler before adding `memo`, `useMemo`, `useCallback`. Premature memo adds complexity without gains.
5. **Suspense & boundaries** — Wrap async routes or lazy components in `<Suspense fallback={...}>`. Use **error boundaries** (class `componentDidCatch` or `react-error-boundary`) at route/feature granularity.
6. **Forms & server state** — Prefer **React Query** (`useQuery`, `useMutation`) or **TanStack Query** for server cache; keep UI state local.
7. **Keys & lists** — Stable keys from IDs, not array index, for dynamic lists.

## Checklist

- [ ] Composition used; no unnecessary mega-components
- [ ] State colocated; context split where needed
- [ ] Effects declare accurate dependency arrays
- [ ] Memoization backed by profiler evidence
- [ ] Suspense/error boundaries on async boundaries

## Tips

Example pattern — derived state: `const total = items.reduce(...)` without `useMemo` unless expensive. For event handlers passed to memoized children: `const onSave = useCallback(() => { ... }, [deps])`. Co-locate tests with **Vitest** + **Testing Library** (`@testing-library/react`).
