# WebSocket

## When to Activate

Use when building real-time dashboards, chat, or collaborative editing over persistent connections. Apply when scaling fan-out, handling auth, or debugging reconnect loops.

## Process

1. **Auth at handshake**: Validate JWT or session cookie during the HTTP upgrade; reject before accepting the socket. Do not rely on first message for auth on public endpoints.
2. **Protocol design**: Namespace channels (`/room/{id}`) and message envelopes `{ type, id, payload }` with schema validation (**zod**, **protobuf** for binary).
3. **Ping/pong**: Server-initiated heartbeats; close idle clients after TTL to free file descriptors. Clients exponential-backoff reconnect with jitter.
4. **Backpressure**: Track unsent buffer size per socket; drop or sample low-priority events when overloaded; never unbounded queue per connection.
5. **Authorization**: On each subscribe, verify room membership server-side; do not trust client-provided room ids alone.
6. **Load testing**: Simulate reconnect storms with **k6** WebSocket or **Artillery**. Monitor connection count, message rate, and GC pauses.

## Checklist

- [ ] Authentication during upgrade
- [ ] Channel namespaces and schemas defined
- [ ] Heartbeats and idle disconnects configured
- [ ] Backpressure policy documented
- [ ] Per-subscription authz enforced
- [ ] Reconnect storm tested

## Tips

**Socket.IO** namespaces simplify routing; **uWS**/**ws** (Node) for minimal overhead. Behind load balancers, enable sticky sessions or use a **Redis** pub/sub adapter for horizontal scale.
