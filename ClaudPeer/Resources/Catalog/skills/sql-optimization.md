# SQL Optimization: Plans, Indexes, and Workload Tuning

## When to Activate

Use when queries slow down under production volume, CPU spikes on the database, or before scaling read replicas.

## Process

1. **Capture truth with EXPLAIN.** PostgreSQL: `EXPLAIN (ANALYZE, BUFFERS) SELECT ...` on a staging clone with masked production stats. MySQL: `EXPLAIN ANALYZE` (8.0.18+) or `EXPLAIN FORMAT=JSON`.
2. **Index selective predicates.** Add btree indexes on high-cardinality filters and join keys. Example PG: `CREATE INDEX CONCURRENTLY idx_orders_user_created ON orders (user_id, created_at DESC);` Example MySQL: `CREATE INDEX idx_status ON tickets (status, updated_at);`
3. **Kill N+1.** Batch fetches with `WHERE id = ANY($1)` or JOINs; use ORM eager loading hooks and verify with SQL logging (`log_min_duration_statement` in PG).
4. **Maintain statistics.** PG: `ANALYZE orders;` tune `default_statistics_target` for skewed columns. MySQL: `ANALYZE TABLE orders;` ensure `innodb_stats_persistent=ON`.
5. **Cache carefully.** Use application caches only when staleness is acceptable; prefer materialized views or read models for heavy aggregates—document TTL and invalidation.
6. **Document hot queries.** Keep a runbook of top 10 p95 queries, their plans, and owners; review after schema migrations.

## Checklist

- [ ] Baseline EXPLAIN on realistic data size
- [ ] Indexes justified by selectivity and sort needs
- [ ] N+1 eliminated or bounded
- [ ] Stats jobs scheduled post-bulk-load
- [ ] Cache semantics documented

## Tips

Watch for sequential scans caused by `OR` across columns—consider `UNION ALL` or trigram/GiN indexes for text search. Partition large time-series tables before adding replicas.
