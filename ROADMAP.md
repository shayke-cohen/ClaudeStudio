
# Odyssey Roadmap — iOS App, Secure Remote Access & Multi-User Federation

> **Vision:** Use your Mac-hosted AI agents from any device, anywhere, with anyone.

**Status:** Planning
**Last updated:** 2026-04-13

---

## Background

Odyssey today is macOS-only and single-user. The TypeScript sidecar runs as a subprocess — it can't run on iOS. The WebSocket between Swift app and sidecar is `ws://localhost:9849` with no authentication, safe only on localhost.

The CloudKit-based `SharedRoomService` already handles multi-instance sync for conversations owned by the same Apple ID. It uses CloudKit record types (Room, RoomMessage, RoomMembership, RoomInvite), 8-second poll cycles with LAN hints, and a `hostSequence` Lamport clock for causal ordering. Phase 6 adds Matrix alongside CloudKit for cross-user federation — it does not replace CloudKit.

This roadmap delivers six phases:

1. **Security foundation** — auth + TLS so remote connections are safe
2. **Cross-network discovery** — STUN + signed invite codes
3. **OdysseyCore shared package** — shared Swift code for both targets
4. **iOS thin client** — iPhone app that connects to your Mac's sidecar
5. **UX enhancements** — silent observer agents + agent ownership display
6. **Multi-user federation** — Matrix transport for cross-user chats

Draws from the [AgentChat design spec](agentchat-spec.md) (April 2026) for the cryptographic identity model, invite code pattern, NAT traversal approach, and Matrix "reduced scope" transport design.

---

## Architecture

```
iPhone (iOS App)
  │  wss:// (TLS + bearer token)
  │  LAN:       Bonjour → direct connect (same Wi-Fi, zero config)
  │  WAN:       STUN hole-punch → direct UDP (~85-90% home/office NATs)
  │  CGNAT/LTE: CloudKit relay → CKQuerySubscription push (~1-3s latency)
  ▼
Mac sidecar (:9849 WS / :9850 HTTP)
  │  ConversationStore (in-memory + disk cache, fed from SwiftData via Mac app)
  │  SessionManager, BlackboardStore, TaskBoardStore (unchanged)
  ▼
Agent sessions (Claude API / Ollama / etc.)

─────────────────────────────────────────

Phase 6 adds:

Mac A sidecar ── Matrix homeserver ── Mac B sidecar
     │                                      │
 iPhone A                               iPhone B
(via wss to Mac A)                   (via wss to Mac B)
```

### Key design principles

- **iOS is always a thin client.** It connects to a Mac sidecar over the network, never runs agents locally.
- **Your Mac is the agent host.** iPhone is the remote control.
- **Sidecar is the data bridge.** The Mac Swift app pushes SwiftData conversation snapshots into the sidecar's in-memory `ConversationStore` so iOS clients can query them without touching SwiftData directly.
- **CloudKit serves two roles:** fast path for same-Apple-ID conversation sync, and NAT-traversal relay fallback (via `OdysseyRelay` records + `CKQuerySubscription` push). Matrix handles cross-user federation.
- **Existing wire protocol is reused unchanged.** `SidecarCommand` / `SidecarEvent` — same encoding on iOS.

---

## Phase Overview

| # | Phase | Key Deliverable | Unlocks |
|---|---|---|---|
| 1 | Security Foundation | Auth + TLS on sidecar WS | Safe remote connections |
| 2 | Cross-Network Discovery | STUN + signed invite codes | Connect over internet |
| 3 | OdysseyCore Package | Shared Swift package | iOS target compiles |
| 4 | iOS App | iPhone thin client | Use agents from anywhere |
| 5 | UX Enhancements | Silent observer + ownership display | Better group agent UX |
| 6 | Multi-User Federation | Matrix transport + cross-user invites | Chat with other users' Macs and agents |

---

## Phase 1 — Security Foundation

> **Goal:** Make the sidecar WebSocket safe to expose on a network.
> Currently: zero auth, plain `ws://`, localhost-only.
> After: bearer token, `wss://`, cert-pinnable from iOS.

**Within-phase ordering:** 1a must complete before 1b and 1c, because both require the infrastructure it creates (`IdentityManager`, token generation, cert generation).

---

### 1a. Ed25519 Identity Keypairs

**New:** `Odyssey/Services/IdentityManager.swift`
**New:** `Odyssey/Models/UserIdentity.swift`
**Edit:** `Odyssey/Models/Agent.swift` — add `identityBundleJSON: String?`

Generate a long-lived Ed25519 keypair at first launch using `CryptoKit` (zero new dependencies). Store private key in Keychain under `odyssey.identity.<instanceName>` (`kSecAttrAccessibleAfterFirstUnlock`).

Each `Agent` gets its own keypair stored in Keychain as `odyssey.agent.key.<agentId>`. The agent's public key + metadata is signed by the owner's identity key, producing an `AgentIdentityBundle` — a cryptographically verifiable chain of "this agent belongs to this user."

```swift
// Odyssey/Models/UserIdentity.swift
struct UserIdentity: Codable {
    let publicKeyData: Data       // Curve25519.Signing.PublicKey raw bytes
    let displayName: String
    let createdAt: Date
}

struct AgentIdentityBundle: Codable {
    let agentPublicKeyData: Data  // agent's Ed25519 public key
    let agentId: UUID
    let agentName: String
    let ownerPublicKeyData: Data  // owner's Ed25519 public key
    let ownerSignature: Data      // owner signs (agentPublicKey ++ agentId.bytes ++ agentName.utf8)
    let createdAt: Date
}
```

```swift
// Odyssey/Services/IdentityManager.swift  (@MainActor, singleton)
func userIdentity(for instance: InstanceConfig) -> UserIdentity
func agentBundle(for agent: Agent, instance: InstanceConfig) -> AgentIdentityBundle
func sign(_ data: Data, instance: InstanceConfig) throws -> Data
func wsToken(for instance: InstanceConfig) -> String        // 32 random bytes, base64
func tlsCertificate(for instance: InstanceConfig)
    -> (cert: SecCertificate, key: SecKey, derBytes: Data)  // self-signed, for TLS
```

**Keychain layout:**

| Key | Content | Class |
|---|---|---|
| `odyssey.identity.<instance>` | Ed25519 private key | kSecClassKey |
| `odyssey.wstoken.<instance>` | WS bearer token | kSecClassGenericPassword |
| `odyssey.tlskey.<instance>` | TLS private key | kSecClassKey |
| `odyssey.tlscert.<instance>` | TLS cert DER bytes | kSecClassCertificate |
| `odyssey.agent.key.<agentId>` | Per-agent Ed25519 private key | kSecClassKey |

---

### 1b. WebSocket Bearer Token Auth

**Edit:** `sidecar/src/ws-server.ts`
**Edit:** `Odyssey/Services/SidecarManager.swift`

`IdentityManager.wsToken()` generates the token. `SidecarManager` passes it as env var `ODYSSEY_WS_TOKEN` and adds `Authorization: Bearer <token>` to the `URLSessionWebSocketTask` upgrade headers.

`ws-server.ts` checks `Authorization` on every new WS connection; closes with code 4401 if missing or wrong.

```typescript
// sidecar/src/ws-server.ts — in the ws open handler
const expectedToken = process.env.ODYSSEY_WS_TOKEN;
if (expectedToken && ws.data.authHeader !== `Bearer ${expectedToken}`) {
    ws.close(4401, "Unauthorized");
    return;
}
```

> **Important:** `SidecarManager.swift` must add the auth header before `ws-server.ts` starts enforcing it. Deploy both changes together.

---

### 1c. TLS — Switch to `wss://`

**Edit:** `sidecar/src/index.ts`
**Edit:** `Odyssey/Services/SidecarManager.swift`

`IdentityManager.tlsCertificate()` generates a self-signed cert using `Security.framework` for `localhost` + the Mac's local hostname. Writes PEM files to `~/.odyssey/instances/<name>/tls.{cert,key}.pem`.

```typescript
// sidecar/src/index.ts
const tlsConfig = process.env.ODYSSEY_TLS_CERT ? {
    cert: Bun.file(process.env.ODYSSEY_TLS_CERT),
    key:  Bun.file(process.env.ODYSSEY_TLS_KEY!),
} : undefined;
Bun.serve({ port: wsPort, tls: tlsConfig, ... });
```

`SidecarManager.swift` connects via `wss://localhost:9849`. Implements `URLSessionDelegate.urlSession(_:didReceive:completionHandler:)` to accept the self-signed cert by pinning its SHA-256 fingerprint. iOS clients pin against the cert bytes received in the invite code.

**iOS ATS requirement:** iOS App Transport Security blocks self-signed certs by default. The iOS `Info.plist` must declare domain exceptions for the Mac's hostnames. Add to `OdysseyiOS/Resources/Info.plist`:
```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSExceptionDomains</key>
    <dict>
        <!-- Allow self-signed cert on .local mDNS hostnames (LAN) -->
        <key>local</key>
        <dict>
            <key>NSExceptionAllowsInsecureHTTPLoads</key><false/>
            <key>NSRequiresCertificateTransparency</key><false/>
            <key>NSExceptionMinimumTLSVersion</key><string>TLSv1.2</string>
        </dict>
    </dict>
    <!-- For WAN IPs: certificate pinning in URLSessionDelegate handles validation;
         ATS still requires TLS — met by wss://.
         Self-signed certs are accepted via SecTrust override in the delegate,
         not by disabling ATS. The delegate IS called for wss:// on iOS when
         the cert fails system trust — allowing pinning to succeed. -->
</dict>
```
For WAN connections (IP address, not `.local`), the `URLSessionDelegate` override handles cert pinning without additional ATS exceptions, because `wss://` satisfies ATS's TLS requirement even with a self-signed cert when the delegate explicitly approves it.

---

## Phase 2 — Cross-Network Discovery

### 2a. STUN + NAT Traversal

**New:** `Odyssey/Services/NATTraversalManager.swift`
**Edit:** `Odyssey/Services/P2PNetworkManager.swift` — add `wan` field to Bonjour TXT record

`NATTraversalManager` sends a STUN Binding Request via raw UDP `NWConnection` to `stun.l.google.com:19302` and parses the Binding Response mapped address.

```swift
@MainActor final class NATTraversalManager: ObservableObject {
    @Published var publicEndpoint: String?    // "203.0.113.5:9849" or nil
    @Published var stunStatus: STUNStatus     // idle / discovering / success / failed

    func discoverPublicEndpoint() async
    // Attempts simultaneous UDP packets to peer's public IP:port.
    // Returns direct NWConnection on success (works ~85-90% of home/office NATs).
    func holePunch(to peerEndpoint: String) async -> NWConnection?
}
```

**Connection priority for iOS → Mac:**
1. **LAN (Bonjour)** — same Wi-Fi, near-zero latency, always works
2. **WAN direct (STUN + hole-punch)** — works ~85–90% of home/office routers
3. **TURN relay** — covers symmetric NATs, CGNAT, and cellular; latency depends on relay geography

STUN servers (free, no account): `stun.l.google.com:19302`, `stun.cloudflare.com:3478` (fallback).

> **Why no CloudKit relay?** CloudKit relay would work but adds tight iCloud coupling to what is otherwise a direct P2P connection. Standard TURN (RFC 5766) is designed exactly for this relay use case and is available from multiple free/cheap providers without any Apple account dependency. Phase 6 Matrix relay supersedes TURN for cross-user scenarios.

**TURN relay configuration:**

TURN relays traffic bidirectionally when direct connection fails. Settings → iOS Pairing → "Relay Server" lets users enter their TURN credentials. Odyssey ships with a default that points to a configurable community endpoint; users can substitute their own coturn server for full control.

**TURN server options (no self-hosted infrastructure required):**

| Provider | Free tier | Notes |
|---|---|---|
| [Metered.ca](https://metered.ca) | 500 MB/mo relay bandwidth | Simple API key; most apps use this for free tier |
| [coturn](https://github.com/coturn/coturn) | Self-hosted, unlimited | Docker one-liner; full control |
| Cloudflare Calls TURN | Unlimited for Cloudflare users | Part of Cloudflare Calls product |
| Custom | Any RFC 5766 TURN server | Enter `turn:host:port`, username, credential |

**`TURNConfig` stored in `PeerCredentials`:**

```swift
struct TURNConfig: Codable {
    let uri: String          // "turn:turn.metered.ca:443?transport=tcp"
    let username: String
    let credential: String
    var ttl: Date?           // credential expiry; nil = non-rotating
}
```

The TURN URI, username, and credential travel inside the invite payload (under `hints.turn`), so the inviting Mac can tell the iOS device exactly which relay to use:

```json
"hints": {
  "lan": "192.168.1.5",
  "wan": "203.0.113.5:9849",
  "turn": {
    "uri": "turn:turn.metered.ca:443?transport=tcp",
    "username": "...",
    "credential": "..."
  }
}
```

**Relay session lifecycle:**
- When hole-punch fails (3 attempts, 2s timeout each), `NATTraversalManager` opens a TCP connection to the TURN server.
- Allocates a TURN relay channel; wraps `SidecarCommand`/`SidecarEvent` JSON as TURN `Data` indications.
- On iOS foreground, attempts direct reconnect first; falls back to TURN if direct fails.
- Backgrounded iOS: messages queue on Mac side; iOS drains on next foreground activation (same `reconnectIfNeeded()` path). Real-time push while backgrounded is handled in Phase 6 via Matrix push gateway.

---

### 2b. Signed Invite Codes

**New:** `Odyssey/Services/InviteCodeGenerator.swift`
**Edit:** `Odyssey/Models/SharedRoomInvite.swift` — add `signedPayloadJSON: String?`, `pairingType: PairingType`
**New:** `Odyssey/Views/Settings/iOSPairingSettingsView.swift` — Mac Settings panel showing QR
**Edit:** `Odyssey/App/LaunchIntent.swift` — handle `odyssey://connect?invite=<base64url>`

#### Invite payload structure (~400 chars, base64url)

```json
{
  "v": 1,
  "type": "device",
  "userPublicKey": "<base64 Ed25519 public key>",
  "displayName": "Shay's MacBook Pro",
  "tlsCertDER": "<base64 DER bytes of self-signed TLS cert>",
  "wsToken": "<base64 bearer token>",
  "wsPort": 9849,
  "hints": {
    "lan": "192.168.1.5",
    "wan": "203.0.113.5:9849"
  },
  "exp": 1713000000,
  "singleUse": true,
  "sig": "<base64 Ed25519 signature over all above fields canonically serialized>"
}
```

Deep link: `odyssey://connect?invite=<base64url-payload>`

```swift
struct InviteCodeGenerator {
    static func generateDevice(
        identity: IdentityManager, instance: InstanceConfig,
        expiresIn: TimeInterval = 300, singleUse: Bool = true
    ) async throws -> InvitePayload

    static func generateUser(   // Phase 6 — cross-user invite
        identity: IdentityManager, instance: InstanceConfig,
        matrixUserId: String?, expiresIn: TimeInterval = 86400
    ) async throws -> InvitePayload

    static func decode(_ base64url: String) throws -> InvitePayload
    static func verify(_ payload: InvitePayload) throws  // checks signature + expiry
    static func qrCode(for payload: InvitePayload, size: CGFloat = 300) -> CGImage?
}
```

**Mac Settings → iOS Pairing (`iOSPairingSettingsView.swift`):**
- QR code that auto-refreshes when the 5-minute token expires
- "Copy invite link" button (pastes the `odyssey://connect?invite=...` URL)
- Toggle: "Allow iOS connections" — restarts sidecar with `ODYSSEY_WS_BIND=0.0.0.0` and note about firewall
- List of paired devices: display name, last connected, "Revoke" button (regenerates WS token → invalidates all existing iOS credentials)

**Sidecar restart path (required for the toggle):**
The current `SidecarManager` has no restart-with-new-env mechanism — `attemptReconnect()` reconnects to an existing sidecar but doesn't relaunch it with different flags. Add:

```swift
// Odyssey/Services/SidecarManager.swift
func restart(environmentOverrides: [String: String]) async {
    // 1. Persist running session IDs (for resume after restart)
    let pausedSessionIds = await pauseAllActiveSessions()
    // 2. Kill existing sidecar process
    await stop()
    // 3. Merge overrides into launch environment
    self.environmentOverrides = environmentOverrides
    // 4. Relaunch
    await start()
    // 5. On .connected: resume paused sessions
    self.pendingResumeSessions = pausedSessionIds
}
```

`pauseAllActiveSessions()` sends `session.pause` for all active sessions before killing the process, so the Claude API sessions are preserved and resumable after restart. In-flight streaming responses are lost — the UI shows a "Reconnecting…" state.

---

## Phase 3 — OdysseyCore Shared Swift Package

> Extracts shared Swift code into `Packages/OdysseyCore/` so the iOS target compiles without AppKit.

**Critical architectural note — SwiftData stays on Mac only:**
iOS does NOT get its own SwiftData stack. The `@Model` classes are coupled to `OdysseyApp.swift`'s `ModelContainer` with Mac-specific store paths (`~/.odyssey/...`). Moving them to OdysseyCore would require duplicate schema registration — a maintenance nightmare. Instead, iOS reads all data exclusively via the sidecar REST API (Phase 4g/4h). OdysseyCore contains **Codable wire-type structs**, not SwiftData models.

### What moves into OdysseyCore

| Source | Notes |
|---|---|
| `Odyssey/Services/SidecarProtocol.swift` | Wire types as Codable structs only — strip all `Process`/AppKit/`@Model` |
| Wire types (new): `ConversationSummaryWire`, `MessageWire`, `ProjectSummaryWire`, `ParticipantWire` | Defined in Phase 4g/4h; live here |
| `Odyssey/Services/IdentityManager.swift` | CryptoKit — cross-platform |
| `Odyssey/Services/InviteCodeGenerator.swift` | CryptoKit + CoreImage — cross-platform |
| `Odyssey/Services/NATTraversalManager.swift` | Network.framework — cross-platform |
| `MarkdownContent.swift` | Needs `#if os(macOS)` / `#if os(iOS)` guards (see table below) |
| `MessageBubble`, `StreamingIndicator`, `ToolCallView` | Pure SwiftUI — no changes needed |
| `CodeBlockView.swift` | Replace `NSTextView` path with `Text` + monospace font on iOS |

### Platform guards required

| File | macOS-only code | iOS replacement |
|---|---|---|
| `MarkdownContent.swift` | `import AppKit`, `NSTextView`, `NSWorkspace.shared.open()` | `import UIKit`, `UITextView`, `UIApplication.shared.open()` |
| `CodeBlockView.swift` | `NSTextView`, `NSScrollView`, `NSFont` | `Text` with monospace + `ScrollView` |
| Any `NSPasteboard` usage | `NSPasteboard.general` | `UIPasteboard.general` |

Pattern: `#if os(macOS) … #elseif os(iOS) … #endif` around all platform-specific imports and calls.

### What stays macOS-only in the `Odyssey/` target

All SwiftData `@Model` classes (`Odyssey/Models/*.swift`), `SidecarManager.swift`, `PasteableTextField.swift`, `HighlightedCodeView.swift`, `SplitViewConfigurator.swift`, `WindowTitleSetter.swift`, `LocalFileReferenceSupport.swift`, `ChatExportPresenters.swift`, `ChatNotificationManager.swift`, `ConfigSyncService.swift` (FSEvents), `LogAggregator.swift`, all git/process services.

### Package layout

```
Packages/OdysseyCore/
├── Package.swift
└── Sources/OdysseyCore/
    ├── Protocol/     (SidecarProtocol wire types — Codable structs)
    ├── WireTypes/    (ConversationSummaryWire, MessageWire, ProjectSummaryWire, etc.)
    ├── Identity/     (IdentityManager, UserIdentity, AgentIdentityBundle)
    ├── Networking/   (InviteCodeGenerator, NATTraversalManager)
    └── Views/        (MessageBubble, MarkdownContent, StreamingIndicator, ToolCallView)
```

```swift
// Packages/OdysseyCore/Package.swift
let package = Package(
    name: "OdysseyCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "OdysseyCore", targets: ["OdysseyCore"])],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.0.0"),
    ],
    targets: [.target(name: "OdysseyCore",
        dependencies: [.product(name: "MarkdownUI", package: "swift-markdown-ui")])]
)
```

> **MarkdownUI deduplication:** `project.yml` currently lists `MarkdownUI` as a direct Mac target dependency. When OdysseyCore is created, **remove** `- package: MarkdownUI` from the Mac target in `project.yml` and add `- package: OdysseyCore` instead. Leaving both causes duplicate symbol linker errors.

**`project.yml` changes:** add `Packages/OdysseyCore` local package; remove direct `MarkdownUI` from Mac target; Mac target imports via `OdysseyCore`; iOS target depends on `OdysseyCore`.

---

## Phase 4 — iOS App

> iPhone thin client that connects to your Mac's sidecar. Same wire protocol, new form factor.

**Critical architectural note:** SwiftData lives only in the Mac app. The sidecar is stateless regarding conversation history. To give iOS access to past conversations, the Mac app pushes conversation snapshots into a new sidecar `ConversationStore` (in-memory + disk cache). iOS then reads these via new HTTP endpoints. See §4g.

---

### iOS v1 Scope — Explicit Non-Goals

The following Mac features are **not in scope for Phase 4** (iOS v1). They can be added in follow-on phases:

| Feature | Reason deferred |
|---|---|
| File attachments (drag-drop, images) | Requires sidecar file bridge; complex on iOS |
| Group conversation creation | v1 supports single-agent chats; multi-participant in Phase 5+ |
| Task board write operations | View-only: `GET /api/v1/tasks` is fine; create/edit deferred |
| Autonomous mode toggle | Requires `ConversationExecutionMode` sync from Mac; deferred |
| Scheduled tasks / cron triggers | Mac-only concept, no iOS equivalent |
| Inspector file tree | Mac filesystem is not browsable from iOS |
| Session fork | Deferred; adds UI complexity |
| Plan mode | Deferred; Opus override + custom system prompt |
| Agent editor | iOS agents are read-only; editing requires Mac |
| MCP server configuration | Mac-only; iOS reads agent configs from sidecar API |
| Git workspace / GitHub clone | Filesystem operations stay on Mac |

---

### 4a. XcodeGen Target

```yaml
# project.yml additions
targets:
  OdysseyiOS:
    type: application
    platform: iOS
    deploymentTarget: "17.0"
    bundleIdPrefix: com.odyssey.app
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.odyssey.app.ios
        INFOPLIST_FILE: OdysseyiOS/Resources/Info.plist
        CODE_SIGN_ENTITLEMENTS: OdysseyiOS/Resources/OdysseyiOS.entitlements
    sources: [OdysseyiOS]
    dependencies:
      - package: OdysseyCore
```

**New:** `OdysseyiOS/Resources/OdysseyiOS.entitlements`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.network.client</key><true/>
    <key>com.apple.security.network.server</key><false/>
</dict>
</plist>
```

> No CloudKit container entitlement required — Phase 2 uses TURN relay, not CloudKit. If Phase 6 Matrix push is implemented, the only additional entitlement is `aps-environment` (APNS), which Xcode adds automatically when Push Notifications capability is enabled.

**New:** `OdysseyiOS/Resources/Info.plist` — critical keys required for networking:

```xml
<!-- Bonjour service browsing (LAN discovery) -->
<key>NSBonjourServices</key>
<array>
    <string>_odyssey._tcp</string>
</array>

<!-- Local network usage description (iOS 14+ prompt) -->
<key>NSLocalNetworkUsageDescription</key>
<string>Odyssey uses your local network to connect to your Mac's AI agents.</string>

<!-- ATS: allow self-signed cert on .local mDNS hostnames -->
<!-- WAN IP connections: cert pinning via URLSessionDelegate handles trust;
     ATS is satisfied because wss:// is TLS. No NSExceptionAllowsInsecureHTTPLoads needed. -->
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSExceptionDomains</key>
    <dict>
        <key>local</key>
        <dict>
            <key>NSExceptionAllowsInsecureHTTPLoads</key><false/>
            <key>NSRequiresCertificateTransparency</key><false/>
        </dict>
    </dict>
</dict>

<!-- Camera access for QR pairing -->
<key>NSCameraUsageDescription</key>
<string>Scan the pairing QR code displayed on your Mac.</string>

<!-- Background modes: required if Phase 6 Matrix push is implemented -->
<!-- Add when Phase 6 ships: -->
<!-- <key>UIBackgroundModes</key><array><string>remote-notification</string></array> -->
```

**File list additions for §Files Changed Summary:**

| File | Type |
|---|---|
| `OdysseyiOS/Resources/OdysseyiOS.entitlements` | New |
| `OdysseyiOS/Resources/Info.plist` | New |

---

### 4b. `RemoteSidecarManager`

**New:** `OdysseyiOS/Services/RemoteSidecarManager.swift`

Replaces `SidecarManager` for iOS. No subprocess. Connects to a stored Mac endpoint via `wss://` with bearer token + TLS cert pinning.

```swift
@MainActor final class RemoteSidecarManager: ObservableObject {
    @Published var status: SidecarStatus = .disconnected
    @Published var connectedPeer: PairedDevice?

    // 1. Try LAN hint, 2. WAN hint, 3. hole-punch, 4. relay
    func connect(using credentials: PeerCredentials) async
    func send(_ command: SidecarCommand) async throws
    var events: AsyncStream<SidecarEvent> { get }
    func disconnect()

    // Called on app foreground — reconnects if dropped
    func reconnectIfNeeded() async
}
```

**TLS pinning:** `URLSessionDelegate` rejects any cert whose SHA-256 fingerprint doesn't match the one stored in `PeerCredentials`. No CA trust needed.

**Background / foreground handling:**
- iOS suspends the app after ~30 seconds of backgrounding; WS drops
- On `scenePhase == .background`: `RemoteSidecarManager.suspendForBackground()` sends `session.pause` for every active session before the WS closes. This prevents the Mac from treating the dropped connection as an unexpected error and leaves sessions in a resumable state.
- On `scenePhase == .active`: `RemoteSidecarManager.reconnectIfNeeded()` triggers automatic reconnect, then resumes sessions via `session.resume` for any conversation that has a stored `claudeSessionId`.
- Keepalive ping every 15 seconds (same as Mac `SidecarManager`) while active
- Pending commands during reconnect: queued in-memory with 10-second retry
- `OdysseyiOSApp.swift` drives this via `.onChange(of: scenePhase)`:
```swift
.onChange(of: scenePhase) { _, newPhase in
    switch newPhase {
    case .background: Task { await sidecarManager.suspendForBackground() }
    case .active:     Task { await sidecarManager.reconnectIfNeeded() }
    default: break
    }
}
```

---

### 4c. `PeerCredentialStore`

**New:** `OdysseyiOS/Services/PeerCredentialStore.swift`

Stores accepted invite payloads in iOS Keychain. Supports multiple paired Macs.

```swift
struct PeerCredentials: Codable, Identifiable {
    let id: UUID
    let displayName: String          // "Shay's MacBook Pro"
    let userPublicKeyData: Data
    let tlsCertDER: Data
    let wsToken: String
    let wsPort: Int
    let lanHint: String?             // "192.168.1.5"
    let wanHint: String?             // "203.0.113.5:9849"
    let pairedAt: Date
    var lastConnectedAt: Date?
    var claudeSessionIds: [UUID: String]  // conversationId → claudeSessionId (for resume)
}
```

`claudeSessionIds` allows iOS to resume paused agent sessions: before sending `session.create`, check if a stored `claudeSessionId` exists for this conversation and send `session.resume` instead.

---

### 4d. `iOSAppState`

**New:** `OdysseyiOS/App/OdysseyiOSApp.swift`
**New:** `OdysseyiOS/App/iOSAppState.swift`

`iOSAppState` is the iOS equivalent of `AppState`. Owns `RemoteSidecarManager`, handles incoming `SidecarEvent` stream, maintains streaming buffers per conversation, drives the conversation list.

```swift
@MainActor @Observable final class iOSAppState {
    var conversations: [ConversationSummary] = []
    var streamingBuffers: [UUID: String] = [:]
    var activeConversationId: UUID?
    var connectionStatus: SidecarStatus = .disconnected

    // Loaded from /api/v1/conversations after connect
    func loadConversations() async
    // Loaded from /api/v1/conversations/{id}/messages
    func loadMessages(for conversationId: UUID) async -> [MessageSummary]
    // Sends session.create (or session.resume if claudeSessionId stored)
    func startOrResumeSession(conversationId: UUID, agentConfig: AgentConfig) async throws
}
```

---

### 4e. App Navigation Structure

```
TabView
├── 💬  Conversations   →  ConversationListView
│                              └──► iOSChatView (per conversation)
├── 🤖  Agents          →  iOSAgentListView (read-only)
└── ⚙️  Settings        →  iOSSettingsView
                               ├── PairingView (QR scanner + paired Mac list)
                               └── ConnectionStatusView
```

---

### 4f. iOS Views

All pure SwiftUI, no AppKit. Reuse `MessageBubble`, `MarkdownContent`, `StreamingIndicator`, `ToolCallView` from `OdysseyCore`.

#### `ConversationListView`
**New:** `OdysseyiOS/Views/ConversationListView.swift`
- `List` of conversations from `iOSAppState.conversations` (loaded via `GET /api/v1/conversations`)
- Shows: topic, last message preview, timestamp, unread dot, participant avatar row with agent badge
- Pull-to-refresh calls `iOSAppState.loadConversations()`
- "+" button → `NewConversationSheet` (picks an agent, sends `session.create`)
- Tap row → `iOSChatView`

#### `iOSChatView`
**New:** `OdysseyiOS/Views/iOSChatView.swift`
- `ScrollView` + `LazyVStack` of `MessageBubble` from OdysseyCore
- Messages loaded via `GET /api/v1/conversations/{id}/messages?limit=50`; older messages loaded on scroll-to-top
- Native `TextEditor` input; "Send" button; streaming tokens update the last bubble in real-time
- `StreamingIndicator` (from OdysseyCore) shows agent "thinking…"
- @mention popup overlay: shows participant list filtered by `@` prefix
- Participant list button → sheet showing all participants with agent badges

#### `iOSAgentListView`
**New:** `OdysseyiOS/Views/iOSAgentListView.swift`
- Read-only list from `GET /api/v1/agents` (existing endpoint)
- Shows: name, icon/color, model, provider badge, running session count
- Tap → detail sheet: description, skills, capabilities; "New Chat" button starts a conversation

#### `NewConversationSheet`
**New:** `OdysseyiOS/Views/NewConversationSheet.swift`
- Picks one or more agents from the Mac's agent list
- Optional topic text field
- On confirm: calls `iOSAppState.startOrResumeSession()` → `session.create` via WS

#### `iOSPairingView`
**New:** `OdysseyiOS/Views/iOSPairingView.swift`
- Shown full-screen on first launch if no paired Mac
- `DataScannerViewController` (iOS 16+) for camera-based QR scanning
- "Paste invite link" button for manual entry
- On valid scan: `InviteCodeGenerator.decode()` + `verify()` → `PeerCredentialStore.save()` → connect
- Paired Mac list with "Last connected", connection method badge (LAN/WAN/Relay), "Revoke" button

#### `ConnectionStatusView`
**New:** `OdysseyiOS/Views/ConnectionStatusView.swift`
- Connection method badge: LAN / WAN Direct / Relay
- Round-trip latency (measured on 15s keepalive pings)
- Reconnect button; "Disconnect & Forget" option

---

### 4g. Conversation Data Bridge (Mac → Sidecar → iOS)

> **The critical architectural piece.** SwiftData lives on the Mac. iOS needs conversation history. Solution: Mac app pushes SwiftData snapshots to sidecar's new `ConversationStore`.

#### New sidecar commands (Swift → Sidecar)

```typescript
// sidecar/src/types.ts — new commands
| { type: "conversation.sync"; conversations: ConversationSummaryWire[] }
| { type: "conversation.messageAppend"; conversationId: string; message: MessageWire }
| { type: "conversation.create"; conversationId: string; topic: string; participants: ParticipantWire[] }
```

```typescript
interface ConversationSummaryWire {
    id: string;
    topic: string;
    lastMessageAt: string;         // ISO 8601
    lastMessagePreview: string;
    unread: boolean;
    participants: ParticipantWire[];
}

interface MessageWire {
    id: string;
    text: string;
    type: string;                  // MessageType raw value
    senderParticipantId: string | null;
    timestamp: string;
    isStreaming: boolean;
    toolName?: string;
    toolOutput?: string;
    thinkingText?: string;
}

interface ParticipantWire {
    id: string;
    displayName: string;
    isAgent: boolean;
    isLocal: boolean;
}
```

#### New sidecar store

**New:** `sidecar/src/stores/conversation-store.ts`

```typescript
class ConversationStore {
    private conversations: Map<string, ConversationSummaryWire> = new Map();
    private messages: Map<string, MessageWire[]> = new Map();    // conversationId → messages

    sync(conversations: ConversationSummaryWire[]): void
    appendMessage(conversationId: string, message: MessageWire): void
    listConversations(): ConversationSummaryWire[]
    getMessages(conversationId: string, limit?: number, before?: string): MessageWire[]
}
```

Persists to `~/.odyssey/instances/<name>/conversation-cache.json` on disk so iOS can load history even after sidecar restarts.

#### New HTTP endpoints (`sidecar/src/api-router.ts`)

```
GET  /api/v1/conversations                                → ConversationSummaryWire[]
GET  /api/v1/conversations/:id/messages?limit=50&before=  → MessageWire[]
```

These endpoints are read-only for iOS. All writes go through the existing WS `session.create` / `session.message` commands, which trigger the Mac Swift app to persist to SwiftData and push back via `conversation.messageAppend`.

#### Mac app trigger points (where to call `conversation.sync` / `conversation.messageAppend`)

| Trigger | Action |
|---|---|
| Sidecar connects (`.connected` event) | Send `conversation.sync` with last 50 conversations |
| `stream.token` finalizes → `session.result` | Send `conversation.messageAppend` with the full agent message |
| User sends a message (`session.message`) | Also send `conversation.messageAppend` with the user message |
| `conversation.create` from iOS client | Mac receives event, creates SwiftData Conversation, syncs back |

**Edit:** `Odyssey/Services/SidecarManager.swift` — add `pushConversationSync()` called on `.connected`
**Edit:** `AppState.handleEvent()` — add `conversation.messageAppend` push after `session.result`
**Edit:** `ChatView.swift` (or message send path) — add `conversation.messageAppend` push after user send
**Edit:** `sidecar/src/ws-server.ts` — add `conversation.sync`, `conversation.messageAppend`, `conversation.create` handlers

---

### 4h. Project & Working Directory Support on iOS

> Projects live in SwiftData on the Mac. The sidecar is unaware of them. iOS needs to browse available projects and associate new conversations with a project's `rootPath`.

**New sidecar command:**
```typescript
// sidecar/src/types.ts
| { type: "project.sync"; projects: ProjectSummaryWire[] }
```

```typescript
interface ProjectSummaryWire {
    id: string;           // UUID
    name: string;
    rootPath: string;     // Project.rootPath — becomes AgentConfig.workingDirectory
    icon: string;         // SF Symbol name
    color: string;
    isPinned: boolean;
    pinnedAgentIds: string[];
}
```

**New sidecar store:** `sidecar/src/stores/project-store.ts` — identical pattern to `ConversationStore`: in-memory map, populated via `project.sync` command, no disk persistence (rebuilt on every Mac connect).

**New HTTP endpoint:** `GET /api/v1/projects` → `ProjectSummaryWire[]`

**`ConversationSummaryWire` additions:**
```typescript
interface ConversationSummaryWire {
    // ... existing fields ...
    projectId: string | null;
    projectName: string | null;
    workingDirectory: string | null;   // from AgentConfig.workingDirectory
}
```

**Mac app trigger:** Push `project.sync` immediately after `conversation.sync` on sidecar connect.

**iOS UI changes:**

`NewConversationSheet` — gains a **Project** picker section:
- Fetches `GET /api/v1/projects` on sheet open
- Shows project list with icon + name; "No project (freeform)" option at top
- Selected project's `rootPath` is passed as `AgentConfig.workingDirectory` on `session.create`
- Pinned agents from the selected project are pre-selected in the agent picker

`iOSChatView` header / inspector area:
- Shows "📁 `<projectName>`" label with the working directory path in a monospace font
- Tapping shows a small sheet: project name, full path, pinned agents
- No file tree (Mac filesystem is not browsable from iOS); file tree is Mac-only

`ConversationListView` rows:
- Small project badge (icon + name in caption style) under the conversation topic for project-scoped conversations
- Freeform conversations show no badge

---

### 4i. Accessibility Identifiers for iOS Views

Per CLAUDE.md convention (`viewName.elementName` dot-separated camelCase). Add to CLAUDE.md prefix map:

| View | Prefix |
|---|---|
| `ConversationListView` | `iOSConversationList.*` |
| `iOSChatView` | `iOSChat.*` |
| `iOSAgentListView` | `iOSAgentList.*` |
| `NewConversationSheet` | `iOSNewConversation.*` |
| `iOSPairingView` | `iOSPairing.*` |
| `ConnectionStatusView` | `iOSConnectionStatus.*` |

Examples:
- `iOSConversationList.list`, `iOSConversationList.newButton`, `iOSConversationList.row.<id>`
- `iOSChat.messageList`, `iOSChat.inputField`, `iOSChat.sendButton`, `iOSChat.participantsButton`
- `iOSPairing.scannerView`, `iOSPairing.pasteButton`, `iOSPairing.pairedDeviceRow.<id>`

---

## Phase 5 — UX Enhancements

### 5a. Silent Observer Activation Mode

> Agents that see every message but never respond unsolicited. Ideal for logging, summarization, and analytics agents.

**Edit:** `Odyssey/Models/Participant.swift` — add `.silentObserver` to `ParticipantRole`
**Edit:** `Odyssey/Services/GroupPeerFanOutContext.swift` — for `.silentObserver`: inject transcript into session but skip response collection; does not count against `maxAdditionalSidecarTurns` budget
**Edit:** `Odyssey/Services/GroupRoutingPlanner.swift` — new routing branch for silent observers
**Edit:** Group member list views — show eye icon for silent observers; tooltip "Receives all messages, responds only when @mentioned"

The three modes:

| Mode | Sees messages | Responds unsolicited | Counts toward turn budget | Can be @mentioned |
|---|---|---|---|---|
| `active` | ✅ | ✅ | ✅ | ✅ |
| `observer` | ✅ | Budget-limited | ✅ | ✅ |
| `silentObserver` | ✅ | ❌ | ❌ | ✅ |

---

### 5b. Agent Ownership Display

> "Agent Name · by Owner" in group participant lists. Meaningful only once Phase 1a (identity keypairs) is in place — ownership is then cryptographically verifiable.

**Edit:** `Odyssey/Models/Participant.swift` — add `ownerDisplayName: String?` (denormalized for display, populated from `AgentIdentityBundle`)
**Edit:** Group participant list views:
```swift
// In participant row:
Text(participant.displayName)
if let owner = participant.ownerDisplayName {
    Text("· by \(owner)").foregroundStyle(.secondary).font(.caption)
}
if participant.isVerified { Image(systemName: "checkmark.seal.fill").foregroundStyle(.blue) }
```

`isVerified: Bool` — true if the remote agent's `AgentIdentityBundle` signature validates against the owner's known Ed25519 public key. Unverified remote agents show without the badge (backward-compatible with pre-Phase-1 peers).

---

## Phase 6 — Multi-User Federation

> Different users on different Macs sharing conversations with each other's agents.
> Builds on CloudKit `SharedRoomService` — adds Matrix alongside it, does not replace it.

### What This Unlocks

| Scenario | Before Phase 6 | After Phase 6 |
|---|---|---|
| Your Mac + your iPhone | ✅ Phase 4 | ✅ |
| Your Mac + colleague's Mac (LAN) | ✅ Existing | ✅ |
| Your Mac + colleague's Mac (WAN) | ✅ Phase 2 (STUN) | ✅ |
| Your iPhone + colleague's iPhone | ❌ | ✅ (each connects to own Mac; agents bridge via Matrix) |
| Offline queuing (Mac asleep) | ❌ | ✅ Matrix queues messages |
| iOS push when Mac is offline | ❌ | ✅ Matrix → APNS |
| Presence (who's online) | ❌ | ✅ Matrix presence API |

### How Existing Infrastructure Is Reused

The current `SharedRoomService` is solid for same-Apple-ID sync. Phase 6 adds Matrix transport as a second transport alongside CloudKit:

| Function | CloudKit (existing) | Matrix (new) |
|---|---|---|
| Same-Apple-ID sync | ✅ (unchanged) | — |
| LAN optimization hints | ✅ (unchanged) | — |
| Cross-user discovery | — | ✅ `@user:server` IDs |
| Cross-user messaging | — | ✅ Matrix room events |
| Offline message queuing | — | ✅ homeserver stores events |
| Presence | — | ✅ `/presence` API |
| iOS push notifications | — | ✅ Matrix → APNS push gateway |

---

### 6a. Transport Protocol Abstraction

**New:** `Packages/OdysseyCore/Sources/OdysseyCore/Transport/Transport.swift`
**New:** `Odyssey/Services/TransportManager.swift`
**Edit:** `Odyssey/Models/Conversation.swift` — add `roomOrigin: RoomOrigin`

```swift
// OdysseyCore — Transport.swift
protocol Transport: AnyObject, Sendable {
    var id: String { get }
    var displayName: String { get }
    var status: TransportStatus { get }
    var delegate: (any TransportDelegate)? { get set }

    func connect(credentials: TransportCredentials) async throws
    func disconnect() async
    func send(_ message: OutboundTransportMessage, to room: TransportRoomID) async throws
    func createRoom(participants: [RemoteIdentity], name: String?) async throws -> TransportRoomID
    func invite(_ identity: RemoteIdentity, to room: TransportRoomID) async throws
    func setPresence(_ presence: PresenceStatus) async throws
    func searchUsers(query: String) async throws -> [RemoteIdentity]
    var inbound: AsyncStream<InboundTransportMessage> { get }
}

struct RemoteIdentity: Codable, Hashable {
    let matrixId: String?           // "@user:matrix.org"
    let publicKeyData: Data?        // Ed25519 public key (from Phase 1)
    let displayName: String
    let isAgent: Bool
    let ownerIdentity: RemoteIdentity?  // for agents: their owner
}

enum RoomOrigin: Codable {
    case local                                      // no transport (existing local-only)
    case cloudKit                                   // existing CloudKit SharedRoomService
    case matrix(homeserver: String, roomId: String) // Phase 6
}
```

`TransportManager` routes outbound messages based on `conversation.roomOrigin` and delivers inbound to `SharedRoomService` for persistence. Existing `SharedRoomService` is lightly refactored to implement `Transport` as `CloudKitTransport`.

---

### 6b. Lightweight Matrix HTTP Client

**New:** `Odyssey/Services/MatrixClient.swift`

URLSession-based. Hits only the Matrix C-S API endpoints needed. No matrix-rust-sdk (too large: ~50 MB binary; complex build setup). Every call is a straightforward `URLSession.data(for:)`.

```swift
final class MatrixClient {
    init(homeserver: URL)

    // Auth
    // NOTE: matrix.org has disabled open registration since 2023. Users must:
    //   (a) provide their own homeserver URL (recommended default: matrix.org for login only), or
    //   (b) register on a homeserver that still allows it (matrix.org, element.io guest, etc.),
    //   (c) use an admin-provided registration token (homeserver-specific).
    // The register() method should gracefully handle M_FORBIDDEN/M_LIMIT_EXCEEDED and surface
    // "Registration failed — try a custom homeserver" in MatrixAccountView.
    func register(username: String, password: String, registrationToken: String? = nil) async throws -> MatrixCredentials
    func login(username: String, password: String) async throws -> MatrixCredentials
    // Token refresh: call when a request returns M_UNKNOWN_TOKEN (access token expired)
    func refreshToken(_ refreshToken: String) async throws -> MatrixCredentials

    // Sync (long-poll, 30s timeout; returns since token for next call)
    func sync(since: String?, timeout: Int = 30_000) async throws -> MatrixSyncResponse

    // Rooms
    func createRoom(name: String?, inviteUserIds: [String]) async throws -> String   // roomId
    func inviteUser(_ userId: String, to roomId: String) async throws
    func joinRoom(_ roomIdOrAlias: String) async throws
    func sendEvent(roomId: String, type: String, content: [String: Any]) async throws -> String // eventId

    // Presence
    func setPresence(status: String, statusMsg: String?) async throws
    func getPresence(userId: String) async throws -> MatrixPresence

    // Discovery
    func searchUsers(query: String) async throws -> [MatrixUser]
}

struct MatrixCredentials: Codable {
    let accessToken: String
    let refreshToken: String?   // nil on older homeservers that don't support refresh
    let deviceId: String        // must persist across restarts to avoid creating duplicate devices
    let userId: String          // "@user:homeserver"
    let homeserver: URL
}
```

**Persistence requirements for `MatrixCredentials`:**
- Store in Keychain under `odyssey.matrix.<instanceName>` (same Keychain layout as Phase 1).
- `deviceId` must survive app restarts — if lost, homeserver accumulates orphaned devices.
- `syncToken` (`nextBatch` from last sync response) must persist to disk so sync resumes from the right point after restart rather than replaying the entire event history.
- On M_UNKNOWN_TOKEN (401): attempt `refreshToken()` once; if that also fails, re-prompt for login credentials.

**Matrix registration reality check:**
- `matrix.org` has disabled open registration to prevent spam. The `MatrixAccountView` "Create account" button should default to showing a custom homeserver field, not assume `matrix.org`.
- Recommended default for users who want zero setup: link to [Element.io](https://app.element.io/#/register) for browser-based registration, then use `login()` in Odyssey with the resulting credentials.

**Matrix endpoints used:**

| Method | Endpoint | Purpose |
|---|---|---|
| POST | `/_matrix/client/v3/register` | Create agent bot account |
| POST | `/_matrix/client/v3/login` | User login |
| GET | `/_matrix/client/v3/sync?since=&timeout=30000` | Long-poll for events |
| POST | `/_matrix/client/v3/createRoom` | Create federated room |
| PUT | `/_matrix/client/v3/rooms/{id}/send/m.room.message/{txnId}` | Send message |
| POST | `/_matrix/client/v3/rooms/{id}/invite` | Invite user |
| GET/PUT | `/_matrix/client/v3/presence/{userId}/status` | Presence |
| POST | `/_matrix/client/v3/user_directory/search` | Find users |

**Message encoding:** Odyssey messages sent as `m.room.message` with `msgtype: "m.text"` + custom `odyssey` field:
```json
{
  "msgtype": "m.text",
  "body": "<plain text preview>",
  "odyssey": {
    "messageId": "...",
    "senderId": "...",
    "participantType": "agentSession",
    "agentBundle": { "..." }
  }
}
```

No Olm/Megolm E2EE in Phase 6. Content is already protected by Phase 1/2 Ed25519 signing + TLS. Matrix homeserver sees signed-but-readable content — acceptable for a developer tool.

---

### 6c. `MatrixTransport` Adapter

**New:** `Odyssey/Services/MatrixTransport.swift`

Implements `Transport` protocol using `MatrixClient`. Runs a background sync loop (`sync(since:)` long-poll). Converts Matrix room events to `InboundTransportMessage` and delivers via delegate. Handles backoff on network errors (2s → 4s → 8s → 30s cap).

```swift
// @MainActor — sync loop tasks are detached, but state mutations hop to main actor
@MainActor final class MatrixTransport: Transport {
    private let client: MatrixClient
    // Persisted to disk at ~/.odyssey/instances/<name>/matrix-sync-token.txt
    private var syncToken: String?
    private var syncTask: Task<Void, Never>?

    func connect(credentials: TransportCredentials) async throws {
        // restore persisted sync token if available
        syncToken = loadPersistedSyncToken()
        // login (or refresh token if stored credentials exist)
        // start sync loop
        syncTask = Task.detached(priority: .utility) { [weak self] in
            await self?.syncLoop()
        }
    }

    // Sync loop: long-poll → parse events → persist token → deliver → repeat
    private func syncLoop() async {
        while !Task.isCancelled {
            do {
                let response = try await client.sync(since: syncToken, timeout: 30_000)
                syncToken = response.nextBatch
                persistSyncToken(response.nextBatch)   // write to disk immediately
                for (roomId, roomData) in response.rooms.join {
                    for event in roomData.timeline.events {
                        await deliver(event, roomId: roomId)
                    }
                }
            } catch let error as MatrixError where error.code == "M_UNKNOWN_TOKEN" {
                // access token expired — attempt refresh, then retry
                do { try await client.refreshToken(storedRefreshToken) }
                catch { await backoff(max: 30) ; return }  // refresh failed → stop loop
            } catch {
                await backoff()
            }
        }
    }
}
```

---

### 6d. Cross-User Invite Flow

**Edit:** `Odyssey/Services/InviteCodeGenerator.swift` — `generateUser()` adds `matrixUserId` to payload
**New:** `Odyssey/Views/Pairing/UserInviteSheet.swift` — "Share Profile" sheet for user-to-user pairing
**Edit:** `Odyssey/Models/SharedRoomInvite.swift` — add `matrixRoomId`, `matrixHomeserver`, `peerMatrixUserId`

User invite payload (extends device invite payload with `type: "user"`):
```json
{
  "v": 1,
  "type": "user",
  "userPublicKey": "...",
  "displayName": "Shay",
  "matrixUserId": "@shay:matrix.org",
  "matrixHomeserver": "https://matrix.org",
  "hints": { "lan": "...", "wan": "..." },
  "exp": 1713000000,
  "sig": "..."
}
```

**Flow:**
1. User A: Settings → Federation → "Share Profile" → QR code / link
2. User B scans/taps → validates Ed25519 signature → stores User A's identity + Matrix ID
3. User B's Odyssey invites User A to a Matrix room
4. Both Macs join the Matrix room → messages route via P2P (STUN) when both online; Matrix relay when one offline
5. User A's agents appear in User B's group as `ParticipantType.remoteAgent(...)` with verified `AgentIdentityBundle`
6. Presence: each user's Mac updates Matrix presence on connect/disconnect → other users see online/offline badges

---

### 6e. Matrix Account Setup UI

**New:** `Odyssey/Views/Settings/MatrixAccountView.swift`

New section: **Settings → Federation → Matrix Account**

- **Homeserver field** (defaults to `https://matrix.org`) — users can enter any homeserver URL
- **"Sign in"** — login to existing Matrix account on the specified homeserver
- **"Create account"** — attempts `register()` on the homeserver; surfaces a clear error + fallback link if the homeserver has disabled open registration (most public servers have). Fallback message: *"Registration is disabled on this homeserver. Create a free account at [app.element.io](https://app.element.io/#/register), then sign in here."* Agent bot accounts use registration tokens from the same homeserver if configured.
- Shows: current `@user:server` identity, device ID, sync status, last sync timestamp, sync token stored (shows "synced to event X")
- **"Reset sync"** — clears persisted sync token; re-fetches all events from scratch (useful after device ID loss)
- **"Sign out"** — clears `MatrixCredentials` from Keychain; stops sync loop; leaves all joined rooms first
- Agent bot accounts: created automatically on first use; shown as sub-list "Your agents on Matrix" with per-agent `@agent-<name>:<server>` identity

---

### 6f. iOS Push Notifications via Matrix

**New:** `OdysseyiOS/Services/MatrixPushRegistration.swift`
**Edit:** `OdysseyiOS/App/OdysseyiOSApp.swift` — register for remote notifications on launch

iOS registers its APNS device token with the Mac. Mac configures a Matrix pusher via `POST /_matrix/client/v3/pushers/set` pointing to a public push gateway (Element's public Sygnal instance, or self-hosted).

When Mac is offline, Matrix delivers incoming messages to the push gateway, which forwards to APNS, which wakes the iPhone. Notification shows: conversation topic, sender name, message preview.

```swift
// OdysseyiOS/Services/MatrixPushRegistration.swift
struct MatrixPushRegistration {
    // Called by iOS app; sends APNS token to connected Mac via WS command
    static func registerAPNSToken(_ token: Data, via manager: RemoteSidecarManager) async throws
    // Mac side: sets up Matrix pusher for this iOS device
    static func configurePusher(apnsToken: String, matrixClient: MatrixClient) async throws
}
```

New WS command:
```typescript
| { type: "ios.registerPush"; apnsToken: string; appId: string }  // iOS → sidecar → Mac app
```

---

### 6g. Multi-User UI (macOS)

**Edit:** `Odyssey/Views/Settings/` — add **Federation** section (Matrix account, known peers, share profile button)
**Edit:** Group participant list views — presence dot on avatars (green/grey/yellow); ownership label with verified badge
**Edit:** Conversation list — "Offline" badge when a remote peer's Mac is offline with tooltip "Messages will be delivered when they reconnect"

---

## Files Changed Summary

| Phase | File | Type |
|---|---|---|
| 1a | `Odyssey/Services/IdentityManager.swift` | New |
| 1a | `Odyssey/Models/UserIdentity.swift` | New |
| 1a | `Odyssey/Models/Agent.swift` | Edit |
| 1b | `sidecar/src/ws-server.ts` | Edit |
| 1b | `Odyssey/Services/SidecarManager.swift` | Edit |
| 1c | `sidecar/src/index.ts` | Edit |
| 1c | `Odyssey/Services/SidecarManager.swift` | Edit |
| 2a | `Odyssey/Services/NATTraversalManager.swift` | New |
| 2a | `Odyssey/Services/P2PNetworkManager.swift` | Edit |
| 2b | `Odyssey/Services/InviteCodeGenerator.swift` | New |
| 2b | `Odyssey/Models/SharedRoomInvite.swift` | Edit |
| 2b | `Odyssey/Views/Settings/iOSPairingSettingsView.swift` | New |
| 2b | `Odyssey/App/LaunchIntent.swift` | Edit |
| 3 | `Packages/OdysseyCore/Package.swift` | New |
| 3 | `Packages/OdysseyCore/Sources/OdysseyCore/` | New |
| 3 | `project.yml` | Edit |
| 3 | `CLAUDE.md` | Edit — iOS accessibility prefix map |
| 4a | `project.yml` | Edit |
| 4a | `OdysseyiOS/Resources/OdysseyiOS.entitlements` | New |
| 4a | `OdysseyiOS/Resources/Info.plist` | New |
| 4b | `OdysseyiOS/Services/RemoteSidecarManager.swift` | New |
| 4c | `OdysseyiOS/Services/PeerCredentialStore.swift` | New |
| 4d | `OdysseyiOS/App/OdysseyiOSApp.swift` | New |
| 4d | `OdysseyiOS/App/iOSAppState.swift` | New |
| 4e | `OdysseyiOS/Views/ConversationListView.swift` | New |
| 4e | `OdysseyiOS/Views/iOSChatView.swift` | New |
| 4e | `OdysseyiOS/Views/iOSAgentListView.swift` | New |
| 4e | `OdysseyiOS/Views/NewConversationSheet.swift` | New |
| 4e | `OdysseyiOS/Views/iOSPairingView.swift` | New |
| 4e | `OdysseyiOS/Views/ConnectionStatusView.swift` | New |
| 4g | `sidecar/src/stores/conversation-store.ts` | New |
| 4g | `sidecar/src/types.ts` | Edit — new commands |
| 4g | `sidecar/src/ws-server.ts` | Edit — new command handlers |
| 4g | `sidecar/src/api-router.ts` | Edit — new conversation endpoints |
| 4g | `Odyssey/Services/SidecarManager.swift` | Edit — push conversation + project sync on connect |
| 4g | `Odyssey/App/AppState.swift` | Edit — push messageAppend on result/send |
| 4h | `sidecar/src/stores/project-store.ts` | New |
| 4h | `sidecar/src/types.ts` | Edit — `project.sync` command + `ProjectSummaryWire` |
| 4h | `sidecar/src/ws-server.ts` | Edit — `project.sync` handler |
| 4h | `sidecar/src/api-router.ts` | Edit — `GET /api/v1/projects` |
| 5a | `Odyssey/Models/Participant.swift` | Edit |
| 5a | `Odyssey/Services/GroupPeerFanOutContext.swift` | Edit |
| 5a | `Odyssey/Services/GroupRoutingPlanner.swift` | Edit |
| 5b | Group participant list views | Edit |
| 6a | `Packages/OdysseyCore/.../Transport/Transport.swift` | New |
| 6a | `Odyssey/Services/TransportManager.swift` | New |
| 6a | `Odyssey/Models/Conversation.swift` | Edit — `roomOrigin` |
| 6b | `Odyssey/Services/MatrixClient.swift` | New |
| 6c | `Odyssey/Services/MatrixTransport.swift` | New |
| 6d | `Odyssey/Services/InviteCodeGenerator.swift` | Edit |
| 6d | `Odyssey/Views/Pairing/UserInviteSheet.swift` | New |
| 6d | `Odyssey/Models/SharedRoomInvite.swift` | Edit |
| 6e | `Odyssey/Views/Settings/MatrixAccountView.swift` | New |
| 6f | `OdysseyiOS/Services/MatrixPushRegistration.swift` | New |
| 6f | `OdysseyiOS/App/OdysseyiOSApp.swift` | Edit |
| 6g | `Odyssey/Views/Settings/` | Edit |

---

## Dependency Order

```
Phase 1 (Security)
  └─► Phase 2 (Discovery)
        └─► Phase 3 (OdysseyCore)
              ├─► Phase 4 (iOS App)        ← needs 3 to compile
              ├─► Phase 5 (UX)             ← can start after 3, independent of 4
              └─► Phase 6 (Federation)     ← needs 4 for iOS push; needs 1a for crypto
```

Within Phase 1: **1a → 1b and 1c** (1b and 1c both depend on 1a's infrastructure).

---

## Open Questions

1. **TURN relay default:** Ship with Metered.ca free tier as the out-of-box TURN config (500 MB/mo covers most personal use), with a Settings field for custom `turn:` URI + credentials. Users who want full control run coturn via Docker.

2. **Matrix homeserver:** `matrix.org` has disabled open registration. Default UI: homeserver field pre-filled with `https://matrix.org` for login; for new accounts, link to [app.element.io](https://app.element.io/#/register). Custom homeserver is the only option for automated agent-bot registration.

3. **Agent Matrix bot accounts:** Should each agent have its own `@agent-<name>:server` Matrix identity for independent presence and discoverability? Adds management complexity but enables per-agent online status.

4. **Key rotation:** If the WS bearer token leaks, users need "Revoke all paired iOS devices" in Mac Settings → iOS Pairing. Rotation regenerates the token; existing iOS credentials become invalid.

5. **Multiple Macs on iOS:** If a user has both a MacBook and a Mac Studio, the iPhone should show both Macs and let the user pick (or show a merged conversation view). `PeerCredentialStore` supports multiple `PeerCredentials` already.

6. **Conversation history depth:** How many messages does `conversation-store.ts` cache per conversation? Recommend: last 200 messages per conversation, configurable.

7. **Message E2EE (future):** Matrix messages in Phase 6 are signed (Ed25519) but readable by the homeserver. Adding Olm/Megolm would protect content from homeserver operators. Deferred — acceptable for a developer tool initially.

8. **App Store review:** The iOS app connects to a user-controlled server (their own Mac) over local/VPN network. This is analogous to SSH or remote desktop apps, which are App Store-approved. No special entitlements needed beyond the network client entitlement.

---

## Testing

Odyssey uses three complementary testing layers (see `TESTING.md`): **XCTest** (unit + integration), **AppXray** (inside-out live app state), and **Argus** (outside-in E2E macOS automation). iOS tests add a fourth layer: **iOS Simulator XCTest** and **Argus mobile** via `device({ action: "allocate", platform: "ios" })`.

---

### Phase 1 — Security Foundation Tests

#### XCTest — `OdysseyTests/IdentityManagerTests.swift` (new)

| Test | What it verifies |
|---|---|
| `testKeypairGenerationAndPersistence` | `userIdentity()` returns the same key on second call (loaded from Keychain) |
| `testSignAndVerify` | `sign()` output verifies with the corresponding public key |
| `testAgentBundleSignature` | `agentBundle()` owner signature verifies against owner public key |
| `testWSTokenFormat` | `wsToken()` returns 32-byte base64, stable across calls |
| `testTLSCertGeneration` | `tlsCertificate()` returns valid DER bytes parseable by `SecCertificateCreateWithData` |
| `testDistinctInstancesHaveDifferentKeys` | Two different `InstanceConfig` names produce different keypairs |
| `testKeychainIsolation` | Deleting one instance's keys doesn't affect another instance |

#### Sidecar unit — `sidecar/test/unit/ws-auth.test.ts` (new)

| Test | What it verifies |
|---|---|
| `rejectsConnectionWithoutToken` | WS server closes with 4401 when `ODYSSEY_WS_TOKEN` is set and header is missing |
| `rejectsConnectionWithWrongToken` | WS server closes with 4401 on wrong bearer token |
| `acceptsConnectionWithCorrectToken` | WS server sends `sidecar.ready` on correct token |
| `allowsAllConnectionsWhenTokenUnset` | When `ODYSSEY_WS_TOKEN` is unset, no auth check occurs (backward compat) |

#### Sidecar integration — `sidecar/test/integration/tls.test.ts` (new)

| Test | What it verifies |
|---|---|
| `tlsUpgradeWithValidCert` | `wss://` connection succeeds with self-signed cert when client pins it |
| `tlsRejectsUnpinnedCert` | Connection fails when client doesn't trust the cert |
| `fallbackToPlainWSWhenNoCert` | When `ODYSSEY_TLS_CERT` unset, sidecar binds plain `ws://` |

---

### Phase 2 — Cross-Network Discovery Tests

#### XCTest — `OdysseyTests/NATTraversalTests.swift` (new)

| Test | What it verifies |
|---|---|
| `testSTUNRequestEncoding` | STUN Binding Request bytes match RFC 5389 format |
| `testSTUNResponseParsing` | Parses a known-good STUN Binding Response byte sequence to correct IP:port |
| `testSTUNResponseParsing_IPv6` | Handles IPv6 mapped addresses |
| `testPublicEndpointDiscovery` | Integration: contacts real STUN server (marked `@network`, skipped in CI) |

#### XCTest — `OdysseyTests/InviteCodeTests.swift` (new)

| Test | What it verifies |
|---|---|
| `testDeviceInviteRoundTrip` | `generate()` → `decode()` → `verify()` succeeds |
| `testUserInviteRoundTrip` | Same for `type: "user"` with `matrixUserId` |
| `testExpiredInviteRejected` | `verify()` throws when `exp` is in the past |
| `testTamperedInviteRejected` | `verify()` throws when `displayName` modified after signing |
| `testSingleUseSemantics` | Verify `singleUse: true` field serializes/deserializes correctly |
| `testQRCodeProducesValidImage` | `qrCode()` returns non-nil `CGImage` |
| `testDeepLinkParsing` | `LaunchIntent.fromURL("odyssey://connect?invite=...")` sets `connectInvite` |
| `testBase64UrlEncoding` | Encoded payload survives URL round-trip without padding issues |

#### XCTest — `OdysseyTests/CloudKitRelayTests.swift` (new)

| Test | What it verifies |
|---|---|
| `testRelayRecordEncoding` | `OdysseyRelay` CKRecord fields encode/decode payload bytes correctly |
| `testSequenceOrdering` | Records with higher `sequenceId` are processed last |
| `testTTLCleanup` | Records older than 5 minutes are flagged for deletion |

---

### Phase 3 — OdysseyCore Package Tests

#### Build validation

| Check | How |
|---|---|
| iOS Simulator build | `xcodebuild build -scheme OdysseyiOS -destination 'platform=iOS Simulator,name=iPhone 16'` — must compile with zero AppKit errors |
| macOS build unchanged | `xcodebuild build -scheme Odyssey` — existing tests still pass |
| Package isolation | `swift build` inside `Packages/OdysseyCore/` — no `#if os(macOS)` leaks |

#### XCTest — `OdysseyTests/SidecarProtocolTests.swift` (extend existing)

| Test | What it verifies |
|---|---|
| `testNewCommandsRoundTrip` | `conversation.sync`, `project.sync`, `conversation.messageAppend` encode/decode without loss |
| `testAgentListCommandEncoding` | `agent.list` command serializes correctly |
| `testConversationSummaryWireDecoding` | `ConversationSummaryWire` JSON decodes with all new fields (projectId, workingDirectory) |

---

### Phase 4 — iOS App Tests

#### XCTest (iOS target) — `OdysseyiOSTests/RemoteSidecarManagerTests.swift` (new)

Uses a local mock WS server (Bun test helper or `Network.framework` listener in Swift).

| Test | What it verifies |
|---|---|
| `testConnectsWithCorrectToken` | `RemoteSidecarManager.connect()` sends correct bearer token |
| `testRejectsOnWrongToken` | Closes and emits `.disconnected` when server closes 4401 |
| `testReconnectsAfterDrop` | On WS drop, reconnects within 2 seconds |
| `testCertPinningRejectsWrongCert` | Connection refused if server presents different cert than stored |
| `testCommandEncodingMatchesMac` | Commands encoded by `RemoteSidecarManager` are byte-identical to Mac `SidecarManager` |
| `testEventStreamDelivery` | Incoming events appear on the `events` `AsyncStream` |
| `testConnectionPriorityOrder` | LAN hint tried before WAN hint; WAN tried before CloudKit relay |

#### XCTest (iOS target) — `OdysseyiOSTests/PeerCredentialStoreTests.swift` (new)

| Test | What it verifies |
|---|---|
| `testSaveAndLoad` | Saved `PeerCredentials` round-trips through Keychain |
| `testMultiplePeers` | Two credentials stored under different IDs both retrievable |
| `testDeleteRemovesPeer` | Deleted credential no longer appears in `load()` |
| `testSessionIdPersistence` | `claudeSessionIds` dict persists across store reinit |

#### XCTest (iOS target) — `OdysseyiOSTests/iOSAppStateTests.swift` (new)

| Test | What it verifies |
|---|---|
| `testConversationListParsing` | `loadConversations()` parses mock HTTP response correctly |
| `testMessageHistoryParsing` | `loadMessages()` parses mock response; preserves order |
| `testProjectContextOnNewConversation` | `startOrResumeSession()` passes project `rootPath` as `workingDirectory` |
| `testSessionResumeWhenClaudeSessionIdStored` | Sends `session.resume` instead of `session.create` when ID is stored |
| `testStreamingTokensUpdateBuffer` | `stream.token` events accumulate in `streamingBuffers[conversationId]` |

#### Sidecar unit — `sidecar/test/unit/conversation-store.test.ts` (new)

| Test | What it verifies |
|---|---|
| `testSyncPopulatesStore` | `sync([...])` makes conversations available via `listConversations()` |
| `testAppendAddsMessage` | `appendMessage()` appends and appears in `getMessages()` |
| `testMessageOrdering` | Messages returned in timestamp order |
| `testLimitAndBefore` | `getMessages(id, limit: 10, before: ts)` returns correct slice |
| `testDiskPersistence` | Store survives reinit by reading from cache file |

#### Sidecar unit — `sidecar/test/unit/project-store.test.ts` (new)

| Test | What it verifies |
|---|---|
| `testProjectSyncPopulatesStore` | `project.sync` command populates `GET /api/v1/projects` |
| `testWorkingDirectoryInConversation` | Conversation with `workingDirectory` returns it in summary wire |

#### Sidecar API — `sidecar/test/api/http-api.test.ts` (extend existing)

| Test | What it verifies |
|---|---|
| `GET /api/v1/conversations returns 200` | Returns array of `ConversationSummaryWire` after `conversation.sync` |
| `GET /api/v1/conversations/:id/messages` | Returns `MessageWire[]` in order |
| `GET /api/v1/projects returns 200` | Returns `ProjectSummaryWire[]` after `project.sync` |
| `GET /api/v1/conversations 401 without token` | Returns 401 when WS auth is configured |

#### AppXray — iOS pairing flow (inside-out)

```javascript
// Validate iOS pairing view state after scanning invite
inspect({ platform: "ios", token })
// Assert PairingView is shown on first launch
assert({ selector: "@testId('iOSPairing.scannerView')", visible: true })
// Inject mock valid invite code
act({ action: "tap", selector: "@testId('iOSPairing.pasteButton')" })
act({ action: "type", selector: "@label('Invite Link')", text: mockInviteUrl })
// Assert connection status changes to connected
wait({ condition: "elementVisible", selector: "@testId('iOSConnectionStatus.connectedBadge')" })
```

#### Argus E2E — `OdysseyiOSTests/e2e/pairing-flow.test.ts` (new)

```yaml
# argus/e2e/ios-pairing.yaml
name: iOS pairing and first chat
steps:
  - device: { platform: ios, app: "com.odyssey.app.ios" }
  - assert: { selector: "@testId('iOSPairing.scannerView')", visible: true }
  - act: { action: tap, selector: "@testId('iOSPairing.pasteButton')" }
  - act: { action: type, selector: "@label('Invite Link')", text: "$ODYSSEY_TEST_INVITE" }
  - wait: { selector: "@testId('iOSConversationList.list')", timeout: 10000 }
  - act: { action: tap, selector: "@testId('iOSConversationList.newButton')" }
  - wait: { selector: "@testId('iOSNewConversation.agentList')" }
  - act: { action: tap, selector: "@testId('iOSNewConversation.agentRow.0')" }
  - act: { action: tap, selector: "@testId('iOSNewConversation.confirmButton')" }
  - wait: { selector: "@testId('iOSChat.messageList')" }
  - act: { action: type, selector: "@testId('iOSChat.inputField')", text: "Hello" }
  - act: { action: tap, selector: "@testId('iOSChat.sendButton')" }
  - wait: { selector: "@testId('iOSChat.streamingIndicator')", timeout: 30000 }
  - assert: { selector: "@testId('iOSChat.messageList')", minChildren: 2 }
```

---

### Phase 5 — UX Enhancement Tests

#### XCTest — `OdysseyTests/GroupPromptBuilderTests.swift` (extend existing)

| Test | What it verifies |
|---|---|
| `testSilentObserverReceivesTranscriptNotResponse` | Fan-out delivers to `.silentObserver` participants but doesn't await response |
| `testSilentObserverNotCountedInBudget` | Budget counter unchanged after silent observer fan-out |
| `testSilentObserverRespondsTOAtMention` | When `.silentObserver` is @mentioned, `addressedToMe = true` is set |
| `testOwnerDisplayNameFromBundle` | `Participant.ownerDisplayName` resolves correctly from `AgentIdentityBundle` |
| `testVerifiedBadgeWithValidBundle` | `isVerified = true` when bundle signature validates |
| `testUnverifiedBadgeWithTamperedBundle` | `isVerified = false` when bundle signature fails |

---

### Phase 6 — Multi-User Federation Tests

#### XCTest — `OdysseyTests/MatrixClientTests.swift` (new)

Uses `URLProtocol` stub to mock Matrix HTTP responses — no real homeserver needed for unit tests.

| Test | What it verifies |
|---|---|
| `testLoginRequestFormat` | POST to `/_matrix/client/v3/login` has correct JSON body |
| `testSyncParsesRoomEvents` | `sync()` parses a minimal Matrix sync response with `m.room.message` events |
| `testSendEventBuildsTxnId` | Each `sendEvent()` call uses a unique `txnId` |
| `testPresenceUpdateRequest` | `setPresence()` sends correct PUT to presence endpoint |
| `testUserSearchParsesResults` | `searchUsers()` parses `user_directory/search` response |
| `testSyncBackoffOnError` | `MatrixTransport` sync loop backs off on 5xx errors |
| `testSyncResumeFromToken` | After first sync, `since` token is passed on next call |

#### XCTest — `OdysseyTests/TransportManagerTests.swift` (new)

| Test | What it verifies |
|---|---|
| `testCloudKitOriginRoutesToCloudKit` | `TransportManager.publish()` calls `CloudKitTransport` for `.cloudKit` rooms |
| `testMatrixOriginRoutesToMatrix` | Routes to `MatrixTransport` for `.matrix(...)` rooms |
| `testLocalOriginIsNoOp` | `.local` rooms don't trigger any transport send |
| `testInboundDeliveredToSharedRoomService` | Matrix inbound events are forwarded to `CloudKitRoomService` for persistence |

#### XCTest — `OdysseyTests/InviteCodeTests.swift` (extend)

| Test | What it verifies |
|---|---|
| `testUserInviteIncludesMatrixId` | `generateUser()` payload contains `matrixUserId` |
| `testUserInviteVerifiesSignature` | Tampered `matrixUserId` fails `verify()` |

#### Sidecar integration — `sidecar/test/integration/matrix-transport.test.ts` (new)

Uses a mock Matrix server (Bun HTTP mock) — no live homeserver needed.

| Test | What it verifies |
|---|---|
| `connectAndSyncLoop` | `MatrixTransport.connect()` starts sync loop; events delivered to delegate |
| `sendMessageEncodesOdysseyField` | Sent `m.room.message` contains `odyssey` custom field |
| `receivedEventDecodedCorrectly` | Incoming Matrix event with `odyssey` field decoded to `InboundTransportMessage` |
| `syncTokenPersisted` | `nextBatch` token from sync response used as `since` in next poll |

#### Argus E2E — cross-user federation smoke test

```yaml
# argus/e2e/federation.yaml
name: Two Odyssey instances federate via Matrix
# Requires: two Mac instances running, both signed in to Matrix
steps:
  - session: { app: "Odyssey", instance: "instanceA" }
  - act: { action: click, selector: "@testId('sidebar.newThreadButton')" }
  - act: { action: click, selector: "@testId('chat.inputField')" }
  - act: { action: type, text: "Hello from Instance A" }
  - act: { action: click, selector: "@testId('chat.sendButton')" }
  - session: { app: "Odyssey", instance: "instanceB" }
  - wait: { selector: "@text('Hello from Instance A')", timeout: 15000 }
  - assert: { selector: "@testId('sidebar.conversationList')", minChildren: 1 }
```

---

### Test Infrastructure

#### Mock WS Server (`sidecar/test/helpers/mock-ws-server.ts`)

Reusable Bun WebSocket server for `RemoteSidecarManager` and auth tests:
```typescript
export function createMockWSServer(opts: {
    token?: string;
    tlsCert?: string;
    onCommand?: (cmd: SidecarCommand) => SidecarEvent[];
}): { url: string; close: () => void }
```

#### Mock Matrix Server (`sidecar/test/helpers/mock-matrix-server.ts`)

Minimal Bun HTTP server that responds to the Matrix endpoints used:
```typescript
export function createMockMatrixServer(opts: {
    userId: string;
    roomEvents?: MatrixRoomEvent[];
}): { baseUrl: string; close: () => void }
```

#### iOS Test Fixtures (`OdysseyiOSTests/Fixtures/`)

| File | Content |
|---|---|
| `TestPeerCredentials.swift` | Pre-built `PeerCredentials` with test cert + token |
| `TestInvitePayload.swift` | Signed invite payload using a deterministic test keypair |
| `MockRemoteSidecarManager.swift` | In-memory manager that replays recorded events for UI tests |
| `TestConversations.swift` | Sample `ConversationSummaryWire` and `MessageWire` arrays |

#### CI Test Matrix

| Suite | When | Command |
|---|---|---|
| Mac XCTest | Every PR | `xcodebuild test -scheme Odyssey -destination 'platform=macOS'` |
| iOS XCTest (Simulator) | Every PR | `xcodebuild test -scheme OdysseyiOS -destination 'platform=iOS Simulator,name=iPhone 16'` |
| Sidecar unit tests | Every PR | `cd sidecar && bun test sidecar/test/unit/` |
| Sidecar integration tests | Every PR | `cd sidecar && bun test sidecar/test/integration/` |
| Sidecar API tests | Every PR | `cd sidecar && bun test sidecar/test/api/` |
| Argus E2E (macOS) | Nightly | `argus run argus/e2e/*.yaml` |
| Argus E2E (iOS device) | Nightly | `argus run --platform ios argus/e2e/ios-*.yaml` |
| Network integration tests | Manual / `@network` tag | STUN, CloudKit relay, Matrix live homeserver |
