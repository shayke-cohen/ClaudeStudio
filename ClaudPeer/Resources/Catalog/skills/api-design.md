# API Design

## When to Activate

Use when designing REST/GraphQL/gRPC/WebSocket contracts, internal service boundaries, or public SDKs—before implementation hardens mistakes.

## Process

1. **Consumer journeys** — Walkthrough primary flows: discover resource, create, paginate list, handle conflict. Name resources and verbs for tasks users perform.
2. **Explicit types** — Use JSON Schema, OpenAPI, or protobuf for payloads. Prefer enums and structured errors over opaque strings. Version breaking changes (`/v2`, package major).
3. **Pagination and filters** — Cursor-based pagination for large sets; document max page size. Stable sort keys. Rate limits and `429` semantics stated.
4. **Idempotency** — For POST that creates billing or side effects, accept `Idempotency-Key` header or dedupe token. Document replay behavior.
5. **Errors** — Machine-readable `code`, human `message`, optional `details`. Map auth failures to `401`/`403` consistently; never leak stack traces.
6. **Auth** — Specify schemes (`Authorization: Bearer`, mTLS). Document scopes required per route. Consider optional fields vs breaking additions.

## Checklist

- [ ] Happy path and failure path documented with examples
- [ ] Pagination, sorting, and limits defined
- [ ] Idempotency strategy for mutating operations
- [ ] Versioning plan for incompatible changes
- [ ] Authn/z requirements per endpoint

## Tips

Design for observability: stable operation names in traces. Add deprecation headers before removal. Mock servers from OpenAPI (`prism`, `mockoon`) to validate clients early.
