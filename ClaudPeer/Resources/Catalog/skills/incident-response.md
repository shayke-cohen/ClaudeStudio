# Incident Response

## When to Activate

When production SLOs breach, security events fire, or customer-impacting outages begin — coordinate response before root-cause analysis.

## Process

1. **Declare severity** — Use a rubric (SEV1 user-wide down, SEV4 minor). Post in `#incident` or PagerDuty **Incident** with title, impact, commander.
2. **Assign roles** — **Incident Commander** owns timeline and decisions; **Communications** handles status page and customer updates; **Subject experts** debug. Rotate if fatigue sets in.
3. **Stabilize first** — Prefer fast mitigations: **rollback** (`kubectl rollout undo`, redeploy previous tag), **scale** replicas, **disable feature flag**, **block bad traffic** (WAF rule), or **failover** if rehearsed.
4. **Communicate status** — Regular updates (e.g. every 15 min for SEV1): current impact, hypothesis, next update time. Use **Statuspage.io** or internal template.
5. **Capture decisions** — Timestamped log in shared doc: actions taken, who approved, links to dashboards/queries. Avoid verbal-only agreements.
6. **Resolve & handoff** — Confirm metrics recovered; schedule cleanup tasks. Create **postmortem** within 48–72 hours: timeline, root cause, contributing factors, **blameless** learnings, action items with owners.
7. **Follow through** — Track action items to completion; link preventive tests or monitors in the ticket.

## Checklist

- [ ] Severity declared; roles assigned
- [ ] Mitigation prioritized over perfect diagnosis
- [ ] Customers/internal stakeholders updated on cadence
- [ ] Decision log maintained with evidence
- [ ] Blameless postmortem scheduled with actions

## Tips

Practice fire drills on staging. Keep runbooks for rollback and feature killswitches one click away. After repeated incidents, fund engineering fixes, not longer bridges.
