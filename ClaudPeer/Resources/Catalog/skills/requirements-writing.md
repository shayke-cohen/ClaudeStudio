# Requirements Writing: Problem, Constraints, and Solution Clarity

## When to Activate

Use before engineering estimates, RFP responses, or whenever stakeholders need shared truth on what “done” means.

## Process

1. **State the user outcome.** Lead with the job-to-be-done and measurable success (e.g., “reduce checkout time p95 by 20%”). Avoid prescribing implementation unless constrained.
2. **Separate must/should/could.** Use **MoSCoW** or similar; tie must-haves to compliance or revenue risk; park nice-to-haves explicitly to prevent scope arguments later.
3. **Constraints upfront.** List platforms, locales, performance budgets, accessibility level, legal retention, and integrations—engineering should not discover these mid-build.
4. **Acceptance tests.** Write Given/When/Then or checklist items verifiable by QA; include negative paths (invalid input, offline mode) and permission variants.
5. **Failure behavior.** Document timeouts, retries, and user-visible errors; specify logging/metrics needed for operations.
6. **Iterate early.** Review drafts with engineering in a 30-minute sync; adjust for feasibility; capture open questions as tracked decisions, not vague prose.

## Checklist

- [ ] Outcome metric defined
- [ ] Priorities labeled (must/should/could)
- [ ] Constraints and non-functional reqs listed
- [ ] Acceptance tests cover happy + edge paths
- [ ] Open questions have owners/dates

## Tips

Link to designs and data diagrams instead of duplicating them. Version requirements in git or your PM tool; note changes in a short changelog for auditability.
