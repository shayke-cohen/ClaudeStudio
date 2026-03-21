# Secrets Management

## When to Activate

When creating new services, after credential leaks, or when rotating API keys — ensure secrets never sprawl in repos, images, or chat logs.

## Process

1. **Never commit secrets** — Use **git-secrets**, **trufflehog**, or **Gitleaks** in pre-commit/CI. If leaked, rotate immediately; history rewrite is secondary to revocation.
2. **Central store** — **HashiCorp Vault** (`vault kv put secret/app db_password=...`), **AWS Secrets Manager**, **GCP Secret Manager**, or **Azure Key Vault**. Inject at runtime via CSI drivers, sidecars, or env from orchestrator.
3. **Least privilege** — Scope tokens to minimal roles; short TTL where possible (OIDC federation for CI/CD instead of long-lived AWS keys).
4. **Rotation** — Automate on schedule and on incident. Document emergency rotation: who can issue new DB password, how apps pick up new value (reload vs restart).
5. **Runtime injection** — Kubernetes: `Secret` mounted as file or env from **External Secrets**. Docker: `--secret` (Swarm) or runtime env from orchestrator, not `Dockerfile` `ENV`.
6. **Break-glass** — Rare admin paths logged and alerted; time-limited elevation; mandatory post-access review.
7. **Audit** — Enable access logs on secret stores; alert on unusual read patterns.

## Checklist

- [ ] Repo scanning blocks commits with high-entropy tokens
- [ ] Secrets live in vault/KMS with access policies
- [ ] Rotation playbook exists and was tested once
- [ ] CI uses OIDC or short-lived creds, not static keys in vars
- [ ] Break-glass procedure documented and rare

## Tips

Prefer separate secrets per env. Use namespacing (`prod/app/db`). Never log secret values — redact in structured logging. For local dev, use personal dev keys with minimal scope, not prod copies.
