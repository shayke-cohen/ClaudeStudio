# User Stories: Vertical Slices with Testable Value

## When to Activate

Use when breaking epics into backlog items for agile delivery—especially when balancing UX, APIs, and data work in single releasable increments.

## Process

1. **Classic format.** “As a `<persona>`, I want `<capability>` so that `<benefit>`.” Personas should map to real permissions/roles, not generic “user.”
2. **Independent value.** Each story should shippable behind a flag or thin scope; if it only makes sense with three others, merge or re-slice vertically (UI + API + persistence touch together).
3. **Acceptance criteria as checklists.** Bullet observable outcomes (“PDF downloads with correct watermark”) rather than vague “works well.”
4. **Spikes for uncertainty.** Timebox research stories (e.g., two days) with explicit questions and expected artifacts (doc, prototype, benchmark numbers).
5. **Non-functional tagging.** Add labels for performance, security, a11y, analytics so teams don’t ship “invisible” requirements only in prose footnotes.
6. **Refinement cadence.** Revisit estimates when scope creeps; split stories exceeding ~3 days of team effort to keep flow predictable.

## Checklist

- [ ] Persona/role matches auth model
- [ ] Story delivers standalone value or is merged
- [ ] Acceptance criteria are binary testable
- [ ] Spikes have timebox + output artifact
- [ ] NFR tags applied where relevant

## Tips

Pair stories with a single mock or API sketch to reduce rework. Keep technical tasks separate only when they unblock multiple stories—otherwise embed them to preserve end-to-end ownership.
