# API Testing (Contract, Negative, Performance)

## When to Activate

Use before shipping or refactoring HTTP APIs, after auth changes, when adding pagination or versioning, or when CI needs stronger regression gates than smoke tests alone.

## Process

1. **Inventory the contract** — OpenAPI/Swagger or Postman collections are the source of truth. Export a machine-readable spec (`openapi.json`) and treat breaking changes as test failures.
2. **Build an auth matrix** — For each role or token type, list allowed and denied routes. Exercise missing token, expired token, wrong scope, and cross-tenant IDs. Tools: `curl`, **Newman** (`newman run collection.json`), **REST Client** in VS Code, or **Bruno**.
3. **Happy path + schema** — Assert HTTP status, required headers (`Content-Type`, caching, `ETag`), and JSON body against JSON Schema or contract tests (**Dredd**, **Schemathesis**, **Pact** for consumer-driven contracts).
4. **Negative cases** — Invalid JSON, wrong types, oversize payloads, SQL-injection-style strings, unicode, and boundary values. Expect consistent error envelopes (`code`, `message`, `requestId`).
5. **Pagination & filtering** — Verify stable ordering, `limit`/`cursor` bounds, empty pages, and filter combinations that return zero rows without 500s.
6. **Idempotency** — Replay `POST` with `Idempotency-Key` (or safe `PUT`/`DELETE`) and confirm no duplicate side effects; check response codes on replay (`200`/`409` as designed).
7. **Rate limits** — Drive concurrent requests with **k6** or **hey** (`hey -n 1000 -c 50 https://api/...`). Assert `429`, `Retry-After`, and headers documenting limits.
8. **Version compatibility** — Maintain a small suite per major version; run against staging with `Accept`/`API-Version` headers or path prefixes (`/v1/` vs `/v2/`).
9. **Performance baselines** — Capture p95 latency and error rate under light load; fail CI if regression exceeds agreed thresholds.

## Checklist

- [ ] Contract/spec is versioned and referenced in tests
- [ ] Authn/authz matrix covered for critical routes
- [ ] Status, headers, and schema assertions on success and errors
- [ ] Pagination, filters, and idempotency verified
- [ ] Rate-limit behavior documented and tested
- [ ] Versioned compatibility suite runs in CI

## Tips

Prefer deterministic tests: seed data via migrations or fixtures, disable non-essential background jobs in test envs, and tag tests (`@contract`, `@negative`, `@perf`) so fast suites stay default in PR pipelines.
