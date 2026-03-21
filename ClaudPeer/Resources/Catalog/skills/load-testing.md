# Load Testing (Stress & Capacity)

## When to Activate

Before major launches, after performance fixes, when scaling targets change, or when latency SLOs are missed under peak — validate capacity, not just correctness.

## Process

1. **Define realistic workflows** — Map critical user journeys (login → browse → checkout). Encode as **k6** scenarios, **Artillery** YAML flows, or **Locust** task sets; weight steps by production traffic mix.
2. **Set SLOs** — Example: p95 API latency < 500 ms, error rate < 0.1%. Document breaking point as the RPS where SLOs fail for 5+ minutes.
3. **Environment parity** — Run against staging sized like prod (or a scaled-down model with extrapolation). Isolate from production unless using shadow traffic with safeguards.
4. **Ramp gradually** — Use stages: `ramp-up`, `steady`, `spike`, `cool-down`. In k6: `stages: [{ duration: '2m', target: 100 }, ...]`. In Artillery: `phases` with `arrivalRate` and `rampTo`.
5. **Observe golden signals** — Watch p50/p95/p99 latency, error rate, CPU, memory, DB connections, queue depth, and cache hit ratio. Use APM (**Datadog**, **New Relic**) and infra metrics.
6. **Find bottlenecks** — Profile hot paths (flame graphs, DB slow query logs). Re-run after each fix to confirm the bottleneck moved rather than masked.
7. **Document results** — Save graphs, max sustainable RPS, and resource headroom. Attach to the ticket or capacity runbook.

## Checklist

- [ ] Scenarios mirror real workflows and weights
- [ ] Ramp/spike/cool-down defined; no cold-start surprise as “pass”
- [ ] p95/p99 and errors tracked against SLOs
- [ ] Bottleneck hypothesis validated with profiling evidence
- [ ] SLOs and breaking points written down for ops

## Tips

Warm caches before measuring steady state. Use correlation IDs in requests to trace failures. Keep load tests short in CI (smoke load) and run full tests on a schedule or release gate.
