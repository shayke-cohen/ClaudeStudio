# ETL Pipelines: Idempotency, Quality, and Scale

## When to Activate

Use when moving data between systems, building analytics lakes, or hardening nightly batch jobs where partial failure is costly.

## Process

1. **Define SLAs.** Target freshness (e.g., T+1 by 06:00 UTC), maximum acceptable lag, and data quality thresholds (null rates, row counts).
2. **Idempotent stages.** Use deterministic keys and `MERGE`/`INSERT ... ON CONFLICT` patterns; store watermarks (`updated_at`) for incremental extracts. Re-runs should not duplicate facts.
3. **Schema and count checks.** Assert source vs destination row counts within tolerance; validate JSON/Avro schemas with contracts; fail fast on type drift.
4. **Late-arriving data.** Model event time vs processing time; allow backfills with partition rewinds; document out-of-order handling in **dbt** snapshots or Slowly Changing Dimensions.
5. **Partition for scale.** Hive-style `dt=YYYY-MM-DD` or BigQuery partitioned tables; prune scans; coalesce small files after transforms.
6. **Lineage and orchestration.** Document upstream owners in **Dagster** assets or **Airflow** DAG docs; expose OpenLineage where possible. Alert on SLA breaches via PagerDuty/webhooks.

## Checklist

- [ ] SLA + alerting defined per pipeline
- [ ] Idempotent loads verified by dry reruns
- [ ] Quality gates (counts, null checks) enforced
- [ ] Late data strategy documented
- [ ] Partitions and backfill path tested

## Tips

Keep transforms in versioned SQL (**dbt**) with tests (`unique`, `not_null`, `relationships`). Use staging schemas to quarantine bad batches before promoting to prod tables.
