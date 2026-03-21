# Queue Processing

## When to Activate

Use when moving work off the request path: emails, webhooks, media processing, or fan-out events. Apply when retries duplicate side effects or DLQs grow unexplained.

## Process

1. **Idempotent consumers**: Use natural idempotency keys (`event_id`, `order_id`) stored in DB with unique constraint before performing irreversible actions. Design handlers safe under at-least-once delivery.
2. **Retry policy**: Exponential backoff with **full jitter** (`sleep = random(0, min(cap, base * 2^attempt))`). Cap attempts; move to **DLQ** (SQS dead-letter, RabbitMQ DLX) with alerting.
3. **Payload size**: Pass references (S3 keys) not megabyte blobs. Keep messages under broker limits (SQS 256KB, RabbitMQ configurable).
4. **Monitoring**: Track **age of oldest message**, processing rate, and error ratio. Page on DLQ depth > threshold.
5. **Failure injection**: Chaos-test poison messages and broker outages in staging. Verify dashboards and runbooks.
6. **Ordering**: Avoid assuming global order; use partition keys (**SQS FIFO**, **Kafka** partitions) only when strictly needed.

## Checklist

- [ ] Consumers idempotent with dedupe keys
- [ ] Backoff + jitter; max retries defined
- [ ] DLQ monitored with triage playbook
- [ ] Payloads small or offloaded to object storage
- [ ] Chaos or load tests cover retries

## Tips

**BullMQ** (Redis) fits Node workers; **RabbitMQ** for complex routing; **AWS SQS** for managed scale. Document exactly-once vs at-least-once expectations for each job type.
