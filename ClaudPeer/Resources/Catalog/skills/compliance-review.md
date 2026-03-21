# Compliance Review: Controls, Evidence, and Audit Readiness

## When to Activate

Use when preparing for SOC 2, ISO 27001, GDPR DPIAs, HIPAA BAA work, PCI DSS scope, or translating legal terms into engineering tasks.

## Process

1. **Translate requirements to controls.** Break policies into testable statements (e.g., “production access requires MFA and ticket reference”). Map each to owners in Security, Eng, and IT.
2. **Collect evidence.** Store screenshots, Terraform plans, access reports, pen test summaries, and training records in a controlled repository or GRC tool with timestamps and version tags.
3. **Gap analysis.** For each control: pass/partial/fail; record risk, compensating controls, and remediation ETA. Tie gaps to incidents or near-misses when relevant.
4. **Link controls to real risks.** Avoid checkbox theater—document which threats (credential theft, data loss) each control mitigates and residual risk after mitigation.
5. **Auditor narrative.** Produce architecture diagrams, data flow maps, and subprocessors list. Prepare walkthrough scripts for sample selection (tickets, access reviews).
6. **Framework specifics.** **GDPR:** lawful basis, retention, DSR runbooks. **HIPAA:** PHI minimization, BAAs, audit logs. **PCI:** scope reduction, segmentation evidence. **SOC 2:** CC policies mapped to criteria.

## Checklist

- [ ] Control library with owners and test frequency
- [ ] Evidence folder structure + retention policy
- [ ] Open gaps tracked with dates
- [ ] Diagrams current for prod and data stores
- [ ] Subprocessors and DPIA artifacts current

## Tips

Version-control policy PDFs alongside engineering controls. Automate evidence where possible (IAM export cron, Terraform drift detection). Rehearse the story with an internal “mock audit” first.
