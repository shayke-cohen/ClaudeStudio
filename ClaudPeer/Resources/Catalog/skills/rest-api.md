# REST API Design

## When to Activate

Use when designing or hardening HTTP APIs consumed by web, mobile, or partners. Apply for new resources, pagination changes, error shape standardization, or versioning policy.

## Process

1. **Resources as nouns**: Use plural path segments (`/users`, `/users/{id}/orders`). Map operations to verbs via HTTP methods: `GET` retrieve, `POST` create, `PUT`/`PATCH` update, `DELETE` remove.
2. **Status codes**: Use `201 Created` with `Location` on create; `204` for empty success; `400` validation, `401` unauthenticated, `403` forbidden, `404` missing, `409` conflict, `422` semantic errors, `429` rate limit, `5xx` server faults—avoid always `200` with error bodies.
3. **Problem details**: Return **RFC 7807** `application/problem+json` with `type`, `title`, `status`, `detail`, `instance` for errors; keep stable `type` URIs for client branching.
4. **Pagination/filter/sort**: Prefer cursor pagination for large sets (`?cursor=` + `limit`); document max limits. Use explicit filter params (`?status=active`) and whitelist sort fields (`?sort=-created_at`).
5. **Validation**: Validate at the boundary; return field-level errors in problem extension. Reject unknown JSON properties if strict contracts matter.
6. **Versioning**: Use URL prefix (`/v1/...`) or header; never break existing clients without a new version. Document sunset dates.
7. **Docs**: Maintain **OpenAPI 3** with request/response examples, auth schemes (Bearer, OAuth2 scopes), and rate limit headers.

## Checklist

- [ ] Resource paths are noun-based and consistent
- [ ] Status codes match semantics
- [ ] Errors use problem+json or equivalent
- [ ] Pagination/filter/sort documented with limits
- [ ] OpenAPI published with auth scopes

## Tips

Expose **ETag** / **If-None-Match** for cacheable reads. Document **Idempotency-Key** for `POST` where duplicates are costly.
