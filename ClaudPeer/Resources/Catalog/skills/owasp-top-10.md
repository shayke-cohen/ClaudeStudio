# OWASP Top 10 (2021): Practical Mitigations

## When to Activate

Use during design review, threat modeling, code audit, or pre-release security pass for web apps and APIs.

## Process

1. **A01 Broken access control.** Enforce authorization on every route and object ID; deny by default; use server-side checks, not hidden UI. Test horizontal/vertical privilege moves with automated tests.
2. **A02 Cryptographic failures.** Use TLS 1.2+ everywhere; store passwords with **Argon2id** or **bcrypt**; use vetted libraries (**libsodium**, language crypto APIs). Rotate keys via KMS; never hardcode secrets.
3. **A03 Injection.** Parameterize SQL (`PreparedStatement`), use ORM bind parameters; sanitize/encode output contextually; validate with allowlists for commands/file paths.
4. **A04 Insecure design.** Threat-model flows; use secure defaults; separate admin surfaces; document abuse cases (signup, password reset, file upload).
5. **A05 Security misconfiguration.** Harden frameworks: disable debug, default accounts, directory listing; set secure headers (`Content-Security-Policy`, `Strict-Transport-Security`); minimal cloud IAM.
6. **A06 Vulnerable components.** SBOM + Dependabot/Snyk; patch criticals; pin versions in lockfiles.
7. **A07 Auth failures.** MFA where valuable; rate limit logins; secure session cookies (`HttpOnly`, `Secure`, `SameSite`); monitor credential stuffing.
8. **A08 Integrity failures.** Sign releases; verify dependency checksums; avoid unsafe deserialization (pickle, YAML `!!python`); use SLSA/supply-chain practices.
9. **A09 Logging/monitoring.** Log auth decisions and admin actions without storing secrets; centralize logs; alert on anomalies; retain for incident response.
10. **A10 SSRF.** Block internal/metadata URLs in user-supplied fetchers; resolve and validate hosts; network egress controls for workers.

## Checklist

- [ ] Authz matrix documented and tested
- [ ] Crypto and TLS configurations reviewed
- [ ] All inputs bound or validated
- [ ] Headers, CORS, and error pages reviewed
- [ ] Dependency and integrity controls in CI

## Tips

Map each finding to OWASP ASVS level targets for measurable coverage. Pair mitigations with regression tests (e.g., IDOR fuzz cases).
