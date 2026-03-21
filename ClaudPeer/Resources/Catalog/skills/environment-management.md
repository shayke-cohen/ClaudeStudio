# Environment Management (Dev / Stage / Prod)

## When to Activate

When onboarding teams, debugging env-only bugs, or tightening release discipline — reduce “snowflake” servers and implicit configuration.

## Process

1. **Parity goals** — Same container images, config shape, and feature flags schema across envs; scale and data differ. Document intentional differences (e.g. rate limits relaxed in dev).
2. **Configuration discipline** — Twelve-factor style: store config in env vars or parameter store; never bake secrets into images. Use `.env.example` with dummy values.
3. **Secrets & rotation** — Document who owns rotation, frequency, and break-glass access. Automate rotation where APIs allow (**AWS Secrets Manager** rotation Lambda).
4. **Data policies** — Anonymize prod dumps for stage; forbid real PII on laptops. Define retention and GDPR deletion paths per env.
5. **Migrations** — Run forward migrations in stage before prod; test rollback strategy. Keep migration jobs idempotent and logged per env.
6. **Provisioning** — Automate with **Terraform**, **Ansible**, or golden AMIs; avoid manual firewall tweaks. **Terraform workspace** or directory per env with locked state.
7. **Validation** — Smoke test after provision: health checks, sample CRUD, background workers consuming queues.

## Checklist

- [ ] Parity documented; exceptions justified
- [ ] Secrets sourced from vault/store; rotation known
- [ ] Data handling policy explicit per environment
- [ ] Migrations tested on staging first
- [ ] Provisioning automated and reproducible

## Tips

Name resources with `env` labels for cost allocation. Use feature flags to test prod code paths in staging without copying prod data. Periodically rebuild lower envs from IaC to kill drift.
