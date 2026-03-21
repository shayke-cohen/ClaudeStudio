# Delegation Patterns

## When to Activate

Use when splitting work to specialists, contractors, or sub-agents. Use when a task is too large to verify in one pass or when domain expertise (security, data, mobile) is required.

## Process

1. **Package context** — **Goal**, **constraints** (time, tech, compliance), **artifacts** (links to code paths, designs), and **definition of done** (tests passing, metrics, screenshots).
2. **Right-size work** — Delegations should complete in hours to a few days with a verifiable artifact. If bigger, split into milestones with review gates.
3. **Structured handbacks** — Require a standard return: summary, files touched, risks, open questions, and links to PRs or patches. Reject vague “done” without evidence.
4. **Escalate ambiguity early** — If requirements conflict after 30 minutes of exploration, stop and ask the delegator with options A/B—don’t guess silently.
5. **Record decisions** — Log answers in ticket comments, ADR, or blackboard so downstream delegations inherit the same truth.
6. **Verify** — Reviewer runs tests, spot-checks edge cases, and confirms DoD. Use checklists for repetitive delegations.

## Checklist

- [ ] Goal, constraints, artifacts, and DoD written
- [ ] Scope small enough to review thoroughly
- [ ] Handback format specified and followed
- [ ] Ambiguities escalated with proposed options
- [ ] Decisions captured for future delegates

## Tips

Avoid “telephone game” chains deeper than two hops without a written spec. For agents, pass **file paths and line ranges** instead of paraphrasing code. Rotate reviewers so organizational bias does not miss the same bugs.
