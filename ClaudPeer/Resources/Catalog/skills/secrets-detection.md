# Secrets Detection: Stop Credential Leaks Early

## When to Activate

Use when bootstrapping repos, after incidents, or tightening CI—anywhere tokens, keys, or `.env` files might enter git history or logs.

## Process

1. **Pre-commit scanning.** Run **Gitleaks** `gitleaks protect --staged` or **TruffleHog** `trufflehog git file://. --since-commit HEAD` in a hook; block commits on verified secrets.
2. **CI scanning.** Add a job scanning full history on main: `gitleaks detect --source . --verbose`. On GitHub, enable **Secret scanning** and push protection for org repos.
3. **Rotate immediately.** If a secret hits a remote, assume compromise: revoke keys in provider consoles, reissue tokens, and invalidate sessions—don’t rely on `git revert` alone.
4. **Reduce false positives.** Maintain `.gitleaks.toml` or TruffleHog exclude paths for fixtures; use allowlists with narrow regex and comments explaining why.
5. **Audit build logs and crashes.** Strip env dumps from CI output; configure crash SDKs to scrub PII; verify Fastlane/Xcode logs don’t echo signing passwords.
6. **.env hygiene.** Keep `.env*` in `.gitignore`; provide `.env.example` without real values; load secrets from CI secret stores at runtime only.

## Checklist

- [ ] Pre-commit + CI secret scanners enabled
- [ ] Push protection / org policies configured
- [ ] Rotation runbook tested for top secret types
- [ ] Allowlists documented and minimal
- [ ] Logs and crash pipelines reviewed for leakage

## Tips

Use `git filter-repo` or BFG only with security team guidance—prefer rotation over history rewrite when feasible. Educate contributors: paste redacted snippets in tickets.
