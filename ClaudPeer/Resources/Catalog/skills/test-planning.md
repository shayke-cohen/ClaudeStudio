# Risk-Based Test Planning

## When to Activate

At sprint planning, before large features, or when test debt threatens release confidence — align coverage with risk, not uniform checkbox counts.

## Process

1. **Identify risks** — List failure modes; score **impact** (revenue, security, data loss) and **likelihood** (change frequency, complexity). Prioritize high-impact × high-likelihood first.
2. **Map requirements** — For each user story, note acceptance criteria and map to **test types**: unit, contract, API, UI, exploratory, performance, security.
3. **Define entry criteria** — Builds green on main, feature behind flag or environment ready, test data available, mocks stable.
4. **Define exit criteria** — No open **P0/P1** bugs, agreed scenarios pass, performance within budget, rollback verified.
5. **Estimate effort** — Data setup time, env dependencies, automation feasibility (stable selectors, APIs). Flag “needs tool X” early (Playwright, k6, Vault access).
6. **Traceability** — Link tests to risks in the tracker (Jira/Linear) so gaps are visible when scope changes.
7. **Review with team** — Dev, QA, and PM agree on what “done” means for testing before coding peaks.

## Checklist

- [ ] Risk matrix updated for the feature
- [ ] Each critical requirement has a mapped test type
- [ ] Entry/exit criteria written and shared
- [ ] Data/tools/automation feasibility noted
- [ ] Traceability from risk → test → release gate

## Tips

Avoid “test everything equally.” Spend depth on money paths and auth. Keep a thin smoke suite always green; deepen coverage where history shows bugs cluster.
