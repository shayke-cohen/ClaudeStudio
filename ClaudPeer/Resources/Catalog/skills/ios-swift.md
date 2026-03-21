# iOS Swift (SwiftUI & UIKit)

## When to Activate

Use when building or reviewing iOS features with **Swift 6** concurrency, navigation, or App Store submission readiness. Apply for new screens, background modes, and performance tuning.

## Process

1. **Swift 6 concurrency**: Prefer `async/await`; mark UI-touching code `@MainActor`. Use `Sendable` types across actors; fix data races the compiler flags—do not blanket `@unchecked Sendable` without proof.
2. **Navigation**: Centralize routes with `NavigationStack` path binding or coordinator pattern; avoid implicit state in deep view hierarchies. Test state restoration where applicable.
3. **Subviews**: Extract child views to reduce body recomputation; pass narrow dependencies, not entire models when possible.
4. **Permissions**: Declare **Info.plist** usage strings before calling **AVFoundation**, **Photos**, **Location**. Handle **denied** and **limited** photo states gracefully.
5. **Background**: Enable only required **Background Modes**; use **BGTaskScheduler** for deferrable work; respect **Low Power Mode**.
6. **Accessibility**: Support **Dynamic Type**, **VoiceOver** labels/hints, and **Reduce Motion**. Test on smallest/largest content sizes.
7. **Performance**: Profile launch with **Xcode Instruments** (Time Profiler, Allocations, Leaks). Watch **Memory Graph** for retain cycles in closures—use `[weak self]` when appropriate.

## Checklist

- [ ] Strict concurrency warnings addressed
- [ ] MainActor used for UI updates
- [ ] Navigation state explicit and testable
- [ ] Info.plist strings for all sensitive APIs
- [ ] Dynamic Type and VoiceOver verified
- [ ] Instruments run on release-like build

## Tips

Run on multiple OS versions in **Simulator** and one physical device. Use **`swiftformat`** / **`swiftlint`** in CI. Archive with **TestFlight** before wide release.
