# Kubernetes Deployment

## When to Activate

When moving workloads to K8s, tuning production reliability, or changing rollout strategy — align manifests with observed load and failure modes.

## Process

1. **Declare desired state** — Store YAML in Git; apply via CI. Prefer **Helm** (`helm upgrade --install myapp ./chart -n prod`) or **Kustomize** for overlays per environment.
2. **Requests and limits** — Set `resources.requests` to scheduling truth; set `limits` to cap runaway pods. Load-test to validate; adjust when OOMKilled or throttled.
3. **Probes** — `readinessProbe` gates traffic; `livenessProbe` restarts unhealthy containers. Keep checks cheap and side-effect free (`GET /health/ready`).
4. **Secrets** — Avoid plain `Secret` YAML in repos. Use **External Secrets Operator**, **AWS Secrets Manager** + CSI, or **Sealed Secrets**. Rotate credentials via automation.
5. **Rollouts** — Use `Deployment` `strategy: RollingUpdate` with `maxUnavailable`/`maxSurge`. For advanced traffic shift, add **Flagger** or a service mesh canary.
6. **Rollback plan** — `kubectl rollout undo deployment/myapp -n prod` or `helm rollback myapp 3`. Verify one-command rollback in staging drills.
7. **Observe** — `kubectl get pods -n prod -w`, `kubectl logs deploy/myapp -f`, `kubectl describe pod` for events.

## Checklist

- [ ] Manifests versioned; apply path documented
- [ ] CPU/memory requests and limits set from data
- [ ] Readiness/liveness distinct and fast
- [ ] Secrets sourced from external store
- [ ] Rollback tested; progressive delivery if needed

## Tips

Use **PodDisruptionBudgets** for HA. Label workloads consistently (`app`, `version`, `env`) for metrics and network policies. Keep config in `ConfigMap`, secrets out of images.
