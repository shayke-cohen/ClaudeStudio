# CSS Architecture at Scale

## When to Activate

When styles become unpredictable, specificity wars appear, or design tokens drift — make styling consistent and refactor-safe.

## Process

1. **Design tokens** — Centralize color, spacing, typography in CSS variables (`:root { --color-bg: #0b0d10; }`) or **Style Dictionary** output consumed by app and docs. Document dark mode overrides on `[data-theme="dark"]`.
2. **Limit specificity** — Avoid deep selectors (`div div .sidebar a`); prefer single class per **BEM** block (`card__title--large`) or **CSS Modules** (`import styles from './Card.module.css'`).
3. **Colocate styles** — Keep component styles beside components; expose only local class names. For **Tailwind**, agree on `@apply` sparingly inside small component wrappers.
4. **Theming** — One source of tokens; components consume variables, not raw hex scattered in files. Test contrast for both themes (**WCAG** contrast checker in CI if possible).
5. **Predictable globals** — Reset/normalize once; define base typography and link styles in a single layer. Document exceptions.
6. **Dead code removal** — Run **PurgeCSS** with Tailwind or periodic audits for unused module classes. Remove orphaned SCSS partials.
7. **Documentation** — Storybook or token site shows states: hover, focus-visible, disabled, loading.

## Checklist

- [ ] Tokens defined; components reference variables
- [ ] No deep selector chains; BEM or CSS Modules enforced
- [ ] Styles colocated with components
- [ ] Dark/light (or brand variants) tested
- [ ] Unused rules periodically purged

## Tips

Prefer `:focus-visible` over `:focus` for keyboard users. Use `prefers-reduced-motion` for animations. When mixing CSS-in-JS, ensure SSR-safe APIs and critical CSS strategy for performance.
