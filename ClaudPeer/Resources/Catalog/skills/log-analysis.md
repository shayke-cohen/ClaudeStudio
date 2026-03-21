# Log Analysis During Incidents

## When to Activate

When debugging production issues, validating a canary, or post-incident — turn raw logs into a coherent timeline without drowning in volume.

## Process

1. **Anchor the window** — Start from alert time ± buffer. If user supplied a **correlation ID** or **trace ID**, filter on that first across services.
2. **Progressive filtering** — Broad query (`service:checkout AND level:ERROR`) then narrow (`status:500 AND path:/api/cart`). In **Datadog** Logs, **Grafana Loki** (`LogQL`), or **CloudWatch Logs Insights**, add fields not full-text grep when possible.
3. **Compare canary vs baseline** — Same query, split by `version` or `deployment` tag; quantify error ratio delta, not just presence.
4. **Pattern extraction** — Use “top values” on `exception.type` or `error.code`; cluster repeated stack traces to find the dominant failure mode.
5. **Cross-link** — Jump from log line to trace span in APM; verify hypothesis with metrics (spike aligns with deploy or traffic change).
6. **Summarize** — Write timeline: first error, blast radius (regions, % requests), mitigations tried, root cause hypothesis, evidence links.

## Checklist

- [ ] Time range and correlation IDs established
- [ ] Queries narrowed from coarse to precise
- [ ] Canary/baseline compared when relevant
- [ ] Dominant error patterns identified with counts
- [ ] Timeline documented with links to queries

## Tips

Ensure logs include `request_id`, `user_hash` (not raw PII), `build_sha`. Redact secrets at source. Save useful queries as shared views for the next incident.
