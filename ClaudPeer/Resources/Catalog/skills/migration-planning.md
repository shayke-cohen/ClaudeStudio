# Migration Planning: Cutover, Rollback, and Parity

## When to Activate

Use when replacing databases, payment providers, identity systems, or merging acquisitions—any dual-write or big-bang cutover.

## Process

1. **Inventory sources and mappings.** Document every table/field mapping, transformation, and defaulting rule; identify PII and regulated data flows explicitly.
2. **Parallel operations.** Run dual writes or change-data-capture into the new system; compare row counts, checksums, and sampled joins nightly; fix discrepancies before cutover.
3. **Staging rehearsal.** Execute full migration + rollback in a prod-like environment with anonymized data; measure downtime and throughput (`pg_dump`, bulk loaders).
4. **Cutover plan.** Define freeze windows, feature flags, and traffic shift steps. Include go/no-go criteria (error rate, lag, reconciliation deltas).
5. **Rollback triggers.** Pre-create scripts to revert DNS, flip flags, or restore read replicas; timebox decision points (e.g., rollback if error >1% for 15 minutes).
6. **Post-migration verification.** Run parity queries, soak test critical user journeys, and monitor business KPIs for 48–72 hours. Communicate status to support.

## Checklist

- [ ] Mapping sheet signed by data owners
- [ ] Reconciliation dashboards live during dual-run
- [ ] Dry-run completed with timings
- [ ] Rollback scripts tested
- [ ] Comms plan for customers + support

## Tips

Treat migrations as product launches: single owner, RACI chart, and incident commander on cutover day. Log every manual SQL with ticket IDs for audit trails.
