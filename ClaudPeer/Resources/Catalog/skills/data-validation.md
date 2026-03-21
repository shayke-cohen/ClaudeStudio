# Data Validation: Trustworthy Datasets End to End

## When to Activate

Use at ingestion boundaries, before training models, or when data quality incidents spike in downstream dashboards.

## Process

1. **Validate early.** Apply schema checks (Avro/JSON Schema), range checks, and referential checks at ingest APIs or landing zones; reject or dead-letter invalid events.
2. **Monitor distributions.** Track null rate, distinct counts, and quantiles over time; alert on sudden shifts (possible upstream bug). Use warehouse monitors or **SodaCL** checks in CI.
3. **Quarantine bad batches.** Route failing partitions to `quarantine.*` tables with error codes; allow replay after fixes; never silently drop without metrics.
4. **Ownership and paging.** Tag datasets with on-call rotation; tie alerts to runbooks (“if null_rate > 5%, check vendor API status”).
5. **Great Expectations / dbt tests.** GE suites for critical tables; dbt `schema.yml` tests on marts. Run on schedule and on merge for changed models.
6. **Sample audits.** Periodic manual spot checks: join keys, currency fields, timezone alignment; document outcomes in a rolling log.

## Checklist

- [ ] Contract tests at producer and consumer
- [ ] Distribution monitors with thresholds
- [ ] Quarantine path + replay documented
- [ ] On-call mapping for each critical dataset
- [ ] Automated tests in CI for changed models

## Tips

Prefer assertions close to the writer (fail fast) and summaries close to the reader (catch integration drift). Version validation rules alongside code.
