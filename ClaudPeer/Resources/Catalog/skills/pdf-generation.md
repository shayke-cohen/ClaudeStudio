# PDF Generation

## When to Activate

Use for invoices, reports, certificates, and printable exports. Choose tooling based on layout complexity: HTML/CSS engines for rich design; programmatic libraries for precise vector/text.

## Process

1. **Fonts** — Embed or subset fonts for correct rendering; verify licensing. **Puppeteer**/`playwright` PDF: load `@font-face` with `font-display: block`. **wkhtmltopdf** / **WeasyPrint**: embed fonts in CSS. **PDFKit**: register font files explicitly.
2. **Pagination** — Define `@page { size: A4; margin: 12mm; }`, `break-inside: avoid` on table rows/cards, repeating `thead` for tables. Test multi-page edge cases (footnotes, signatures).
3. **Headers and footers** — Use engine features (Puppeteer `headerTemplate`/`footerTemplate` with margins) or render in HTML with fixed positions—watch overlap with body content.
4. **Accessibility** — Prefer tagged PDFs: semantic HTML → engines that preserve structure (WeasyPrint aims better than naive print-to-PDF). Set document title, language, alt text for images where supported.
5. **Security** — Disable JavaScript in untrusted HTML; sanitize inputs to prevent SSRF when fetching assets. Password-protect if containing PII; avoid embedding secrets in metadata.
6. **Scale verification** — Load-test generation time and output size; stream responses; cap concurrent jobs. Compare file sizes across engines for the same template.

## Checklist

- [ ] Fonts embedded/subset; license OK
- [ ] Page breaks tested for tables and sections
- [ ] Headers/footers do not clip content
- [ ] Accessibility tags/title/lang addressed
- [ ] Untrusted HTML sanitized; outputs secured
- [ ] Performance and file size acceptable at peak

## Tips

Prototype in browser print preview before automating. For pixel-perfect vector charts, generate SVG then convert. Keep templates in git with snapshot PDFs in tests (`pdftotext` diff or visual thresholds).
