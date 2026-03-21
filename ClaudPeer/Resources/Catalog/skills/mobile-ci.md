# Mobile CI: Build, Sign, and Test in Pipelines

## When to Activate

Use when automating iOS/Android builds for PRs, nightly QA, or store submission—especially when teams need reproducible signing, simulator tests, and artifact traceability.

## Process

1. **Pin toolchains.** iOS: lock Xcode via Bitrise stack, GitHub Actions `macos-14` + `sudo xcode-select -s /Applications/Xcode_15.app`, or Fastlane `xcversion`. Android: pin NDK/AGP in `gradle/libs.versions.toml` and use Docker or self-hosted images with fixed API levels.
2. **Cache dependencies.** `bundle install --path vendor/bundle` + cache `vendor/bundle`; `pod install` with CocoaPods cache; Gradle: enable remote build cache and cache `~/.gradle/caches`. Use lockfiles (`Gemfile.lock`, `Podfile.lock`).
3. **Secure signing.** Store `.p12`, provisioning profiles, keystore, and `key.properties` in **Bitrise Code Signing**, **GitHub Actions secrets**, or cloud KMS-wrapped files. Inject at runtime; never commit secrets. Use Fastlane **match** for iOS cert/profile sync across the team.
4. **Test on simulators.** `xcodebuild test -scheme MyApp -destination 'platform=iOS Simulator,name=iPhone 15'`. Android: start `adb` then `./gradlew connectedDebugAndroidTest` or trigger **Firebase Test Lab** from CI with the same ABI matrix you ship.
5. **Artifacts + metadata.** Upload `.ipa`, `.aab`, and mapping files with build number, git SHA, and `xcodebuild -showBuildSettings` / Gradle `versionName`. Attach SBOM or dependency list when compliance asks.
6. **Gate releases.** Require green unit/UI tests, lint (`swiftlint`, `detekt`), and manual approval for production lanes. Run Fastlane `deliver` / `supply` only from protected branches with environment approvals.

## Checklist

- [ ] Xcode/NDK/Flutter versions pinned and documented
- [ ] Dependency caches restored before compile
- [ ] Secrets only via vault/secrets; ephemeral keychain on macOS runners
- [ ] Simulator/UI tests run on PR or nightly
- [ ] Artifacts tagged with version + commit + mapping uploads scheduled

## Tips

Use `fastlane scan` for iOS tests and `gradle test` for JVM unit tests in parallel jobs. On GitHub Actions, split Android (ubuntu) and iOS (macOS) workflows to save minutes; add `actions/cache` keys that include lockfile hashes.
