# Infrastructure as Code

## When to Activate

When provisioning cloud resources, onboarding new environments, or replacing click-ops — make infra reviewable, repeatable, and drift-resistant.

## Process

1. **Terraform workflow** — `terraform fmt -recursive`, `terraform validate`, `terraform plan -out=tfplan` in CI; `terraform apply tfplan` after approval. Lock provider versions in `required_providers` and use `.terraform.lock.hcl`.
2. **Pulumi / CloudFormation** — Same discipline: preview diffs (`pulumi preview`, CloudFormation change sets) before apply; store state remotely with locking (S3 + DynamoDB for Terraform; Pulumi Service or self-hosted backend).
3. **Modularize** — Split **VPC**, **eks**, **data** modules to limit blast radius. Compose per env with small root stacks (`env/prod`, `env/stage`).
4. **Separate environments** — Distinct state files and accounts/subscriptions; never share prod state with dev. Use workspace or directory per env consistently.
5. **PR reviews** — Treat infra changes like app code: two eyes on plans, especially security groups, IAM, and public endpoints.
6. **Drift detection** — Schedule `terraform plan` (read-only) or **CloudFormation drift detection**; alert on non-empty diff. Remediate by re-applying or fixing manual changes.
7. **Secrets** — Reference **Vault**, **SSM Parameter Store**, or cloud secret managers; do not commit `.tfvars` with credentials.

## Checklist

- [ ] IaC in Git; plan/apply separated with approvals
- [ ] Providers and modules version-pinned
- [ ] Environments isolated (state, accounts, vars)
- [ ] Scheduled drift checks with alerts
- [ ] No plaintext secrets in repo or state (use encryption)

## Tips

Use `terraform import` cautiously with documentation. Tag all resources (`Environment`, `Owner`, `CostCenter`) for cost and ownership. Keep destroy workflows protected (manual confirm) to prevent accidents.
