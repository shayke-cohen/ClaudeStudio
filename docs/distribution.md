# Distribution — Building & Shipping Odyssey.app

How to build a notarized Odyssey.app that runs on any Mac with no Gatekeeper
warnings. Captures the non-obvious gotchas we hit setting this up for the
first time — read before touching signing, entitlements, or the sidecar bundle.

## The flow

1. **Product → Archive** in Xcode (scheme: Odyssey, destination: My Mac)
2. **Window → Organizer** → select the archive → **Distribute App**
3. **Direct Distribution** → Xcode builds, signs with Developer ID, uploads
   to Apple for notarization, staples the ticket
4. **Export...** → saves the notarized `.app` to a folder
5. Copy to any Mac → double-click → it just opens

## Requirements

- Apple Developer Program membership (team ID `U6BSY4N9E3`)
- **Developer ID Application** certificate in login keychain
  (not development cert — that only works locally)
- `bun` on `PATH` during archive (used by `build-sidecar-binary.sh`)

## Architecture of the bundled app

```
Odyssey.app/Contents/Resources/
├── odyssey-bun               # Bun runtime, ~59MB, signed by Oven (7FRXF46ZSN)
├── odyssey-sidecar.js        # Bundled TypeScript sidecar (~1.4MB)
└── local-agent/bin/
    └── OdysseyLocalAgentHost # Swift-built helper, signed with Hardened Runtime
```

`SidecarManager.launchSidecar()` checks for `odyssey-bun` + `odyssey-sidecar.js`
in the app resources first (distribution path) and falls back to `bun run
sidecar/src/index.ts` from the dev checkout (development path). See
`LocalProviderSupport.resolveBundledSidecar()`.

## Key files

| File | Purpose |
|------|---------|
| `project.yml` | XcodeGen source of truth — bundle ID, team, entitlements, build phases |
| `Odyssey/Resources/Odyssey.entitlements` | Runtime entitlements (no CloudKit — see below) |
| `scripts/build-sidecar-binary.sh` | Pre-build phase: bundles bun + JS into Resources |
| `scripts/build-local-agent-host.sh` | Pre-build phase: builds Swift helper + signs with Hardened Runtime |
| `Odyssey/Services/SidecarManager.swift` | Runtime: prefers bundled sidecar |
| `Odyssey/Services/LocalProviderSupport.swift` | Path resolution for bundled binaries |

## Gotchas we hit — read these

### 1. `bun build --compile` binaries cannot be code-signed

The single-file executable bun produces has a pre-allocated `LC_CODE_SIGNATURE`
slot with invalid data that `codesign` refuses to replace (`invalid or
unsupported format for signature`). Even zeroing the slot doesn't help.

**Solution:** bundle the bun runtime binary (already signed with Hardened
Runtime by Oven) + a plain JS bundle from `bun build --target=bun` (no
`--compile`). JS files don't need signing; the bun binary is re-signed by
Xcode during distribution, preserving its hardened-runtime flag.

### 2. XcodeGen inlines script content into `project.pbxproj`

When `project.yml` uses `preBuildScripts: path: scripts/foo.sh`, XcodeGen
reads the file and embeds the content into the project file. **Editing the
script alone is not enough** — you must run `xcodegen generate` afterward,
or Xcode will run the stale inlined version.

Verify with:
```bash
grep "shellScript" Odyssey.xcodeproj/project.pbxproj | grep <your-change>
```

### 3. SwiftData picks up CloudKit from entitlements automatically

If the `.entitlements` file has `com.apple.developer.icloud-services` or
CloudKit container identifiers, `ModelConfiguration(url:)` silently enables
CloudKit sync — and SwiftData requires every attribute to be `Optional` or
have a default, or it crashes on load with `loadIssueModelContainer`.

**Two fixes, applied together:**
- `Odyssey/Resources/Odyssey.entitlements`: no iCloud/CloudKit keys
- `OdysseyApp.swift`: `ModelConfiguration(url: storeURL, cloudKitDatabase: .none)` (belt and suspenders)

### 4. Swift Package binaries are ad-hoc signed without Hardened Runtime

`swift build` produces ad-hoc-signed Mach-Os without the `runtime` flag. If
you just copy them into Resources, notarization rejects them with
"Hardened Runtime is Not Enabled".

**Solution:** `build-local-agent-host.sh` re-signs with
`codesign --options runtime` immediately after copy, using
`EXPANDED_CODE_SIGN_IDENTITY` (Xcode-provided) or `-` (ad-hoc with
runtime flag — Xcode's distribution re-sign preserves the flag and swaps
the identity to Developer ID).

### 5. AppXray's `.xrayId()` is `#if DEBUG` only

The SDK guards `.xrayId()` behind `#if DEBUG`. Release/Archive builds fail
to compile with "Value of type '…' has no member 'xrayId'" across hundreds
of call sites. `.stableXrayId()` (in `StableXrayModifier.swift`) already has
the guard, but direct `.xrayId()` calls need a Release-only no-op stub.
That stub lives in `StableXrayModifier.swift` inside `#if !DEBUG`.

### 6. `com.odyssey.app` bundle ID is globally taken

Apple's developer portal had it claimed by someone else. Use
`com.shaycohen.odyssey` (our actual bundle ID). If you need to change it
again, grep and update:
- `project.yml` (PRODUCT_BUNDLE_IDENTIFIER)
- `Odyssey/Resources/Info.plist` (CFBundleURLName)

### 7. "No Team Found in Archive" at distribution

If `DEVELOPMENT_TEAM` isn't set in `project.yml`, Xcode archives with
automatic signing but loses the team in the archive, blocking Direct
Distribution. We have `DEVELOPMENT_TEAM: U6BSY4N9E3` pinned in
`project.yml`.

### 8. Xcode caches script content in DerivedData

After editing `scripts/build-*.sh` + regenerating the project, if the old
output (`odyssey-sidecar` compiled binary) persists in the archive, the
build cache is stale. Clear it:
```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/Odyssey-*
```

## Sharing without notarization (dev only)

For quick tests between your own Macs, skip notarization:
1. Copy the `.app` to the other Mac
2. `xattr -cr /Applications/Odyssey.app` — strips quarantine
3. Launch normally

This only works for machines you control. For anyone else, notarize.

## Verifying the output

After Export, confirm the bundle is correctly set up:
```bash
# All Mach-Os signed with Hardened Runtime?
codesign -dv --verbose=2 Odyssey.app 2>&1 | grep "flags="
codesign -dv Odyssey.app/Contents/Resources/odyssey-bun 2>&1 | grep flags
codesign -dv Odyssey.app/Contents/Resources/local-agent/bin/OdysseyLocalAgentHost 2>&1 | grep flags
# Expect: flags=0x10000(runtime) on all three

# Notarization stapled?
stapler validate Odyssey.app
# Expect: "The validate action worked!"

# Gatekeeper check
spctl -a -v Odyssey.app
# Expect: "accepted source=Notarized Developer ID"
```
