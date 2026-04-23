# GH Inbox Sidebar Section — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a collapsible "GH Inbox" section to the sidebar (after Schedules) that lists GitHub issues as rows with 6 context-menu actions: Open in GitHub, Run Now, Open Conversation, Assign & Run, Close Issue, Delete.

**Architecture:** Issues are existing `Conversation` records queried by `githubIssueNumber != nil`. A new `ghIssueClose` wire command triggers `gh issue close` in the sidecar and returns a `ghIssueClosed` event that archives the conversation. `ghIssueRunNow` is a Swift-only method that creates or resumes sessions using existing `session.create` / `session.resume` commands.

**Tech Stack:** Swift 6 / SwiftUI / SwiftData (macOS 14), TypeScript / Bun sidecar, `gh` CLI for GitHub operations.

---

## File Map

| File | Change |
|---|---|
| `Odyssey/Models/Conversation.swift` | Add `ghOverrideAgentId: UUID?` |
| `Odyssey/Services/SidecarProtocol.swift` | Add `ghIssueClose` command + `GHIssueCloseWire`; add `ghIssueClosed` event + decoding |
| `sidecar/src/types.ts` | Add `gh.issue.close` command type; add `gh.issue.closed` event type |
| `sidecar/src/ws-server.ts` | Handle `gh.issue.close` case; run `gh issue close`, broadcast `gh.issue.closed` |
| `Odyssey/App/AppState.swift` | Add `ghIssueRunNow(_:agentOverride:)` + `handleGHIssueClosed(repo:number:)` + `handleEvent` case |
| `Odyssey/Views/MainWindow/SidebarView.swift` | Add `@Query ghIssues`, `@AppStorage isGHInboxExpanded`, `@State issueToDelete`; insert `ghInboxSection`; add section/row/menu builder methods |
| `OdysseyTests/AppStateGHInboxTests.swift` | New: XCTest for `ghIssueRunNow` (creates session) and `handleGHIssueClosed` (archives conv) |
| `sidecar/test/unit/gh-inbox.test.ts` | New: unit test that `gh.issue.close` broadcasts `gh.issue.closed` |

---

## Task 1: Wire Protocol — `ghIssueClose` command + `ghIssueClosed` event

**Files:**
- Modify: `Odyssey/Services/SidecarProtocol.swift`
- Modify: `sidecar/src/types.ts`

### Steps

- [ ] **1.1 Add `ghIssueClose` to `SidecarCommand` enum**

In `SidecarProtocol.swift`, add after `case ghPollerConfig(...)` (line ~52):

```swift
case ghIssueClose(repo: String, number: Int)
```

- [ ] **1.2 Add encoding for `ghIssueClose` in `encodeToJSON()`**

In `SidecarProtocol.swift`, add before the closing `}` of the switch in `encodeToJSON()` (after the `.ghPollerConfig` case, line ~284):

```swift
case .ghIssueClose(let repo, let number):
    struct GHIssueCloseWire: Encodable {
        let type: String; let repo: String; let number: Int
    }
    return try encoder.encode(GHIssueCloseWire(type: "gh.issue.close", repo: repo, number: number))
```

- [ ] **1.3 Add `ghIssueClosed` to `SidecarEvent` enum**

In `SidecarProtocol.swift`, add after `case ghIssueCreated(...)` (line ~795):

```swift
case ghIssueClosed(repo: String, number: Int)
```

- [ ] **1.4 Add decoding for `ghIssueClosed` in `IncomingWireMessage.toEvent()`**

In `SidecarProtocol.swift`, add after the `"gh.issue.created"` case (line ~1181):

```swift
case "gh.issue.closed":
    guard let r = issueRepo, let num = issueNumber else { return nil }
    return .ghIssueClosed(repo: r, number: num)
```

- [ ] **1.5 Add `gh.issue.close` to `SidecarCommand` union in `types.ts`**

In `sidecar/src/types.ts`, add after the `"gh.poller.config"` line (line ~61):

```typescript
  | { type: "gh.issue.close"; repo: string; number: number }
```

- [ ] **1.6 Add `gh.issue.closed` to `SidecarEvent` union in `types.ts`**

In `sidecar/src/types.ts`, add after the `"gh.issue.created"` line (line ~320):

```typescript
  | { type: "gh.issue.closed"; repo: string; number: number }
```

- [ ] **1.7 Commit**

```bash
git add Odyssey/Services/SidecarProtocol.swift sidecar/src/types.ts
git commit -m "feat: add ghIssueClose command and ghIssueClosed event to wire protocol"
```

---

## Task 2: Sidecar — Handle `gh.issue.close`

**Files:**
- Modify: `sidecar/src/ws-server.ts`
- Create: `sidecar/test/unit/gh-inbox.test.ts`

### Steps

- [ ] **2.1 Write the failing test**

Create `sidecar/test/unit/gh-inbox.test.ts`:

```typescript
import { describe, test, expect, mock, beforeEach } from "bun:test";

// We test the command dispatch logic by verifying the broadcast shape.
// This test mocks runGh to avoid hitting the CLI.

describe("gh.issue.close ws-server dispatch", () => {
  test("broadcasts gh.issue.closed on successful close", async () => {
    const broadcasts: unknown[] = [];

    // Minimal mock of the tool context broadcast
    const ctx = {
      broadcast: (event: unknown) => broadcasts.push(event),
      ghPollerConfig: undefined,
    };

    // Import the handler logic via a small inline harness (avoids full server init)
    // We call the dispatchCommand helper that ws-server.ts exposes for testing.
    // NOTE: ws-server.ts must export a dispatchCommand(command, ctx) function for this test to work.
    // The implementation task adds that export.
    const { dispatchGHCommand } = await import("../../src/gh-command-handler.js");

    await dispatchGHCommand({ type: "gh.issue.close", repo: "owner/repo", number: 42 }, ctx as any);

    expect(broadcasts).toHaveLength(1);
    expect(broadcasts[0]).toMatchObject({ type: "gh.issue.closed", repo: "owner/repo", number: 42 });
  });
});
```

- [ ] **2.2 Run test to confirm it fails**

```bash
cd sidecar && bun test test/unit/gh-inbox.test.ts
```

Expected: FAIL — `gh-command-handler.js` not found.

- [ ] **2.3 Create `sidecar/src/gh-command-handler.ts`**

```typescript
import { runGh } from "./gh-cli.js";
import { logger } from "./logger.js";

export interface GHCommandContext {
  broadcast: (event: object) => void;
}

export async function dispatchGHCommand(
  command: { type: string; repo?: string; number?: number },
  ctx: GHCommandContext
): Promise<void> {
  if (command.type === "gh.issue.close") {
    if (!command.repo || command.number === undefined) return;
    try {
      await runGh(["issue", "close", String(command.number), "--repo", command.repo]);
      ctx.broadcast({ type: "gh.issue.closed", repo: command.repo, number: command.number });
    } catch (err) {
      logger.error("github", "gh.issue.close failed", { error: String(err) });
    }
  }
}
```

- [ ] **2.4 Wire `dispatchGHCommand` into `ws-server.ts`**

In `sidecar/src/ws-server.ts`, add the import after the existing `runGh` import:

```typescript
import { dispatchGHCommand } from "./gh-command-handler.js";
```

In the `handleCommand` switch block, add after the `"gh.poller.config"` case (before the closing `}`):

```typescript
      case "gh.issue.close":
        await dispatchGHCommand(command, this.ctx);
        break;
```

- [ ] **2.5 Run test to confirm it passes**

```bash
cd sidecar && bun test test/unit/gh-inbox.test.ts
```

Expected: PASS.

- [ ] **2.6 Commit**

```bash
git add sidecar/src/gh-command-handler.ts sidecar/src/ws-server.ts sidecar/test/unit/gh-inbox.test.ts
git commit -m "feat: handle gh.issue.close in sidecar, extract dispatchGHCommand"
```

---

## Task 3: Conversation Model — `ghOverrideAgentId`

**Files:**
- Modify: `Odyssey/Models/Conversation.swift`

### Steps

- [ ] **3.1 Add `ghOverrideAgentId` field**

In `Conversation.swift`, add after `var githubIssueRepo: String?` (line ~138):

```swift
var ghOverrideAgentId: UUID?    // agent override set by Assign & Run
```

- [ ] **3.2 Build-check to verify SwiftData migration compiles**

```bash
make build-check
```

Expected: Build succeeds (SwiftData adds the nullable column via lightweight migration).

- [ ] **3.3 Commit**

```bash
git add Odyssey/Models/Conversation.swift
git commit -m "feat: add ghOverrideAgentId to Conversation for GH inbox agent override"
```

---

## Task 4: AppState — `ghIssueRunNow` + `handleGHIssueClosed`

**Files:**
- Modify: `Odyssey/App/AppState.swift`
- Create: `OdysseyTests/AppStateGHInboxTests.swift`

### Steps

- [ ] **4.1 Write the failing tests**

Create `OdysseyTests/AppStateGHInboxTests.swift`:

```swift
import XCTest
import SwiftData
@testable import Odyssey

@MainActor
final class AppStateGHInboxTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var appState: AppState!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Agent.self, Session.self, Conversation.self,
            ConversationMessage.self, MessageAttachment.self,
            Participant.self, Skill.self, Connection.self, MCPServer.self,
            PermissionSet.self, BlackboardEntry.self,
            configurations: config
        )
        context = container.mainContext
        appState = AppState()
        appState.modelContext = context
    }

    override func tearDown() async throws {
        appState = nil
        container = nil
        context = nil
    }

    // MARK: - GH1: ghIssueRunNow creates a new session when none exists

    func testGH1_ghIssueRunNow_createsSessionWhenNone() throws {
        let agent = Agent(name: "Dev", systemPrompt: "dev")
        context.insert(agent)

        let conv = Conversation(topic: "GH #1: Fix bug", threadKind: .autonomous)
        conv.githubIssueNumber = 1
        conv.githubIssueRepo = "owner/repo"
        conv.githubIssueUrl = "https://github.com/owner/repo/issues/1"
        context.insert(conv)
        try context.save()

        appState.ghIssueRunNow(conv, agentOverride: agent)

        let sessions = (conv.sessions ?? [])
        XCTAssertEqual(sessions.count, 1, "Should have created one session")
        XCTAssertEqual(sessions.first?.agent?.name, "Dev")
        XCTAssertEqual(sessions.first?.mode, .autonomous)
    }

    // MARK: - GH2: ghIssueRunNow with override stores ghOverrideAgentId

    func testGH2_ghIssueRunNow_storesAgentOverride() throws {
        let agent = Agent(name: "Override Agent", systemPrompt: "")
        context.insert(agent)

        let conv = Conversation(topic: "GH #2: Feature", threadKind: .autonomous)
        conv.githubIssueNumber = 2
        conv.githubIssueRepo = "owner/repo"
        context.insert(conv)
        try context.save()

        appState.ghIssueRunNow(conv, agentOverride: agent)

        XCTAssertEqual(conv.ghOverrideAgentId, agent.id)
    }

    // MARK: - GH3: handleGHIssueClosed archives the conversation

    func testGH3_handleGHIssueClosed_archivesConversation() throws {
        let conv = Conversation(topic: "GH #5: Close me", threadKind: .autonomous)
        conv.githubIssueNumber = 5
        conv.githubIssueRepo = "owner/repo"
        conv.isArchived = false
        context.insert(conv)
        try context.save()

        appState.handleEventForTesting(.ghIssueClosed(repo: "owner/repo", number: 5))

        XCTAssertTrue(conv.isArchived, "Conversation should be archived after issue close")
    }

    // MARK: - GH4: handleGHIssueClosed does nothing for unknown issue

    func testGH4_handleGHIssueClosed_unknownIssue_doesNotCrash() {
        // Should not throw or crash when no matching conversation exists
        appState.handleEventForTesting(.ghIssueClosed(repo: "owner/repo", number: 9999))
        // Test passes if no crash
    }
}
```

- [ ] **4.2 Run tests to confirm they fail**

```bash
make build-check 2>&1 | grep -E "error:|AppStateGHInbox"
```

Expected: compile errors — `ghIssueRunNow` and the `ghIssueClosed` event case don't exist yet.

- [ ] **4.3 Add `ghIssueRunNow` to `AppState.swift`**

In `AppState.swift`, in the `// MARK: - GitHub Issue Bridge Event Handlers` section (after `handleGHIssueCreated`, around line 1969), add:

```swift
// MARK: - GH Inbox Actions

@MainActor
func ghIssueRunNow(_ conv: Conversation, agentOverride: Agent? = nil) {
    guard let ctx = modelContext else { return }

    // Store agent override if provided
    if let override = agentOverride {
        conv.ghOverrideAgentId = override.id
        try? ctx.save()
    }

    // Resolve target agent: override arg → stored override → existing session's agent
    let targetAgent: Agent? = {
        if let a = agentOverride { return a }
        if let overrideId = conv.ghOverrideAgentId {
            let d = FetchDescriptor<Agent>(predicate: #Predicate { $0.id == overrideId })
            if let a = try? ctx.fetch(d).first { return a }
        }
        return conv.primarySession?.agent
    }()

    guard let agent = targetAgent else {
        Log.github.warning("ghIssueRunNow: no agent resolved for conv \(conv.id)")
        return
    }

    let existingSession = conv.primarySession

    // Resume if a pausable session with a claudeSessionId exists
    if let session = existingSession,
       let claudeSessionId = session.claudeSessionId,
       session.status == .paused || session.status == .interrupted {
        session.status = .active
        try? ctx.save()
        sendToSidecar(.sessionResume(sessionId: session.id.uuidString, claudeSessionId: claudeSessionId))
        Log.github.info("ghIssueRunNow: resumed session \(session.id) for conv \(conv.id)")
        return
    }

    // Create a new session
    let provisioner = AgentProvisioner(modelContext: ctx)
    let mission = conv.topic ?? conv.githubIssueNumber.map { "GitHub Issue #\($0)" } ?? "GitHub Issue"
    let (config, newSession) = provisioner.provision(agent: agent, mission: mission, mode: .autonomous)

    newSession.conversations = [conv]
    conv.sessions = (conv.sessions ?? []) + [newSession]
    ctx.insert(newSession)
    try? ctx.save()

    sendToSidecar(.sessionCreate(conversationId: newSession.id.uuidString, agentConfig: config))
    Log.github.info("ghIssueRunNow: created session \(newSession.id) for conv \(conv.id)")
}
```

- [ ] **4.4 Add `handleGHIssueClosed` to `AppState.swift`**

Immediately after `ghIssueRunNow`, add:

```swift
@MainActor
private func handleGHIssueClosed(repo: String, number: Int) {
    guard let ctx = modelContext else { return }
    let descriptor = FetchDescriptor<Conversation>(
        predicate: #Predicate { $0.githubIssueNumber == number }
    )
    guard let conv = (try? ctx.fetch(descriptor))?.first(where: { $0.githubIssueRepo == repo }) else {
        Log.github.warning("gh.issue.closed: no conversation for #\(number) in \(repo)")
        return
    }
    conv.isArchived = true
    try? ctx.save()
    Log.github.info("gh.issue.closed: archived conv \(conv.id) for #\(number) in \(repo)")
}
```

- [ ] **4.5 Add `ghIssueClosed` case to `handleEvent` switch in `AppState.swift`**

In `handleEvent`, after the `case .ghIssueCreated(...)` block (around line 1898):

```swift
case .ghIssueClosed(let repo, let number):
    Log.github.info("gh.issue.closed #\(number, privacy: .public) \(repo, privacy: .public)")
    handleGHIssueClosed(repo: repo, number: number)
```

- [ ] **4.6 Run tests to confirm they pass**

```bash
make build-check
```

Expected: Build succeeds. Then run:

```bash
xcodebuild test -scheme Odyssey -only-testing OdysseyTests/AppStateGHInboxTests 2>&1 | tail -20
```

Expected: All 4 tests pass.

- [ ] **4.7 Commit**

```bash
git add Odyssey/App/AppState.swift OdysseyTests/AppStateGHInboxTests.swift
git commit -m "feat: add ghIssueRunNow and handleGHIssueClosed to AppState"
```

---

## Task 5: SidebarView — GH Inbox Section

**Files:**
- Modify: `Odyssey/Views/MainWindow/SidebarView.swift`

### Steps

- [ ] **5.1 Add stored properties to `SidebarView`**

In `SidebarView.swift`, add after the existing `@AppStorage("sidebar.allSchedulesExpanded")` line (around line 192):

```swift
@AppStorage("sidebar.ghInboxExpanded") private var isGHInboxExpanded: Bool = true
```

Add after the existing `@Query(sort: \ScheduledMission...)` line (around line 143):

```swift
@Query(
    filter: #Predicate<Conversation> { $0.githubIssueNumber != nil && $0.isArchived == false },
    sort: \Conversation.startedAt,
    order: .reverse
)
private var ghIssues: [Conversation]
```

Add with the other `@State` delete-confirmation vars (around line 178):

```swift
@State private var issueToDelete: Conversation?
@State private var showingGHIssueSheet = false
```

- [ ] **5.2 Insert `ghInboxSection` into the sidebar `List`**

In `sidebarList` (around line 438), add between `globalUtilitiesSection` and `pinnedSection`:

```swift
return List {
    globalUtilitiesSection

    if !ghIssues.isEmpty {
        ghInboxSection
    }

    pinnedSection
    // ... rest unchanged
```

- [ ] **5.3 Add `ghInboxSection` computed var**

After the closing `}` of `globalUtilitiesSection` (around line 1577), add:

```swift
@ViewBuilder
private var ghInboxSection: some View {
    Section {
        if isGHInboxExpanded {
            ForEach(ghIssues) { conv in
                ghInboxIssueRow(conv)
            }
        }
    } header: {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isGHInboxExpanded.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isGHInboxExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("GH Inbox")
                        .font(.headline.weight(.semibold))
                    let unhandledCount = ghIssues.filter {
                        ($0.primarySession?.status ?? .completed) != .active
                    }.count
                    if unhandledCount > 0 {
                        Text("\(unhandledCount)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.red)
                            .clipShape(Capsule())
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer()
            Button {
                showingGHIssueSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Create GitHub issue")
            .help("Create GitHub issue")
        }
    }
    .sheet(isPresented: $showingGHIssueSheet) {
        CreateGHIssueSheet(conversation: nil, project: nil)
            .environment(appState)
            .environment(\.modelContext, modelContext)
    }
    .stableXrayId("sidebar.ghInboxSection")
    .alert("Delete Issue Conversation?", isPresented: Binding(
        get: { issueToDelete != nil },
        set: { if !$0 { issueToDelete = nil } }
    )) {
        Button("Delete", role: .destructive) {
            if let conv = issueToDelete {
                modelContext.delete(conv)
                try? modelContext.save()
            }
            issueToDelete = nil
        }
        Button("Cancel", role: .cancel) { issueToDelete = nil }
    } message: {
        if let conv = issueToDelete {
            Text("Remove the local conversation for \"\(conv.topic ?? "this issue")\"? The GitHub issue will not be affected.")
        }
    }
}
```

- [ ] **5.4 Add `ghInboxIssueRow` method**

After the closing `}` of `ghInboxSection`, add:

```swift
@ViewBuilder
private func ghInboxIssueRow(_ conv: Conversation) -> some View {
    let session = conv.primarySession
    let isRunning = session?.status == .active
    let isPaused = session?.status == .paused || session?.status == .interrupted
    let dotColor: Color = isRunning ? .blue : isPaused ? .orange : .green

    Button {
        if let urlString = conv.githubIssueUrl, let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    } label: {
        HStack(spacing: 8) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(issueRowTitle(conv))
                    .font(.callout)
                    .lineLimit(1)
                if let agentName = session?.agent?.name {
                    Text(agentName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
        }
        .padding(.leading, 18)
    }
    .buttonStyle(.plain)
    .stableXrayId("sidebar.ghInboxRow.\(conv.id.uuidString)")
    .contextMenu {
        // 1. Open in GitHub
        Button {
            if let urlString = conv.githubIssueUrl, let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            Label("Open in GitHub", systemImage: "arrow.up.right.square")
        }
        .disabled(conv.githubIssueUrl == nil)

        // 2. Run Now
        Button {
            appState.ghIssueRunNow(conv)
        } label: {
            Label("Run Now", systemImage: "play.fill")
        }
        .disabled(isRunning)

        // 3. Open Conversation
        Button {
            windowState.selectedConversationId = conv.id
        } label: {
            Label("Open Conversation", systemImage: "bubble.left")
        }
        .disabled((conv.messages ?? []).isEmpty)

        Divider()

        // 4. Assign & Run (submenu — agents only; `agents` is the @Query var on SidebarView)
        Menu {
            ForEach(agents.filter { $0.isEnabled }) { agent in
                Button(agent.name) {
                    appState.ghIssueRunNow(conv, agentOverride: agent)
                }
            }
        } label: {
            Label("Assign & Run…", systemImage: "cpu")
        }

        Divider()

        // 5. Close Issue
        Button {
            if let repo = conv.githubIssueRepo, let number = conv.githubIssueNumber {
                appState.sendToSidecar(.ghIssueClose(repo: repo, number: number))
            }
        } label: {
            Label("Close Issue", systemImage: "checkmark.circle")
        }
        .disabled(conv.githubIssueRepo == nil || conv.githubIssueNumber == nil)

        // 6. Delete
        Button(role: .destructive) {
            issueToDelete = conv
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}

private func issueRowTitle(_ conv: Conversation) -> String {
    if let number = conv.githubIssueNumber {
        let title = conv.topic ?? "Issue"
        // Strip the "GH #N: " prefix if it was auto-generated
        let prefix = "GH #\(number): "
        return "#\(number) \(title.hasPrefix(prefix) ? String(title.dropFirst(prefix.count)) : title)"
    }
    return conv.topic ?? "GitHub Issue"
}
```

- [ ] **5.5 Verify `sendToSidecar` is accessible from the view**

`sendToSidecar` is already declared `internal` (no access modifier) on `AppState` — the context menu call `appState.sendToSidecar(...)` in `ghInboxIssueRow` will compile without changes. Confirm with:

```bash
grep -n "func sendToSidecar" Odyssey/App/AppState.swift
```

Expected output: `777:    func sendToSidecar(_ command: SidecarCommand) {` (no `private` prefix).

- [ ] **5.6 Build-check**

```bash
make build-check
```

Expected: Build succeeds. Fix any remaining compile errors (missing imports, name mismatches).

- [ ] **5.7 Commit**

```bash
git add Odyssey/Views/MainWindow/SidebarView.swift Odyssey/App/AppState.swift
git commit -m "feat: add GH Inbox sidebar section with 6 context-menu actions"
```

---

## Task 6: Sidecar Smoke Test + Final Check

**Steps:**

- [ ] **6.1 Run full feedback suite**

```bash
make feedback
```

Expected: Build + sidecar smoke pass.

- [ ] **6.2 Run new Swift tests**

```bash
xcodebuild test -scheme Odyssey -only-testing OdysseyTests/AppStateGHInboxTests 2>&1 | grep -E "passed|failed|error"
```

Expected: 4 tests pass.

- [ ] **6.3 Run new TS unit test**

```bash
cd sidecar && bun test test/unit/gh-inbox.test.ts
```

Expected: 1 test passes.

- [ ] **6.4 Final commit if any fixups**

```bash
git add -p
git commit -m "fix: gh inbox sidebar polish and smoke fixes"
```

---

## Spec Coverage Checklist

| Requirement | Task |
|---|---|
| Section after Schedules | 5.2 |
| `@Query` on `githubIssueNumber != nil` | 5.1 |
| Status dots (blue/orange/green) | 5.4 |
| Badge count (unhandled) | 5.3 |
| Collapse/expand with `@AppStorage` | 5.1, 5.3 |
| Single-click opens in GitHub | 5.4 |
| Context menu: Open in GitHub | 5.4 |
| Context menu: Run Now | 5.4 |
| Context menu: Open Conversation (disabled if no messages) | 5.4 |
| Context menu: Assign & Run sub-menu | 5.4 |
| Context menu: Close Issue → sidecar command | 5.4 |
| Context menu: Delete with confirmation | 5.3, 5.4 |
| `ghIssueClose` wire command | 1.1–1.2, 1.5 |
| `ghIssueClosed` event | 1.3–1.4, 1.6 |
| Sidecar `gh.issue.close` handler | 2.3–2.4 |
| `Conversation.ghOverrideAgentId` | 3.1 |
| `AppState.ghIssueRunNow` | 4.3 |
| `AppState.handleGHIssueClosed` | 4.4–4.5 |
| Accessibility identifiers | 5.3, 5.4 |
