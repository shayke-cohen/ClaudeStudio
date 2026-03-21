# Vue Patterns (Composition API & SFCs)

## When to Activate

When scaffolding Vue 3 apps, refactoring Options API, or chasing reactivity bugs — favor clarity and shallow reactive graphs.

## Process

1. **State near usage** — Use `ref`/`reactive` inside composables scoped to a feature (`useCart.ts`) instead of a global store for everything.
2. **Extract composables** — Share logic with functions returning refs/computed/methods; name with `useX` prefix. Keeps Single File Components (`.vue`) thin.
3. **Dumb components** — Prefer props down, `emit` up. Avoid child mutating parent objects unless intentional (`v-model` pattern with `defineModel` in Vue 3.4+).
4. **Type props and emits** — `<script setup lang="ts">` with `defineProps<{ id: string; count?: number }>()` and `defineEmits<{ (e: 'save', v: string): void }>()` for compile-time safety.
5. **Avoid deep reactivity cost** — Large readonly lists: `shallowRef` or `markRaw` for third-party class instances. Do not wrap huge JSON in `reactive` if you only replace wholesale.
6. **Watch carefully** — `watch`/`watchEffect` with explicit sources; flush timing (`flush: 'post'`) when DOM reads needed. Debounce expensive watchers.
7. **Async setup** — Use `defineAsyncComponent` or route-level code splitting; handle loading/error states in parent.

## Checklist

- [ ] Composables encapsulate reusable logic
- [ ] Presentational components are prop-driven
- [ ] Props/emits typed in `<script setup>`
- [ ] Heavy objects use shallow/markRaw appropriately
- [ ] Watchers scoped with clear dependencies

## Tips

Prefer `computed` for derived values instead of manual sync in `watch`. Use **Pinia** for cross-route shared state with devtools support. Test composables in isolation with **Vitest** calling the function directly.
