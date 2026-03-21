# Penetration Testing: Goal-Oriented Offensive Testing

## When to Activate

Use for pre-launch hardening, annual assessments, or after major architecture changes—when you need independent validation within agreed rules.

## Process

1. **Define scope and RoE.** List in-scope hosts, APIs, accounts, and forbidden actions (DoS, social engineering, prod data deletion). Get written authorization and emergency contacts.
2. **Recon and mapping.** Use **Nmap** (`nmap -sV -sC target`) for surface discovery; **Burp Suite** or **OWASP ZAP** for HTTP/API mapping; document unauthenticated vs authenticated surfaces separately.
3. **High-impact chains.** Prioritize credential theft (session fixation, OAuth misconfig), privilege escalation (IDOR, mass assignment), and data exfil (export endpoints, GraphQL introspection). Avoid low-noise spray unless scoped.
4. **Record repro steps.** For each finding: prerequisites, request/response samples (redacted), screenshots, and impact narrative. Use consistent IDs (PEN-001).
5. **Severity rubric.** Map to CVSS or a simple critical/high/medium/low scale with business context (regulated data = bump). Separate “informational” hygiene issues.
6. **Fix verification.** After patches, retest the exact chain; run regression scripts in Burp/ZAP; confirm logging/alerts fire on exploit attempts.

## Checklist

- [ ] Signed scope + out-of-scope list
- [ ] Test accounts and API keys provisioned with expiry
- [ ] Raw traffic logs stored securely; PII minimized
- [ ] Report with severity, repro, and remediation hints
- [ ] Retest tickets closed with evidence

## Tips

Automate baseline scans in CI (`zap-baseline.py`) but treat pen test as human-driven chain finding. Pair with developers during debrief to estimate fix cost accurately.
