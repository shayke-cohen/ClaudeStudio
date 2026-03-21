# Runbook Authoring

## When to Activate

Use for on-call playbooks, deployment procedures, data fixes, and incident response. Create before production launch of a new service and after every significant postmortem action item.

## Process

1. **Write for 3am** — Short imperative steps: “1. Open Grafana dashboard X. 2. Run `kubectl logs deploy/api -n prod --tail=200`.” Assume fatigue; avoid prose walls.
2. **Verification** — After each risky step, state **expected output** or metric threshold (“p95 < 500ms for 5m”). Include copy-paste queries: Loki `sum(rate(...))`, Datadog metric names, CloudWatch Log Insights snippets.
3. **Link context** — Dashboards, SLOs, PagerDuty service, Slack `#incidents`, service repo, and **escalation** (who to page when SEV-1).
4. **Rollback** — Exact commands: `helm rollback api 3`, `terraform apply` to previous tag, or feature flag flip in LaunchDarkly/Unleash with verification.
5. **Routine tasks** — Certificate renewal, key rotation, reindex jobs: calendar triggers + runbook steps + rollback.
6. **Game days** — Quarterly, execute runbooks in staging; time them and fix gaps. Note duration and last drill date in the doc header.

## Checklist

- [ ] Trigger conditions and severity clear
- [ ] Steps are numbered with commands and expected results
- [ ] Dashboards, logs queries, and alerts linked
- [ ] Rollback path documented and tested
- [ ] Escalation contacts current

## Tips

Use a template repo for runbooks (`RUNBOOK_TEMPLATE.md`). Keep one runbook per service plus cross-cutting “region failover.” Store in `docs/runbooks/` or your internal wiki with the same structure so search works.
