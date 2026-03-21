# API Documentation

## When to Activate

Use when exposing REST, GraphQL, or gRPC APIs to internal or external consumers. Update whenever auth, pagination, error shapes, or versioning change—ideally in the same PR as the code.

## Process

1. **Auth and limits** — Document schemes (OAuth2, API keys, mTLS), token lifetimes, scopes, **rate limits** (per key/IP), and retry guidance (`429` + `Retry-After`).
2. **Pagination and filtering** — Cursor vs offset: show query params, max page size, and how to detect end-of-list. Include sorting and stable ordering guarantees if any.
3. **Request/response examples** — Real JSON for happy path and one representative error per class (`4xx` validation, `401`, `403`, `404`, `409`). Use `curl` examples: `curl -sS -H "Authorization: Bearer $TOKEN" https://api.example.com/v1/items`.
4. **Schemas from source** — Generate OpenAPI from FastAPI, NestJS decorators, or `tsoa`; GraphQL from SDL; protobuf for gRPC. Avoid hand-maintained tables that drift.
5. **Versioning** — URL path (`/v1/`) or header strategy—pick one and document deprecation policy and sunset headers.
6. **Changelog for breaking changes** — Link to Keep a Changelog or OpenAPI diff; call out field removals and enum changes explicitly.

## Checklist

- [ ] Auth, rate limits, and pagination documented
- [ ] Examples use realistic payloads and curl/httpie
- [ ] Schemas generated or validated in CI
- [ ] Versioning and deprecation rules stated
- [ ] Breaking changes noted with migration steps

## Tips

Publish docs with Redocly, Stoplight Elements, or Mintlify. Add an “errors” appendix mapping codes to remediation. For internal APIs, a Postman/Insomnia collection checked into `docs/` speeds partner teams more than prose alone.
