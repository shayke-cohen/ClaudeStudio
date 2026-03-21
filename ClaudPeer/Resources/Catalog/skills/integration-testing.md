# Integration Testing

## When to Activate

Use when multiple components must cooperate: database + repository, HTTP API + auth middleware, Swift app service + sidecar over WebSocket.

## Process

1. **Choose real dependencies that matter** — Run Postgres/Redis via Docker Compose or Testcontainers (`testcontainers-node`, `swift-service-lifecycle`). Mock only third parties you do not own and cannot stage.
2. **Seed minimal data** — Migrations up, insert fixtures with IDs you control. Tear down or use transactions per test to avoid order dependence.
3. **Assert externally visible outcomes** — HTTP status/body, DB rows, WebSocket frames—not internal singleton state. Time-bound waits with polling, not bare `sleep`.
4. **CI parity** — Same compose file locally and in GitHub Actions. Pin image digests. Expose ports dynamically to keep parallel jobs isolated.
5. **Parallel-friendly** — Unique database names or schemas per worker (`TEST_WORKER_ID`). Avoid shared files in `/tmp` without locks.

## Checklist

- [ ] Services started deterministically from CI config
- [ ] Tests do not depend on execution order
- [ ] Assertions on IO boundaries, not private fields
- [ ] Logs captured on failure for triage
- [ ] Runtime under acceptable CI budget

## Tips

Tag slow suites (`@slow`) for optional runs. Use health checks (`wait-on`, `curl --retry`) before tests. For WebSocket flows, drive a real client against `ws://localhost:9849` with timeouts.
