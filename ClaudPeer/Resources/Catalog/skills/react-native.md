# React Native

## When to Activate

Use when bridging JS and native code, shipping OTA updates, or tuning performance on Android low-end devices. Apply before release hardening and native dependency upgrades.

## Process

1. **Thread model**: Keep JS thread light—defer heavy work to native modules or **Reanimated**/**Hermes**-friendly patterns. Profile with **React Native Performance Monitor** and **Flipper** (or **React Native DevTools**).
2. **Platform files**: Use `.ios.js` / `.android.js` or `Platform.select` when UX or APIs diverge; avoid sprawling `if (Platform.OS)` in every render.
3. **Native modules**: Version **CocoaPods** and **Gradle** dependencies explicitly; run `pod install` lockfiles in CI. Document breaking native API changes in release notes.
4. **Deep links & push**: Test **Universal Links** / **App Links** with asset files hosted correctly. Verify **FCM**/`APNs` tokens refresh and notification tap routes.
5. **OTA**: If using **CodePush** or similar, stage rollouts; never ship native-breaking JS. Pair OTA with exact **binary** version ranges.
6. **Crashes**: Integrate **Sentry** or **Firebase Crashlytics** with **dSYM**/ProGuard mapping and **source maps** uploaded in CI for symbolicated stacks.
7. **Low-end Android**: Reduce shadow/elevation abuse, list virtualization (`FlashList`), and image sizing (`react-native-fast-image` or **expo-image**). Test on e.g. **Galaxy A** class hardware.

## Checklist

- [ ] JS thread profiled; heavy work offloaded
- [ ] Platform-specific entry points where needed
- [ ] Native dependency versions pinned; iOS/Android build reproducible
- [ ] Deep links and push flows tested on devices
- [ ] Crash reporting + source maps configured
- [ ] Lists and images optimized for Android budget devices

## Tips

Run **`npx react-native doctor`**. Use **New Architecture** (Fabric/TurboModules) when stable for your stack. Keep **Hermes** enabled unless a library blocks it.
