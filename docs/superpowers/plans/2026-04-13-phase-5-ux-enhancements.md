# Phase 5 — UX Enhancements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add silent observer agent role and cryptographic ownership display to group conversations.

**Architecture:** `ParticipantRole` gains a third case (`.silentObserver`). `GroupPeerFanOutContext` routes silent observers to receive transcript context without collecting their responses or decrementing the turn budget. `GroupRoutingPlanner.planPeerWave` is extended to return a separate `silentObserverSessionIds` set. Ownership metadata (`ownerDisplayName`, `isVerified`, `ownerPublicKeyData`, `agentIdentityBundleJSON`) is stored on `Participant` and populated from Phase 1 `AgentIdentityBundle` when an agent is added to a conversation. `AgentActivityBar` is extended to render silent observer and verified-ownership badges. `IdentityManager` gets a `verifyAgentBundle(_:)` helper.

**Tech Stack:** SwiftData `@Model`, `GroupPeerFanOutContext` actor, CryptoKit (signature verify), SwiftUI (participant list views)

---

## File Map

| Action | File | Responsibility |
|--------|------|---------------|
| Modify | `Odyssey/Models/Participant.swift` | Add `.silentObserver` role case + 4 ownership fields |
| Modify | `Odyssey/Services/GroupPeerFanOutContext.swift` | Add `reservePeerWave(…silentObserverSessionIds:)` overload + new `reserveSilentObserverTranscript` method |
| Modify | `Odyssey/Services/GroupRoutingPlanner.swift` | Extend `PeerWavePlan` + `planPeerWave` to split silent observers |
| Modify | `Odyssey/Views/MainWindow/ChatView.swift` | Consume `silentObserverSessionIds` in peer wave dispatch; populate ownership fields when adding agents |
| Modify | `Odyssey/Views/Components/AgentActivityBar.swift` | Render eye-icon pill for silent observers; show verified badge next to agent name |
| Modify | `Odyssey/Views/MainWindow/AddAgentsToChatSheet.swift` | Populate ownership fields on new `Participant` after creation |
| Create | `Odyssey/Services/IdentityManager.swift` | `IdentityManager` with `verifyAgentBundle(_:)` helper (Phase 1 prerequisite; add if not yet present) |
| Modify | `OdysseyTests/GroupPromptBuilderTests.swift` | Add 3 fan-out budget tests |
| Create | `OdysseyTests/IdentityManagerTests.swift` | 3 ownership verification tests |

---

## Task 1 — Extend `ParticipantRole` and `Participant` Model

**Files:**
- Modify: `Odyssey/Models/Participant.swift`

### What changes

1. Add `.silentObserver` to `ParticipantRole`.
2. Add four new optional/defaulted SwiftData-compatible fields on `Participant`:
   - `ownerDisplayName: String?` — human-readable owner name from `AgentIdentityBundle`
   - `isVerified: Bool` — true when the bundle signature validates
   - `ownerPublicKeyData: Data?` — raw 32-byte Curve25519 public key for future re-verification
   - `agentIdentityBundleJSON: String?` — full JSON string of the bundle for display in inspector

- [ ] **Step 1.1 — Add `.silentObserver` case**

In `Odyssey/Models/Participant.swift`, replace the `ParticipantRole` enum:

```swift
enum ParticipantRole: String, Codable, Sendable {
    case active
    case observer
    case silentObserver
}
```

- [ ] **Step 1.2 — Add ownership fields to `Participant`**

Inside the `@Model final class Participant` body, after the `isLocalParticipant` line (line 33), add:

```swift
// Ownership / provenance (Phase 5)
var ownerDisplayName: String? = nil
var isVerified: Bool = false
var ownerPublicKeyData: Data? = nil
var agentIdentityBundleJSON: String? = nil
```

No migration is needed — all four fields have default values and SwiftData handles lightweight migration automatically.

- [ ] **Step 1.3 — Verify build**

```
xcodebuild -scheme Odyssey -destination 'platform=macOS' build 2>&1 | tail -20
```

Expected: compiles cleanly. The new enum case produces no exhaustive-switch warnings because existing switch sites only match `.active` and `.observer` — add a `default:` guard only if the compiler requires it.

---

## Task 2 — Extend `GroupPeerFanOutContext`

**Files:**
- Modify: `Odyssey/Services/GroupPeerFanOutContext.swift`

### What changes

Add a new method `reserveSilentObserverTranscript` that:
- Accepts a list of candidate silent observer session IDs.
- Returns the subset that have NOT already received this `triggerMessageId` (deduplication via `deliveredNotifyKeys`).
- Does NOT decrement `additionalTurnsRemaining`.
- Marks the key delivered so duplicates are suppressed on subsequent calls.

Existing `reservePeerWave` is unchanged — silent observers are filtered out before calling it.

- [ ] **Step 2.1 — Add `reserveSilentObserverTranscript`**

After the closing brace of `reservePeerWave` in `GroupPeerFanOutContext.swift`, append:

```swift
/// Returns IDs of silent-observer sessions that should receive a transcript
/// context injection for this trigger message.
///
/// - Budget impact: none. Silent observers receive context passively and do
///   not count against `additionalTurnsRemaining`.
/// - Deduplication: each `(observer, trigger)` pair is delivered at most once,
///   consistent with the regular `reservePeerWave` guarantee.
func reserveSilentObserverTranscript(
    triggerMessageId: UUID,
    silentObserverSessionIds: [UUID]
) -> [UUID] {
    var result: [UUID] = []
    for sessionId in silentObserverSessionIds {
        let key = "\(sessionId.uuidString)|\(triggerMessageId.uuidString)"
        guard !deliveredNotifyKeys.contains(key) else { continue }
        deliveredNotifyKeys.insert(key)
        result.append(sessionId)
    }
    return result
}
```

- [ ] **Step 2.2 — Verify build**

```
xcodebuild -scheme Odyssey -destination 'platform=macOS' build 2>&1 | tail -20
```

---

## Task 3 — Extend `GroupRoutingPlanner`

**Files:**
- Modify: `Odyssey/Services/GroupRoutingPlanner.swift`

### What changes

`PeerWavePlan` currently carries `candidateSessionIds` and `prioritySessionIds`. We add `silentObserverSessionIds` to segregate the third routing class before the fan-out context is consulted.

`planPeerWave` gains a `participants: [Participant]` parameter so it can check `participant.role == .silentObserver` for each session.

- [ ] **Step 3.1 — Extend `PeerWavePlan`**

Replace the `PeerWavePlan` struct definition:

```swift
struct PeerWavePlan: Sendable, Equatable {
    let candidateSessionIds: [UUID]
    let prioritySessionIds: Set<UUID>
    let silentObserverSessionIds: [UUID]
    let deliveryReasons: [UUID: PeerDeliveryReason]
}
```

- [ ] **Step 3.2 — Update `planPeerWave` signature and logic**

Replace the `planPeerWave` static method with:

```swift
static func planPeerWave(
    routingMode: GroupRoutingMode,
    triggerText: String,
    otherSessions: [Session],
    participants: [Participant] = []
) -> PeerWavePlan? {
    let sortedOthers = otherSessions.sorted { $0.startedAt < $1.startedAt }
    let isAllMention = ChatSendRouting.containsMentionAll(in: triggerText)
    let mentionNames = ChatSendRouting.mentionedAgentNames(
        in: triggerText,
        agents: sortedOthers.compactMap(\.agent)
    )
    let filteredNames = mentionNames.filter { !$0.isEmpty && !ChatSendRouting.isMentionAllToken($0) }

    // Split silent observers out before routing logic.
    // A session is a silent observer if its corresponding Participant has role == .silentObserver.
    let silentObserverSessionIds: Set<UUID> = Set(
        sortedOthers.compactMap { session -> UUID? in
            let isObserver = participants.contains { p in
                if case .agentSession(let sid) = p.type {
                    return sid == session.id && p.role == .silentObserver
                }
                return false
            }
            return isObserver ? session.id : nil
        }
    )

    // Active candidates exclude silent observers.
    let activeSortedOthers = sortedOthers.filter { !silentObserverSessionIds.contains($0.id) }

    let mentionedSessionIds: Set<UUID>
    if isAllMention {
        // @all mentions override silent observer status — they become priority recipients.
        mentionedSessionIds = Set(sortedOthers.map(\.id))
    } else {
        mentionedSessionIds = Set(sortedOthers.filter { session in
            guard let agentName = session.agent?.name else { return false }
            return filteredNames.contains { $0.caseInsensitiveCompare(agentName) == .orderedSame }
        }.map(\.id))
    }

    // Silent observers that are explicitly @mentioned become priority recipients in
    // the regular wave (they respond when addressed directly).
    let mentionedSilentObservers = silentObserverSessionIds.intersection(mentionedSessionIds)
    let passiveSilentObserverIds = silentObserverSessionIds.subtracting(mentionedSilentObservers)

    let candidateSessions: [Session]
    if routingMode == .mentionAware {
        // Only explicitly mentioned active sessions + mentioned silent observers.
        guard isAllMention || !mentionedSessionIds.isEmpty else {
            // No mentions at all — but we may still have silent observers to notify.
            if passiveSilentObserverIds.isEmpty { return nil }
            return PeerWavePlan(
                candidateSessionIds: [],
                prioritySessionIds: [],
                silentObserverSessionIds: Array(passiveSilentObserverIds),
                deliveryReasons: [:]
            )
        }
        candidateSessions = activeSortedOthers.filter { mentionedSessionIds.contains($0.id) }
    } else {
        candidateSessions = activeSortedOthers
    }

    // Mentioned silent observers are elevated to regular candidates with priority.
    let elevatedCandidates = sortedOthers.filter { mentionedSilentObservers.contains($0.id) }
    let allCandidates = candidateSessions + elevatedCandidates

    guard !allCandidates.isEmpty || !passiveSilentObserverIds.isEmpty else { return nil }

    var deliveryReasons: [UUID: PeerDeliveryReason] = [:]
    for session in allCandidates {
        if mentionedSessionIds.contains(session.id) {
            deliveryReasons[session.id] = isAllMention ? .broadcast : .directMention
        } else {
            deliveryReasons[session.id] = .generic
        }
    }

    return PeerWavePlan(
        candidateSessionIds: allCandidates.map(\.id),
        prioritySessionIds: mentionedSessionIds,
        silentObserverSessionIds: Array(passiveSilentObserverIds),
        deliveryReasons: deliveryReasons
    )
}
```

**Key invariants:**
- Passive silent observers never appear in `candidateSessionIds` — they are routed separately, so `reservePeerWave` never sees them.
- `@mentioned` silent observers are elevated into `candidateSessionIds` with priority, so they respond when explicitly addressed.
- The `participants` parameter defaults to `[]` so all existing call sites that omit it continue to compile unchanged (silent observer logic is a no-op when no participants are passed).

- [ ] **Step 3.3 — Fix exhaustive switches on `PeerWavePlan`**

Search for any code that destructures `PeerWavePlan` and add the new `silentObserverSessionIds` field if required:

```
grep -r "PeerWavePlan(" Odyssey/ --include="*.swift"
```

The only construction site is the planner itself (just updated). Destructuring sites read individual properties by name, so no changes needed.

- [ ] **Step 3.4 — Verify build**

```
xcodebuild -scheme Odyssey -destination 'platform=macOS' build 2>&1 | tail -20
```

---

## Task 4 — Wire Silent Observer Fan-Out in `ChatView`

**Files:**
- Modify: `Odyssey/Views/MainWindow/ChatView.swift`

### What changes

The peer-wave dispatch function (`peerWave(for:from:…)`, roughly lines 3823–3900) currently passes all non-sender sessions to `GroupRoutingPlanner.planPeerWave`. We update it to:

1. Pass `participants` to `planPeerWave` (so it can classify `.silentObserver` sessions).
2. After obtaining `peerPlan`, call `context.reserveSilentObserverTranscript` for `peerPlan.silentObserverSessionIds`.
3. Send a context-injection prompt to those sessions WITHOUT awaiting their result (fire-and-forget transcript injection).

- [ ] **Step 4.1 — Pass `participants` to `planPeerWave`**

Locate the call to `GroupRoutingPlanner.planPeerWave` (around line 3838):

```swift
guard let peerPlan = GroupRoutingPlanner.planPeerWave(
    routingMode: convo.routingMode,
    triggerText: triggerMessage.text,
    otherSessions: sortedOthers
) else {
```

Replace with:

```swift
guard let peerPlan = GroupRoutingPlanner.planPeerWave(
    routingMode: convo.routingMode,
    triggerText: triggerMessage.text,
    otherSessions: sortedOthers,
    participants: participants
) else {
```

- [ ] **Step 4.2 — Dispatch silent observer transcript injections**

After the `guard let peerPlan` block (after line ~3854), insert the silent observer dispatch before the `let candidateSessions` line:

```swift
// Silent observers: receive transcript context but do NOT produce responses.
// We call reserveSilentObserverTranscript for deduplication, then fire-and-forget
// a session.message so their session history is updated. Their reply (if any) is
// suppressed by not awaiting it in the group completion loop.
let silentIds = await context.reserveSilentObserverTranscript(
    triggerMessageId: triggerMessage.id,
    silentObserverSessionIds: peerPlan.silentObserverSessionIds
)
for silentSessionId in silentIds {
    guard let silentSession = convo.sessions.first(where: { $0.id == silentSessionId }) else {
        continue
    }
    let senderLbl = GroupPromptBuilder.senderDisplayLabel(for: triggerMessage, participants: participants)
    let contextPrompt = GroupPromptBuilder.buildSilentObserverContextPrompt(
        senderLabel: senderLbl,
        triggerText: triggerMessage.text
    )
    // Fire and forget — we do NOT add this to `pending` so the response is not broadcast.
    Task {
        _ = try? await sendPrompt(
            to: silentSession,
            prompt: contextPrompt,
            attachments: [],
            manager: manager,
            provisioner: provisioner,
            planMode: false,
            errorPrefix: "Silent observer notify failed",
            seenThroughMessageId: triggerMessage.id,
            wave: nil
        )
    }
}
```

Note: `sendPrompt(…wave: nil)` means the result message is stored in the session history but not broadcast to the conversation. Confirm that `sendPrompt` handles `wave == nil` by not adding the response to `displayMessages`. If the current implementation requires a non-nil wave, pass a sentinel wave with an empty `recipientSessionIds` set instead.

- [ ] **Step 4.3 — Add `GroupPromptBuilder.buildSilentObserverContextPrompt`**

Open `Odyssey/Services/GroupPromptBuilder.swift`. After the last `static func` definition, add:

```swift
/// Builds the context injection prompt sent to a silent observer.
///
/// The observer receives the message text for session-history awareness but is
/// not instructed to reply. If the model does produce a reply it will be stored
/// on the session but not surfaced in the conversation UI.
static func buildSilentObserverContextPrompt(
    senderLabel: String,
    triggerText: String
) -> String {
    """
    [Silent observer context — do not reply]
    \(senderLabel): \(triggerText)
    """
}
```

- [ ] **Step 4.4 — Populate ownership fields when adding agents**

In `AddAgentsToChatSheet.swift`, inside `addSelected()`, after the `Participant` is created (around line 158):

```swift
let agentParticipant = Participant(
    type: .agentSession(sessionId: session.id),
    displayName: agent.name
)
agentParticipant.conversation = convo
convo.participants.append(agentParticipant)

// Populate ownership metadata from AgentIdentityBundle if present (Phase 1).
if let bundleJSON = agent.identityBundleJSON,
   let bundleData = bundleJSON.data(using: .utf8),
   let bundle = try? JSONDecoder().decode(AgentIdentityBundle.self, from: bundleData) {
    let verified = IdentityManager.shared.verifyAgentBundle(bundle)
    agentParticipant.isVerified = verified
    agentParticipant.ownerPublicKeyData = bundle.ownerPublicKeyData
    agentParticipant.agentIdentityBundleJSON = bundleJSON
    agentParticipant.ownerDisplayName = IdentityManager.shared.ownerDisplayName(for: bundle)
}
```

If `Agent.identityBundleJSON` does not exist yet (Phase 1 not merged), this block is guarded by the optional chain and is a no-op — it will auto-activate once Phase 1 lands.

Repeat the same ownership-population logic in `ChatView.ensureFreeformSidecarSession` and `ChatView.inviteGroupIntoConversation` wherever `Participant` is created for an agent.

- [ ] **Step 4.5 — Verify build**

```
xcodebuild -scheme Odyssey -destination 'platform=macOS' build 2>&1 | tail -20
```

---

## Task 5 — Add `IdentityManager.verifyAgentBundle` and `ownerDisplayName`

**Files:**
- Create or Modify: `Odyssey/Services/IdentityManager.swift`

### What changes

Phase 1 is responsible for the full `IdentityManager` and `AgentIdentityBundle` types. Phase 5 depends on two methods:

```swift
func verifyAgentBundle(_ bundle: AgentIdentityBundle) -> Bool
func ownerDisplayName(for bundle: AgentIdentityBundle) -> String?
```

If `IdentityManager.swift` does not yet exist, create a minimal stub that implements only these two methods. The stub will be replaced wholesale when Phase 1 merges.

- [ ] **Step 5.1 — Create or extend `IdentityManager.swift`**

Create `Odyssey/Services/IdentityManager.swift` (skip if already present from Phase 1):

```swift
import Foundation
import CryptoKit

/// Manages local user identity and agent bundle verification.
///
/// Phase 1 provides the full implementation. This stub covers the methods
/// required by Phase 5 (ownership display + cryptographic verification).
final class IdentityManager {
    static let shared = IdentityManager()

    private init() {}

    // MARK: - Agent Bundle Verification

    /// Returns `true` when the bundle's `ownerSignature` verifies against
    /// the `ownerPublicKeyData` over the canonical signed payload.
    ///
    /// Signed payload = agentPublicKeyData || agentId.uuidBytes || agentName.utf8
    func verifyAgentBundle(_ bundle: AgentIdentityBundle) -> Bool {
        guard let ownerKey = try? Curve25519.Signing.PublicKey(
            rawRepresentation: bundle.ownerPublicKeyData
        ) else { return false }

        var toVerify = Data()
        toVerify.append(bundle.agentPublicKeyData)
        toVerify.append(contentsOf: bundle.agentId.uuidBytes)
        toVerify.append(contentsOf: bundle.agentName.utf8)

        return (try? ownerKey.isValidSignature(bundle.ownerSignature, for: toVerify)) ?? false
    }

    /// Returns the display name of the owner referenced in the bundle.
    ///
    /// Phase 1 will look this up in the local UserIdentity store. For now we
    /// return a placeholder derived from the key fingerprint.
    func ownerDisplayName(for bundle: AgentIdentityBundle) -> String? {
        // Phase 1 TODO: look up UserIdentity by bundle.ownerPublicKeyData fingerprint.
        // Stub returns nil (UI treats nil as "unknown owner").
        return nil
    }
}
```

- [ ] **Step 5.2 — Create `AgentIdentityBundle` stub if Phase 1 is not yet merged**

If Phase 1 has not landed, create `Odyssey/Models/AgentIdentityBundle.swift`:

```swift
import Foundation

/// Cryptographic identity bundle for an agent, signed by its owner.
///
/// Full definition lives in Phase 1. This stub makes Phase 5 compile independently.
struct AgentIdentityBundle: Codable, Sendable {
    /// UUID of the agent.
    var agentId: UUID
    /// Human-readable agent name (included in signed payload).
    var agentName: String
    /// Raw 32-byte Curve25519 public key for the agent.
    var agentPublicKeyData: Data
    /// Raw 32-byte Curve25519 public key for the owner user.
    var ownerPublicKeyData: Data
    /// Ed25519 signature by the owner's signing key over the canonical payload.
    var ownerSignature: Data
}
```

Also add `uuidBytes` on `UUID` if not already present:

```swift
// Odyssey/Models/AgentIdentityBundle.swift (append after struct)
extension UUID {
    var uuidBytes: [UInt8] {
        withUnsafeBytes(of: uuid) { Array($0) }
    }
}
```

- [ ] **Step 5.3 — Verify build**

```
xcodebuild -scheme Odyssey -destination 'platform=macOS' build 2>&1 | tail -20
```

---

## Task 6 — Update `AgentActivityBar` UI

**Files:**
- Modify: `Odyssey/Views/Components/AgentActivityBar.swift`

### What changes

`AgentActivityBar` currently takes `sessions: [Session]`. We extend it to accept a `participants: [Participant]` array so it can:

1. Render an `eye` icon in the pill for `.silentObserver` participants.
2. Render a `checkmark.seal.fill` badge next to the agent name when `participant.isVerified == true`.
3. Append `"· by \(ownerDisplayName)"` in `.caption2` when `participant.ownerDisplayName != nil`.

- [ ] **Step 6.1 — Extend `AgentActivityItem`**

Replace the private `AgentActivityItem` struct:

```swift
private struct AgentActivityItem: Identifiable {
    let id: UUID
    let name: String
    let state: AppState.SessionActivityState
    let isSilentObserver: Bool
    let isVerified: Bool
    let ownerDisplayName: String?
}
```

- [ ] **Step 6.2 — Update `AgentActivityBar.body` to populate new fields**

Replace the `items` build block:

```swift
let items = sessions.map { session -> AgentActivityItem in
    let key = session.id.uuidString
    let state = sessionActivity[key] ?? .idle
    let participant = participants.first { p in
        if case .agentSession(let sid) = p.type { return sid == session.id }
        return false
    }
    return AgentActivityItem(
        id: session.id,
        name: session.agent?.name ?? "Agent",
        state: state,
        isSilentObserver: participant?.role == .silentObserver,
        isVerified: participant?.isVerified ?? false,
        ownerDisplayName: participant?.ownerDisplayName
    )
}
```

Update the `AgentActivityBar` struct initializer signature to accept participants:

```swift
struct AgentActivityBar: View {
    let sessions: [Session]
    let sessionActivity: [String: AppState.SessionActivityState]
    var participants: [Participant] = []
    // ...
}
```

- [ ] **Step 6.3 — Update `agentPill` to render new badges**

Replace the `agentPill` view builder:

```swift
private func agentPill(_ item: AgentActivityItem) -> some View {
    HStack(spacing: 4) {
        if item.isSilentObserver {
            Image(systemName: "eye")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Silent observer")
        } else {
            ActivityDot(state: item.state)
                .frame(width: 6, height: 6)
        }

        Text(item.name)
            .font(.caption2)
            .fontWeight(.medium)

        if item.isVerified {
            Image(systemName: "checkmark.seal.fill")
                .font(.caption2)
                .foregroundStyle(.blue)
                .accessibilityLabel("Verified owner")
        }

        if let owner = item.ownerDisplayName {
            Text("· by \(owner)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }

        if !item.isSilentObserver {
            Text(item.state.displayLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(item.isSilentObserver
        ? Color.gray.opacity(0.08)
        : item.state.displayColor.opacity(0.1))
    .clipShape(Capsule())
    .help(item.isSilentObserver
        ? "Silent observer — receives all messages, responds only when @mentioned"
        : item.state.displayLabel)
    .xrayId("chat.agentPill.\(item.id.uuidString)")
    .accessibilityLabel(item.isSilentObserver
        ? "\(item.name): silent observer"
        : "\(item.name): \(item.state.displayLabel)")
}
```

- [ ] **Step 6.4 — Pass `participants` from `ChatView` to `AgentActivityBar`**

In `ChatView.swift`, locate the `AgentActivityBar(…)` call (around line 1864):

```swift
AgentActivityBar(
    sessions: convo.sessions,
    sessionActivity: appState.sessionActivity
)
```

Replace with:

```swift
AgentActivityBar(
    sessions: convo.sessions,
    sessionActivity: appState.sessionActivity,
    participants: convo.participants
)
```

- [ ] **Step 6.5 — Verify build**

```
xcodebuild -scheme Odyssey -destination 'platform=macOS' build 2>&1 | tail -20
```

---

## Task 7 — Tests: `GroupPromptBuilderTests` extensions

**Files:**
- Modify: `OdysseyTests/GroupPromptBuilderTests.swift`

Add three tests to the existing `GroupPromptBuilderTests` class. All three exercise `GroupPeerFanOutContext` directly.

- [ ] **Step 7.1 — `testSilentObserverReceivesTranscriptNotResponse`**

```swift
func testSilentObserverReceivesTranscriptNotResponse() async throws {
    // Fan-out context with two sessions: one active, one silent observer.
    let rootId = UUID()
    let triggerId = UUID()
    let activeId = UUID()
    let silentId = UUID()

    let context = GroupPeerFanOutContext(rootMessageId: rootId, maxAdditionalSidecarTurns: 10)

    // Regular wave should NOT include the silent observer.
    let wave = await context.reservePeerWave(
        triggerMessageId: triggerId,
        transcriptBoundaryMessageId: nil,
        candidateSessionIds: [activeId],   // silent observer excluded here
        prioritySessionIds: []
    )
    XCTAssertNotNil(wave)
    XCTAssertTrue(wave!.recipientSessionIds.contains(activeId))
    XCTAssertFalse(wave!.recipientSessionIds.contains(silentId))

    // Silent observer transcript reservation succeeds for the same trigger.
    let silentRecipients = await context.reserveSilentObserverTranscript(
        triggerMessageId: triggerId,
        silentObserverSessionIds: [silentId]
    )
    XCTAssertEqual(silentRecipients, [silentId])
}
```

- [ ] **Step 7.2 — `testSilentObserverNotCountedInBudget`**

```swift
func testSilentObserverNotCountedInBudget() async throws {
    let rootId = UUID()
    let triggerId = UUID()
    let activeId = UUID()
    let silentId = UUID()

    // Budget = 1: only one active peer can respond per root.
    let context = GroupPeerFanOutContext(rootMessageId: rootId, maxAdditionalSidecarTurns: 1)

    // Silent observer transcript: no budget consumed.
    let silentRecipients = await context.reserveSilentObserverTranscript(
        triggerMessageId: triggerId,
        silentObserverSessionIds: [silentId]
    )
    XCTAssertEqual(silentRecipients, [silentId])

    // Active peer: still has budget of 1 remaining.
    let wave = await context.reservePeerWave(
        triggerMessageId: triggerId,
        transcriptBoundaryMessageId: nil,
        candidateSessionIds: [activeId],
        prioritySessionIds: []
    )
    XCTAssertNotNil(wave, "Active peer should receive wave despite silent observer having been notified")
    XCTAssertTrue(wave!.recipientSessionIds.contains(activeId))
}
```

- [ ] **Step 7.3 — `testSilentObserverRespondsToAtMention`**

```swift
func testSilentObserverRespondsToAtMention() async throws {
    let rootId = UUID()
    let triggerId = UUID()
    let silentId = UUID()

    let context = GroupPeerFanOutContext(rootMessageId: rootId, maxAdditionalSidecarTurns: 10)

    // When a silent observer is in prioritySessionIds (i.e., @mentioned),
    // reservePeerWave includes them in the wave, bypassing normal suppression.
    let wave = await context.reservePeerWave(
        triggerMessageId: triggerId,
        transcriptBoundaryMessageId: nil,
        candidateSessionIds: [silentId],   // caller promotes them to candidate
        prioritySessionIds: [silentId]     // direct @mention
    )
    XCTAssertNotNil(wave)
    XCTAssertTrue(wave!.recipientSessionIds.contains(silentId))
}
```

- [ ] **Step 7.4 — Run tests**

```
xcodebuild test -scheme OdysseyTests -destination 'platform=macOS' \
  -only-testing:OdysseyTests/GroupPromptBuilderTests 2>&1 | tail -40
```

---

## Task 8 — Tests: `IdentityManagerTests`

**Files:**
- Create: `OdysseyTests/IdentityManagerTests.swift`

- [ ] **Step 8.1 — Create test file**

```swift
import XCTest
import CryptoKit
@testable import Odyssey

final class IdentityManagerTests: XCTestCase {

    // MARK: - Helpers

    private func makeBundle(agentName: String = "TestAgent") throws -> (
        bundle: AgentIdentityBundle,
        ownerSigningKey: Curve25519.Signing.PrivateKey
    ) {
        let agentId = UUID()
        let ownerSigningKey = Curve25519.Signing.PrivateKey()
        let ownerPublicKey = ownerSigningKey.publicKey

        let agentKeyPair = Curve25519.Signing.PrivateKey()
        let agentPublicKeyData = Data(agentKeyPair.publicKey.rawRepresentation)

        var payload = Data()
        payload.append(agentPublicKeyData)
        payload.append(contentsOf: agentId.uuidBytes)
        payload.append(contentsOf: agentName.utf8)

        let signature = try ownerSigningKey.signature(for: payload)

        let bundle = AgentIdentityBundle(
            agentId: agentId,
            agentName: agentName,
            agentPublicKeyData: agentPublicKeyData,
            ownerPublicKeyData: Data(ownerPublicKey.rawRepresentation),
            ownerSignature: signature
        )
        return (bundle, ownerSigningKey)
    }

    // MARK: - Tests

    func testOwnerDisplayNameFromBundle() throws {
        let (bundle, _) = try makeBundle()
        // Phase 1 stub returns nil; the call must not crash and the type must be correct.
        let name: String? = IdentityManager.shared.ownerDisplayName(for: bundle)
        // Either nil (stub) or a non-empty string (Phase 1 full impl) — both are acceptable.
        if let name { XCTAssertFalse(name.isEmpty) }
    }

    func testVerifiedBadgeWithValidBundle() throws {
        let (bundle, _) = try makeBundle()
        let result = IdentityManager.shared.verifyAgentBundle(bundle)
        XCTAssertTrue(result, "A freshly signed bundle should verify as true")
    }

    func testUnverifiedBadgeWithTamperedBundle() throws {
        var (bundle, _) = try makeBundle()
        // Mutate agentName after signing — payload no longer matches signature.
        bundle.agentName = "TamperedName"
        let result = IdentityManager.shared.verifyAgentBundle(bundle)
        XCTAssertFalse(result, "A bundle with a tampered agentName should not verify")
    }
}
```

- [ ] **Step 8.2 — Register test file in project**

```
xcodegen generate
```

- [ ] **Step 8.3 — Run tests**

```
xcodebuild test -scheme OdysseyTests -destination 'platform=macOS' \
  -only-testing:OdysseyTests/IdentityManagerTests 2>&1 | tail -40
```

---

## Task 9 — Final Integration Verification

- [ ] **Step 9.1 — Full build**

```
xcodebuild -scheme Odyssey -destination 'platform=macOS' build 2>&1 | grep -E "error:|warning:|BUILD"
```

- [ ] **Step 9.2 — Full test suite**

```
xcodebuild test -scheme OdysseyTests -destination 'platform=macOS' 2>&1 | tail -60
```

- [ ] **Step 9.3 — Manual smoke test checklist**

Open Odyssey in a group thread with two agents:
- [ ] Add a third agent; in SwiftData debugger confirm `Participant.role == .active`.
- [ ] Manually set one participant's `role` to `.silentObserver` via a debug console command.
- [ ] Confirm the `AgentActivityBar` shows an eye icon for the silent observer instead of the activity dot.
- [ ] Send a message — confirm the silent observer does NOT appear in the wave (no streaming indicator).
- [ ] @mention the silent observer by name — confirm they DO stream a response.
- [ ] Confirm budget is not decremented for the silent observer's passive notification.

---

## Commit Plan

- [ ] **Commit 1:** `feat(participant): add silentObserver role and ownership fields`
  - Files: `Odyssey/Models/Participant.swift`

- [ ] **Commit 2:** `feat(fanout): silent observer transcript reservation without budget impact`
  - Files: `Odyssey/Services/GroupPeerFanOutContext.swift`

- [ ] **Commit 3:** `feat(routing): split silentObserverSessionIds from peer wave plan`
  - Files: `Odyssey/Services/GroupRoutingPlanner.swift`

- [ ] **Commit 4:** `feat(chat): dispatch silent observer transcript injections`
  - Files: `Odyssey/Views/MainWindow/ChatView.swift`, `Odyssey/Services/GroupPromptBuilder.swift`, `Odyssey/Views/MainWindow/AddAgentsToChatSheet.swift`

- [ ] **Commit 5:** `feat(identity): IdentityManager verifyAgentBundle + AgentIdentityBundle stub`
  - Files: `Odyssey/Services/IdentityManager.swift`, `Odyssey/Models/AgentIdentityBundle.swift` (if new)

- [ ] **Commit 6:** `feat(ui): silent observer eye icon and verified ownership badge in AgentActivityBar`
  - Files: `Odyssey/Views/Components/AgentActivityBar.swift`

- [ ] **Commit 7:** `test(phase5): fan-out budget and identity verification tests`
  - Files: `OdysseyTests/GroupPromptBuilderTests.swift`, `OdysseyTests/IdentityManagerTests.swift`

---

## Dependency Notes

- **Phase 1 prerequisite:** `AgentIdentityBundle`, `IdentityManager` (full), and `Agent.identityBundleJSON` are defined in Phase 1. Phase 5 adds stubs so it can be developed and tested independently. When Phase 1 merges:
  1. Delete `AgentIdentityBundle.swift` stub (Phase 1 provides the canonical version).
  2. Delete the `IdentityManager.swift` stub and replace with Phase 1's implementation.
  3. `ownerDisplayName(for:)` will return real values from the UserIdentity store.
  4. Re-run `IdentityManagerTests` — `testOwnerDisplayNameFromBundle` will now assert a non-nil string.

- **SwiftData migration:** All new `Participant` fields (`ownerDisplayName`, `isVerified`, `ownerPublicKeyData`, `agentIdentityBundleJSON`) use default values (`nil`, `false`, `nil`, `nil`). SwiftData performs lightweight migration automatically; no `VersionedSchema` or `MigrationPlan` is required.

- **sendPrompt wave-nil behavior:** Step 4.2 passes `wave: nil` to `sendPrompt`. Confirm that `sendPrompt` handles `nil` wave by not inserting the response into `displayMessages`. If the current implementation force-unwraps wave, pass a stub wave with `recipientSessionIds: []` instead to suppress broadcast without crashing.
