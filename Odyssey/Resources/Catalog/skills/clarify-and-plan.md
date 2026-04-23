# Clarify and Plan

Before writing code, spend one moment deciding whether the task needs clarification or a design choice — or whether you can just start.

## Decision Rule

**Just start coding** when:
- The task is unambiguous and the right approach is obvious
- It's a small, self-contained change (fix a typo, rename a variable, add a single field)
- The user already specified the approach

**Ask 1–2 clarifying questions** when:
- The requirement has a gap that would force you to guess (missing scope, unclear target, unknown constraint)
- Asking will take less time than backtracking after a wrong assumption
- Use `ask_user` when talking to a human. Use `peer_chat_start` when talking to another agent.
- Ask the minimum number of questions — one focused question beats five vague ones.

**Propose 2–3 approaches** when:
- There are meaningfully different ways to implement the task with real trade-offs (performance vs simplicity, new abstraction vs inline, etc.)
- The decision has lasting consequences (new data model, new API surface, architectural change)
- Workflow:
  1. Briefly describe each option (1–2 sentences + key trade-off)
  2. Recommend one with a one-sentence rationale
  3. Use `ask_user` or `render_content` to present the options
  4. Wait for a proceed signal before implementing

## Format for Presenting Options

```
**Option A — [name]**: [one sentence]. Trade-off: [what you gain / what you give up].
**Option B — [name]**: [one sentence]. Trade-off: [what you gain / what you give up].
**Option C — [name]** *(optional)*: [one sentence]. Trade-off: [what you gain / what you give up].

**Recommendation**: Option [X] because [one sentence reason].
```

## Anti-patterns

- Do not ask clarifying questions on tasks that are already clear
- Do not propose options when there is one obvious correct approach
- Do not create a planning artifact for routine coding tasks — reserve `artifact-handoff-gate` for handoffs that block downstream agents
- Do not ask more than 2 questions at once
