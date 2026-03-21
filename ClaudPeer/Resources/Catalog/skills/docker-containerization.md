# Docker Containerization

## When to Activate

Apply when onboarding developers, packaging services for Kubernetes or CI, or eliminating “works on my machine” drift. Images should be minimal, reproducible, and safe to run in shared clusters.

## Process

1. **Multi-stage builds** — Use a `builder` stage with compilers and dev dependencies, then copy artifacts into a slim runtime image. Example pattern: `FROM node:20-bookworm AS build` … `FROM node:20-bookworm-slim AS runtime` with only `dist/` and production `node_modules/`.
2. **Pin base images** — Prefer digest pins: `FROM node:20-bookworm-slim@sha256:…` alongside a human-readable tag in comments. Rebuild on a cadence for CVE patches (`docker pull`, CI rebuild).
3. **Non-root execution** — `RUN useradd -r -u 10001 appuser && chown -R appuser /app`, then `USER appuser`. Ensure writable dirs (`/tmp`, app data) have correct ownership; never run as root in Kubernetes unless unavoidable and documented.
4. **Layer caching** — Order Dockerfile from least to most frequently changing: base, OS packages, dependency manifests (`package.json`, lockfile), install deps, then copy source. Single `RUN` for `apt-get update && apt-get install -y … && rm -rf /var/lib/apt/lists/*`.
5. **Healthchecks** — For daemons: `HEALTHCHECK --interval=30s --timeout=3s CMD curl -fsS http://127.0.0.1:8080/health || exit 1` (install minimal curl/wget or use a tiny static binary).
6. **Document build args and env** — Use `ARG` for versions; `ENV` for runtime tuning. Ship `.env.example` and README snippets: `docker build -t myapp:1.0 .`, `docker run -e NODE_ENV=production -p 8080:8080 myapp:1.0`.
7. **Scan in CI** — Run **Trivy** `trivy image myapp:1.0` or **Grype**; fail on critical CVEs unless waived with owner and expiry.

## Checklist

- [ ] Multi-stage build; build tools absent from final image
- [ ] Base image tag + digest policy documented
- [ ] Process runs as non-root with correct filesystem perms
- [ ] HEALTHCHECK defined for long-running services
- [ ] Build args, env vars, exposed ports documented
- [ ] Image scanning integrated into pipeline

## Tips

Add a **`.dockerignore`** excluding `.git`, `node_modules`, secrets, and local artifacts. Use `CMD`/`ENTRYPOINT` exec form. For local dev, **Docker Compose** can bind-mount source while production stays immutable image-only.
