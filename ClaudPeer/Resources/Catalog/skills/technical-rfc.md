# Technical RFC Writing

## When to Activate

Use before large architecture changes, new services, data model shifts, or anything that will be expensive to undo. Skip for trivial changes; use a short ADR instead for single decisions.

## Process

1. **State the problem** — User pain, scale trigger, or compliance need. List **constraints** (latency, budget, team skills) and explicit **non-goals** to prevent scope creep.
2. **Present options** — At least two real alternatives (including “do nothing” if viable). For each: diagram, cost, operational burden, security, and migration pain.
3. **Recommend one** — Clear choice with rationale tied to constraints. Acknowledge tradeoffs you are accepting.
4. **Rollout plan** — Phases, feature flags, dual-write/dual-read if needed, rollback steps, and **decision deadline** for comments (e.g., “feedback by EOD Friday; decision Monday”).
5. **Testing and observability** — How you will prove correctness (integration tests, load tests), what metrics and dashboards will validate success, and what alerts to add.
6. **Socialize** — Post in Slack/Teams with `@` to affected teams; link from the tracking issue (Jira/Linear/GitHub). Revise once after feedback, then mark status: Proposed → Accepted → Superseded.

## Checklist

- [ ] Problem, constraints, and non-goals are explicit
- [ ] Multiple options with honest tradeoffs
- [ ] Migration, rollback, and flag strategy described
- [ ] Testing, metrics, and alerts planned
- [ ] Comment deadline and decision owner named

## Tips

Keep the doc under ~5–8 pages; move appendices to linked docs. Use Mermaid or Excalidraw for diagrams. If discussion spirals, call a 30-minute decision meeting with a time-boxed outcome. Store RFCs in `docs/rfcs/` or your wiki with a stable URL.
