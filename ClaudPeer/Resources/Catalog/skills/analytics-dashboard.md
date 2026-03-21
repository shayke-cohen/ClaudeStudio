# Analytics Dashboards: Honest Metrics for Decisions

## When to Activate

Use when designing executive/product dashboards, debugging misleading KPIs, or rolling out self-serve analytics.

## Process

1. **Clarify the question.** Each chart answers one decision (e.g., “Are trials converting within 14 days?”). Remove vanity metrics unless paired with denominators.
2. **Cohorts and denominators.** Prefer cohort retention curves over global averages; always show base population size to avoid silent sample shrinkage.
3. **Document definitions.** Maintain a data dictionary: metric formula, grain (user/day/order), timezone (`UTC` vs business tz), and refresh cadence. Surface “as of” timestamps on UI.
4. **Bias guards.** Call out survivorship bias (only users who reached step X) and **Simpson’s paradox** when slicing by segments; offer drill-downs instead of one aggregate line.
5. **Permissions.** Row-level security in **Looker**, **Tableau**, or warehouse views; test with non-admin accounts; audit embed tokens.
6. **Regression tests.** For critical metrics, run dbt/warehouse queries comparing to known fixtures after model changes.

## Checklist

- [ ] One primary question per visualization
- [ ] Denominators visible on rate charts
- [ ] Definitions doc linked from dashboard
- [ ] Timezone and freshness labeled
- [ ] Access controls validated for each role

## Tips

Add annotations for campaigns and incidents. When stakeholders disagree, reproduce the metric in a notebook/SQL file and attach the query ID for auditability.
