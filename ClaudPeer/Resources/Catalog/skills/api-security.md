# API Security: Hardening HTTP and GraphQL

## When to Activate

Use when exposing public or partner APIs, adding GraphQL/mobile backends, or when abuse (scraping, stuffing, IDOR) appears in production metrics.

## Process

1. **Authenticate consistently.** Prefer OAuth2/OIDC or signed tokens with short TTL + rotation; reject mixed auth modes per route. Enforce `Authorization` on every state-changing call.
2. **Authorize per resource instance.** Resolve object IDs server-side; check tenant/user ownership before read/update. GraphQL: disable introspection in prod; implement field-level auth and query cost limits.
3. **Rate limit and throttle.** Use gateway or middleware (e.g., **Envoy**, **Kong**, **AWS API Gateway**) with per-IP and per-user keys; backoff on 429. Detect credential stuffing via velocity + impossible travel signals.
4. **Validate inputs.** Enforce `Content-Type`, max body size, and JSON schema / OpenAPI validation. Reject unknown fields where ambiguity enables bypass.
5. **Prevent IDOR.** Use opaque IDs or signed capabilities; avoid exposing sequential integers without checks. Fuzz adjacent IDs in tests.
6. **Security logging.** Log auth failures, policy denials, and admin actions to SIEM; include request ID, never raw passwords or tokens.
7. **Fuzzing.** Run **RESTler**, **Schemathesis**, or Burp Intruder on OpenAPI—focus on authz boundaries and type confusion.

## Checklist

- [ ] Auth required on all non-public routes
- [ ] Object-level authz tests for CRUD
- [ ] Rate limits + payload limits configured
- [ ] GraphQL limits/introspection posture defined
- [ ] Security events wired to alerts

## Tips

Publish an API error contract: stable codes, no internal traces. Rotate API keys and webhooks on compromise; use mTLS for high-trust integrations.
