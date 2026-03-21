# End-to-End Testing

## When to Activate

Use for critical user journeys across UI, backend, and identity—after unit/integration coverage, not as the only safety net.

## Process

1. **Pick critical paths** — Login, pay, sync, or primary workflow only. Avoid duplicating every unit case at E2E speed.
2. **Stable selectors** — Prefer accessibility identifiers (`accessibilityIdentifier` in SwiftUI), `data-testid` on web, not CSS nth-child. Document selector policy in repo.
3. **State waits** — Replace fixed sleeps with expectations on elements, network idle, or API stubs completing. Use framework timeouts (`XCTExpectations`, Playwright `expect`).
4. **Isolated accounts** — Dedicated test users, disposable emails, feature flags off defaults. Reset state via API or seed scripts before each run.
5. **Artifacts on failure** — Save screenshots, video, HAR, and console logs. Upload in CI (`actions/upload-artifact`).
6. **Lean suite** — Target <30 minutes mainline; shard parallel jobs by feature area.

## Checklist

- [ ] Journeys map to business risk, not coverage vanity
- [ ] Selectors stable across theme changes
- [ ] Tests self-contained with cleanup
- [ ] Failures diagnosable from artifacts
- [ ] Runtime monitored; slow tests refactored or demoted

## Tips

Use Maestro YAML for mobile flows, Playwright for web. Mock payment providers with official sandboxes. Quarantine flaky tests behind a ticket until fixed—do not silence.
