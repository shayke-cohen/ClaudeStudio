# Mobile Testing

## When to Activate

Use for iOS/Android releases, permission-sensitive flows, or hardware-specific behavior—simulators first, devices for final validation.

## Process

1. **Matrix** — Test oldest supported OS + newest, small and large phones, tablet if supported. Xcode: multiple sim destinations; Android: API levels via `avdmanager`.
2. **Permissions** — Pre-grant with `simctl privacy` or `adb shell pm grant` where possible; otherwise assert system dialogs with Maestro/XCUITest flows.
3. **Lifecycle** — Background/foreground, low memory (`simulate memory warning`), airplane mode toggles, dark mode, dynamic type.
4. **Deep links and push** — Universal/App Links with `xcrun simctl openurl`, Android `adb shell am start -a android.intent.action.VIEW -d`. Push via sandbox payloads or local notification triggers.
5. **Upgrades** — Install previous build, migrate data, install new build; verify schema migrations and stored credentials.
6. **Evidence** — Capture `xcrun simctl io booted screenshot`, `adb exec-out screencap`, and `log stream`/`logcat` on failure. Symbolicate crashes from `.ips`/`tombstone`.

## Checklist

- [ ] Representative OS versions and screen sizes exercised
- [ ] Permission and offline paths covered
- [ ] Deep link entry verified for main screens
- [ ] Upgrade from N-1 build smoke-tested
- [ ] Logs/screenshots attached to bug reports

## Tips

Use accessibility identifiers for automation per platform guidelines. Run `xcodebuild test -destination 'platform=iOS Simulator,name=iPhone 15'` in CI. For macOS apps, validate menu shortcuts and sandbox file access separately from iOS assumptions.
