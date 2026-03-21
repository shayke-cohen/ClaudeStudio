# Flutter: Widgets, Platform Channels, and Release Pipelines

## When to Activate

Use this skill when building or shipping Flutter apps across iOS and Android: custom native integrations, list performance, release size, or production crash quality.

## Process

1. **Keep widgets pure.** Push side effects to `initState`, `didChangeDependencies`, or notifiers (`ChangeNotifier`, `Riverpod`, `Bloc`). Prefer `const` constructors and immutable models so rebuilds stay cheap.
2. **Lists that reorder need keys.** Use `ValueKey`/`ObjectKey` on list children when order or identity changes; avoid rebuilding entire trees on every frame.
3. **Isolate platform channels.** Wrap `MethodChannel`/`EventChannel` in a small service class; validate arguments on both Dart and native sides; never block the UI isolate on channel round-trips—use `compute` or async handlers.
4. **Typography QA.** Run golden tests or manual checks on both platforms: `flutter run -d ios` and `flutter run -d android`; verify line height, font scaling (`MediaQuery.textScaler`), and CJK/RTL if applicable.
5. **Build size and shaders.** Use `flutter build apk --analyze-size` / `flutter build appbundle --analyze-size`; enable deferred loading for heavy features; run `flutter build` with `--tree-shake-icons`. Warm up shaders with `flutter run --cache-sksl` and ship cached SKSL where your pipeline allows.
6. **Crash reporting.** Integrate Firebase Crashlytics or Sentry Flutter; upload **dSYM** (iOS) and **ProGuard/R8 mapping** (Android). CI: `flutter build` with split debug symbols, then upload mapping files in the same job that produced the binary.

## Checklist

- [ ] Stateful logic separated from pure `build` methods
- [ ] Stable keys on dynamic/reorderable lists
- [ ] Channel layer has timeouts, error mapping, and typed DTOs
- [ ] iOS + Android visual pass on real devices
- [ ] Size report reviewed; SKSL warmup considered
- [ ] Symbol upload wired to the exact build ID

## Tips

Prefer `flutter test --coverage` in CI. Use `dart analyze` and `flutter doctor -v` on pinned SDK versions. For plugins, pin minimum iOS deployment target and Android `compileSdk` explicitly in `android/app/build.gradle.kts`.
