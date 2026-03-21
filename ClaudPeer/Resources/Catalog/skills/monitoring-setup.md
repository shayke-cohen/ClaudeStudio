# Monitoring, Dashboards & SLOs

## When to Activate

When launching a service, after incidents exposed blind spots, or when alerts fatigue the team — align telemetry with user pain and on-call reality.

## Process

1. **Golden signals** — Dashboard **latency** (p95/p99), **traffic** (RPS), **errors** (rate + budget), **saturation** (CPU, memory, queue depth, DB pool). Tools: **Prometheus** + **Grafana**, **Datadog** APM, or cloud-native metrics.
2. **RED/USE methods** — For each service: Rate, Errors, Duration per request; Utilization, Saturation, Errors on resources.
3. **SLOs** — Define SLIs (e.g. successful requests < 500 ms) and error budgets. Track burn rate; page on multi-window burn (**Google SRE** alerting patterns) not single blips.
4. **User-impacting alerts** — Prefer symptom-based alerts (“checkout error spike”) over cause-only (“pod restarted”) unless cause predicts imminent user impact.
5. **Consistent tags** — `service`, `env`, `version`, `region` on metrics, logs, and traces for correlation. Avoid high-cardinality labels (raw user IDs) in Prometheus.
6. **Tracing** — Enable OpenTelemetry exporters to **Jaeger** or vendor APM; sample wisely in prod (head-based + tail sampling where supported).
7. **Runbooks** — Every alert links to a runbook: verify, mitigate, escalate. Test alerts quarterly with game days.

## Checklist

- [ ] Dashboards cover golden signals per critical service
- [ ] SLOs and error budgets defined and visible
- [ ] Alert rules reduce noise; on-call agrees they are actionable
- [ ] Tags consistent across metrics/logs/traces
- [ ] Runbooks linked from alert routes

## Tips

Use SLO widgets in Grafana/Datadog for leadership visibility. Silence alerts with end times only, never infinite mute. Log structured JSON with `trace_id` for cross-system joins.
