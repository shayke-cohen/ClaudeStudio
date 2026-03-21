# Browser Automation

## When to Activate

Use for E2E regression tests, RPA with governance, or UI verification when APIs are insufficient. Prefer stable, user-facing selectors and environments you control (staging, ephemeral previews).

## Process

1. **Resilient selectors** — Order of preference: `data-testid`, `role` + name, stable `aria-label`, text with regex—not CSS nth-child or auto-generated classes. In **Playwright**: `page.getByRole('button', { name: 'Submit' })`. **Cypress**: `cy.findByRole`. **Selenium 4**: relative locators + explicit waits.
2. **Auto-waits** — Replace `sleep()` with framework waits: Playwright’s auto-waiting, Cypress assertions, Selenium `WebDriverWait` + `expected_conditions`. Wait for network idle only when needed to avoid flakiness.
3. **Traces on failure** — Enable Playwright trace/video on retry (`npx playwright test --trace on-first-retry`), Cypress screenshots + video, Selenium remote logs. Attach to CI artifacts.
4. **Parameterize environments** — `BASE_URL`, auth secrets from CI vars; never hardcode prod credentials. Use `.env.test` excluded from git.
5. **Isolate sessions** — Clear storage between tests or use incognito contexts; parallelize with sharding: `npx playwright test --shard=1/4`.
6. **Flaky test policy** — Quarantine with ticket, root-cause (timing, animation, data race), fix or delete—do not accumulate `@flaky` forever.

## Checklist

- [ ] Selectors prioritize test ids / roles
- [ ] Waits are event-driven, not fixed sleeps
- [ ] CI captures trace/video/logs on failure
- [ ] Environments and secrets externalized
- [ ] Flakes tracked with owners and deadlines

## Tips

Stub third-party scripts in test. Use API setup for data (`request.newContext` in Playwright) faster than UI. Run smoke suite on PR; full suite nightly. Document local run: `npx playwright install` and `npx cypress open`.
