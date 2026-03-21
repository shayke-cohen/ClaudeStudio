# Web Performance

## When to Activate

Use before launch, after major feature adds, or when **Core Web Vitals** regress in **CrUX** or **Search Console**. Apply when LCP, INP, or CLS scores slip or bundle size grows without budget.

## Process

1. **Measure real users**: Instrument **web-vitals** (`npm i web-vitals`) and send LCP, INP, CLS to analytics. Compare lab runs: `npx lighthouse https://example.com --view` and Chrome DevTools Performance panel.
2. **Critical path**: Inline critical CSS or use `media="print" onload` patterns sparingly; prefer `link rel="preload"` for hero fonts with `font-display: swap` or `optional`. Compress images (AVIF/WebP), set explicit `width`/`height` or aspect-ratio to reserve space.
3. **JavaScript budget**: Set targets (e.g. <170KB gzip initial). Use dynamic `import()` for routes and heavy widgets. Audit with `npx source-map-explorer dist/**/*.js` or **Bundle Analyzer** (webpack/vite).
4. **Preconnect/preload**: `link rel="preconnect"` to API and font origins; preload only above-the-fold assets to avoid bandwidth contention.
5. **Layout stability**: Reserve space for ads, embeds, and lazy images. Avoid inserting content above existing content without placeholders.
6. **Deploy cache**: Version hashed assets (`[name].[contenthash].js`); use `Cache-Control: immutable` for hashed files. Invalidate HTML or use short `max-age` on `index.html`. Document purge steps for CDN (Cloudflare, Fastly).

## Checklist

- [ ] RUM metrics collected (LCP, INP, CLS)
- [ ] Lighthouse run documented for key URLs
- [ ] Route-level code splitting enabled
- [ ] Images/fonts optimized; CLS risks mitigated
- [ ] CDN and browser caching strategy documented

## Tips

Use **Chrome DevTools** Coverage tab to find unused JS/CSS. Prefer **HTTP/2** or **HTTP/3** and avoid synchronously chained third-party scripts in `<head>`.
