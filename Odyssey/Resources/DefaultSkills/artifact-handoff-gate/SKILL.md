---
name: artifact-handoff-gate
description: Shared artifact-first handoff rules for Odyssey agents before downstream execution, signoff, or publication.
category: Odyssey
enabled: true
triggers:
  - architecture handoff
  - design handoff
  - test strategy
  - signoff
  - rollout plan
  - implementation plan
---

# Artifact Handoff Gate

Use this workflow when your work will become the input to another agent, unblock implementation, authorize release, or create a durable decision artifact.

## Core Rule

Before downstream work continues at a major handoff or signoff moment:

1. Gather enough context to draft the right artifact
2. Present the artifact in chat with `render_content`
3. Persist the current draft to the blackboard
4. Pause for approval or explicit proceed when the artifact will guide downstream work
5. Write repo docs only after the artifact is approved or finalized

Drafts belong in chat + blackboard first. Durable repo docs are for approved or final artifacts only.

## Required Workflow

### 1. Start with visible progress

- Begin with `show_progress`
- Ask focused clarifying questions with `ask_user` only when the handoff is ambiguous or blocked
- Do not jump straight to delegation, release, or implementation without the artifact

### 2. Render the artifact in chat

Use `render_content` for the human-readable artifact.

- Prefer Markdown or HTML for structured briefs
- Use Mermaid when diagrams, flows, architecture, or wireframes will reduce ambiguity
- Keep artifacts decision-oriented and scoped to the handoff

### 3. Persist the draft to the blackboard

Write structured draft state under a predictable namespace:

- `artifacts.<role>.<profile>.current`
- `artifacts.<role>.<profile>.approval`
- `artifacts.<role>.<profile>.handoff`

Recommended approval shape:

```json
{
  "status": "pending",
  "artifactPath": null,
  "readyForHandoff": false
}
```

### 4. Pause before continuation

At major handoffs or signoff moments:

- ask for approval when the artifact freezes product, design, architecture, API, or release direction
- otherwise ask for an explicit proceed signal before downstream execution continues
- do not treat blackboard persistence alone as approval

### 5. Publish the durable doc only after approval/finalization

- Reuse existing repo conventions if they already exist
- If the repo has no clear convention, default to `docs/<artifact-kind>/`
- The approved/final doc should contain the same substance already shown in chat, including Mermaid when useful

## Role Profiles

Use the profile that matches your role and the handoff you are creating.

### Product

- Artifact: PRD + low-fidelity wireframes
- Chat: structured PRD plus Mermaid flows/wireframes
- Blackboard: `artifacts.product.product-spec.*`
- Docs: `docs/prd/<feature-slug>.md`
- Approval: required before implementation handoff
- If you are Product Manager, also follow `product-artifact-gate`

### Architecture / Technical Lead

- Artifact: ADR or RFC + architecture/system diagram
- Chat: summary, options, recommendation, risks, rollout, rollback
- Blackboard: `artifacts.technical.architecture-decision.*`
- Docs: existing ADR/RFC location, otherwise `docs/adr/` or `docs/rfc/`
- Approval: required before engineering execution depends on the decision

### API Design

- Artifact: API contract package + sequence/data-flow diagram
- Chat: endpoints/operations, schemas, errors, examples, compatibility notes
- Blackboard: `artifacts.api.api-contract.*`
- Docs: existing API docs location, otherwise `docs/api/`
- Approval: required before backend/frontend implementation depends on the contract

### UX / Design

- Artifact: UX spec + user flow + low-fidelity wireframes
- Chat: screen inventory, states, responsive rules, a11y notes, Mermaid flow/wireframes
- Blackboard: `artifacts.design.ux-spec.*`
- Docs: existing design-doc location, otherwise `docs/design/`
- Approval: required before frontend implementation or major UX changes continue

### Research / Analysis

- Artifact: research brief or analysis brief
- Chat: question, answer, evidence, citations, risks, recommended next steps
- Blackboard: `artifacts.research.research-brief.*` or `artifacts.analysis.analysis-brief.*`
- Docs: existing research/docs location, otherwise `docs/research/`
- Approval: required only when the brief becomes the basis for downstream strategic decisions

### Planning / Orchestration

- Artifact: implementation plan or execution plan
- Chat: milestones, owners, dependencies, acceptance criteria, optional Mermaid dependency graph
- Blackboard: `artifacts.plan.implementation-plan.*`
- Docs: existing plan docs location, otherwise `docs/plans/`
- Approval: usually an explicit proceed gate before implementation, not a heavyweight approval loop

### Review / QA / Release

- Reviewer artifact: review summary with verdict, blockers, and residual risk
- Tester artifact: test strategy, risk matrix, or signoff summary with evidence
- Release artifact: release checklist, rollout plan, rollback plan, go/no-go state
- Blackboard: `artifacts.review.review-summary.*`, `artifacts.test.test-signoff.*`, `artifacts.release.release-plan.*`
- Docs: existing testing/release docs location, otherwise `docs/testing/` or `docs/release/`
- Approval: required before merge, deploy, or release actions when quality or rollout status is the gate

### Implementation Roles

- Artifact: lightweight implementation plan, change summary, or review handoff
- Chat: planned scope, touched areas, verification, notable risks
- Blackboard: `artifacts.impl.change-handoff.*`
- Docs: only when the output is meant to be durable beyond the session
- Do not force a heavyweight approval gate before routine coding

## Output Rules

- Keep artifacts concise, structured, and easy to approve or revise
- State assumptions and unresolved risks explicitly
- End in one of these states:
  - `Awaiting approval`
  - `Awaiting proceed signal`
  - `Approved and ready for handoff`
