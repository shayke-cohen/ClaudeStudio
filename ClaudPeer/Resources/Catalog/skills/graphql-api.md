# GraphQL API Design

## When to Activate

Use when designing schemas, implementing resolvers, or operating GraphQL in production. Apply before exposing new fields, when seeing N+1 queries, or when adding subscriptions.

## Process

1. **Schema evolution**: Prefer additive changes; new fields nullable or defaulted. Avoid removing or changing field types without deprecation (`@deprecated`) and a migration window. Use interfaces and unions thoughtfully for polymorphism.
2. **N+1 prevention**: Batch loads with **DataLoader** (per-request caching) or ORM eager loading. Log resolver counts per operation in development.
3. **Safeguards**: Enforce **max depth**, **query complexity**, and **pagination limits** (relay-style connections). Reject introspection in production unless locked to tooling IPs.
4. **Authorization**: Resolve auth at field level where data sensitivity differs; avoid returning `null` for unauthorized without distinguishing from missing data if that leaks information—model consistently.
5. **Observability**: Instrument resolver duration and error rates (OpenTelemetry). Tag slow operations in traces.
6. **Persisted queries**: Allow only pre-registered operation hashes for mobile/public clients to block arbitrary query cost. Use **Apollo Router** or **GraphQL Yoga** plugins for allowlists.
7. **Mutations**: One domain action per mutation, return `userErrors` + payload pattern for validation failures familiar to clients.

## Checklist

- [ ] Changes are additive or deprecated with timeline
- [ ] DataLoader or equivalent prevents N+1
- [ ] Depth/complexity limits configured
- [ ] Field-level authz documented and tested
- [ ] Slow resolvers visible in APM
- [ ] Persisted queries for untrusted clients (if applicable)

## Tips

Run **`@graphql-eslint`** in CI. Use **GraphQL Voyager** or **Apollo Sandbox** for internal docs. Load test with **k6** or **Artillery** using recorded operations.
