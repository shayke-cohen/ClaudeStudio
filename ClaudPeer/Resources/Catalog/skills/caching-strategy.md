# Caching Strategy

## When to Activate

Use when adding CDN edge cache, application cache, or database read replicas—or when debugging stale data, privacy leaks, or thundering herds. Apply at architecture reviews and incident postmortems involving cache.

## Process

1. **Name keys and TTLs**: Document cache key schema (`user:{id}:profile:v2`) and TTL policy per entity type. Store TTL in config, not scattered literals.
2. **Correctness on writes**: Invalidate or update cache in the same transaction boundary as the DB write when strong consistency is required; otherwise use versioned keys or short TTL for eventually consistent reads.
3. **User scoping**: Never cache personalized responses at CDN without `Vary: Cookie` or per-user cache keys—prefer private browser cache or no-store for authenticated HTML.
4. **Stampede protection**: Use **probabilistic early expiration**, **singleflight** (one recomputation per key), or locks in **Redis** (`SET key NX EX`) for hot keys.
5. **HTTP/CDN**: Set `Cache-Control`, `s-maxage`, `stale-while-revalidate`, and `Surrogate-Key` (Fastly) or tag purges (Cloudflare) for grouped invalidation on deploy.
6. **Measurement**: Track hit ratio, origin offload, and p95 latency. Alert on sudden miss spikes (possible invalidation bug).

## Checklist

- [ ] Key naming and TTL table documented
- [ ] Write path updates or invalidates cache intentionally
- [ ] No shared CDN cache for sensitive per-user payloads
- [ ] Hot-key stampede mitigations in place
- [ ] Purge/invalidation runbook for releases
- [ ] Hit rate and latency monitored

## Tips

Use **Redis** `INFO stats` and `latency doctor`. Prefer **ETag**/`Last-Modified` for API clients. For GraphQL, avoid caching anonymous POST at edge unless using persisted queries with GET.
