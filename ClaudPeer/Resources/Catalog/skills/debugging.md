# Systematic Debugging

## When to Activate

Use when behavior diverges from expectations: crashes, flaky tests, wrong data, or performance cliffs—before guessing a fix.

## Process

1. **Reproduce reliably** — Minimal steps, fixed seed, recorded inputs. Script with `curl`, CLI flags, or a reduced test case. If flaky, capture timestamps and environment.
2. **Form hypotheses** — List plausible causes (data, timing, config, version). Rank by likelihood and cost to falsify.
3. **Isolate variables** — Binary search: `git bisect start`, `git bisect bad`, `git bisect good <sha>`. Toggle feature flags, swap dependencies, run with `log level=debug`.
4. **Observe** — Use logs, breakpoints (`lldb`), Instruments (Time Profiler, Allocations), or `sample` on macOS. For Node/Bun: `--inspect`, CPU profiles. Confirm which layer fails (UI, app, sidecar, DB).
5. **Fix the cause** — Prefer correcting invalid assumptions or missing validation over masking symptoms. Keep the change minimal.
6. **Prevent recurrence** — Add a regression test or assertion at the boundary where the bug escaped.

## Checklist

- [ ] Reproduction is documented and repeatable
- [ ] Hypothesis tested; wrong paths ruled out
- [ ] Fix addresses root cause, not only the symptom
- [ ] Regression test or guard added where feasible
- [ ] Monitoring or logs improved if failure was silent

## Tips

Rubber-duck the data path: source → transform → sink. When stuck, compare working vs broken binary states with `git diff`. Avoid “fixing” by catching and ignoring errors without understanding.
