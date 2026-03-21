# Design System

## When to Activate

Use when multiple teams ship UI that drifts visually or behaviorally, or when onboarding designers and engineers to shared tokens and components. Apply at system creation, major rebrand, or governance gaps.

## Process

1. **Codify tokens**: Define color, type, space, radius, elevation, and motion in **Style Dictionary**, **Tokens Studio**, or CSS variables. Publish to npm or sync to Figma variables for single source of truth.
2. **Component library**: Build primitives (Button, Input) before composites (DatePicker). Document props, states, and anatomy diagrams. Host docs in **Storybook** with design links.
3. **Contribution rules**: Require RFC or ADR for new patterns; use PR templates with visual diff screenshots and a11y checklist. Enforce lint (ESLint, Stylelint) for token usage only.
4. **Usage guidance**: For each component, add **Do / Don’t** examples (correct hierarchy vs misleading colors). Link to product copy and iconography rules.
5. **Deprecation**: Announce deprecations in release notes, provide migration snippets, set removal dates, and ship codemods or search queries for old import paths.
6. **Adoption**: Track npm downloads, Storybook story usage, or design file component instances. Survey teams quarterly for missing tokens.
7. **Quality**: Run **axe** on stories; test light/dark/high-contrast themes; snapshot critical components in **Chromatic** or **Percy**.

## Checklist

- [ ] Tokens versioned and consumed by code and design
- [ ] Components documented with Do/Don’t
- [ ] Contribution and review process documented
- [ ] Deprecations include migration path and timeline
- [ ] Theming and a11y tested in CI

## Tips

Align naming: `color.action.primary.default` beats `blue-500`. Prefer **semantic tokens** over raw palette in application code.
