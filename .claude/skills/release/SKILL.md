---
name: release
description: Use when building and publishing a new Odyssey release — version bump, archive, notarize, DMG, GitHub release, appcast update.
---

# Odyssey Release

## Overview

One script handles the full pipeline: version bump → archive → notarize → DMG → GitHub release → appcast update. Always commit pending changes first, then run the script.

## Prerequisites

All must be installed and configured before releasing:

| Tool | Install |
|---|---|
| `xcodegen` | `brew install xcodegen` |
| `create-dmg` | `brew install create-dmg` |
| `gh` | `brew install gh` + `gh auth login` |
| `xcrun notarytool` | Xcode CLI tools |
| `sign_update` | Sparkle key stored at `~/tools/sparkle/sign_update` |

**Required env var** (add to `~/.zshrc`):
```sh
export SIGN_UPDATE_PATH="$HOME/tools/sparkle/sign_update"
```

**Notarization keychain profile:** `odyssey-notarize`  
To recreate: `xcrun notarytool store-credentials odyssey-notarize --apple-id <ID> --team-id U6BSY4N9E3 --password <app-specific-password>`

## Signing Identity

| Field | Value |
|---|---|
| Certificate | `Developer ID Application: WIX.COM, INC.` |
| Team ID | `U6BSY4N9E3` |
| Cert SHA-1 | `6A50689139A14362F3180114960F71391CDE0E12` |
| Releases repo | `shayko-cohen/Odyssey-releases` |

The script auto-selects the cert with the latest expiry if multiple exist in Keychain.

## Release Steps

### 1. Commit all pending changes
```sh
git status
git add -A && git commit -m "feat: ..."
git push origin main
```

### 2. Bump version in `project.yml`
```yaml
CURRENT_PROJECT_VERSION: <N+1>
MARKETING_VERSION: "X.Y.Z"
```
The release script also auto-increments the build number — so you only need to set `MARKETING_VERSION` here; the script will bump `CURRENT_PROJECT_VERSION` by 1 again automatically.

### 3. Regenerate Xcode project
```sh
xcodegen generate
git add project.yml Odyssey.xcodeproj
git commit -m "chore: bump to vX.Y.Z (build N)"
```

### 4. Run the release script
```sh
export SIGN_UPDATE_PATH="$HOME/tools/sparkle/sign_update"
bash scripts/release.sh X.Y.Z
```

Takes ~5–8 minutes (archive + Apple notarization wait).

### 5. Verify the DMG runs
```sh
hdiutil attach ~/Downloads/Odyssey-X.Y.Z.dmg -quiet
"/Volumes/Odyssey X.Y.Z/Odyssey.app/Contents/MacOS/Odyssey" &
sleep 4 && kill -0 $! && echo "✅ Running" || echo "❌ Crashed"
```

### 6. Commit Xcode project sync (if script left changes)
```sh
git status
git add -A && git commit -m "chore: sync Xcode project after vX.Y.Z release"
git push origin main
```

## What the Script Does Internally

1. Validates all prerequisites
2. Bumps `MARKETING_VERSION` and increments `CURRENT_PROJECT_VERSION` in `project.yml`, runs `xcodegen`
3. Auto-generates release notes from `feat:` and `fix:` commits since the last version bump
4. `xcodebuild archive` → Developer ID signed `.xcarchive`
5. `xcodebuild -exportArchive` using `distribution/ExportOptions.plist`
6. `xcrun notarytool submit` + waits for Apple `Accepted`
7. `xcrun stapler staple` — attaches notarization ticket to `.app`
8. `create-dmg` — builds signed DMG with icon layout
9. `sign_update` — generates EdDSA signature for Sparkle auto-update integrity
10. `gh release create` on `shayke-cohen/Odyssey-releases` with generated release notes as body
11. Clones releases repo, prepends new `<item>` in `appcast.xml` with `<description><![CDATA[...]]></description>` — Sparkle renders this HTML in the update dialog, commits & pushes
12. Commits version bump to private source repo and pushes

## Common Failures

| Symptom | Cause | Fix |
|---|---|---|
| `SIGN_UPDATE_PATH: ERROR` | Env var not set | `export SIGN_UPDATE_PATH="$HOME/tools/sparkle/sign_update"` |
| App crashes on launch (exit 133) | CloudKit enabled without entitlement | Keep `ModelConfiguration(url: storeURL)` — no `cloudKitDatabase:` param |
| `database is locked` build error | Stale `XCBuildData/build.db` | `rm -rf ~/Library/Developer/Xcode/DerivedData/Odyssey-*/XCBuildData` |
| Notarization rejected | Entitlements mismatch | Remove any CloudKit/APS entitlements from `Odyssey.entitlements` |
| GitHub upload stalls | Network / large DMG (~50 MB) | Re-run script; delete draft release first with `gh release delete vX.Y.Z --repo shayko-cohen/Odyssey-releases --yes` |
| `cp: Permission denied` on sidecar binary | Stale DerivedData permissions | `chmod -R +w ~/Library/Developer/Xcode/DerivedData/Odyssey-*` |

## Critical Rule: No CloudKit in Release

`OdysseyApp.swift` must use:
```swift
let config = ModelConfiguration(url: storeURL)
```

**Never** `cloudKitDatabase: .private(...)` — Developer ID signing strips the CloudKit entitlement, causing a `SIGTRAP` crash at launch.
