# Visual Regression Testing

## When to Activate

After UI refactors, design system updates, or any change that could alter layout, theming, or components shared across many screens.

## Process

1. **Stabilize renders** — Stub network and clock; hide or freeze animations (`prefers-reduced-motion`, CSS). Replace dynamic timestamps and random avatars with fixed fixtures.
2. **Fix viewport and theme** — Capture at standard breakpoints (e.g. 1280×720, 375×812). Run separate baselines for light/dark if both ship.
3. **Choose scope** — Full-page for critical flows; **component-level** snapshots for design systems. **Playwright**: `await page.screenshot({ path: 'snap.png', fullPage: true })`.
4. **Integrate a diff service** — **Percy** (`percy exec -- playwright test`) or **Chromatic** for Storybook compare pixel or perceptual diffs; review only meaningful deltas.
5. **Review intentionally** — Approve new baselines in the diff UI with PR comments explaining why the visual change is correct.
6. **Pair with a11y** — Run **axe-core** or Lighthouse on the same build; visual passes should not hide missing focus rings or contrast failures.

## Checklist

- [ ] Fonts loaded deterministically (subset or wait for `document.fonts.ready`)
- [ ] Animations/time/randomness controlled
- [ ] Viewport, theme, and locale fixed per snapshot
- [ ] Intentional diffs approved and documented
- [ ] Scoped snapshots where full-page is noisy

## Tips

Mask volatile regions (ads, maps) in Percy/Chromatic if needed. Keep snapshot count small to avoid review fatigue. Rebaseline after dependency upgrades that affect rendering engines.
