# Serverless

## When to Activate

Use when deploying **AWS Lambda**, **Vercel Functions**, **Cloudflare Workers**, or Azure Functions—or when cold starts, timeouts, and IAM sprawl hurt reliability and security.

## Process

1. **Small handlers**: One responsibility per function; share code via internal packages or Lambda layers. Bundle with **esbuild** or **esbuild-register**; run `npm ls` audits and remove unused deps.
2. **Cold starts**: Lazy-import heavy SDKs inside handlers when safe; reuse AWS SDK v3 clients in global scope for Lambda. Increase memory to gain CPU proportionally; measure with **AWS Lambda Power Tuning** tool.
3. **Timeouts and concurrency**: Set timeout just above measured p99; configure reserved concurrency for critical functions; use async invocation for fire-and-forget side effects when duplicates are acceptable.
4. **Idempotency**: Platforms retry on failure—use idempotency keys and conditional writes (**DynamoDB** `ConditionExpression`, **Stripe** idempotency headers) for payments, inventory, and notifications.
5. **Observability**: Emit structured JSON logs; enable **AWS X-Ray** or OpenTelemetry Lambda layers; include `awsRequestId` / `trace_id` in error reports for correlation.
6. **IAM least privilege**: One role per function with minimal actions/resources; deny `*` wildcards. Validate with **IAM Access Analyzer** or policy-as-code (**cdk-nag**, **CloudFormation Guard**).

## Checklist

- [ ] Handler code and dependencies minimized; bundle analyzed
- [ ] Cold start profiled at expected memory settings
- [ ] Timeout and concurrency tuned with load tests
- [ ] Side-effecting handlers are idempotent
- [ ] Logs/traces correlate across calls
- [ ] IAM policies scoped narrowly per function

## Tips

Test locally with **`sam local invoke`** or **`vercel dev`**. For **Cloudflare Workers**, respect CPU time limits; use **Durable Objects** only when you need strongly consistent coordination. Configure **DLQ** or Lambda **onFailure** destinations for async invocations.
