# Animation

## When to Activate

Use when adding motion to clarify hierarchy, feedback, or transitions—or when auditing janky interactions. Apply for onboarding, modals, page transitions, and micro-interactions.

## Process

1. **Purpose**: Classify motion as **orientation** (where content went), **feedback** (success/error), or **delight** (brand)—skip decoration that distracts from tasks.
2. **Reduced motion**: Respect `prefers-reduced-motion: reduce` with `@media (prefers-reduced-motion: reduce) { * { animation-duration: 0.01ms !important; ... } }` or feature-specific alternatives (instant state change, opacity only).
3. **Performant properties**: Animate `transform` and `opacity` only; avoid animating `width`, `height`, `top`, `left`, and `box-shadow` on large layers. Use `will-change` sparingly and remove after animation.
4. **Timing**: Standardize durations (e.g. 120ms tap, 200–300ms modal) and easing (`cubic-bezier(0.2, 0, 0, 1)`). Document tokens: `--motion-duration-short`, `--ease-standard`.
5. **Profiling**: Record **Chrome DevTools** Performance with 6× CPU throttle; check **Firefox Profiler** for long frames. On mobile, test mid-tier Android devices.
6. **Accessibility**: Ensure motion does not trigger vestibular issues; provide static equivalents when reduced motion is on.

## Checklist

- [ ] Each animation has a clear user-centered purpose
- [ ] `prefers-reduced-motion` handled
- [ ] Only transform/opacity animated on hot paths
- [ ] Durations/easing come from tokens
- [ ] Profiled on throttled CPU / real device

## Tips

Prefer **CSS** transitions for simple state; use **Web Animations API** or **Framer Motion** when sequencing. Avoid infinite looping animations in primary workflows.
