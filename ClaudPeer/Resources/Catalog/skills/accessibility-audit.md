# Accessibility Audit (WCAG 2.1 AA)

## When to Activate

Before release, after navigation or form changes, when supporting new locales/themes, or when users report keyboard or screen reader issues.

## Process

1. **Keyboard first** — Tab through all interactive elements; verify visible focus, no traps, and that custom widgets respond to Enter/Space/Escape. **WCAG 2.1.1** Keyboard, **2.4.3** Focus Order, **2.4.7** Focus Visible.
2. **Semantics** — Use native elements where possible; for custom controls set **roles**, **states** (`aria-expanded`), and **names** (`aria-label` or associated `<label>`). **4.1.2** Name, Role, Value.
3. **Live regions** — Announce async updates with `aria-live` appropriately (`polite` vs `assertive`). **4.1.3** Status Messages.
4. **Contrast & scaling** — Check text/graphics contrast (**1.4.3** Contrast Minimum, **1.4.11** Non-text Contrast). Zoom to 200% without loss of content (**1.4.4** Resize text).
5. **Automated scan** — Run **axe DevTools**, **Lighthouse** accessibility, or **Pa11y** (`pa11y https://localhost:3000`) in CI for quick catches.
6. **Screen reader spot-check** — VoiceOver on macOS (`Cmd+F5`), NVDA on Windows, or TalkBack on Android on primary flows.
7. **Document findings** — Map each issue to WCAG criterion and severity; fix in code, not with `aria-hidden` hacks that hide real content.

## Checklist

- [ ] Full keyboard path with visible focus
- [ ] Labels, headings hierarchy, and landmarks sane
- [ ] Dynamic content uses live regions where needed
- [ ] Contrast and zoom verified on real components
- [ ] Automated + at least one manual screen reader pass

## Tips

Prefer fixing order in the DOM over positive `tabindex`. Test with real forms and error messages — **3.3.1** Error Identification, **3.3.3** Error Suggestion. Pair visual regression with a11y to catch focus ring removal.
