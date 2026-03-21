# Responsive Design

## When to Activate

Use when designing or implementing layouts for web or hybrid apps that must work across viewport sizes, pointer vs touch, and assistive technologies. Apply before shipping new screens, when audits show overflow or tiny tap targets, or when supporting foldables and notches.

## Process

1. **Start mobile-first**: Design and implement the narrowest breakpoint first, then add `min-width` media queries (CSS) or responsive modifiers (Tailwind: `sm:`, `md:`). Avoid desktop-first shrink-down, which hides overflow and touch issues until late.
2. **Touch targets**: Aim for at least 44×44 pt (Apple HIG) / 48×48 dp (Material) for interactive elements. Increase hit slop with padding, not only larger visuals. Space adjacent controls to prevent mis-taps.
3. **Fluid type and spacing**: Use `clamp(min, preferred, max)` for font-size and spacing (e.g. `clamp(1rem, 2.5vw, 1.25rem)`). Pair with `rem`/`em` for accessibility scaling.
4. **Safe areas**: Apply `env(safe-area-inset-*)` padding on fixed headers, full-bleed media, and bottom nav. Test in Safari iOS and Android Chrome with gesture bars.
5. **Keyboard overlap**: On mobile web, listen for Visual Viewport API or use `interactive-widget=resizes-content` in viewport meta where appropriate. Ensure focused inputs scroll into view and CTAs remain reachable.
6. **Reading order**: Structure DOM in semantic order; use CSS Grid/Flex order sparingly. Verify with screen reader linear navigation and tab order (`Tab` / `Shift+Tab`).
7. **Low-end performance**: Prefer CSS animations on `transform`/`opacity`, lazy-load below-fold images (`loading="lazy"`), avoid huge box shadows and expensive filters on scroll containers.

## Checklist

- [ ] Narrowest breakpoint designed and tested first
- [ ] Touch targets ≥44pt with adequate spacing
- [ ] Typography/spacing use `clamp` or equivalent fluid scales
- [ ] Safe-area insets applied to fixed UI
- [ ] Forms usable with on-screen keyboard
- [ ] DOM order matches intended reading order
- [ ] No critical jank on throttled CPU in DevTools

## Tips

Test real devices and **Chrome DevTools** device mode with CPU throttling. Use **Firefox Responsive Design Mode** for `prefers-reduced-motion` and zoom. Document breakpoints in tokens (e.g. `--bp-md: 48rem`) so teams align on when layouts shift.
