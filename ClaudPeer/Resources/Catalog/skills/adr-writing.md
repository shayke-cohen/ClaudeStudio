# ADR Writing

## When to Activate

Use for significant, hard-to-reverse technical choices: framework, database, auth model, API style, or deployment topology. Use when the “why” will be questioned in six months. Prefer ADRs over long Slack threads.

## Process

1. **Use a short template** — **Title**, **Status** (Proposed / Accepted / Deprecated / Superseded by ADR-NNN), **Context** (forces at play), **Decision** (what we chose), **Consequences** (positive, negative, follow-ups).
2. **Number sequentially** — Name files `0001-record-architecture-decisions.md` or `ADR-0042-postgres-over-mysql.md`. Never reuse numbers.
3. **Supersede, don’t rewrite** — When the decision changes, write a new ADR that references the old one and mark the old status **Superseded**. Preserve history; do not edit accepted text silently.
4. **Link to reality** — Add links to repos, paths, tickets (Jira key, GitHub issue), dashboards, or SLO docs so readers can verify the decision in code.
5. **Record rejected alternatives** — One paragraph per rejected option and why it failed against constraints—saves re-debating later.
6. **Store near the codebase** — e.g., `docs/adr/` or `adr/` at repo root. Mirror in wiki only as an index with links.

## Checklist

- [ ] Context, decision, and consequences are each plain and short
- [ ] Status and supersession links are correct
- [ ] Rejected alternatives noted with reasons
- [ ] Links to code, tickets, or metrics included
- [ ] File name uses sequential numbering

## Tips

Keep each ADR to one decision; split bundles into multiple ADRs. If stakeholders are non-technical, add a **Summary** paragraph up top. In Git, treat ADRs like code: PR review, no force-push on main for history rewrites.
