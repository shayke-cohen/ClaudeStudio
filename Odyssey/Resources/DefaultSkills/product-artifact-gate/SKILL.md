---
name: product-artifact-gate
description: Artifact-first product planning that requires PRD and low-fi wireframes before implementation handoff.
category: Odyssey
enabled: true
triggers:
  - PRD
  - wireframe
  - product spec
  - requirements handoff
  - before implementation
---

# Product Artifact Gate

Use this workflow whenever you are acting as the Product Manager for work that may lead to implementation.

## Hard Gate

Do **not** hand work to engineering, ask a Coder to begin, or say implementation can start until:

1. Requirements have been gathered with `ask_user`
2. A PRD draft has been shown in chat with `render_content`
3. Low-fidelity wireframes have been shown in chat with `render_content` using Mermaid
4. Draft artifacts have been written to the blackboard
5. The user has explicitly approved the artifacts

If any of those are missing, you are still in the product-definition phase.

## Required Workflow

### 1. Gather requirements first

- Your first visible action should be `show_progress`
- Use `ask_user` to gather the most important missing requirement before drafting
- Ask follow-up questions only until the scope, constraints, and success criteria are clear enough to draft

### 2. Draft the PRD in chat

Use `render_content` to present a PRD draft that includes:

- problem statement
- goals
- non-goals
- target users or jobs-to-be-done
- key flows
- Must / Should / Could requirements
- acceptance criteria
- open questions or assumptions

### 3. Draft low-fi wireframes in chat

Use `render_content` with Mermaid for lightweight wireframes or flow diagrams.

- Keep them low fidelity and implementation-oriented
- Show the main screen states, layout regions, or user flow steps
- Do **not** wait for a separate designer unless the user explicitly asks for one

### 4. Persist drafts to the blackboard

Write structured JSON drafts to these keys:

- `product.prd.current`
- `product.wireframes.current`
- `product.approval.status`

Recommended `product.approval.status` shape:

```json
{
  "status": "pending",
  "artifactPath": null,
  "readyForImplementation": false
}
```

### 5. Ask for approval

Use `ask_user` with clear choices such as approve, revise, or defer.

- If the user asks for revisions, update the PRD and wireframes, refresh the blackboard drafts, and ask again
- Do **not** write the repo artifact before approval

### 6. Write the approved repo artifact

Only after explicit approval:

- write a single Markdown artifact under `docs/prd/<feature-slug>.md`
- include the approved PRD plus embedded Mermaid wireframes in the same file
- update `product.approval.status` to approved with the artifact path and `readyForImplementation: true`

### 7. Handoff to implementation

Only after the approved artifact exists may you:

- tell the user implementation is ready
- delegate to `Coder`
- summarize a build-ready handoff for engineering

## Output Rules

- Keep the PRD crisp and decision-oriented
- State assumptions explicitly
- Prefer tables and bullets for requirements and acceptance criteria
- End with one of these states only:
  - `Awaiting approval`
  - `Approved and ready for implementation`
