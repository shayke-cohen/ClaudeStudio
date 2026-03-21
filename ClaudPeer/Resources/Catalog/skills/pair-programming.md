# Pair Programming

## When to Activate

Use for complex design, tricky bugs, onboarding, or high-risk changes where two perspectives reduce rework—locally or over screen share.

## Process

1. **Align on goal** — One sentence outcome and time box (e.g. “fix reconnect loop in 45m”). Agree on definition of done.
2. **Driver** — Types and runs; narrates intent (“I will extract validation next”). Keeps momentum; avoids silent exploration.
3. **Navigator** — Watches for drift from goal, spots edge cases, suggests names and tests. Captures follow-ups instead of derailing mid-edit.
4. **Swap roles** — Switch at natural breakpoints: green test, passing build, or end of a subtask. Roughly every 15–25 minutes if energy drops.
5. **Thin slices** — Ship the smallest vertical slice that proves the approach (e.g. one command path + test) before generalizing.

## Checklist

- [ ] Goal and done criteria stated aloud
- [ ] Driver narrates; navigator challenges assumptions
- [ ] Roles rotated at least once per session
- [ ] Tangents parked on a short list
- [ ] Session ends with next step or PR outline

## Tips

Use a shared branch or live share; avoid long silent reading—skim separately, then pair on decisions. When opinions clash, prototype the cheaper option behind a flag. Record decisions in the PR or ADR stub.
