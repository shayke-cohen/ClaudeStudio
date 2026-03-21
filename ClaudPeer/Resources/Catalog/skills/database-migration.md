# Database Migration

## When to Activate

Use when changing production schema or backfilling data under load. Apply for zero-downtime deploys, large table rewrites, and compliance-driven data fixes.

## Process

1. **Expand-contract**: Phase 1 add nullable column or new index; dual-write or backfill; Phase 2 switch reads to the new path; Phase 3 remove the old column or stop writers. Never drop the old path in the same release that stops writing it.
2. **Backfills**: Batch updates with `LIMIT` loops and throttling (`pg_sleep`, job delays) to avoid lock storms. Track progress in a metadata table; make jobs resumable and idempotent.
3. **Locks**: On PostgreSQL prefer `CREATE INDEX CONCURRENTLY`; avoid long transactions on hot rows. Schedule risky DDL in low-traffic windows with `pg_stat_activity` monitoring.
4. **Online tools**: MySQL large changes: **gh-ost** or **Percona pt-online-schema-change**. PostgreSQL bloat: **pg_repack** (plan disk headroom and maintenance windows).
5. **Migrations as code**: Use **Flyway** or **Liquibase** with ordered versions; pair each change with verification SQL. Test on a restored prod-sized snapshot, not only empty dev DBs.
6. **Runbooks**: Document duration estimates, success checks, and abort criteria. Rehearse rollback: feature flags off, restore replica, or forward-fix scripts ready.

## Checklist

- [ ] Expand-contract plan lists explicit phases and owners
- [ ] Backfill is batched, throttled, and resumable
- [ ] DDL reviewed for lock risk; concurrent indexes where applicable
- [ ] Tested against prod-scale data clone
- [ ] Operational runbook includes verify queries and rollback

## Tips

Watch **pg_locks** and **pg_stat_progress_create_index** during deploys. Keep migrations small; split risky steps across releases. Document charset/collation impacts for MySQL moves.
