# PWA Development

## When to Activate

Use when shipping an installable web app, offline-first experiences, or update strategies for field workers and flaky networks. Apply when adding a service worker or Web App Manifest.

## Process

1. **HTTPS only**: Service workers require secure contexts. Use **Let’s Encrypt** or platform TLS (Vercel, Netlify, Cloudflare) in all environments.
2. **Manifest**: Ship `manifest.webmanifest` with `name`, `short_name`, `icons` (192/512), `start_url`, `display`, and `theme_color`. Validate with Chrome Application panel.
3. **Service worker versioning**: Bump cache name on deploy (`const CACHE = 'app-v3'`). In `activate`, `caches.keys()` and delete old caches. Never cache `index.html` forever without a network-first or stale-while-revalidate strategy.
4. **Offline fallbacks**: Precache shell assets; use **Workbox** (`npm i workbox-webpack-plugin` or `vite-plugin-pwa`) for routing recipes. Provide an offline page for navigation requests.
5. **Permissions**: Request **notifications**, **geolocation**, or **clipboard** only immediately after a user gesture and with clear value copy. Check `Notification.permission` before prompting.
6. **Install prompt**: Listen for `beforeinstallprompt`, defer `prompt()` until user clicks “Install,” and log outcomes for analytics. Test in Chrome and Edge; Safari has separate Add to Home Screen flow.
7. **Storage**: Monitor `navigator.storage.estimate()`. Prune old caches and IndexedDB stores; handle **QuotaExceededError** with user-visible cleanup paths.

## Checklist

- [ ] HTTPS everywhere
- [ ] Manifest complete and linked
- [ ] SW updates evict old caches safely
- [ ] Offline shell or fallback page tested
- [ ] Permission prompts are contextual
- [ ] Storage usage monitored

## Tips

Run `npx lighthouse https://yoursite --only-categories=pwa`. Use **Workbox** recipes: `NetworkFirst` for API, `StaleWhileRevalidate` for static assets.
