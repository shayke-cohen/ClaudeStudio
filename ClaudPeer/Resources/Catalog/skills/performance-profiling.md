# Performance Profiling

## When to Activate

Use when latency, CPU, memory, or battery regress—after measuring, not before guessing. Applies to macOS/iOS apps, Node/Bun services, and data pipelines.

## Process

1. **Baseline** — Capture p50/p95 latency under representative load (`hey`, `k6`, `wrk`). Record CPU%, RSS, and disk I/O. Store results in the PR or perf doc.
2. **Reproduce in profile** — macOS/iOS: Xcode Instruments (Time Profiler, Allocations, SwiftUI). CLI services: `node --cpu-prof`, `clinic doctor`, or `sample <pid>`. Enable debug symbols for readable stacks.
3. **Find dominant cost** — Sort by self time; ignore micro-optimizations until hot frames exceed ~5% of samples. Check lock contention and async queue depth.
4. **Fix and re-measure** — Apply one change; compare baselines. Watch for memory leaks (`leaks`, heap snapshots) after caching changes.
5. **Guardrails** — Add micro-benchmarks (`swift package benchmark`, `vitest bench`) or perf tests in CI with loose thresholds. Document known hotspots.

## Checklist

- [ ] Baseline metrics recorded before changes
- [ ] Profiler shows hotspot evidence, not intuition
- [ ] After fix, p95 improved or memory flat
- [ ] Regressions detectable in CI or manual checklist
- [ ] Tradeoffs noted (cache size vs freshness)

## Tips

Warm caches before benchmarking. Test release builds for Swift; debug can mislead. For IO-bound work, measure concurrency limits separately from CPU. Avoid optimizing cold start unless it is the SLO.
