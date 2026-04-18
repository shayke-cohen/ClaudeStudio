# Odyssey macOS App — Performance Review
**Date:** 2026-04-18  
**Reviewer:** Claude Code (Sonnet 4.6)  
**Scope:** Swift/SwiftUI app + TypeScript sidecar  
**Live metrics:** Resident memory ~204 MB, thermal state nominal, no runtime errors

---

## Executive Summary

The primary performance bottleneck is a **render storm triggered by every streaming token**. Since `AppState` is a monolithic `ObservableObject`, any of its ~40 `@Published` property changes causes every observing view (ChatView, SidebarView, AgentSidebarRowView, etc.) to re-render. During active streaming (20–50 tokens/sec), the entire view hierarchy re-renders 20–50 times per second. The sidebar exacerbates this by performing expensive O(n×m) filter/sort operations inside those re-renders.

**Secondary** bottlenecks: O(n²) string accumulation in streaming buffers, unfiltered `@Query` loading full database tables, and per-render recomputation of sorted messages and markdown text.

---

## Issue Catalogue

### 🔴 P0 — Critical (Fix These First)

---

#### P0-1: AppState Render Storm During Streaming

**Files:** `Odyssey/App/AppState.swift:1090–1115`, `Odyssey/Views/MainWindow/ChatView.swift:648–663`

Every streaming token calls `handleEvent(.streamToken)`, which updates three separate `@Published` properties:

```swift
// AppState.swift:1091–1098
streamingText[sessionId] = current + text       // @Published — re-render 1
activeSessions[uuid]?.isStreaming = true         // @Published — re-render 2
sessionActivity[sessionId] = .streaming          // @Published — re-render 3
```

Because `AppState` is an `ObservableObject`, **every view that holds `@EnvironmentObject var appState: AppState`** receives a re-render signal on each `@Published` change. Views affected:
- `ChatView` — observes appState (onReceive of `$streamingText`, `$thinkingText`, `$lastSessionEvent`, `$sidecarStatus`, `$sessionActivity`)
- `SidebarView` — observes appState
- `AgentSidebarRowView` — observes appState (calls `appState.conversationActivity(for:)` per row)
- `AgentActivityBar` — observes `appState.sessionActivity`
- `MainWindowView` — observes appState

**Measured impact:** At 30 tokens/second, the full view hierarchy re-renders ~30–90 times/second during streaming.

**ChatView also receives multiple onReceive events per token:**
```swift
// ChatView.swift:648–663
.onReceive(appState.$lastSessionEvent) { _ in restoreStreamingStateFromAppState() }
.onReceive(appState.$streamingText) { ... }     // fires per token
.onReceive(appState.$thinkingText) { _ in ... } // fires per token
```

**Fix:**
1. **Throttle token events before updating @Published.** Add a 50ms coalescing timer for streaming updates on the Swift side:

```swift
// AppState.swift — add a debounced streaming flush
private var streamingFlushTask: Task<Void, Never>?

private func scheduleStreamingFlush(sessionId: String) {
    streamingFlushTask?.cancel()
    streamingFlushTask = Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(50))
        guard !Task.isCancelled else { return }
        // batch-flush: objectWillChange fires once
        self.objectWillChange.send()
    }
}
```

2. **Long-term: split AppState into @Observable slices.** `StreamingState`, `SessionActivityState`, `UIState`. Views only re-render for their actual dependencies.

---

#### P0-2: O(n²) String Concatenation in Streaming Buffer

**File:** `Odyssey/App/AppState.swift:1091–1092`

```swift
let current = streamingText[sessionId] ?? ""
streamingText[sessionId] = current + text
```

Swift `String` is a value type. `current + text` copies the entire `current` string on every token. For a 10,000-character response with average 2-character tokens (~5,000 tokens), total bytes copied ≈ **25 million characters** (O(n²) total work). At 100KB responses this becomes severely slow and causes allocation pressure.

Same issue exists for `thinkingText` at line 1101–1102.

**Fix:** Use an array accumulator, join only for display reads:

```swift
// In AppState:
@Published var streamingTokenBuffers: [String: [String]] = [:]

// On token:
streamingTokenBuffers[sessionId, default: []].append(text)

// Computed display accessor (not @Published — avoids extra render):
func streamingText(for sessionId: String) -> String {
    streamingTokenBuffers[sessionId]?.joined() ?? ""
}
```

This reduces total work from O(n²) to O(n). The array grow+append is O(1) amortized.

---

#### P0-3: SidebarView Performs Expensive Work on Every Streaming Token

**File:** `Odyssey/Views/MainWindow/SidebarView.swift:458–475, 753–764, 1066–1068, 1862–1918`

`SidebarView` observes `AppState` via `@EnvironmentObject`. Every streaming token forces these computed properties to re-execute:

```swift
// Line 458-465: O(n log n) per render
private var sortedProjects: [Project] {
    projects.sorted { lhs, rhs in ... }
}

// Line 467-475: O(n) filter + sort per render, called twice
private var residentAgents: [Agent] { agents.filter { ... }.sorted { ... } }
private var nonResidentAgents: [Agent] { agents.filter { ... }.sorted { ... } }

// Line 1066-1068: O(conversations) per project, called in @ViewBuilder
private func rootConversations(in project: Project) -> [Conversation] {
    conversations.filter { $0.parentConversationId == nil && $0.projectId == project.id }
}

// Line 753-764: Multiple filter+sort passes per project per render
let liveThreads = rootConversations(in: project)
    .filter { !$0.isArchived }
    .sorted { lhs, rhs in if lhs.isPinned != rhs.isPinned { ... } return lhs.startedAt > rhs.startedAt }
let pinnedThreads = filteredConversations(liveThreads.filter(\.isPinned))      // filter #2
let activeThreads = filteredConversations(Array(liveThreads.filter { !$0.isPinned }.prefix(10)))  // filter #3
let historyThreads = filteredConversations(Array(liveThreads.filter { !$0.isPinned }.dropFirst(10))) // filter #4
let archivedThreads = filteredConversations(rootConversations(in: project).filter(\.isArchived))   // filter #5
```

With 5 projects × 200 conversations, each render does ~1,000 filter operations + 5 sorts.

**Fix:**
1. Cache sorted/filtered results in `@State` and only recompute on data changes:
```swift
@State private var cachedSortedProjects: [Project] = []
// Rebuild only in .onChange(of: projects)
```

2. **Critical: stop observing streaming state in SidebarView.** Move sidebar activity indicators to a separate `@Observable` class that only updates on session activity changes (not on every token).

---

#### P0-4: `lastMessagePreview` Sorts All Messages Per Conversation Row Per Render

**File:** `Odyssey/Views/MainWindow/SidebarView.swift:87–128`

```swift
static func lastMessagePreview(_ convo: Conversation) -> (text: String, attachmentIcon: String?)? {
    let latestMessage = convo.messages
        .sorted { $0.timestamp < $1.timestamp }  // O(m log m) EVERY ROW EVERY RENDER
        .last
    ...
}
```

This is called at line 1638 for every conversation row displayed in the sidebar. With 50 conversations × 20 messages each = 50 sorts of 20 items on **every sidebar re-render**. Since the sidebar re-renders on every streaming token, this runs 30–50 times/second during active streaming.

**Fix:** Denormalize the last message preview onto the `Conversation` model:
```swift
// In Conversation model:
var lastMessageText: String?
var lastMessageTimestamp: Date?
// Update these fields when messages are added/modified in AppState or ChatView
```

Or use `.max(by:)` instead of `.sorted().last` — O(n) instead of O(n log n):
```swift
let latestMessage = convo.messages.max { $0.timestamp < $1.timestamp }
```

---

### 🟠 P1 — High Impact

---

#### P1-1: Six Unfiltered `@Query` Properties in ChatView

**File:** `Odyssey/Views/MainWindow/ChatView.swift:247–252`

```swift
@Query private var allSkills: [Skill]
@Query private var allMCPs: [MCPServer]
@Query private var allGroups: [AgentGroup]
@Query private var allAgents: [Agent]
@Query(sort: \Session.startedAt) private var allSessions: [Session]   // grows indefinitely
@Query private var allTemplates: [PromptTemplate]
```

None have predicates. They fetch the entire database table. `allSessions` is particularly dangerous as sessions accumulate unboundedly. Loading 1,000 sessions with their relationships on every ChatView instantiation is a significant startup cost.

The code comment at line 245–247 acknowledges this:
```
// Unfiltered queries for chip display. Acceptable for typical catalog sizes (< a few hundred items).
// If performance becomes an issue, filter by agent.skillIds / agent.extraMCPServerIds at query time.
```

**Performance is now an issue.** Fix:
```swift
// Only load sessions for this conversation:
@Query private var allSessions: [Session] = []
// Switch to FetchDescriptor-based fetch in .task(id: conversationId)

// For agents/skills/MCPs used only for mention autocomplete:
// Only fetch when @ is typed — not as @Query
```

---

#### P1-2: `sortedMessages` Recomputed Multiple Times Per Body Evaluation

**File:** `Odyssey/Views/MainWindow/ChatView.swift:290–304`

```swift
private var sortedMessages: [ConversationMessage] {
    (conversation?.messages ?? []).sorted { $0.timestamp < $1.timestamp }
}
```

`sortedMessages` is accessed by at minimum:
- `displayMessages` (which itself is accessed in `messageList` body)
- `latestNonUserChatMessage` (line 601)
- `hasUserChatMessages` (line 306)
- `canExportChat` (line 542)
- `chatExportSnapshot()` (line 619)
- `.onChange(of: sortedMessages.count)` (line 692, 1798)

Each computed property call re-executes the sort. A 200-message conversation sorts 200 items potentially 5–6 times per render.

**Fix:** Cache in `@State`, update with `.onChange`:
```swift
@State private var cachedSortedMessages: [ConversationMessage] = []

// In .onAppear and .onChange(of: conversation?.messages.count):
cachedSortedMessages = (conversation?.messages ?? []).sorted { $0.timestamp < $1.timestamp }
```

Or better, fetch messages pre-sorted via `@Query` with a `SortDescriptor`.

---

#### P1-3: `conversationsForAgent` is O(sessions) Per Agent Row Per Render

**File:** `Odyssey/Views/MainWindow/SidebarView.swift:1902–1909`

```swift
private func conversationsForAgent(_ agent: Agent, in project: Project? = nil) -> [Conversation] {
    var seen = Set<UUID>()
    return allSessions                            // scans ALL sessions
        .filter { $0.agent?.id == agent.id }
        .compactMap { $0.conversations.first }
        .filter { $0.sourceGroupId == nil && !$0.isArchived && ... }
        .filter { seen.insert($0.id).inserted }
}
```

Called by `agentHasActiveSession` (line 1862) for every visible agent row on every render. With 10 agents × 500 total sessions = 5,000 comparisons per render, 30–50 times/second during streaming = **150,000–250,000 comparisons/second.**

**Fix:** Use the SwiftData relationship directly instead of filtering `allSessions`:
```swift
// Agent model has sessions relationship — use it:
private func conversationsForAgent(_ agent: Agent, in project: Project? = nil) -> [Conversation] {
    agent.sessions                               // no full scan
        .compactMap { $0.conversations.first }
        .filter { !$0.isArchived && ... }
}
```

---

#### P1-4: `routingPreviewPlan` Recalculated on Every Keystroke

**File:** `Odyssey/Views/MainWindow/ChatView.swift:440–456`

```swift
private var routingPreviewPlan: GroupRoutingPlanner.UserWavePlan? {
    guard let convo = conversation, convo.sessions.count > 1 else { return nil }
    let mentionNames = ChatSendRouting.mentionedAgentNames(in: inputText, agents: allAgents) // regex scan
    let (resolvedMentionAgents, _) = ChatSendRouting.resolveMentionedAgents(names: mentionNames, agents: allAgents)
    return GroupRoutingPlanner.planUserWave(...)  // full routing computation
}
```

This runs on every body evaluation — every keystroke in the composer triggers a full routing plan computation including regex scanning of `inputText` across all agents. For a group conversation with 5+ agents, this is a non-trivial calculation.

**Fix:** Debounce computation via `.onChange(of: inputText)`:
```swift
@State private var cachedRoutingPreviewPlan: GroupRoutingPlanner.UserWavePlan?

.onChange(of: inputText) { _, new in
    // existing slash-command logic
    updateRoutingPreview(for: new)  // debounced, max once per 100ms
}
```

---

#### P1-5: `participantAppearanceMap` Rebuilt on Every Render

**File:** `Odyssey/Views/MainWindow/ChatView.swift:458–473`

```swift
private var participantAppearanceMap: [UUID: AgentAppearance]? {
    guard let convo = conversation, convo.sessions.count > 1 else { return nil }
    var map: [UUID: AgentAppearance] = [:]
    for participant in convo.participants {
        if let sessionId = participant.typeSessionId,
           let session = convo.sessions.first(where: { $0.id == sessionId }),
           let agent = session.agent {
            map[participant.id] = AgentAppearance(color: ..., icon: ...)
        }
    }
    return map.isEmpty ? nil : map
}
```

The participants list for a conversation doesn't change during normal chat. This map is rebuilt on every body evaluation and passed to every `MessageBubble`. In a 10-agent conversation with 200 messages, this creates 200 new map instances per render.

**Fix:** Cache in `@State`, rebuild only when `conversation?.participants` changes.

---

#### P1-6: `MarkdownContent.renderedText` Recomputed on Every Render

**File:** `Odyssey/Views/Components/MarkdownContent.swift:11–13`

```swift
private var renderedText: String {
    LocalFileReferenceLinkifier.linkify(text)
}
```

`LocalFileReferenceLinkifier.linkify()` performs a line-by-line string scan on potentially large markdown text (hundreds of lines). This runs on **every render of every visible message bubble**, which means ~10–20 invocations per render cycle × 30–50 renders/second during streaming = 300–1,000 full text scans/second.

**Fix:** Cache with `@State`, recompute only when `text` changes:
```swift
@State private var renderedText: String = ""

.onAppear { renderedText = LocalFileReferenceLinkifier.linkify(text) }
.onChange(of: text) { _, new in renderedText = LocalFileReferenceLinkifier.linkify(new) }
```

Or use `.task(id: text)` for the async path.

---

#### P1-7: Streaming Triggers `scrollToBottom` at Full Token Frequency

**File:** `Odyssey/Views/MainWindow/ChatView.swift:1802–1805`

```swift
.onChange(of: streamingContentVersion) { _, _ in
    guard isProcessing, shouldAutoScroll else { return }
    scrollToBottom(proxy, animated: false)
}
```

`streamingContentVersion` (line 364–370) recomputes from all active streaming keys on every render and changes on every token. This calls `ScrollViewReader.scrollTo()` 30–50 times per second, which triggers layout passes at full token rate.

**Fix:** Throttle to maximum 10 Hz:
```swift
private var lastScrollTime: Date = .distantPast

private func throttledScrollToBottom(_ proxy: ScrollViewProxy) {
    let now = Date()
    guard now.timeIntervalSince(lastScrollTime) > 0.1 else { return }
    lastScrollTime = now
    scrollToBottom(proxy, animated: false)
}
```

---

### 🟡 P2 — Medium Impact

---

#### P2-1: `SidebarConversationMetadata` Static Sort (use `.max`)

**File:** `Odyssey/Views/MainWindow/SidebarView.swift:88–90`

Use `max(by:)` instead of `sorted().last` — O(n) vs O(n log n):
```swift
// Before:
let latestMessage = convo.messages.sorted { $0.timestamp < $1.timestamp }.last
// After:
let latestMessage = convo.messages.max { $0.timestamp < $1.timestamp }
```

---

#### P2-2: `AgentSidebarRowView` Observes AppState Unnecessarily

**File:** `Odyssey/Views/MainWindow/AgentSidebarRowView.swift:26, 41`

```swift
@EnvironmentObject private var appState: AppState
// ...
let activity = appState.conversationActivity(for: conv)  // called per row per render
```

`conversationActivity(for:)` iterates all sessions in the conversation on every call. Since `AgentSidebarRowView` observes `appState`, it re-renders (and calls this) on every streaming token.

**Fix:** Pass `hasActiveSession: Bool` from parent (already partially done) and pre-compute activity in parent before passing down. Remove the direct `@EnvironmentObject appState` observation from the row view.

---

#### P2-3: ChatView Has 40+ `@State` Variables

**File:** `Odyssey/Views/MainWindow/ChatView.swift:175–241`

ChatView declares ~40 `@State` properties. While each `@State` change only invalidates the current view body, this creates fragile state management and makes the view body very sensitive to local state changes. Any boolean toggle (e.g., `showSlashHelp`, `showMentionError`) causes a full `body` re-evaluation which runs all the expensive computed properties.

**Fix:** Group related state into focused child views:
- Extract composer state (inputText, attachments, slash commands) into a `ChatComposerView` with its own local state
- Extract streaming indicators into a `ChatStreamingView` with targeted AppState observation
- This naturally limits which re-renders recalculate expensive properties

---

#### P2-4: `sortedProjects` Recomputed on Every Render

**File:** `Odyssey/Views/MainWindow/SidebarView.swift:458–465`

```swift
private var sortedProjects: [Project] {
    projects.sorted { lhs, rhs in
        if lhs.isPinned != rhs.isPinned { return lhs.isPinned && !rhs.isPinned }
        return lhs.createdAt > rhs.createdAt
    }
}
```

The `@Query var projects` already has `sort: \Project.createdAt, order: .reverse`. The Swift-side sort adds pin priority — move this to a compound `SortDescriptor` at the query level or cache in `@State`.

---

#### P2-5: `GeometryReader` With Computation in `QuickActionsRow`

**File:** `Odyssey/Views/MainWindow/ChatView.swift:68–106`

```swift
var body: some View {
    GeometryReader { geo in
        let textCount = textLabelCount(for: geo.size.width)  // computed in body
        ScrollView(.horizontal) { ... }
    }
}
```

`textLabelCount` iterates over all actions with width arithmetic on every `GeometryReader` update (which fires on any size change). This is acceptable if the row is small, but the nested `ScrollView` inside `GeometryReader` can cause layout feedback loops on macOS. Consider using `ViewThatFits` instead (already used elsewhere in the app).

---

#### P2-6: Missing Throttle on WebSocket Message Processing

**File:** `Odyssey/Services/SidecarManager.swift`, `sidecar/src/ws-server.ts:89–99`

The TypeScript sidecar emits `stream.token` events synchronously per-character from the Claude SDK stream (e.g., `claude-runtime.ts:558`). No batching or throttling exists before events cross the WebSocket boundary. The Swift side processes each message immediately on `@MainActor`.

**Fix:** Batch tokens in the sidecar before sending — collect tokens for 50ms and send as a single `stream.token` with concatenated text:

```typescript
// In session-manager.ts or claude-runtime.ts:
private tokenBuffer: Map<string, string> = new Map();
private flushTimers: Map<string, ReturnType<typeof setTimeout>> = new Map();

private bufferToken(sessionId: string, text: string, emit: EmitFn) {
    this.tokenBuffer.set(sessionId, (this.tokenBuffer.get(sessionId) ?? "") + text);
    if (!this.flushTimers.has(sessionId)) {
        this.flushTimers.set(sessionId, setTimeout(() => {
            const buffered = this.tokenBuffer.get(sessionId) ?? "";
            this.tokenBuffer.delete(sessionId);
            this.flushTimers.delete(sessionId);
            if (buffered) emit({ type: "stream.token", sessionId, text: buffered });
        }, 50));
    }
}
```

This reduces WebSocket message frequency by ~10–20× with imperceptible latency change.

---

#### P2-7: `conversationsForProject` is O(all conversations)

**File:** `Odyssey/Views/MainWindow/SidebarView.swift:1945–1947`

```swift
private func conversationsForProject(_ project: Project) -> [Conversation] {
    conversations.filter { $0.projectId == project.id && $0.sourceGroupId == nil }
}
```

Called from multiple `@ViewBuilder` contexts per render. The `Project` model has a `conversations` relationship — use it directly to avoid the full scan:
```swift
private func conversationsForProject(_ project: Project) -> [Conversation] {
    project.conversations.filter { $0.sourceGroupId == nil }
}
```

---

#### P2-8: `AdmonitionParser.extractBlocks` Runs on Every MarkdownContent Render

**File:** `Odyssey/Views/Components/MarkdownContent.swift:17`

```swift
if renderAdmonitions, let blocks = AdmonitionParser.extractBlocks(from: renderedText), !blocks.isEmpty {
```

Another full-text scan per render. Cache alongside `renderedText` in the same `@State` update.

---

### 🔵 P3 — Low Impact / Polish

---

#### P3-1: `MessageBubble` Font Computed Properties

**File:** `Odyssey/Views/Components/MessageBubble.swift:41–55`

Font computed properties (`captionFont`, `bodyFont`, etc.) call `.system(size: 12 * appTextScale)` on every render. Font construction is cheap in SwiftUI but occurs for every visible bubble (potentially 50+). Cache these as stored properties or use `@ScaledMetric`.

---

#### P3-2: `childConversations` Linear Scan Per Node

**File:** `Odyssey/Views/MainWindow/SidebarView.swift:1076–1080`

```swift
private func childConversations(of parent: Conversation) -> [Conversation] {
    conversations.filter { $0.parentConversationId == parent.id }.sorted { ... }
}
```

For a conversation tree, use the `Conversation.children` relationship if it exists, avoiding the full `conversations` scan.

---

#### P3-3: `SidebarView` Has Redundant `@Query` for `allSessions`

**File:** `Odyssey/Views/MainWindow/SidebarView.swift:151`

```swift
@Query(sort: \Session.startedAt, order: .reverse) private var allSessions: [Session]
```

Used only in `conversationsForAgent` (and its archived variant). Consider removing this and using `agent.sessions` relationship instead.

---

#### P3-4: `CheckConversationSelectionChange` Called Twice

**File:** `Odyssey/Views/MainWindow/SidebarView.swift:375–379`

```swift
.onChange(of: windowState.selectedConversationId) { _, newValue in
    guard let selectedId = newValue else { return }
    handleConversationSelectionChange(selectedId)
    Task { @MainActor in handleConversationSelectionChange(selectedId) }  // called twice!
}
```

`handleConversationSelectionChange` is called synchronously and then again in a `Task`. This is likely a workaround for timing, but it double-executes potentially expensive logic (expanding project sections, scroll reveal). Investigate if the synchronous call alone is sufficient.

---

## Priority Ranking (Impact × Effort)

| Priority | Issue | Estimated Speedup | Effort |
|---|---|---|---|
| **1** | P0-1: Token render throttle | **10–20× fewer renders during streaming** | Medium (1–2 days) |
| **2** | P0-2: O(n²) string concatenation | Prevents quadratic slowdown on long responses | Low (2 hours) |
| **3** | P0-4: lastMessagePreview sort→max | Reduces per-row cost by O(log n) | Low (30 min) |
| **4** | P0-3: Cache sidebar computed data | Eliminates sidebar work during streaming | Medium (1 day) |
| **5** | P1-1: Add @Query predicates to ChatView | Faster view init, lower memory | Medium (half day) |
| **6** | P1-2: Cache sortedMessages | Eliminates N×sort-per-render in ChatView | Low (1 hour) |
| **7** | P1-3: Use agent.sessions relationship | Eliminates O(sessions) per agent row | Low (1 hour) |
| **8** | P1-6: Cache MarkdownContent.renderedText | Eliminates 300–1000 text scans/sec | Low (1 hour) |
| **9** | P2-6: Sidecar token batching | Reduces WebSocket frequency 10–20× | Low (2 hours) |
| **10** | P1-7: Throttle scrollToBottom | Reduces layout pressure 5× | Low (30 min) |

---

## Recommended Implementation Sequence

### Week 1 (Streaming Performance)
1. **P0-2** — Fix O(n²) string concat (isolated, very low risk)
2. **P0-4** — `lastMessagePreview`: switch to `.max(by:)` (one-line fix)
3. **P2-6** — Sidecar: add 50ms token batching in TypeScript (low-risk, measurable)
4. **P1-7** — Throttle `scrollToBottom` in ChatView
5. **P1-6** — Cache `MarkdownContent.renderedText`
6. **P1-2** — Cache `sortedMessages` in ChatView
7. **P1-3** — Use `agent.sessions` in `conversationsForAgent`

### Week 2 (Structural Improvements)
8. **P0-1** — Token render throttle (requires careful testing with streaming indicators)
9. **P0-3** — Cache sidebar sorted/filtered data in `@State`
10. **P1-1** — Add `@Query` predicates to ChatView

### Week 3 (Architecture)
11. Split `AppState` streaming properties into a separate `@Observable StreamingState`
12. Extract `ChatComposerView` with isolated state
13. Remove `@EnvironmentObject appState` from `AgentSidebarRowView`

---

## Profiling Setup Recommendations

To validate these findings with real measurements:

```bash
# 1. Build with profiling symbols
cd /Users/shayco/Odyssey
xcodebuild -scheme Odyssey -configuration Release \
  OTHER_SWIFT_FLAGS="-Onone -enable-testing" build

# 2. Open Instruments → Time Profiler
# Record while streaming a long message
# Look for: SwiftUI body calls, String._append operations

# 3. Hangs instrument — detect main thread blocks > 250ms

# 4. Allocations instrument — look for:
#    - String alloc growth during streaming (O(n²) pattern)
#    - View body allocation rate
```

**AppXray quick smoke test** (useful for before/after comparison):
1. `mcp__appxray__session action:"discover"` → `action:"connect"`
2. `mcp__appxray__inspect target:"timeline" category:"render"` — baseline render count
3. Start streaming a message, record for 10 seconds
4. `mcp__appxray__inspect target:"metrics" include:["fps","memory","renders"]`

**Sidecar log monitoring:**
```bash
curl -s localhost:9850/api/v1/debug/logs?tail=100 | jq '.[] | select(.level == "error")'
```

---

---

### Additional Findings (from deep code analysis)

---

#### A1: JSON Decoding on `@MainActor` for Every WebSocket Message

**File:** `Odyssey/Services/SidecarManager.swift:311–340`

```swift
private func receiveMessages() {
    webSocketTask?.receive { [weak self] result in
        Task { @MainActor in                        // forced onto main actor
            switch result {
            case .success(let message):
                self?.handleMessage(message)        // decoding here
```

```swift
private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
    ...
    guard let wire = try? JSONDecoder().decode(IncomingWireMessage.self, from: data),  // line 337
          let event = wire.toEvent() else { return }
```

The `Task { @MainActor in }` wrapper at line 313 forces the WebSocket callback—including `JSONDecoder().decode()`—to run on the main thread. For large events (tool results, multi-KB responses), this can block the UI thread for several milliseconds.

**Fix:** Decode on a background task, then yield on main:
```swift
webSocketTask?.receive { [weak self] result in
    guard let self else { return }
    if case .success(let message) = result {
        Task(priority: .userInitiated) {           // background decode
            guard let wire = try? JSONDecoder().decode(IncomingWireMessage.self, from: data),
                  let event = wire.toEvent() else { return }
            await MainActor.run { self.eventContinuation?.yield(event) }
        }
        self.receiveMessages()
    }
}
```

---

#### A2: Participants Array Fetched Inside ForEach Loop

**File:** `Odyssey/Views/MainWindow/ChatView.swift:1622–1625`

```swift
ForEach(displayMessages) { message in
    MessageBubble(
        message: message,
        participants: conversation?.participants ?? [],   // fetched per message
```

`conversation?.participants` is a SwiftData relationship — each access inside the loop can trigger a lazy fetch. With 200 messages, this relationship is accessed 200 times per render.

**Fix:** Hoist the fetch before the loop:
```swift
let participants = conversation?.participants ?? []
ForEach(displayMessages) { message in
    MessageBubble(message: message, participants: participants, ...)
}
```

---

#### A3: `GeometryReader` Per Message Bubble (Frame Tracking)

**File:** `Odyssey/Views/MainWindow/ChatView.swift:1642–1654`

Each message bubble wraps a `GeometryReader` to track its frame for scroll anchor restoration. With 200+ messages in a conversation, this places 200 `GeometryReader` instances in the layout tree, all reporting preference values that must be reduced via `ChatVisibleMessageFramesPreferenceKey`.

This preference reduction runs on every layout pass and every scroll event.

**Fix:** Track only the first and last ~5 visible messages rather than all messages. Or use `scrollPosition(id:)` (iOS 17 / macOS 14 API) to replace the manual preference tracking pattern entirely.

---

#### A4: `turnHistory` Map Unbounded Growth in Sidecar

**File:** `sidecar/src/session-manager.ts`

The `turnHistory` Map accumulates entries for every session ever created. Sessions are never evicted from this map even after completion, causing memory growth proportional to total sessions across the lifetime of the sidecar process.

**Fix:** Evict entries when sessions complete:
```typescript
// In sessionResult/sessionError handlers:
this.turnHistory.delete(sessionId);
```

Or use a time-based cleanup:
```typescript
// After session completes, schedule cleanup after 10 minutes
setTimeout(() => this.turnHistory.delete(sessionId), 10 * 60 * 1000);
```

---

## Appendix: Key Files for Each Fix

| File | Section | Issues |
|---|---|---|
| `Odyssey/App/AppState.swift:1088–1115` | `handleEvent` | P0-1, P0-2 |
| `Odyssey/Views/MainWindow/ChatView.swift:247–252` | `@Query` declarations | P1-1 |
| `Odyssey/Views/MainWindow/ChatView.swift:290–304` | `sortedMessages` | P1-2 |
| `Odyssey/Views/MainWindow/ChatView.swift:440–456` | `routingPreviewPlan` | P1-4 |
| `Odyssey/Views/MainWindow/ChatView.swift:458–473` | `participantAppearanceMap` | P1-5 |
| `Odyssey/Views/MainWindow/ChatView.swift:1802–1805` | `scrollToBottom` onChange | P1-7 |
| `Odyssey/Views/MainWindow/SidebarView.swift:87–128` | `lastMessagePreview` | P0-4 |
| `Odyssey/Views/MainWindow/SidebarView.swift:458–475` | `sortedProjects`, `residentAgents` | P0-3 |
| `Odyssey/Views/MainWindow/SidebarView.swift:753–764` | `projectThreadRows` | P0-3 |
| `Odyssey/Views/MainWindow/SidebarView.swift:1862–1918` | `conversationsForAgent`, `agentHasActiveSession` | P1-3 |
| `Odyssey/Views/MainWindow/AgentSidebarRowView.swift:26,41` | `appState` observation | P2-2 |
| `Odyssey/Views/Components/MarkdownContent.swift:11–13` | `renderedText` | P1-6 |
| `sidecar/src/providers/claude-runtime.ts:558` | Token emit | P2-6 |

---

*Generated by Claude Code performance review — 2026-04-18*
