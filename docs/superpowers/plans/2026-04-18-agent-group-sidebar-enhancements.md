# Agent & Group Sidebar Enhancements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add show/hide sidebar control for agents/groups, archive/delete on inline thread rows, richer context menus, and remove Duplicate from conversation menus.

**Architecture:** One `Bool` property added to each model; sidebar filters + "N hidden" hints in `SidebarView`; thread row context menus in `AgentSidebarRowView` and `GroupSidebarRowView`; Show in Sidebar toggle added to `ConfigurationDetailView`. No new files.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, macOS 14.0+

---

### Task 1: Add `showInSidebar` to Agent and AgentGroup models

**Files:**
- Modify: `Odyssey/Models/Agent.swift`
- Modify: `Odyssey/Models/AgentGroup.swift`
- Create: `OdysseyTests/AgentSidebarTests.swift`

- [ ] **Step 1: Create the test file**

```swift
// OdysseyTests/AgentSidebarTests.swift
import XCTest
@testable import Odyssey

final class AgentSidebarTests: XCTestCase {
    func testAgentShowInSidebarDefaultsTrue() {
        let agent = Agent(name: "Test Agent")
        XCTAssertTrue(agent.showInSidebar)
    }

    func testAgentGroupShowInSidebarDefaultsTrue() {
        let group = AgentGroup(name: "Test Group")
        XCTAssertTrue(group.showInSidebar)
    }
}
```

- [ ] **Step 2: Run to confirm compile failure**

```bash
xcodebuild test -scheme Odyssey -only-testing OdysseyTests/AgentSidebarTests 2>&1 | grep -E "error:|PASSED|FAILED" | head -10
```
Expected: compile error — `showInSidebar` not found on `Agent` or `AgentGroup`.

- [ ] **Step 3: Add property to Agent**

In `Odyssey/Models/Agent.swift`, after `var isEnabled: Bool = true` (line ~53):

```swift
    var isEnabled: Bool = true
    var showInSidebar: Bool = true
    var configSlug: String?
```

- [ ] **Step 4: Add property to AgentGroup**

In `Odyssey/Models/AgentGroup.swift`, after `var isEnabled: Bool = true` (line ~20):

```swift
    var isEnabled: Bool = true
    var showInSidebar: Bool = true
    var configSlug: String?
```

- [ ] **Step 5: Run tests**

```bash
xcodebuild test -scheme Odyssey -only-testing OdysseyTests/AgentSidebarTests 2>&1 | grep -E "PASSED|FAILED|error:"
```
Expected: `Test Suite 'AgentSidebarTests' passed` — 2 tests passing.

- [ ] **Step 6: Commit**

```bash
git add Odyssey/Models/Agent.swift Odyssey/Models/AgentGroup.swift OdysseyTests/AgentSidebarTests.swift
git commit -m "feat: add showInSidebar to Agent and AgentGroup models"
```

---

### Task 2: Filter sidebar agents/groups and add "N hidden · manage →" hints

**Files:**
- Modify: `Odyssey/Views/MainWindow/SidebarView.swift`

- [ ] **Step 1: Filter nonResidentAgents by showInSidebar**

In `SidebarView.swift`, find `nonResidentAgents` (line ~387). Change the filter:

```swift
// Before:
private var nonResidentAgents: [Agent] {
    agents.filter { $0.isEnabled && !$0.isResident }
        .sorted { $0.name < $1.name }
}

// After:
private var nonResidentAgents: [Agent] {
    agents.filter { $0.isEnabled && !$0.isResident && $0.showInSidebar }
        .sorted { $0.name < $1.name }
}
```

Resident agents (`residentAgents`) are intentionally left unchanged — they always show.

- [ ] **Step 2: Add "N hidden" hint for agents**

In `agentsSection` (line ~1450), inside the `Section { ... }`, after the "show more/fewer" button block, add:

```swift
let hiddenAgentCount = agents.filter { $0.isEnabled && !$0.isResident && !$0.showInSidebar }.count
if hiddenAgentCount > 0 {
    Button {
        windowState.openConfiguration(section: .agents)
    } label: {
        Text("\(hiddenAgentCount) hidden · manage →")
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("sidebar.agentsHiddenHint")
}
```

- [ ] **Step 3: Filter groups by showInSidebar and add hint**

In `groupsSection` (line ~1348), change the `ForEach` filter and add the hint after the `ForEach`:

```swift
// Change line 1350 from:
ForEach(groups.filter { $0.isEnabled }) { group in
// To:
ForEach(groups.filter { $0.isEnabled && $0.showInSidebar }) { group in
```

After the closing `}` of the `ForEach` block (before `} header:`), add:

```swift
let hiddenGroupCount = groups.filter { $0.isEnabled && !$0.showInSidebar }.count
if hiddenGroupCount > 0 {
    Button {
        windowState.openConfiguration(section: .groups)
    } label: {
        Text("\(hiddenGroupCount) hidden · manage →")
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("sidebar.groupsHiddenHint")
}
```

- [ ] **Step 4: Build and verify**

Build (`⌘B`). Temporarily set `agent.showInSidebar = false` on a non-resident agent via the Xcode debugger or a quick inline test to confirm it disappears from the sidebar and "N hidden · manage →" appears.

- [ ] **Step 5: Commit**

```bash
git add Odyssey/Views/MainWindow/SidebarView.swift
git commit -m "feat: filter sidebar agents/groups by showInSidebar, add N hidden hint"
```

---

### Task 3: Add context menu to thread rows in AgentSidebarRowView

**Files:**
- Modify: `Odyssey/Views/MainWindow/AgentSidebarRowView.swift`
- Modify: `Odyssey/Views/MainWindow/SidebarView.swift`

- [ ] **Step 1: Add modelContext and delete callback to AgentSidebarRowView**

In `AgentSidebarRowView.swift`, add the environment and callback:

```swift
struct AgentSidebarRowView: View {
    let agent: Agent
    let conversations: [Conversation]
    @Binding var isExpanded: Bool
    let onNewChat: () -> Void
    let onSelectConversation: (Conversation) -> Void
    var onDeleteConversation: ((Conversation) -> Void)?   // ← add
    var onSelectAgent: (() -> Void)?
    var selectedConversationId: UUID?
    var hasActiveSession: Bool = false

    @Environment(\.modelContext) private var modelContext   // ← add
    @State private var showAllConversations = false         // ← add
```

- [ ] **Step 2: Replace the ForEach in AgentSidebarRowView with context menu + show-all**

Replace the existing `ForEach(conversations.prefix(10))` block (lines 21–52) with:

```swift
let displayed = showAllConversations ? conversations : Array(conversations.prefix(10))
ForEach(displayed) { conv in
    let isConvSelected = selectedConversationId == conv.id
    Button {
        onSelectConversation(conv)
    } label: {
        HStack(spacing: 6) {
            if conv.isUnread {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 6, height: 6)
            }
            Image(systemName: "bubble.left")
                .font(.caption2)
                .foregroundStyle(isConvSelected ? Color.accentColor.opacity(1) : Color.secondary.opacity(0.5))
            Text(conv.topic ?? "Untitled")
                .font(conv.isUnread ? .caption.bold() : .caption)
                .foregroundStyle(isConvSelected ? Color.primary : .primary)
                .lineLimit(1)
            Spacer()
            Text(conv.startedAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(isConvSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
    .buttonStyle(.plain)
    .stableXrayId("sidebar.agentRow.\(agent.id.uuidString).chatRow.\(conv.id.uuidString)")
    .accessibilityIdentifier("sidebar.agentThreadRow.\(conv.id.uuidString)")
    .accessibilityLabel("Open chat \(conv.topic ?? "Untitled")")
    .contextMenu {
        Button("Open Thread") {
            onSelectConversation(conv)
        }
        Divider()
        Button("Archive") {
            conv.isArchived = true
            conv.isPinned = false
            try? modelContext.save()
        }
        .accessibilityIdentifier("sidebar.agentThreadRow.archive.\(conv.id.uuidString)")
        Button("Delete\u{2026}", role: .destructive) {
            onDeleteConversation?(conv)
        }
        .accessibilityIdentifier("sidebar.agentThreadRow.delete.\(conv.id.uuidString)")
    }
}

if !showAllConversations && conversations.count > 10 {
    Button("Show all \(conversations.count) threads →") {
        showAllConversations = true
    }
    .font(.caption2)
    .foregroundStyle(.secondary)
    .buttonStyle(.plain)
    .padding(.leading, 6)
    .accessibilityIdentifier("sidebar.agentShowAllThreads.\(agent.id.uuidString)")
}
```

- [ ] **Step 3: Pass onDeleteConversation from SidebarView**

In `SidebarView.swift`, in `agentSidebarRow`, add `onDeleteConversation` to the `AgentSidebarRowView` init:

```swift
AgentSidebarRowView(
    agent: agent,
    conversations: conversationsForAgent(agent),
    isExpanded: Binding(
        get: { expandedAgentIds.contains(agent.id) },
        set: { expanded in
            if expanded { expandedAgentIds.insert(agent.id) }
            else { expandedAgentIds.remove(agent.id) }
        }
    ),
    onNewChat: { startSession(with: agent) },
    onDeleteConversation: { conv in promptDelete(conv) },   // ← add
    onSelectConversation: { conv in
        windowState.selectedConversationId = conv.id
    },
    onSelectAgent: {
        selectOrCreateAgentChat(agent)
    },
    selectedConversationId: windowState.selectedConversationId,
    hasActiveSession: agentHasActiveSession(agent)
)
```

- [ ] **Step 4: Build and verify**

Build. Expand an agent row and right-click a thread — confirm "Open Thread", "Archive", "Delete…" appear.

- [ ] **Step 5: Commit**

```bash
git add Odyssey/Views/MainWindow/AgentSidebarRowView.swift Odyssey/Views/MainWindow/SidebarView.swift
git commit -m "feat: add archive/delete context menu to inline agent thread rows"
```

---

### Task 4: Add context menu to thread rows in GroupSidebarRowView

**Files:**
- Modify: `Odyssey/Views/GroupLibrary/GroupSidebarRowView.swift`
- Modify: `Odyssey/Views/MainWindow/SidebarView.swift`

- [ ] **Step 1: Add modelContext and delete callback to GroupSidebarRowView**

```swift
struct GroupSidebarRowView: View {
    let group: AgentGroup
    let conversations: [Conversation]
    let allAgents: [Agent]
    @Binding var isExpanded: Bool
    let onNewChat: () -> Void
    let onNewAutonomousChat: (() -> Void)?
    let onSelectConversation: (Conversation) -> Void
    var onDeleteConversation: ((Conversation) -> Void)?   // ← add
    var onSelectGroup: (() -> Void)?
    var onEdit: (() -> Void)?
    var onDuplicate: (() -> Void)?
    var selectedConversationId: UUID?
    var hasActiveSession: Bool = false

    @Environment(\.modelContext) private var modelContext   // ← add
    @State private var showAllConversations = false         // ← add
```

- [ ] **Step 2: Replace ForEach in GroupSidebarRowView with context menu + show-all**

Replace the existing `ForEach(conversations.prefix(10))` block (lines 25–54) with the same pattern as Task 3, substituting `group.id.uuidString` for `agent.id.uuidString`:

```swift
let displayed = showAllConversations ? conversations : Array(conversations.prefix(10))
ForEach(displayed) { conv in
    let isConvSelected = selectedConversationId == conv.id
    Button {
        onSelectConversation(conv)
    } label: {
        HStack(spacing: 6) {
            if conv.isUnread {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 6, height: 6)
            }
            Image(systemName: "bubble.left")
                .font(.caption2)
                .foregroundStyle(isConvSelected ? Color.accentColor.opacity(1) : Color.secondary.opacity(0.5))
            Text(conv.topic ?? "Untitled")
                .font(conv.isUnread ? .caption.bold() : .caption)
                .lineLimit(1)
            Spacer()
            Text(conv.startedAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(isConvSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
    .buttonStyle(.plain)
    .stableXrayId("sidebar.groupRow.\(group.id.uuidString).chatRow.\(conv.id.uuidString)")
    .accessibilityIdentifier("sidebar.agentThreadRow.\(conv.id.uuidString)")
    .contextMenu {
        Button("Open Thread") {
            onSelectConversation(conv)
        }
        Divider()
        Button("Archive") {
            conv.isArchived = true
            conv.isPinned = false
            try? modelContext.save()
        }
        Button("Delete\u{2026}", role: .destructive) {
            onDeleteConversation?(conv)
        }
    }
}

if !showAllConversations && conversations.count > 10 {
    Button("Show all \(conversations.count) threads →") {
        showAllConversations = true
    }
    .font(.caption2)
    .foregroundStyle(.secondary)
    .buttonStyle(.plain)
    .padding(.leading, 6)
    .accessibilityIdentifier("sidebar.agentShowAllThreads.\(group.id.uuidString)")
}
```

- [ ] **Step 3: Pass onDeleteConversation from SidebarView**

In `SidebarView.swift`, in `groupsSection`, find the `GroupSidebarRowView(...)` call and add:

```swift
onDeleteConversation: { conv in promptDelete(conv) },
```

- [ ] **Step 4: Build and verify**

Build. Expand a group row and right-click a thread — confirm the context menu appears.

- [ ] **Step 5: Commit**

```bash
git add Odyssey/Views/GroupLibrary/GroupSidebarRowView.swift Odyssey/Views/MainWindow/SidebarView.swift
git commit -m "feat: add archive/delete context menu to inline group thread rows"
```

---

### Task 5: Update agent context menu in SidebarView

**Files:**
- Modify: `Odyssey/Views/MainWindow/SidebarView.swift`

Current menu (lines 1517–1534): New Session | Divider | Pin/Unpin | Divider | Open in Configuration

New menu: New Session, New Thread in Project… (submenu), Divider, View Session History, Divider, Pin/Unpin, Hide from Sidebar, Divider, Schedule Mission…

- [ ] **Step 1: Add schedule sheet state vars**

Near the other `@State` sheet-trigger vars in `SidebarView` (around line 154), add:

```swift
@State private var showingAgentScheduleEditor = false
@State private var agentScheduleDraft = ScheduledMissionDraft(
    name: "",
    targetKind: .agent,
    projectDirectory: "",
    promptTemplate: ""
)
```

- [ ] **Step 2: Add the schedule sheet presenter**

In the main view body where other `.sheet` modifiers live, add:

```swift
.sheet(isPresented: $showingAgentScheduleEditor) {
    ScheduleEditorView(schedule: nil, draft: agentScheduleDraft)
        .environmentObject(appState)
        .environment(\.modelContext, modelContext)
}
```

- [ ] **Step 3: Replace the agent context menu**

In `agentSidebarRow` (around line 1515), replace the entire `.contextMenu { ... }` block with:

```swift
.contextMenu {
    Button("New Session") {
        startSession(with: agent)
    }
    .accessibilityIdentifier("sidebar.agentRow.newSession.\(agent.id.uuidString)")

    Menu("New Thread in Project\u{2026}") {
        ForEach(projects) { project in
            Button(project.name) {
                startSession(with: agent, in: project)
            }
        }
        if projects.isEmpty {
            Text("No projects")
                .foregroundStyle(.secondary)
        }
    }
    .accessibilityIdentifier("sidebar.agentRow.newThreadInProject.\(agent.id.uuidString)")

    Divider()

    Button("View Session History") {
        if expandedAgentIds.contains(agent.id) {
            expandedAgentIds.remove(agent.id)
        } else {
            expandedAgentIds.insert(agent.id)
        }
    }
    .accessibilityIdentifier("sidebar.agentRow.viewHistory.\(agent.id.uuidString)")

    Divider()

    Button(isPinned ? "Unpin from Sidebar" : "Pin to Sidebar") {
        agent.isResident.toggle()
        try? modelContext.save()
    }
    .accessibilityIdentifier("sidebar.agentRow.togglePin.\(agent.id.uuidString)")

    Button("Hide from Sidebar") {
        agent.showInSidebar = false
        try? modelContext.save()
    }
    .accessibilityIdentifier("sidebar.agentRow.hideSidebar.\(agent.id.uuidString)")

    Divider()

    Button("Schedule Mission\u{2026}") {
        agentScheduleDraft = ScheduledMissionDraft(
            name: "\(agent.name) schedule",
            targetKind: .agent,
            projectDirectory: windowState.projectDirectory,
            promptTemplate: ""
        )
        agentScheduleDraft.targetAgentId = agent.id
        showingAgentScheduleEditor = true
    }
    .accessibilityIdentifier("sidebar.agentRow.schedule.\(agent.id.uuidString)")
}
```

- [ ] **Step 4: Build and verify**

Build. Right-click a non-resident agent — confirm new menu structure. Verify "New Thread in Project…" shows a submenu of projects. Verify "Hide from Sidebar" removes the agent. Verify "Schedule Mission…" opens the schedule editor pre-filled with the agent.

- [ ] **Step 5: Commit**

```bash
git add Odyssey/Views/MainWindow/SidebarView.swift
git commit -m "feat: update agent sidebar context menu with session-focused actions"
```

---

### Task 6: Update group context menu in SidebarView

**Files:**
- Modify: `Odyssey/Views/MainWindow/SidebarView.swift`

Current menu: Start Chat | Edit | Duplicate | Divider | Open in Configuration | Divider | Delete

New menu: Start Chat, New Thread in Project… (submenu), Divider, View Session History, Divider, Hide from Sidebar, Divider, Schedule Mission…, Divider, Edit

- [ ] **Step 1: Add group schedule sheet state vars**

```swift
@State private var showingGroupScheduleEditor = false
@State private var groupScheduleDraft = ScheduledMissionDraft(
    name: "",
    targetKind: .group,
    projectDirectory: "",
    promptTemplate: ""
)
```

- [ ] **Step 2: Add the group schedule sheet presenter**

```swift
.sheet(isPresented: $showingGroupScheduleEditor) {
    ScheduleEditorView(schedule: nil, draft: groupScheduleDraft)
        .environmentObject(appState)
        .environment(\.modelContext, modelContext)
}
```

- [ ] **Step 3: Replace the group contextMenu block**

In `groupsSection` (lines 1386–1410), replace the entire `.contextMenu { ... }` block with:

```swift
.contextMenu {
    Button("Start Chat") {
        if let convoId = appState.startGroupChat(
            group: group,
            projectDirectory: windowState.projectDirectory,
            projectId: nil,
            modelContext: modelContext
        ) {
            windowState.selectedConversationId = convoId
        }
    }
    .accessibilityIdentifier("sidebar.groupContext.startChat.\(group.id.uuidString)")

    Menu("New Thread in Project\u{2026}") {
        ForEach(projects) { project in
            Button(project.name) {
                selectOrCreateGroupChat(group, in: project)
            }
        }
        if projects.isEmpty {
            Text("No projects")
                .foregroundStyle(.secondary)
        }
    }
    .accessibilityIdentifier("sidebar.groupContext.newThreadInProject.\(group.id.uuidString)")

    Divider()

    Button("View Session History") {
        if expandedGroupIds.contains(group.id) {
            expandedGroupIds.remove(group.id)
        } else {
            expandedGroupIds.insert(group.id)
        }
    }
    .accessibilityIdentifier("sidebar.groupContext.viewHistory.\(group.id.uuidString)")

    Divider()

    Button("Hide from Sidebar") {
        group.showInSidebar = false
        try? modelContext.save()
    }
    .accessibilityIdentifier("sidebar.groupContext.hideSidebar.\(group.id.uuidString)")

    Divider()

    Button("Schedule Mission\u{2026}") {
        groupScheduleDraft = ScheduledMissionDraft(
            name: "\(group.name) schedule",
            targetKind: .group,
            projectDirectory: windowState.projectDirectory,
            promptTemplate: group.defaultMission ?? ""
        )
        groupScheduleDraft.targetGroupId = group.id
        showingGroupScheduleEditor = true
    }
    .accessibilityIdentifier("sidebar.groupContext.schedule.\(group.id.uuidString)")

    Divider()

    Button("Edit") { editingGroup = group }
        .accessibilityIdentifier("sidebar.groupContext.edit.\(group.id.uuidString)")
}
```

- [ ] **Step 4: Build and verify**

Build. Right-click a group — confirm Duplicate, Open in Configuration, Delete are gone; new items appear.

- [ ] **Step 5: Commit**

```bash
git add Odyssey/Views/MainWindow/SidebarView.swift
git commit -m "feat: update group sidebar context menu — remove CRUD, add session actions"
```

---

### Task 7: Remove Duplicate from conversation context menu

**Files:**
- Modify: `Odyssey/Views/MainWindow/SidebarView.swift`

- [ ] **Step 1: Remove the Duplicate button from conversationMenuContent**

In `conversationMenuContent` (around line 1675), find and delete these 4 lines:

```swift
Button { duplicateConversation(convo) } label: {
    Label("Duplicate", systemImage: "doc.on.doc")
}
.xrayId("sidebar.conversationContext.duplicate.\(convo.id.uuidString)")
```

Leave `duplicateConversation` function itself in place — it may be used elsewhere.

- [ ] **Step 2: Build and verify**

Build. Right-click any conversation — confirm "Duplicate" is gone. All other items remain.

- [ ] **Step 3: Commit**

```bash
git add Odyssey/Views/MainWindow/SidebarView.swift
git commit -m "feat: remove Duplicate from conversation context menu"
```

---

### Task 8: Add Show in Sidebar toggle to ConfigurationDetailView

**Files:**
- Modify: `Odyssey/Views/Settings/ConfigurationDetailView.swift`

- [ ] **Step 1: Add a sidebarSection computed property**

In `ConfigurationDetailView.swift`, add this new section after `configSection` (find the `configSection` property around line 415 and add below it):

```swift
@ViewBuilder
private var sidebarSection: some View {
    switch item {
    case .agent(let agent):
        VStack(alignment: .leading, spacing: 8) {
            Text("Sidebar")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Toggle("Show in Sidebar", isOn: Binding(
                get: { agent.showInSidebar },
                set: { newValue in
                    agent.showInSidebar = newValue
                    try? modelContext.save()
                }
            ))
            .accessibilityIdentifier("configDetail.showInSidebarToggle")
        }
    case .group(let group):
        VStack(alignment: .leading, spacing: 8) {
            Text("Sidebar")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Toggle("Show in Sidebar", isOn: Binding(
                get: { group.showInSidebar },
                set: { newValue in
                    group.showInSidebar = newValue
                    try? modelContext.save()
                }
            ))
            .accessibilityIdentifier("configDetail.groupShowInSidebarToggle")
        }
    default:
        EmptyView()
    }
}
```

- [ ] **Step 2: Add sidebarSection to the scroll view body**

In `var body`, inside the `ScrollView { VStack { ... } }` (line ~43), add `sidebarSection` after `configSection`:

```swift
ScrollView {
    VStack(alignment: .leading, spacing: 14) {
        chipsSection
        promptSection
        configSection
        sidebarSection   // ← add this line
    }
    .padding(16)
}
```

- [ ] **Step 3: Build and verify**

Build. Open Configuration settings, select an agent — confirm "Sidebar" section with "Show in Sidebar" toggle appears. Toggle off → sidebar loses the agent + "N hidden" hint appears. Toggle on → agent reappears in sidebar.

- [ ] **Step 4: Commit**

```bash
git add Odyssey/Views/Settings/ConfigurationDetailView.swift
git commit -m "feat: add Show in Sidebar toggle to agent/group Configuration detail view"
```

---

## Self-Review

**Spec coverage check:**

| Spec section | Task |
|---|---|
| §1 showInSidebar on Agent + AgentGroup | Task 1 ✓ |
| §2 Sidebar filter + N hidden hint | Task 2 ✓ |
| §3 Inline thread archive/delete + show all | Tasks 3, 4 ✓ |
| §4 Agent context menu | Task 5 ✓ |
| §5 Group context menu | Task 6 ✓ |
| §6 Configuration Show in Sidebar toggle | Task 8 ✓ |
| §7 Accessibility identifiers | Inline throughout ✓ |
| §8 Remove Duplicate from conversation menu | Task 7 ✓ |

**Type consistency:**
- `showInSidebar` — used as `Bool` consistently across all tasks ✓
- `agentScheduleDraft` / `groupScheduleDraft` — `ScheduledMissionDraft` type consistently ✓
- `onDeleteConversation: ((Conversation) -> Void)?` — optional closure, consistent between row views and call sites ✓
- `expandedAgentIds` / `expandedGroupIds` — `Set<UUID>` already in SidebarView, used directly ✓

**Placeholder check:** No TBDs. `projects` @Query already exists in SidebarView (line 142). `startSession(with:in:)` exists at line 2019. `selectOrCreateGroupChat(_:in:)` exists at line 2003.
