# Rate Limiting

## When to Activate

Use when protecting APIs from abuse, noisy neighbors, or cost blowups—or when clients need predictable fairness. Apply at edge (CDN/WAF) and origin.

## Process

1. **Algorithm choice**: **Token bucket** for bursty traffic with smooth average; **sliding window** or **fixed window** for simpler Redis counters; **leaky bucket** for steady egress. Document burst vs sustained limits separately if needed.
2. **Keying**: Rate limit by authenticated `user_id` or `tenant_id` first; fall back to IP for anonymous endpoints. Use separate buckets for expensive operations.
3. **Client response**: Return **429 Too Many Requests** with **`Retry-After`** (seconds or HTTP-date). Include problem details body with `rate_limit_remaining` if helpful.
4. **Shared dependencies**: Limit calls to payment, SMS, and search providers with global quotas and per-tenant sub-quotas to prevent one tenant exhausting shared capacity.
5. **Monitoring**: Track block rate, false positives (support tickets), and latency overhead. Sample logs of limited requests without storing full PII.
6. **Documentation**: Publish limits and headers (`X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset`) in OpenAPI.

## Checklist

- [ ] Algorithm matches traffic shape (burst vs steady)
- [ ] Keys prioritize user/tenant over IP
- [ ] 429 + Retry-After implemented consistently
- [ ] Expensive downstreams have global caps
- [ ] Limits documented for API consumers

## Tips

Implement with **Redis** `INCR` + TTL, **Envoy** local rate limit, or **Cloudflare**/`AWS WAF` rules. Add **allowlists** for trusted cron jobs via mTLS or signed internal headers.
