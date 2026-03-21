# Web Scraping

## When to Activate

Use when extracting public web data for research, monitoring, or migration—and **only** when legal and policy constraints allow. Prefer official APIs, exports, or data partnerships first.

## Process

1. **Legal and policy** — Read `robots.txt`, site Terms of Service, and copyright. For regulated data (PII), involve legal/compliance before scraping.
2. **Prefer APIs** — Use vendor REST/GraphQL feeds, RSS, or bulk dumps. Scraping is a fallback when API terms prohibit your use case, not when APIs exist and suffice.
3. **Throttle and backoff** — Limit concurrency (e.g., 1–2 req/s per host), honor `Crawl-delay`, use exponential backoff on `429`/`5xx`. Set a identifiable `User-Agent` with contact info.
4. **Parse defensively** — HTML changes; use **Cheerio** (Node) or **Beautiful Soup** (Python) with resilient selectors; avoid brittle XPath tied to minified class names. For SPAs, evaluate **Puppeteer**/`playwright` only when necessary—higher cost and ToS risk.
5. **Encoding and pagination** — Detect charset (`charset` meta, `response.encoding` in `requests`); follow `rel=next` or API-style page params; cap max pages per run.
6. **Store minimal data** — Keep only fields you need; redact secrets from logs. Snapshot raw HTML only when retention policy allows.
7. **Monitor breakage** — Alert when parse success rate drops; version your extractors.

## Checklist

- [ ] robots.txt / ToS reviewed; API path exhausted
- [ ] Rate limits, User-Agent, and backoff implemented
- [ ] Parser tolerates minor DOM changes
- [ ] Pagination and encoding handled with caps
- [ ] Data minimization and monitoring in place

## Tips

Cache with `ETag`/`If-Modified-Since` when servers support it. Log HTTP status histograms. For large jobs, distribute politely across IPs only if permitted—avoid circumventing blocks unethically.
