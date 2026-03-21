# Error Handling

## When to Activate

Use when defining failures across UI, services, and batch jobs—so operators can act and users see safe, accurate messages.

## Process

1. **Classify** — Expected (validation, not found) vs unexpected (invariant violated). Retryable (network blip, `503`) vs fatal (bad config, auth). Encode in typed errors (`enum APIError: Error`) or `NSError` domains.
2. **Propagate context** — Wrap lower errors with cause chains (`LocalizedError`, `Error.cause` in Swift, `new Error("...", { cause })` in TS). Include correlation IDs from headers or logs.
3. **User messaging** — Map internal codes to concise UI copy; log detailed diagnostics separately. Never echo raw SQL/driver messages to clients.
4. **Observability** — Emit structured fields: `error.code`, `sessionId`, `route`. Use appropriate log level (`error` vs `warning`). Alert on error-rate SLO breaches, not single 404s.
5. **Test failures** — Unit-test error mapping and retry policy with fakes. Integration tests assert HTTP status and body shape for representative failures.

## Checklist

- [ ] Errors typed; stringly comparisons avoided in hot paths
- [ ] Retry only on idempotent or safe operations
- [ ] Sensitive data excluded from user-facing text
- [ ] Logs include correlation and stable codes
- [ ] Failure paths covered by tests

## Tips

Prefer `Result` or `throws` over optional tuples for failure reasons. Centralize mapping in one module per boundary. Document partial failure semantics for batch APIs.
