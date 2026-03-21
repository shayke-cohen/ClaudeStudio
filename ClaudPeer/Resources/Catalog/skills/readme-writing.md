# README Writing

## When to Activate

Use for every repo, library, or service that others will clone, deploy, or contribute to. Refresh when onboarding feedback repeats the same questions or when setup steps change.

## Process

1. **Above the fold** — First paragraph: **what it is**, **who it is for**, and **how to run it locally** in under 30 seconds of reading.
2. **Prerequisites** — Exact versions: Node 20.x, Xcode 15+, Docker 24+, etc. Link to `asdf`, `mise`, or `nvm` if the team standardizes on them.
3. **Environment variables** — Table: name, purpose, required/optional, example (no real secrets). Point to `.env.example`; document how to obtain API keys safely.
4. **Commands** — Copy-paste blocks: `git clone`, `pnpm install`, `pnpm dev`, `docker compose up`, `make test`. Order them in the sequence a new hire follows.
5. **Link deeper docs** — Architecture, ADRs, API docs, runbooks—one line each with stable paths.
6. **Troubleshooting** — Top 3–5 “footguns” (port in use, wrong Ruby version, Apple Silicon quirks) with symptoms and fixes.
7. **Badges** — Only if maintained: CI status from GitHub Actions, codecov, etc. Remove or fix broken badges immediately.

## Checklist

- [ ] What / who / how to run is visible without scrolling on GitHub
- [ ] Prereqs and env vars are explicit with `.env.example`
- [ ] Install, run, test commands are copy-pasteable
- [ ] Links to deeper docs and support channel
- [ ] Troubleshooting covers common local failures
- [ ] Badges reflect current CI

## Tips

Include a **Contributing** section or link to `CONTRIBUTING.md`. For apps, add screenshots or a 10-second screen recording GIF. Run through the README on a clean machine (or CI job `README smoke`) quarterly so drift is caught early.
