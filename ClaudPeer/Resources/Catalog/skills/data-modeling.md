# Data Modeling: Entities That Age Well

## When to Activate

Use when designing new domains, refactoring schemas, or debating normalize vs denormalize for performance.

## Process

1. **Start from access patterns.** List queries and write paths (latency, consistency). Model to make the top paths cheap without sacrificing integrity on money/identity data.
2. **Normalize to reduce anomalies.** Use third normal form for transactional cores; enforce foreign keys and `NOT NULL` where business rules demand it.
3. **Denormalize deliberately.** Add redundant columns or summary tables only with documented invariants and triggers/jobs to keep them consistent.
4. **Stable keys.** Prefer surrogate UUIDs/ULIDs for public references; avoid reusing natural keys that vendors can change. Version entities that need soft migration (`schema_version`).
5. **Cardinality and lifecycle.** Document one-to-many vs many-to-many; define cascade rules, archival, and legal retention. Encode state machines explicitly (`status` + timestamps).
6. **Validate with fixtures.** Seed representative edge cases (empty strings, max lengths, concurrent updates) in integration tests; use DB constraints (`CHECK`, `UNIQUE` partial indexes) as last-line defense.

## Checklist

- [ ] Read/write patterns enumerated and ranked
- [ ] Normalization baseline established
- [ ] Denormalizations listed with invariants
- [ ] Key strategy documented (surrogate vs natural)
- [ ] Lifecycle/retention rules captured

## Tips

Co-locate hot aggregates in the same aggregate root when using DDD—but don’t let domain purity block obvious FK integrity. Review naming consistency (`created_at` vs `createdDate`) across services.
