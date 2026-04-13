# Phase 3 — OdysseyCore Shared Swift Package Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract shared Codable types and SwiftUI views into a cross-platform Swift package that both macOS and iOS targets can import.

**Architecture:** OdysseyCore is a pure Swift package (no AppKit/UIKit in the shared layer). SwiftData `@Model` classes stay in the macOS target. Platform-specific code uses `#if os(macOS)`/`#if os(iOS)` guards. The Mac target gains OdysseyCore as a dependency; Phase 4's iOS target will also depend on it.

**Tech Stack:** Swift Package Manager, SwiftUI, swift-markdown-ui, xcodebuild, XcodeGen

---

## Source File Analysis (Read Before Writing Code)

The following analysis was performed by reading the existing source files. This section is the reference for what platform guards are required.

### `Odyssey/Views/Components/MessageBubble.swift` — Analysis

**Platform-specific dependencies found:**

1. `import AppKit` at line 2 — needed only for `NSPasteboard` in `copyMessage()`
2. `NSPasteboard.general.clearContents()` and `NSPasteboard.general.setString(...)` at lines 323–324 — clipboard write is macOS-only
3. `Color(.textBackgroundColor)` at line 116 — NSColor semantic color, macOS-only
4. `AppKit.NSColor` semantic via `Color(.textBackgroundColor)` initialiser — unavailable on iOS
5. Depends on `ConversationMessage` and `Participant` — both are `@Model` SwiftData classes, **cannot be shared**
6. Depends on `MessageAttachment` — also a `@Model` SwiftData class, **cannot be shared**
7. Depends on `AttachmentThumbnail`, `ToolCallView`, `MermaidDiagramView`, `InlineHTMLCard`, `AnsweredQuestionBubble`, `RichContentOpener` — all macOS-only sub-views
8. Uses `.xrayId(...)` — from `AppXray` which is macOS-only (debug only)
9. Uses `@Environment(\.appTextScale)` — environment key defined in `AppSettings.swift` (Mac target)

**Verdict:** `MessageBubble` is **deeply coupled to SwiftData `@Model` types and macOS-only sub-views**. It cannot be moved into OdysseyCore as-is. OdysseyCore will instead contain a **wire-type-backed** `MessageBubbleCore` view that operates on `MessageWire` (the Codable struct) rather than `ConversationMessage`. The full `MessageBubble` stays in the macOS target and is not modified.

### `Odyssey/Views/Components/StreamingIndicator.swift` — Analysis

```swift
import SwiftUI

struct StreamingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(.secondary)
                    .frame(width: 5, height: 5)
                    .scaleEffect(animating ? 1.0 : 0.5)
                    .opacity(animating ? 1.0 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(index) * 0.2),
                        value: animating
                    )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .onAppear { animating = true }
        .xrayId("streamingIndicator")
        .accessibilityLabel("Loading")
        .accessibilityElement(children: .ignore)
    }
}
```

**Platform-specific dependencies found:**

1. `.xrayId("streamingIndicator")` — from `AppXray`, macOS-only

**Verdict:** 99% pure SwiftUI. The only change needed is to wrap `.xrayId(...)` in a `#if os(macOS)` guard so the iOS build does not depend on `AppXray`. The rest of the view compiles cleanly on both platforms.

### `Odyssey/Views/Components/MarkdownContent.swift` — Analysis

**Platform-specific dependencies found:**

1. `import AppKit` at line 3
2. `NSWorkspace.shared.open(url)` at line 55 in `handleOpenURL()` — macOS-only URL opener; iOS equivalent is `UIApplication.shared.open(url)`
3. `Color(.textBackgroundColor)` in the `odyssey(scale:)` theme extension at line 410 — macOS NSColor semantic
4. `NSRegularExpression`, `NSString`, `NSRange` in `AdmonitionParser.extractBlocks()` at lines 262–277 — Foundation types available on both platforms; no guard needed
5. `@AppStorage(AppSettings.renderAdmonitionsKey, store: AppSettings.store)` at line 8 — references `AppSettings` which is in the Mac target; needs a guard or abstraction
6. `@Environment(\.appTextScale)` — environment key defined in Mac-only `AppSettings.swift`

**Verdict:** Three areas require `#if os(macOS)` guards:
- `handleOpenURL`: `NSWorkspace` call → replace with `#if os(macOS)` / `#if os(iOS)` block
- `odyssey(scale:)` theme: `Color(.textBackgroundColor)` → use `Color(.systemBackground)` equivalent per platform
- `@AppStorage` and `appTextScale` environment key: OdysseyCore must re-declare the environment key internally (or accept `scale` as a parameter)

---

## File Structure

```
Packages/OdysseyCore/
├── Package.swift
└── Sources/OdysseyCore/
    ├── Protocol/
    │   └── WireTypes.swift              ← Codable wire model structs for REST API responses
    ├── Identity/
    │   └── IdentityTypes.swift          ← UserIdentity, AgentIdentityBundle, TLSBundle
    ├── Networking/
    │   └── InviteTypes.swift            ← InvitePayload, InviteHints, TURNConfig
    └── Views/
        ├── StreamingIndicator.swift     ← copy from Odyssey/Views/Components/, add #if guard
        ├── MarkdownContentCore.swift    ← adapted MarkdownContent without AppSettings/AppKit deps
        └── MessageBubbleCore.swift      ← new: operates on MessageWire, not ConversationMessage
Tests/OdysseyCoreTes ts/
    └── WireTypesCodableTests.swift      ← Codable round-trip tests
```

**Files NOT modified** in this phase:
- `Odyssey/Views/Components/MessageBubble.swift` — stays in Mac target unchanged
- `Odyssey/Views/Components/StreamingIndicator.swift` — stays in Mac target unchanged (OdysseyCore gets a copy)
- `Odyssey/Views/Components/MarkdownContent.swift` — stays in Mac target unchanged (OdysseyCore gets an adapted copy)
- Any `@Model` classes

---

## Task 1: Create Package Directory Structure

- [ ] **Step 1.1: Create `Packages/OdysseyCore/` directory tree**

  ```bash
  mkdir -p /Users/shayco/Odyssey/Packages/OdysseyCore/Sources/OdysseyCore/Protocol
  mkdir -p /Users/shayco/Odyssey/Packages/OdysseyCore/Sources/OdysseyCore/Identity
  mkdir -p /Users/shayco/Odyssey/Packages/OdysseyCore/Sources/OdysseyCore/Networking
  mkdir -p /Users/shayco/Odyssey/Packages/OdysseyCore/Sources/OdysseyCore/Views
  mkdir -p /Users/shayco/Odyssey/Packages/OdysseyCore/Tests/OdysseyCoreTests
  ```

- [ ] **Step 1.2: Create `Packages/OdysseyCore/Package.swift`**

  ```swift
  // swift-tools-version: 5.9
  import PackageDescription

  let package = Package(
      name: "OdysseyCore",
      platforms: [.macOS(.v14), .iOS(.v17)],
      products: [
          .library(name: "OdysseyCore", targets: ["OdysseyCore"]),
      ],
      dependencies: [
          .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.1"),
      ],
      targets: [
          .target(
              name: "OdysseyCore",
              dependencies: [
                  .product(name: "MarkdownUI", package: "swift-markdown-ui"),
              ]
          ),
          .testTarget(
              name: "OdysseyCoreTests",
              dependencies: ["OdysseyCore"]
          ),
      ]
  )
  ```

---

## Task 2: Protocol Wire Types

These are new Codable structs that do not currently exist in the codebase. They will be used by the iOS target to decode REST API responses from the Mac sidecar.

- [ ] **Step 2.1: Create `Packages/OdysseyCore/Sources/OdysseyCore/Protocol/WireTypes.swift`**

  ```swift
  // Sources/OdysseyCore/Protocol/WireTypes.swift
  import Foundation

  /// Wire representation of a conversation/thread as returned by the REST API.
  /// The iOS app reads these from GET /api/v1/conversations.
  public struct ConversationSummaryWire: Codable, Sendable, Identifiable {
      public let id: String
      public let topic: String
      /// ISO 8601 timestamp string, e.g. "2026-04-13T10:00:00Z"
      public let lastMessageAt: String
      public let lastMessagePreview: String
      public let unread: Bool
      public let participants: [ParticipantWire]
      public let projectId: String?
      public let projectName: String?
      public let workingDirectory: String?

      public init(
          id: String,
          topic: String,
          lastMessageAt: String,
          lastMessagePreview: String,
          unread: Bool,
          participants: [ParticipantWire],
          projectId: String?,
          projectName: String?,
          workingDirectory: String?
      ) {
          self.id = id
          self.topic = topic
          self.lastMessageAt = lastMessageAt
          self.lastMessagePreview = lastMessagePreview
          self.unread = unread
          self.participants = participants
          self.projectId = projectId
          self.projectName = projectName
          self.workingDirectory = workingDirectory
      }
  }

  /// Wire representation of a single message as returned by the REST API.
  /// The iOS app reads these from GET /api/v1/conversations/{id}/messages.
  public struct MessageWire: Codable, Sendable, Identifiable {
      public let id: String
      public let text: String
      /// Message type raw value: "chat", "toolCall", "toolResult", "system", etc.
      public let type: String
      public let senderParticipantId: String?
      /// ISO 8601 timestamp string
      public let timestamp: String
      public let isStreaming: Bool
      /// Present when type == "toolCall" — the tool name
      public let toolName: String?
      /// Present when type == "toolResult" — the tool output
      public let toolOutput: String?
      /// Extended thinking text, if any
      public let thinkingText: String?

      public init(
          id: String,
          text: String,
          type: String,
          senderParticipantId: String?,
          timestamp: String,
          isStreaming: Bool,
          toolName: String?,
          toolOutput: String?,
          thinkingText: String?
      ) {
          self.id = id
          self.text = text
          self.type = type
          self.senderParticipantId = senderParticipantId
          self.timestamp = timestamp
          self.isStreaming = isStreaming
          self.toolName = toolName
          self.toolOutput = toolOutput
          self.thinkingText = thinkingText
      }
  }

  /// Wire representation of a conversation participant.
  public struct ParticipantWire: Codable, Sendable {
      public let id: String
      public let displayName: String
      public let isAgent: Bool
      /// True if this participant is the local Mac user (as opposed to a remote peer).
      public let isLocal: Bool

      public init(id: String, displayName: String, isAgent: Bool, isLocal: Bool) {
          self.id = id
          self.displayName = displayName
          self.isAgent = isAgent
          self.isLocal = isLocal
      }
  }

  /// Wire representation of a project as returned by GET /api/v1/projects.
  public struct ProjectSummaryWire: Codable, Sendable, Identifiable {
      public let id: String
      public let name: String
      public let rootPath: String
      public let icon: String
      public let color: String
      public let isPinned: Bool
      public let pinnedAgentIds: [String]

      public init(
          id: String,
          name: String,
          rootPath: String,
          icon: String,
          color: String,
          isPinned: Bool,
          pinnedAgentIds: [String]
      ) {
          self.id = id
          self.name = name
          self.rootPath = rootPath
          self.icon = icon
          self.color = color
          self.isPinned = isPinned
          self.pinnedAgentIds = pinnedAgentIds
      }
  }
  ```

---

## Task 3: Identity Types

These types are specified in Phase 1 but do not yet exist in the codebase. OdysseyCore gets the plain Codable structs; `IdentityManager` (which does Keychain operations) stays in the Mac target.

- [ ] **Step 3.1: Create `Packages/OdysseyCore/Sources/OdysseyCore/Identity/IdentityTypes.swift`**

  ```swift
  // Sources/OdysseyCore/Identity/IdentityTypes.swift
  import Foundation

  /// The persistent identity of the local user on this Mac.
  /// Stored in Keychain by IdentityManager (Mac target); shared as Codable for cross-platform use.
  public struct UserIdentity: Codable, Sendable, Equatable {
      /// Ed25519 public key bytes (32 bytes), base64url-encoded.
      public let publicKeyBase64url: String
      /// Human-readable display name (from user preferences).
      public let displayName: String
      /// Stable random node ID (UUID string), persisted across launches.
      public let nodeId: String

      public init(publicKeyBase64url: String, displayName: String, nodeId: String) {
          self.publicKeyBase64url = publicKeyBase64url
          self.displayName = displayName
          self.nodeId = nodeId
      }
  }

  /// Bundle of identity material for a single agent instance.
  /// Passed to iOS so it can verify signatures from this agent.
  public struct AgentIdentityBundle: Codable, Sendable {
      /// The agent's name as defined in Agent.name
      public let agentName: String
      /// Ed25519 public key bytes, base64url-encoded
      public let publicKeyBase64url: String
      /// ISO 8601 creation timestamp
      public let createdAt: String

      public init(agentName: String, publicKeyBase64url: String, createdAt: String) {
          self.agentName = agentName
          self.publicKeyBase64url = publicKeyBase64url
          self.createdAt = createdAt
      }
  }

  /// TLS certificate material for the Mac sidecar's self-signed cert.
  /// iOS uses the DER bytes to pin the cert when connecting over TLS.
  public struct TLSBundle: Codable, Sendable {
      /// DER-encoded self-signed certificate, base64-encoded.
      public let certDERBase64: String
      /// ISO 8601 expiry date of the certificate.
      public let expiresAt: String

      public init(certDERBase64: String, expiresAt: String) {
          self.certDERBase64 = certDERBase64
          self.expiresAt = expiresAt
      }
  }
  ```

---

## Task 4: Networking / Invite Types

These types are specified in Phase 2 but do not yet exist. The actual `InviteCodeGenerator` that calls `IdentityManager` and `CoreImage` stays in the Mac target; OdysseyCore just holds the value types that both sides need to encode/decode.

- [ ] **Step 4.1: Create `Packages/OdysseyCore/Sources/OdysseyCore/Networking/InviteTypes.swift`**

  ```swift
  // Sources/OdysseyCore/Networking/InviteTypes.swift
  import Foundation

  /// Network location hints embedded in an invite payload.
  /// Provides both LAN (mDNS/Bonjour) and WAN (STUN-discovered) endpoints.
  public struct InviteHints: Codable, Sendable {
      /// Local LAN IP:port, e.g. "192.168.1.42:9849"
      public let lan: String?
      /// Public WAN IP:port discovered via STUN, e.g. "203.0.113.7:49152"
      public let wan: String?
      /// Bonjour service name, e.g. "Odyssey-Alice._odyssey._tcp.local."
      public let bonjour: String?

      public init(lan: String?, wan: String?, bonjour: String?) {
          self.lan = lan
          self.wan = wan
          self.bonjour = bonjour
      }
  }

  /// TURN relay configuration for NAT traversal fallback.
  public struct TURNConfig: Codable, Sendable {
      public let url: String
      public let username: String
      public let credential: String

      public init(url: String, username: String, credential: String) {
          self.url = url
          self.username = username
          self.credential = credential
      }
  }

  /// The signed payload embedded in an invite QR code or deep link.
  /// Encoded as base64url JSON; the `signature` field covers the canonical JSON of all other fields.
  public struct InvitePayload: Codable, Sendable {
      /// Ed25519 public key of the inviting Mac user, base64url-encoded.
      public let hostPublicKeyBase64url: String
      /// Display name of the inviting user (shown in the iOS accept prompt).
      public let hostDisplayName: String
      /// Bearer token the iOS client must send in the Authorization header.
      public let bearerToken: String
      /// TLS cert DER bytes (base64) for cert-pinning the WebSocket connection.
      public let tlsCertDERBase64: String
      /// Connection hints for reaching the Mac sidecar.
      public let hints: InviteHints
      /// Optional TURN relay for fallback when direct connection fails.
      public let turn: TURNConfig?
      /// ISO 8601 expiry timestamp. iOS must reject the payload if now > expiresAt.
      public let expiresAt: String
      /// Ed25519 signature over the canonical JSON of all other fields, base64url-encoded.
      public let signature: String

      public init(
          hostPublicKeyBase64url: String,
          hostDisplayName: String,
          bearerToken: String,
          tlsCertDERBase64: String,
          hints: InviteHints,
          turn: TURNConfig?,
          expiresAt: String,
          signature: String
      ) {
          self.hostPublicKeyBase64url = hostPublicKeyBase64url
          self.hostDisplayName = hostDisplayName
          self.bearerToken = bearerToken
          self.tlsCertDERBase64 = tlsCertDERBase64
          self.hints = hints
          self.turn = turn
          self.expiresAt = expiresAt
          self.signature = signature
      }
  }
  ```

---

## Task 5: Shared Views

### 5A: StreamingIndicator

The original file is pure SwiftUI except for the `.xrayId(...)` modifier from `AppXray`. OdysseyCore gets a copy where that modifier is guarded behind `#if os(macOS)`.

The original file at `Odyssey/Views/Components/StreamingIndicator.swift` is **not modified** — the Mac target continues to use it directly. OdysseyCore has its own copy.

- [ ] **Step 5.1: Create `Packages/OdysseyCore/Sources/OdysseyCore/Views/StreamingIndicator.swift`**

  ```swift
  // Sources/OdysseyCore/Views/StreamingIndicator.swift
  import SwiftUI

  public struct StreamingIndicator: View {
      @State private var animating = false

      public init() {}

      public var body: some View {
          HStack(spacing: 4) {
              ForEach(0..<3) { index in
                  Circle()
                      .fill(.secondary)
                      .frame(width: 5, height: 5)
                      .scaleEffect(animating ? 1.0 : 0.5)
                      .opacity(animating ? 1.0 : 0.3)
                      .animation(
                          .easeInOut(duration: 0.6)
                              .repeatForever()
                              .delay(Double(index) * 0.2),
                          value: animating
                      )
              }
          }
          .padding(.horizontal, 12)
          .padding(.vertical, 6)
          .onAppear { animating = true }
          .accessibilityLabel("Loading")
          .accessibilityElement(children: .ignore)
      }
  }
  ```

  **Note:** `.xrayId(...)` is intentionally omitted. The Mac-target `StreamingIndicator` in `Odyssey/Views/Components/StreamingIndicator.swift` retains the `.xrayId("streamingIndicator")` call and is NOT replaced by this package version. Both can coexist because they are in different modules.

### 5B: MarkdownContentCore

`MarkdownContent.swift` has three macOS-specific issues:
1. `NSWorkspace.shared.open(url)` → needs `#if os(macOS)` / `#if os(iOS)` guard
2. `Color(.textBackgroundColor)` → use `#if os(macOS)` guard to pick platform-appropriate colour
3. `@AppStorage(AppSettings.renderAdmonitionsKey, store: AppSettings.store)` and `@Environment(\.appTextScale)` → `AppSettings` is in the Mac target; OdysseyCore must declare its own `appTextScale` environment key

The OdysseyCore version is called `MarkdownContentCore` to avoid module-level name collision with the Mac target's `MarkdownContent`.

- [ ] **Step 5.2: Create `Packages/OdysseyCore/Sources/OdysseyCore/Views/AppTextScaleKey.swift`**

  This re-declares the environment key within OdysseyCore so views in the package can use it without depending on `AppSettings.swift` in the Mac target.

  ```swift
  // Sources/OdysseyCore/Views/AppTextScaleKey.swift
  import SwiftUI

  private struct AppTextScaleKey: EnvironmentKey {
      static let defaultValue: CGFloat = 1.0
  }

  public extension EnvironmentValues {
      var appTextScale: CGFloat {
          get { self[AppTextScaleKey.self] }
          set { self[AppTextScaleKey.self] = newValue }
      }
  }
  ```

  **Important:** The Mac app's existing `AppSettings.swift` declares the same key. Swift's environment key lookup is by type identity, not module. Since both declarations use a private struct with the same `defaultValue`, they will behave consistently. The Mac target must NOT import OdysseyCore's declaration into the same file; XcodeGen ensures each target sees only one definition in its module scope.

- [ ] **Step 5.3: Create `Packages/OdysseyCore/Sources/OdysseyCore/Views/MarkdownContentCore.swift`**

  The complete file with platform guards applied. The `AdmonitionParser`, `AdmonitionKind`, `AdmonitionCardView`, `LocalFileReferenceLinkifier`, and `Theme.odyssey(scale:)` extension are all copied from the Mac source and adapted:

  ```swift
  // Sources/OdysseyCore/Views/MarkdownContentCore.swift
  import SwiftUI
  import MarkdownUI

  // MARK: - MarkdownContentCore

  public struct MarkdownContentCore: View {
      let text: String
      var onOpenLocalReference: ((String) -> Void)? = nil
      var renderAdmonitions: Bool = true
      @Environment(\.appTextScale) private var appTextScale

      public init(
          text: String,
          renderAdmonitions: Bool = true,
          onOpenLocalReference: ((String) -> Void)? = nil
      ) {
          self.text = text
          self.renderAdmonitions = renderAdmonitions
          self.onOpenLocalReference = onOpenLocalReference
      }

      private var renderedText: String {
          LocalFileReferenceLinkifier.linkify(text)
      }

      public var body: some View {
          Group {
              if renderAdmonitions,
                 let blocks = AdmonitionParser.extractBlocks(from: renderedText),
                 !blocks.isEmpty {
                  admonitionAwareContent(blocks: blocks)
              } else {
                  Markdown(renderedText)
                      .markdownTheme(.odyssey(scale: appTextScale))
                      .textSelection(.enabled)
              }
          }
          .environment(\.openURL, OpenURLAction { url in
              handleOpenURL(url)
          })
      }

      @ViewBuilder
      private func admonitionAwareContent(blocks: [AdmonitionParser.Block]) -> some View {
          VStack(alignment: .leading, spacing: 4) {
              ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                  switch block {
                  case .markdown(let md):
                      Markdown(md)
                          .markdownTheme(.odyssey(scale: appTextScale))
                          .textSelection(.enabled)
                  case .admonition(let kind, let title, let body):
                      AdmonitionCardView(kind: kind, title: title, content: body)
                  }
              }
          }
      }

      private func handleOpenURL(_ url: URL) -> OpenURLAction.Result {
          if let reference = LocalFileReferenceSupport.localReferenceString(from: url),
             let onOpenLocalReference {
              onOpenLocalReference(reference)
              return .handled
          }
  #if os(macOS)
          // NSWorkspace is AppKit-only; not available on iOS
          import AppKit
          NSWorkspace.shared.open(url)
  #else
          UIApplication.shared.open(url)
  #endif
          return .handled
      }
  }

  // MARK: - LocalFileReferenceSupport (cross-platform shim)

  /// Minimal cross-platform shim that replaces the Mac-only LocalFileReferenceSupport.
  /// Returns the file path string from a file:// URL if it looks like a local reference.
  public enum LocalFileReferenceSupport {
      public static func localReferenceString(from url: URL) -> String? {
          guard url.isFileURL else { return nil }
          return url.path
      }
  }
  ```

  **Note on `import AppKit` inside function body:** Swift does not support import statements inside function bodies. The correct pattern is to use `#if os(macOS)` at the top of the file or rely on the AppKit symbols being conditionally available. The actual implementation should be:

  ```swift
  private func handleOpenURL(_ url: URL) -> OpenURLAction.Result {
      if let reference = LocalFileReferenceSupport.localReferenceString(from: url),
         let onOpenLocalReference {
          onOpenLocalReference(reference)
          return .handled
      }
  #if os(macOS)
      NSWorkspace.shared.open(url)
  #else
      UIApplication.shared.open(url)
  #endif
      return .handled
  }
  ```

  And at the top of the file:
  ```swift
  #if os(macOS)
  import AppKit
  #else
  import UIKit
  #endif
  ```

  The full file body (with `AdmonitionParser`, `AdmonitionKind`, `AdmonitionCardView`, `LocalFileReferenceLinkifier`, and `Theme.odyssey`) is a near-verbatim copy of `Odyssey/Views/Components/MarkdownContent.swift` with these changes:
  - Platform imports at top: `#if os(macOS) import AppKit #else import UIKit #endif`
  - `handleOpenURL`: `NSWorkspace` / `UIApplication` guarded
  - `Color(.textBackgroundColor)` in `Theme.odyssey(scale:)` → replaced with:
    ```swift
    #if os(macOS)
    BackgroundColor(Color(nsColor: .textBackgroundColor).opacity(0.5))
    #else
    BackgroundColor(Color(uiColor: .secondarySystemBackground).opacity(0.5))
    #endif
    ```
  - `@AppStorage` removed → `renderAdmonitions` accepted as a parameter instead
  - `@Environment(\.appTextScale)` works because `AppTextScaleKey.swift` is in the same module

### 5C: MessageBubbleCore

`MessageBubble` operates on `ConversationMessage` (a `@Model` class) and many macOS-only sub-views. A shared version must operate on `MessageWire` instead.

- [ ] **Step 5.4: Create `Packages/OdysseyCore/Sources/OdysseyCore/Views/MessageBubbleCore.swift`**

  This is a **new, simplified** bubble view for iOS. It renders `MessageWire` structs received from the REST API. It intentionally excludes:
  - Fork/schedule context menus (macOS desktop features)
  - Mermaid diagrams (WebKit-heavy, Phase 5 concern)
  - File attachment thumbnails (Phase 4 concern)
  - `AppXray` `.xrayId(...)` calls

  ```swift
  // Sources/OdysseyCore/Views/MessageBubbleCore.swift
  import SwiftUI

  #if os(macOS)
  import AppKit
  #else
  import UIKit
  #endif

  /// A cross-platform chat bubble view driven by `MessageWire`.
  /// Used by the iOS target (Phase 4). The macOS target continues using
  /// the full `MessageBubble` view that operates on `ConversationMessage`.
  public struct MessageBubbleCore: View {
      public let message: MessageWire
      public let participants: [ParticipantWire]
      public var renderAdmonitions: Bool = true
      public var onOpenLocalReference: ((String) -> Void)? = nil

      @Environment(\.appTextScale) private var appTextScale
      @State private var isThinkingExpanded = false
      @State private var isCopied = false

      public init(
          message: MessageWire,
          participants: [ParticipantWire],
          renderAdmonitions: Bool = true,
          onOpenLocalReference: ((String) -> Void)? = nil
      ) {
          self.message = message
          self.participants = participants
          self.renderAdmonitions = renderAdmonitions
          self.onOpenLocalReference = onOpenLocalReference
      }

      private var sender: ParticipantWire? {
          guard let id = message.senderParticipantId else { return nil }
          return participants.first { $0.id == id }
      }

      private var isUser: Bool {
          sender.map { !$0.isAgent } ?? false
      }

      private var captionFont: Font { .system(size: 12 * appTextScale) }
      private var caption2Font: Font { .system(size: 11 * appTextScale) }
      private var bodyFont: Font { .system(size: 14 * appTextScale) }

      public var body: some View {
          Group {
              switch message.type {
              case "chat":
                  chatBubble
              case "toolCall", "toolResult":
                  toolCallCard
              case "system":
                  systemMessage
              case "delegation":
                  delegationCard
              case "blackboardUpdate":
                  blackboardCard
              case "taskEvent":
                  taskEventCard
              case "workspaceEvent":
                  workspaceEventCard
              case "agentInvite":
                  agentInviteCard
              default:
                  chatBubble
              }
          }
      }

      @ViewBuilder
      private var chatBubble: some View {
          HStack(alignment: .top, spacing: 8) {
              if isUser { Spacer(minLength: 60) }
              VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                  Text(sender?.displayName ?? "Unknown")
                      .font(captionFont)
                      .foregroundStyle(.secondary)

                  VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                      if !isUser, let thinking = message.thinkingText, !thinking.isEmpty {
                          thinkingSection(thinking)
                      }
                      if !message.text.isEmpty {
                          if isUser {
                              Text(message.text)
                                  .font(bodyFont)
                                  .textSelection(.enabled)
                          } else {
                              MarkdownContentCore(
                                  text: message.text,
                                  renderAdmonitions: renderAdmonitions,
                                  onOpenLocalReference: onOpenLocalReference
                              )
                          }
                      }
                  }
                  .padding(.horizontal, isUser ? 12 : 0)
                  .padding(.vertical, isUser ? 8 : 0)
                  .background(isUser ? Color.accentColor.opacity(0.15) : Color.clear)
                  .clipShape(RoundedRectangle(cornerRadius: isUser ? 12 : 0))

                  if message.isStreaming {
                      StreamingIndicator()
                  }
              }
              if !isUser { Spacer(minLength: 60) }
          }
          .contextMenu {
              Button {
                  copyMessage()
              } label: {
                  Label("Copy", systemImage: "doc.on.doc")
              }
          }
      }

      @ViewBuilder
      private func thinkingSection(_ thinking: String) -> some View {
          VStack(alignment: .leading, spacing: 0) {
              Button {
                  withAnimation(.easeInOut(duration: 0.2)) {
                      isThinkingExpanded.toggle()
                  }
              } label: {
                  HStack(spacing: 4) {
                      Image(systemName: "brain")
                          .font(caption2Font)
                          .foregroundStyle(.indigo)
                      Text("Thinking")
                          .font(captionFont)
                          .foregroundStyle(.indigo)
                      Spacer()
                      Image(systemName: "chevron.right")
                          .rotationEffect(.degrees(isThinkingExpanded ? 90 : 0))
                          .font(caption2Font)
                          .foregroundStyle(.secondary)
                  }
                  .padding(.horizontal, 8)
                  .padding(.vertical, 5)
              }
              .buttonStyle(.plain)
              .accessibilityLabel(isThinkingExpanded ? "Collapse thinking" : "Expand thinking")

              if isThinkingExpanded {
                  Divider()
                  Text(thinking)
                      .font(captionFont)
                      .foregroundStyle(.secondary)
                      .italic()
                      .textSelection(.enabled)
                      .padding(.horizontal, 8)
                      .padding(.vertical, 6)
                      .frame(maxHeight: 200)
              }
          }
          .background(.indigo.opacity(0.06))
          .clipShape(RoundedRectangle(cornerRadius: 6))
          .overlay(
              RoundedRectangle(cornerRadius: 6)
                  .stroke(.indigo.opacity(0.15), lineWidth: 0.5)
          )
      }

      private func copyMessage() {
  #if os(macOS)
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(message.text, forType: .string)
  #else
          UIPasteboard.general.string = message.text
  #endif
          withAnimation { isCopied = true }
          DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
              withAnimation { isCopied = false }
          }
      }

      @ViewBuilder private var systemMessage: some View {
          HStack {
              Spacer()
              Text(message.text)
                  .font(captionFont)
                  .foregroundStyle(.secondary)
                  .italic()
                  .padding(.horizontal, 12)
                  .padding(.vertical, 4)
                  .background(.quaternary)
                  .clipShape(Capsule())
              Spacer()
          }
      }

      @ViewBuilder private var toolCallCard: some View {
          HStack(spacing: 8) {
              Image(systemName: "wrench.and.screwdriver")
                  .foregroundStyle(.gray)
              VStack(alignment: .leading, spacing: 2) {
                  Text(message.toolName ?? "Tool")
                      .font(captionFont)
                      .fontWeight(.medium)
                  if !message.text.isEmpty {
                      Text(message.text)
                          .font(captionFont)
                          .foregroundStyle(.secondary)
                  }
              }
          }
          .padding(8)
          .background(.gray.opacity(0.1))
          .clipShape(RoundedRectangle(cornerRadius: 8))
      }

      @ViewBuilder private var delegationCard: some View {
          HStack(spacing: 8) {
              Image(systemName: "arrow.right.circle.fill").foregroundStyle(.orange)
              VStack(alignment: .leading, spacing: 2) {
                  Text("Delegated Task").font(captionFont).fontWeight(.medium)
                  Text(message.text).font(captionFont).foregroundStyle(.secondary)
              }
          }
          .padding(8).background(.orange.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 8))
      }

      @ViewBuilder private var blackboardCard: some View {
          HStack(spacing: 8) {
              Image(systemName: "square.grid.2x2.fill").foregroundStyle(.teal)
              VStack(alignment: .leading, spacing: 2) {
                  Text("Blackboard Update").font(captionFont).fontWeight(.medium)
                  Text(message.text).font(captionFont).foregroundStyle(.secondary)
              }
          }
          .padding(8).background(.teal.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 8))
      }

      @ViewBuilder private var taskEventCard: some View {
          HStack(spacing: 8) {
              Image(systemName: "checklist").foregroundStyle(.purple)
              VStack(alignment: .leading, spacing: 2) {
                  Text("Task").font(captionFont).fontWeight(.medium)
                  Text(message.text).font(captionFont).foregroundStyle(.secondary)
              }
          }
          .padding(8).background(.purple.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 8))
      }

      @ViewBuilder private var workspaceEventCard: some View {
          HStack(spacing: 8) {
              Image(systemName: "folder.fill").foregroundStyle(.indigo)
              VStack(alignment: .leading, spacing: 2) {
                  Text("Workspace").font(captionFont).fontWeight(.medium)
                  Text(message.text).font(captionFont).foregroundStyle(.secondary)
              }
          }
          .padding(8).background(.indigo.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 8))
      }

      @ViewBuilder private var agentInviteCard: some View {
          HStack(spacing: 8) {
              Image(systemName: "person.badge.plus").foregroundStyle(.green)
              VStack(alignment: .leading, spacing: 2) {
                  Text("Agent Invited").font(captionFont).fontWeight(.medium)
                  Text(message.text).font(captionFont).foregroundStyle(.secondary)
              }
          }
          .padding(8).background(.green.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 8))
      }
  }
  ```

---

## Task 6: Tests

- [ ] **Step 6.1: Create `Packages/OdysseyCore/Tests/OdysseyCoreTests/WireTypesCodableTests.swift`**

  ```swift
  // Tests/OdysseyCoreTests/WireTypesCodableTests.swift
  import XCTest
  @testable import OdysseyCore

  final class WireTypesCodableTests: XCTestCase {

      // MARK: - ConversationSummaryWire

      func testConversationSummaryWireCodableRoundTrip() throws {
          let participants = [
              ParticipantWire(id: "p1", displayName: "Alice", isAgent: false, isLocal: true),
              ParticipantWire(id: "p2", displayName: "Coder", isAgent: true, isLocal: false),
          ]
          let original = ConversationSummaryWire(
              id: "conv-abc",
              topic: "Build the feature",
              lastMessageAt: "2026-04-13T10:00:00Z",
              lastMessagePreview: "Sure, I'll start now.",
              unread: false,
              participants: participants,
              projectId: "proj-1",
              projectName: "Odyssey",
              workingDirectory: "/Users/alice/Odyssey"
          )

          let encoder = JSONEncoder()
          let data = try encoder.encode(original)

          let decoder = JSONDecoder()
          let decoded = try decoder.decode(ConversationSummaryWire.self, from: data)

          XCTAssertEqual(decoded.id, original.id)
          XCTAssertEqual(decoded.topic, original.topic)
          XCTAssertEqual(decoded.lastMessageAt, original.lastMessageAt)
          XCTAssertEqual(decoded.lastMessagePreview, original.lastMessagePreview)
          XCTAssertEqual(decoded.unread, original.unread)
          XCTAssertEqual(decoded.participants.count, 2)
          XCTAssertEqual(decoded.participants[0].id, "p1")
          XCTAssertEqual(decoded.participants[1].isAgent, true)
          XCTAssertEqual(decoded.projectId, "proj-1")
          XCTAssertEqual(decoded.projectName, "Odyssey")
          XCTAssertEqual(decoded.workingDirectory, "/Users/alice/Odyssey")
      }

      func testConversationSummaryWireOptionalFieldsNil() throws {
          let original = ConversationSummaryWire(
              id: "conv-xyz",
              topic: "Untitled",
              lastMessageAt: "2026-04-13T11:00:00Z",
              lastMessagePreview: "",
              unread: true,
              participants: [],
              projectId: nil,
              projectName: nil,
              workingDirectory: nil
          )
          let data = try JSONEncoder().encode(original)
          let decoded = try JSONDecoder().decode(ConversationSummaryWire.self, from: data)
          XCTAssertNil(decoded.projectId)
          XCTAssertNil(decoded.projectName)
          XCTAssertNil(decoded.workingDirectory)
      }

      // MARK: - MessageWire

      func testMessageWireCodableRoundTrip() throws {
          let original = MessageWire(
              id: "msg-001",
              text: "Hello from the agent!",
              type: "chat",
              senderParticipantId: "p2",
              timestamp: "2026-04-13T10:01:00Z",
              isStreaming: false,
              toolName: nil,
              toolOutput: nil,
              thinkingText: "Let me think about this..."
          )
          let data = try JSONEncoder().encode(original)
          let decoded = try JSONDecoder().decode(MessageWire.self, from: data)
          XCTAssertEqual(decoded.id, original.id)
          XCTAssertEqual(decoded.text, original.text)
          XCTAssertEqual(decoded.type, "chat")
          XCTAssertEqual(decoded.senderParticipantId, "p2")
          XCTAssertFalse(decoded.isStreaming)
          XCTAssertNil(decoded.toolName)
          XCTAssertEqual(decoded.thinkingText, "Let me think about this...")
      }

      func testMessageWireToolCallRoundTrip() throws {
          let original = MessageWire(
              id: "msg-002",
              text: "{\"command\": \"ls\"}",
              type: "toolCall",
              senderParticipantId: "p2",
              timestamp: "2026-04-13T10:02:00Z",
              isStreaming: false,
              toolName: "bash",
              toolOutput: "file1.swift\nfile2.swift",
              thinkingText: nil
          )
          let data = try JSONEncoder().encode(original)
          let decoded = try JSONDecoder().decode(MessageWire.self, from: data)
          XCTAssertEqual(decoded.toolName, "bash")
          XCTAssertEqual(decoded.toolOutput, "file1.swift\nfile2.swift")
          XCTAssertNil(decoded.thinkingText)
      }

      // MARK: - ProjectSummaryWire

      func testProjectSummaryWireCodableRoundTrip() throws {
          let original = ProjectSummaryWire(
              id: "proj-1",
              name: "Odyssey",
              rootPath: "/Users/alice/Odyssey",
              icon: "cpu",
              color: "purple",
              isPinned: true,
              pinnedAgentIds: ["agent-coder", "agent-reviewer"]
          )
          let data = try JSONEncoder().encode(original)
          let decoded = try JSONDecoder().decode(ProjectSummaryWire.self, from: data)
          XCTAssertEqual(decoded.id, "proj-1")
          XCTAssertEqual(decoded.name, "Odyssey")
          XCTAssertEqual(decoded.isPinned, true)
          XCTAssertEqual(decoded.pinnedAgentIds, ["agent-coder", "agent-reviewer"])
      }

      // MARK: - InvitePayload

      func testInvitePayloadCodableRoundTrip() throws {
          let hints = InviteHints(lan: "192.168.1.42:9849", wan: "203.0.113.7:49152", bonjour: nil)
          let turn = TURNConfig(url: "turn:relay.example.com:3478", username: "user", credential: "pass")
          let original = InvitePayload(
              hostPublicKeyBase64url: "abc123",
              hostDisplayName: "Alice",
              bearerToken: "tok_xyz",
              tlsCertDERBase64: "MIIC...",
              hints: hints,
              turn: turn,
              expiresAt: "2026-04-14T10:00:00Z",
              signature: "sig_base64url"
          )
          let data = try JSONEncoder().encode(original)
          let decoded = try JSONDecoder().decode(InvitePayload.self, from: data)
          XCTAssertEqual(decoded.hostPublicKeyBase64url, "abc123")
          XCTAssertEqual(decoded.hints.lan, "192.168.1.42:9849")
          XCTAssertEqual(decoded.hints.wan, "203.0.113.7:49152")
          XCTAssertNil(decoded.hints.bonjour)
          XCTAssertEqual(decoded.turn?.url, "turn:relay.example.com:3478")
          XCTAssertEqual(decoded.expiresAt, "2026-04-14T10:00:00Z")
      }

      // MARK: - UserIdentity

      func testUserIdentityCodableRoundTrip() throws {
          let original = UserIdentity(
              publicKeyBase64url: "AAABBBCCC",
              displayName: "Alice",
              nodeId: "550e8400-e29b-41d4-a716-446655440000"
          )
          let data = try JSONEncoder().encode(original)
          let decoded = try JSONDecoder().decode(UserIdentity.self, from: data)
          XCTAssertEqual(decoded, original)
      }
  }
  ```

---

## Task 7: Update `project.yml`

This task modifies `project.yml` so that XcodeGen wires `OdysseyCore` into the macOS target and removes the now-duplicate direct `MarkdownUI` dependency (since it flows transitively through `OdysseyCore`).

**File to modify:** `/Users/shayco/Odyssey/project.yml`

- [ ] **Step 7.1: Add `OdysseyCore` to the `packages:` section and remove the direct `MarkdownUI` entry**

  Current `packages:` block:
  ```yaml
  packages:
    AppXray:
      path: Dependencies/appxray/packages/sdk-ios
    MarkdownUI:
      url: https://github.com/gonzalezreal/swift-markdown-ui
      from: "2.4.1"
    Highlightr:
      url: https://github.com/raspu/Highlightr
      from: "2.2.1"
  ```

  Replace with:
  ```yaml
  packages:
    AppXray:
      path: Dependencies/appxray/packages/sdk-ios
    OdysseyCore:
      path: Packages/OdysseyCore
    Highlightr:
      url: https://github.com/raspu/Highlightr
      from: "2.2.1"
  ```

  **Why remove `MarkdownUI`?** `OdysseyCore`'s `Package.swift` declares `swift-markdown-ui` as its own dependency. If both the top-level `project.yml` and `OdysseyCore` declare `MarkdownUI`, Xcode will emit a duplicate symbol error. The Mac target receives `MarkdownUI` transitively through `OdysseyCore`.

- [ ] **Step 7.2: Update the `Odyssey` target's `dependencies:` array**

  Current Mac target dependencies:
  ```yaml
  dependencies:
    - package: AppXray
    - package: MarkdownUI
    - package: Highlightr
  ```

  Replace with:
  ```yaml
  dependencies:
    - package: AppXray
    - package: OdysseyCore
    - package: Highlightr
  ```

  `OdysseyCore` is added; `MarkdownUI` is removed (flows transitively).

- [ ] **Step 7.3: Regenerate the Xcode project**

  ```bash
  cd /Users/shayco/Odyssey && xcodegen generate
  ```

---

## Task 8: Verify Mac Target Still Builds

After updating `project.yml` and regenerating the project, verify that removing the direct `MarkdownUI` dependency does not break any Mac-target imports.

- [ ] **Step 8.1: Search for `import MarkdownUI` in the Mac target**

  ```bash
  grep -rn "import MarkdownUI" /Users/shayco/Odyssey/Odyssey/
  ```

  Expected files (all currently import it directly):
  - `Odyssey/Views/Components/MarkdownContent.swift`
  - `Odyssey/Views/Components/CodeBlockView.swift` (likely)

  These files will still compile because `MarkdownUI` is re-exported transitively through `OdysseyCore`. However, Swift Package Manager does not automatically re-export transitive dependencies in all configurations. If the build fails with `cannot find type 'Markdown' in scope`, the fix is to add `@_exported import MarkdownUI` to a file within `OdysseyCore`, or to keep `MarkdownUI` as a direct dependency of the Mac target alongside `OdysseyCore`.

  **Preferred safe approach:** Keep `MarkdownUI` as a direct Mac target dependency AND add `OdysseyCore`. The duplicate package error only occurs if both resolve to different versions. Since `OdysseyCore` pins `from: "2.4.1"` and `project.yml` previously used `from: "2.4.1"`, they resolve to the same version and Xcode deduplicates them.

  **Revised `project.yml` dependencies for the Mac target:**
  ```yaml
  dependencies:
    - package: AppXray
    - package: OdysseyCore
    - package: MarkdownUI
    - package: Highlightr
  ```

  And restore `MarkdownUI` to the `packages:` section:
  ```yaml
  packages:
    AppXray:
      path: Dependencies/appxray/packages/sdk-ios
    OdysseyCore:
      path: Packages/OdysseyCore
    MarkdownUI:
      url: https://github.com/gonzalezreal/swift-markdown-ui
      from: "2.4.1"
    Highlightr:
      url: https://github.com/raspu/Highlightr
      from: "2.2.1"
  ```

  XcodeGen/SPM will deduplicate the `swift-markdown-ui` package since both `project.yml` and `OdysseyCore/Package.swift` specify the same version range.

- [ ] **Step 8.2: Build the macOS target**

  ```bash
  xcodebuild build \
    -scheme Odyssey \
    -destination 'platform=macOS' \
    -quiet \
    2>&1 | tail -20
  ```

  Expected result: `** BUILD SUCCEEDED **`

  Common failure modes and fixes:
  - `Module 'MarkdownUI' was not found` → Add `MarkdownUI` back as a direct Mac target dependency (see Step 8.1)
  - `Redefinition of 'appTextScale'` → The `AppTextScaleKey` in `OdysseyCore` and `AppSettings.swift` both use private struct types. They are in different modules so there is no redefinition. If a conflict appears, rename the OdysseyCore one to `CoreAppTextScaleKey` (private) and keep the public `appTextScale` property name the same.
  - `Cannot find type 'OdysseyCore' in scope` → Run `xcodegen generate` again; open `.xcodeproj` in Xcode; do Product > Clean Build Folder, then build.

---

## Task 9: Verify OdysseyCore Standalone Package Build

- [ ] **Step 9.1: Build OdysseyCore for the host platform (macOS)**

  ```bash
  cd /Users/shayco/Odyssey/Packages/OdysseyCore && swift build
  ```

  Expected: `Build complete!`

- [ ] **Step 9.2: Build OdysseyCore for iOS Simulator (arm64)**

  This confirms the package compiles for iOS without AppKit leaking through.

  ```bash
  cd /Users/shayco/Odyssey/Packages/OdysseyCore && \
    swift build \
      -Xswiftc "-target" \
      -Xswiftc "arm64-apple-ios17.0-simulator"
  ```

  Expected: `Build complete!`

  If this fails with `'AppKit' module not available on iOS` it means one of the `#if os(macOS)` guards is missing. Check:
  1. Top-of-file `#if os(macOS) import AppKit #else import UIKit #endif` in `MarkdownContentCore.swift` and `MessageBubbleCore.swift`
  2. `NSWorkspace` calls wrapped in `#if os(macOS)` blocks
  3. `NSPasteboard` calls wrapped in `#if os(macOS)` blocks
  4. `Color(.textBackgroundColor)` guarded for macOS vs `Color(uiColor: .secondarySystemBackground)` on iOS

- [ ] **Step 9.3: Run OdysseyCore unit tests**

  ```bash
  cd /Users/shayco/Odyssey/Packages/OdysseyCore && swift test
  ```

  Expected: All `WireTypesCodableTests` pass.

---

## Task 10: Verify No Regressions in OdysseyTests

The existing `OdysseyTests` test suite must still pass after the `project.yml` changes.

- [ ] **Step 10.1: Run OdysseyTests**

  ```bash
  xcodebuild test \
    -scheme Odyssey \
    -destination 'platform=macOS' \
    -quiet \
    2>&1 | tail -30
  ```

  Expected: `** TEST SUCCEEDED **`

---

## Summary of All Files Created/Modified

| Action | File | Description |
|--------|------|-------------|
| Create | `Packages/OdysseyCore/Package.swift` | Package manifest: platforms macOS 14 + iOS 17, depends on swift-markdown-ui |
| Create | `Packages/OdysseyCore/Sources/OdysseyCore/Protocol/WireTypes.swift` | `ConversationSummaryWire`, `MessageWire`, `ParticipantWire`, `ProjectSummaryWire` |
| Create | `Packages/OdysseyCore/Sources/OdysseyCore/Identity/IdentityTypes.swift` | `UserIdentity`, `AgentIdentityBundle`, `TLSBundle` |
| Create | `Packages/OdysseyCore/Sources/OdysseyCore/Networking/InviteTypes.swift` | `InvitePayload`, `InviteHints`, `TURNConfig` |
| Create | `Packages/OdysseyCore/Sources/OdysseyCore/Views/AppTextScaleKey.swift` | Cross-platform `appTextScale` environment key |
| Create | `Packages/OdysseyCore/Sources/OdysseyCore/Views/StreamingIndicator.swift` | Pure SwiftUI copy without `.xrayId(...)` |
| Create | `Packages/OdysseyCore/Sources/OdysseyCore/Views/MarkdownContentCore.swift` | Adapted `MarkdownContent` with `#if os(macOS)` guards; accepts `renderAdmonitions` as param |
| Create | `Packages/OdysseyCore/Sources/OdysseyCore/Views/MessageBubbleCore.swift` | New view operating on `MessageWire`; cross-platform clipboard; no SwiftData deps |
| Create | `Packages/OdysseyCore/Tests/OdysseyCoreTests/WireTypesCodableTests.swift` | Round-trip Codable tests for all wire types |
| Modify | `project.yml` | Add `OdysseyCore` local package; add to Mac target dependencies |

**Files NOT modified:**
- `Odyssey/Views/Components/MessageBubble.swift` (Mac target keeps using it as-is)
- `Odyssey/Views/Components/StreamingIndicator.swift` (Mac target keeps its copy)
- `Odyssey/Views/Components/MarkdownContent.swift` (Mac target keeps its copy)
- Any `@Model` class

---

## Critical Constraints Checklist

- [ ] No `@Model` classes in `OdysseyCore` — all types are `Codable` structs
- [ ] No SwiftData imports (`import SwiftData`) anywhere in `Packages/OdysseyCore/`
- [ ] `#if os(macOS)` guards around every `NSPasteboard`, `NSWorkspace`, and `Color(.textBackgroundColor)` usage
- [ ] `#if os(iOS)` counterparts for every macOS-guarded block (`UIPasteboard`, `UIApplication.shared.open`)
- [ ] No `AppXray` dependency — the package does not depend on `AppXray`; `.xrayId(...)` calls are absent from OdysseyCore views
- [ ] Package builds cleanly with `swift build -Xswiftc "-target" -Xswiftc "arm64-apple-ios17.0-simulator"`
- [ ] `appTextScale` environment key declared once in OdysseyCore; the Mac target's `AppSettings.swift` version continues to work in its own module scope with no conflict
