# Component Design

## When to Activate

Use when building or refactoring reusable UI primitives (buttons, inputs, cards, dialogs) in React, Vue, Svelte, or design-system wrappers. Apply before publishing a component to a shared library or when APIs grow inconsistent across products.

## Process

1. **Define a minimal public API**: Expose `variant`, `size`, `disabled`, `loading`, and `error` (or equivalent) as explicit props—not buried CSS classes from consumers. Prefer union types (`variant: 'primary' | 'secondary'`) over free-form strings.
2. **States and composition**: Map empty, loading, error, and success to visible affordances and `aria-*` attributes. For loading, use `aria-busy="true"` and preserve focus management in modals.
3. **Documentation**: Ship live examples (Storybook, Ladle, or Docz) with copy-paste snippets, prop tables, and accessibility notes. Document keyboard interaction and focus order.
4. **Encapsulation**: Avoid requiring consumers to style internal DOM nodes. Use slots/render props for extension points. Forward refs only where needed for focus or measurements.
5. **Tokens**: Consume design tokens for color, radius, spacing, and motion—never hard-code hex values in the component source.
6. **Versioning**: Treat prop renames and default behavior changes as breaking; document in CHANGELOG and provide codemods or deprecation warnings one major version when possible.

## Checklist

- [ ] Props cover variant, size, disabled, loading, error states
- [ ] Examples and a11y notes exist in docs
- [ ] No leaked internal selectors required for styling
- [ ] Tokens used for visual properties
- [ ] Breaking changes versioned and communicated

## Tips

Run **axe DevTools** or **Storybook a11y** addon on each story. Prefer **semantic HTML** (`button`, `a`, `label`) and test with keyboard-only navigation before merging.
