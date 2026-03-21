# Microservices

## When to Activate

Use when evaluating service splits, defining boundaries, or improving reliability across many deployables. Apply before carving a monolith—or when debugging cascading failures and inconsistent data.

## Process

1. **Justify splits**: Separate services only for independent scaling, team ownership, or hard technology constraints—not for fashion. Prefer a modular monolith until domain seams and team topology are clear.
2. **Contracts**: Version APIs (**OpenAPI** for REST, **protobuf** for gRPC, **AsyncAPI** for events). Add consumer-driven contract tests (**Pact**) in CI to catch breaking changes early.
3. **Failure modes**: Assume dependencies are down; use timeouts, bulkheads, and circuit breakers (**resilience4j**, **Polly**). Replace long synchronous chains with async workflows or cached read models.
4. **Data ownership**: One service owns each datastore; integrate through APIs or events, not cross-database joins. Use the **outbox pattern** for reliable publication alongside DB commits.
5. **Observability**: Standardize **OpenTelemetry** with trace context propagation, structured logs including `service.name`, and RED/USE metrics per endpoint and queue.
6. **Graceful degradation**: Feature-flag non-critical features; serve stale cache or simplified responses when peers fail. Define SLOs and error budgets per service in a catalog (**Backstage**).

## Checklist

- [ ] Split rationale tied to scaling or team autonomy
- [ ] APIs/events versioned; contract tests in CI
- [ ] No critical path of long synchronous hops
- [ ] Single owner per dataset; outbox or equivalent for events
- [ ] Tracing, metrics, and runbooks exist per service

## Tips

Prefer **event-driven** integration over chatty synchronous HTTP. Document failure budgets and on-call rotations. Avoid shared libraries that hide implicit coupling without semver discipline.
