# Peer Collaboration

## When to Activate

Use when multiple people or autonomous agents work on the same codebase, spec, or mission in parallel. Essential for swarm workflows, pair rotations, and cross-team features to avoid duplicated effort and conflicting edits.

## Process

1. **Establish shared goals** — One sentence outcome and **non-goals** (“optimize latency, not UX polish this sprint”). Post in the shared channel or blackboard entry everyone references.
2. **Define boundaries** — File areas, services, or workstreams owned by each peer; explicit **handoff format** (summary, open questions, links to commits/PRs).
3. **Prefer explicit summaries** — After each chunk of work: **what changed**, **what’s next**, **blockers**, **assumptions**. Avoid implicit context in long threads.
4. **Avoid duplicate work** — Claim tasks in a visible board (GitHub Project, Linear) or a single “work ledger” message; check before starting.
5. **Human-visible checkpoints** — Short sync points (async is fine): “end of day status” or “before merge” review so humans can redirect early.
6. **Merge order and conflicts** — Agree **who merges first** for touching files; use stacked PRs or feature branches with `git rebase` discipline. Document conflict resolution: prefer smaller PR wins, then follow-up.

## Checklist

- [ ] Shared goal and boundaries written
- [ ] Handoff template agreed (summary / next / blockers)
- [ ] Task claims visible; no silent overlap
- [ ] Checkpoints scheduled or templated
- [ ] Merge order and conflict rules clear

## Tips

Use a single source of truth for decisions (ADR or blackboard) so peers don’t fork rationale. For agents, constrain tool scopes per peer to reduce accidental cross-edits. When friction spikes, switch one peer to “read-only review” for a cycle to stabilize main.
