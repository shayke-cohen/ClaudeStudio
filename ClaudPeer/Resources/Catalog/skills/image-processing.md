# Image Processing

## When to Activate

Use when building uploads, thumbnails, CDNs, print pipelines, or ML vision preprocessing. Activate when users report blurry images, huge payloads, wrong colors, or EXIF leaks.

## Process

1. **Choose formats** — **Lossless** (PNG, WebP lossless) for UI assets and transparency; **lossy** (JPEG, WebP, AVIF) for photos—tune quality with visual review, not only PSNR.
2. **EXIF handling** — Strip location and device metadata for privacy unless required; preserve orientation via transform rather than relying on clients. **Sharp** (`sharp().rotate()`), **ImageMagick** (`magick in.jpg -auto-orient -strip out.jpg`), **Pillow** (`ImageOps.exif_transpose`, `getexif()`).
3. **Responsive variants** — Generate `srcset` widths (e.g., 480/800/1200); use object-fit-aware crops for faces when needed (ML-assisted crop tools).
4. **Color profiles** — Convert to sRGB for web unless print pipeline needs CMYK; embed profile when necessary. Validate with `exiftool` or ImageMagick `identify -verbose`.
5. **ML and vision safety** — Resize with consistent aspect; document mean/std for model cards; avoid leaking PII in training crops; log transforms for reproducibility.
6. **Batch performance** — Benchmark: `sharp` often fastest on Node; **ImageMagick** `mogrify` for shells; **Pillow** with `Image.MAX_IMAGE_PIXELS` guard against decompression bombs. Parallelize with backpressure.

## Checklist

- [ ] Format and quality chosen per use case
- [ ] EXIF stripped or justified; orientation correct
- [ ] Multiple widths/sizes for responsive delivery
- [ ] Color profile intentional (usually sRGB web)
- [ ] Batch jobs bounded and benchmarked

## Tips

Use content-hash filenames for CDN caching (`contenthash.webp`). Validate max upload bytes and dimensions before decode. For animated GIFs, prefer video (MP4/WebM) for size.
