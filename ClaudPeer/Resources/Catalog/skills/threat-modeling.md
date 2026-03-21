# Threat Modeling: STRIDE-Style Security Prioritization

## When to Activate

Use at architecture kickoff, before major features, or when trust boundaries move (new APIs, partners, AI agents, or data stores).

## Process

1. **Diagram trust boundaries.** Draw data flows: users, browsers, mobile apps, APIs, databases, third parties. Mark authentication, authorization, and encryption transitions.
2. **Identify assets and adversaries.** List data worth stealing (PII, tokens, keys) and actors (anonymous users, compromised insiders, supply chain). Note entry points (HTTP, WebSocket, admin tools).
3. **STRIDE per element.** Spoofing, Tampering, Repudiation, Information disclosure, Denial of service, Elevation of privilege—for each flow/component list realistic attacks.
4. **Score risks.** Use **DREAD** (Damage, Reproducibility, Exploitability, Affected users, Discoverability) or a simple impact × likelihood matrix. Document assumptions (e.g., “corp network is trusted”).
5. **Attack trees.** For crown-jewel goals (admin takeover, data exfil), decompose required steps; find cheapest mitigations that cut branches (MFA, network policy, input validation).
6. **Owners and mitigations.** Each risk gets owner, target date, and residual risk. Revisit when schemas, auth, or deployment topology changes.

## Checklist

- [ ] Current architecture diagram + trust boundaries
- [ ] Asset inventory aligned to data classes
- [ ] STRIDE worksheet completed for top flows
- [ ] Prioritized backlog of mitigations with owners
- [ ] Assumptions and open questions logged

## Tips

Keep models living in-repo (`docs/threat-model.md` or diagrams-as-code). Review deltas in PRs that touch auth, parsers, or network egress.
