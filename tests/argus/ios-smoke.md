# OdysseyiOS — Argus Smoke Test

Manual/interactive Argus MCP sequence that validates the iOS app launches
and the pairing screen is wired up. Run via an MCP-enabled client (e.g.
Claude Code with the argus MCP server). Target the booted iPhone 17
simulator (UDID `B1B452F0-45C4-4FC2-8807-EAA7DDE53C56`, iOS 26.4).

Expected duration: ~30 seconds.

## Prereqs

- OdysseyiOS installed on the simulator:
  `xcrun simctl install B1B452F0-45C4-4FC2-8807-EAA7DDE53C56 <path-to-OdysseyiOS.app>`
- The simulator booted.

## Steps

### 1. Allocate simulator
```
device({ action: "allocate", platform: "ios", app: "com.odyssey.app.ios" })
```
→ Returns `token`. Use on every subsequent call.

### 2. Inspect initial screen — Pair with Mac
```
inspect({ token })
```
Expected actionableElements (by id):
- `pairing.scanQRButton` (Scan QR Code button)
- `pairing.pairButton` (Pair button — disabled when no invite code)
- `pairing.inviteCodeField` (TextView)
- Static text "Pair with your Mac"
- Static text "On your Mac, open Odyssey → Settings → Devices…"

Assert:
- Element count >= 10
- `pairing.pairButton.enabled === false`
- No system alert present
- Orientation portrait

### 3. Tap invite code field and paste dummy code
```
act({ action: "tap", selector: "pairing.inviteCodeField", token })
act({ action: "input", selector: "pairing.inviteCodeField",
      text: "dummy-invite-for-smoke-test", token })
```
Assert:
- `pairing.pairButton.enabled === true` after text entry
  (If this does not become enabled, the invite-code parser has a bug)

### 4. Tap Cancel
```
act({ action: "tap", text: "Cancel", token })
```
Expected: pairing sheet dismisses.

### 5. Release
```
device({ action: "release", token })
```

## Known limitations

- Cannot complete pairing without a live Mac sidecar generating an invite.
- A more thorough test that covers the real pair flow is deferred — it
  requires Mac + iOS orchestrated together. Run locally via the Swift
  app's Settings → Devices page.

## Post-conditions

- Simulator remains booted (not rebooted) so follow-up smoke runs
  are fast.
- App's keychain may contain smoke-test invite code entries; clear
  via `xcrun simctl uninstall <udid> com.odyssey.app.ios` if needed.
