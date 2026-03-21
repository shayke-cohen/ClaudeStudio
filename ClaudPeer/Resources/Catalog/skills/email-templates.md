# Email Templates

## When to Activate

Use for transactional mail (auth, receipts, alerts) and marketing campaigns. Activate when building new templates, fixing rendering bugs, or improving deliverability and compliance (CAN-SPAM, GDPR marketing rules).

## Process

1. **Multipart MIME** — Send **text/plain** and **text/html** parts; plain text should mirror key actions and links. Test with `swaks` or your ESP’s preview.
2. **Layout for clients** — Use **table-based** layout for Outlook; inline **critical CSS** for Gmail limitations. Tools: **MJML** (`mjml input.mjml -o out.html`), **React Email** (`@react-email/components`), **Maizzle** (Tailwind-to-email builds).
3. **Dark mode** — Test `prefers-color-scheme` meta and background colors; avoid pure black/white only; specify `color-scheme` where supported.
4. **Compliance** — Include **List-Unsubscribe** headers and visible unsubscribe/manage-preferences links for marketing. Honest **From**/`Reply-To`; physical address where legally required.
5. **Links and tracking** — Use HTTPS; validate every URL; UTM params consistently. Avoid URL shorteners that hurt reputation.
6. **Deliverability** — Authenticate **SPF**, **DKIM**, **DMARC**. Warm new domains/IPs gradually; segment bounces; monitor spam placement (`Google Postmaster`, Microsoft SNDS).
7. **Pre-send testing** — Use Litmus or Email on Acid; check Apple Mail, Gmail, Outlook. Snapshot HTML in repo for diffs.

## Checklist

- [ ] HTML + text parts both present and aligned
- [ ] Tables/inline CSS validated across major clients
- [ ] Dark mode checked
- [ ] Unsubscribe/manage prefs for marketing
- [ ] SPF/DKIM/DMARC configured; links HTTPS
- [ ] Tested in rendering suite; metrics monitored

## Tips

Keep width ~600px; use system fonts fallbacks. Minify but keep readable source in git. For password resets, short-lived tokens and no PII in subject lines. Log bounces/complaints and auto-suppress addresses.
