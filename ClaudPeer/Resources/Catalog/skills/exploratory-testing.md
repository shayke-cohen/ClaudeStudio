# Exploratory Testing (Chartered Sessions)

## When to Activate

On new features with unknown edge cases, after refactors touching many modules, or when automated suites pass but user reports keep appearing — hunt unknown-unknowns with structure, not random clicking.

## Process

1. **Charter the mission** — Write a one-paragraph goal: “Explore checkout with mixed currencies while toggling network offline mid-payment.” Time-box (45–90 minutes).
2. **Vary dimensions** — Change input order, boundary values, parallel tabs, stale sessions, and rapid double-submits. Intentionally misuse features (paste huge text, invalid dates).
3. **Watch recovery** — Observe error messages, retries, partial state, and idempotency. Note whether users can self-correct without support.
4. **Capture minimal repros** — Screenshot or short screen recording + exact steps + environment/build. File a ticket with severity and component guess.
5. **Debrief** — Summarize themes (e.g. “validation inconsistent on mobile”), coverage notes, and suggested automation candidates. Share with devs same day.
6. **Pair or rotate** — A second tester challenges assumptions; devs can join for 20 minutes to learn failure modes.

## Checklist

- [ ] Charter and time box defined before starting
- [ ] Inputs, ordering, and state varied deliberately
- [ ] Errors and recovery paths exercised
- [ ] Each bug has minimal repro and evidence
- [ ] Debrief produced themes and automation ideas

## Tips

Use session-based notes (timestamped) rather than perfect scripts. Combine with production logs if staging lacks realism. Stop when charter is satisfied, not when the hour ends — extend only with a new charter.
