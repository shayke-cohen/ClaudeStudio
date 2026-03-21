# Structured Logging

## When to Activate

Use when instrumenting services, debugging production issues, or designing on-call dashboards—especially multi-process apps (Swift app + Bun sidecar) behind a load balancer.

## Process

1. **Stable event names** — Use `snake_case` or `dot.separated` keys (`session.message.sent`) that grep and metrics can join. Avoid interpolated sentences as primary identifiers.
2. **Consistent fields** — Standardize `request_id`, `user_id` (hashed if needed), `session_id`, `duration_ms`, `outcome`. Document schema in a short table or OpenTelemetry semantic conventions.
3. **Correlation** — Propagate `X-Request-ID` or W3C `traceparent` across HTTP, WebSocket handshakes, and background jobs. Log the same ID at each hop.
4. **PII hygiene** — Avoid raw emails, tokens, and full payloads in logs. Redact query params; sample bodies only in debug behind flags.
5. **Levels** — `debug` for diagnosis, `info` for lifecycle, `warn` for recoverable anomalies, `error` for operator action. Align with retention: ship `info+` to long-term store.
6. **Verify dashboards** — After changes, confirm Grafana/Datadog panels filter on the new fields; run a dry-run incident drill.

## Checklist

- [ ] Event names and keys stable across versions
- [ ] Request/trace IDs end-to-end
- [ ] No secrets or raw PII in default logs
- [ ] Levels match on-call runbooks
- [ ] Sampling/retention policy documented

## Tips

Prefer JSON logs for servers (`Bun.write` to stdout with JSON). In Swift, use `Logger` with privacy annotations. High-cardinality labels belong in traces/spans, not metric labels.
