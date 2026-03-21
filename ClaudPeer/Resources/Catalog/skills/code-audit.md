# Code Audit: Dangerous Patterns Line by Line

## When to Activate

Use before merge of security-sensitive code, on legacy modules handling auth/parsing/files, or when preparing for external review.

## Process

1. **Injection surfaces.** Search for raw SQL string concat, `exec`, `eval`, shell calls with user input. Require parameterized queries and subprocess with argument lists (`subprocess.run([...])` not `shell=True`).
2. **Deserialization.** Flag YAML/XML parsers with unsafe types, Java `ObjectInputStream`, Python `pickle.loads` on untrusted bytes. Prefer JSON + schema validation.
3. **Crypto.** Ban MD5/SHA1 for passwords; look for hardcoded keys/IVs, ECB mode, static salts. Enforce authenticated encryption (AES-GCM) via vetted libs.
4. **Authz gaps.** Trace every handler: does it check resource ownership? grep for `isAdmin` only at UI layer. Add tests for cross-tenant access.
5. **Secrets and logs.** Scan for API keys with **git grep** patterns; ensure structured logging redacts tokens (`Authorization`, cookies). Verify error messages don’t leak stack traces to clients in prod.
6. **File/path operations.** Wrap `Path` joins; reject `..` traversal; validate MIME vs extension on uploads. For HTTP clients, block SSRF: no raw user URLs to internal IPs.
7. **Pair with tests.** Each confirmed issue gets a failing test first (where safe), then fix—especially for regressions in parsers and authz.

## Checklist

- [ ] Injection/deser/search paths reviewed
- [ ] Crypto usage vetted against standards
- [ ] Authn/authz checked per endpoint
- [ ] Logging and error paths reviewed for leakage
- [ ] File/network egress reviewed for SSRF/traversal

## Tips

Use IDE “find references” from public controllers downward. For large repos, prioritize modules sorted by data sensitivity and external exposure.
