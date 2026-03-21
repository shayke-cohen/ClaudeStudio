# Web Testing

## When to Activate

Use before shipping UI changes, cross-browser releases, or accessibility regressions—combining functional, visual, and a11y signals.

## Process

1. **Define environment** — Node version from `.nvmrc`, `PLAYWRIGHT_BROWSERS_PATH=0` for CI caches, base URL via env (`PLAYWRIGHT_BASE_URL`). Seed feature flags consistently.
2. **Cover navigation and forms** — Happy path plus validation errors. For API-backed views, assert loading/empty/error states, not only success.
3. **Accessibility alongside function** — Run `@axe-core/playwright` or Lighthouse CI on key routes. Check focus order, labels, and contrast—not only `getByRole`.
4. **Network mocking sparingly** — Prefer staging services or contract tests. Use `page.route` for flaky third parties only; document assumptions when stubbing.
5. **Parallel isolated sessions** — `test.describe.configure({ mode: 'parallel' })` with per-test storage state. Avoid shared auth cookies without reset.
6. **Visual checks** — Percy/Chromatic or Playwright `toHaveScreenshot` for components with designer-approved thresholds.

## Checklist

- [ ] Chromium + Firefox (+ WebKit if supported) for critical flows
- [ ] Keyboard-only path smoke-tested where applicable
- [ ] API errors surfaced to users tested
- [ ] Flakes tracked with traces (`trace: 'on-first-retry'`)
- [ ] Secrets never committed; `.env.test` gitignored

## Tips

Use `getByRole`/`getByLabel` over CSS. Stabilize animations (`prefers-reduced-motion` in tests). Keep tests under 60s each; split files by route. Run `pnpm exec playwright test --grep @smoke` locally before push.
