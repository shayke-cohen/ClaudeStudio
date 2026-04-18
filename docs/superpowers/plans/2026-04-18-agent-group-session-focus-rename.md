# Agent/Group Session Auto-Focus and Rename Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When creating a new chat from an agent or group, automatically expand and select it in the sidebar, and auto-rename it from the first message (plus add a manual Rename option).

**Architecture:** Two independent fixes — (1) expansion timing patched by directly inserting into `expandedAgentIds`/`expandedGroupIds` at creation time, plus a deferred `Task` retry for picker-originated sessions; (2) initial `topic: nil` enables existing `autoNameConversation` guard, with `onRename` callbacks added to the agent/group row components.

**Tech Stack:** Swift 6 / SwiftUI / SwiftData — macOS 14.0+ target. No new dependencies.

---

## File Map

| File | What changes |
|---|---|
| `Odyssey/Views/MainWindow/SidebarView.swift` | Expansion inserts, deferred Task, topic nil in `startSession`, onRename wiring |
| `Odyssey/Views/MainWindow/AgentPickerPopover.swift` | topic nil in `openThread` |
| `Odyssey/Views/MainWindow/AgentSidebarRowView.swift` | `onRename` param + context menu on conversation rows |
| `Odyssey/Views/GroupLibrary/GroupSidebarRowView.swift` | `onRename` param + context menu on conversation rows |
| `Odyssey/App/AppState.swift` | topic nil for interactive group chats in `startGroupChat` |
| `Odyssey/Views/MainWindow/ChatView.swift` | Group-chat format in `autoNameConversation` |

---

### Task 1: Fix agent session focus + nil initial topic in `startSession`

**Files:**
- Modify: `Odyssey/Views/MainWindow/SidebarView.swift` (method `startSession(with:in:)`, around line 1723)

- [ ] **Step 1: Apply the two changes to `startSession(with:in:)`**

Find this method (currently around line 1723). Make two edits: change `topic: agent.name` to `topic: nil`, and add `expandedAgentIds.insert(agent.id)` right before the `windowState.selectedConversationId` assignment.

The final method body should look like this (only the changed lines shown with context):

```swift
private func startSession(with agent: Agent, in project: Project? = nil) {
    let targetProject = project
    let session = Session(agent: agent, mode: .interactive)
    if session.workingDirectory.isEmpty {
        let fallback = targetProject?.rootPath ?? windowState.projectDirectory
        if let residentDir = agent.defaultWorkingDirectory, !residentDir.isEmpty {
            let expanded = (residentDir as NSString).expandingTildeInPath
            session.workingDirectory = expanded
            ResidentAgentSupport.prepareVaultForSession(in: expanded, agentName: agent.name)
        } else if !fallback.isEmpty {
            session.workingDirectory = fallback
        }
    }
    let conversation = Conversation(
        topic: nil,                          // was: agent.name
        sessions: [session],
        projectId: targetProject?.id,
        threadKind: .direct
    )
    let userParticipant = Participant(type: .user, displayName: "You")
    let agentParticipant = Participant(
        type: .agentSession(sessionId: session.id),
        displayName: agent.name
    )
    userParticipant.conversation = conversation
    agentParticipant.conversation = conversation
    conversation.participants = [userParticipant, agentParticipant]
    session.conversations = [conversation]

    modelContext.insert(session)
    modelContext.insert(conversation)
    try? modelContext.save()
    expandedAgentIds.insert(agent.id)       // NEW: expand before selecting
    windowState.selectedConversationId = conversation.id
}
```

- [ ] **Step 2: Build to confirm no errors**

In Xcode: Product → Build (⌘B). Expect: Build Succeeded.

- [ ] **Step 3: Manual smoke test**

Run the app. Click the `+` button on any agent in the sidebar Agents section. Confirm:
- The agent's DisclosureGroup expands
- The new conversation row is visible and selected
- The conversation shows "Untitled" as its name in the row (topic is nil now)

- [ ] **Step 4: Commit**

```bash
git add Odyssey/Views/MainWindow/SidebarView.swift
git commit -m "fix: expand agent section and use nil topic when starting agent session"
```

---

### Task 2: Fix group session focus in sidebar-initiated paths

**Files:**
- Modify: `Odyssey/Views/MainWindow/SidebarView.swift` (three sites: `groupsSection` onNewChat closure, context menu "Start Chat", `selectOrCreateGroupChat`)

- [ ] **Step 1: Add `expandedGroupIds.insert(group.id)` to `groupsSection` `onNewChat` closure**

Find the `groupsSection` computed property (around line 1048). The `onNewChat` closure currently looks like:

```swift
onNewChat: {
    if let convoId = appState.startGroupChat(
        group: group,
        projectDirectory: windowState.projectDirectory,
        projectId: nil,
        modelContext: modelContext
    ) {
        windowState.selectedConversationId = convoId
    }
},
```

Change it to:

```swift
onNewChat: {
    if let convoId = appState.startGroupChat(
        group: group,
        projectDirectory: windowState.projectDirectory,
        projectId: nil,
        modelContext: modelContext
    ) {
        expandedGroupIds.insert(group.id)
        windowState.selectedConversationId = convoId
    }
},
```

- [ ] **Step 2: Add `expandedGroupIds.insert(group.id)` to context menu "Start Chat"**

In the same `groupsSection`, find the `.contextMenu` on the `GroupSidebarRowView`. The "Start Chat" button currently looks like:

```swift
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
```

Change it to:

```swift
Button("Start Chat") {
    if let convoId = appState.startGroupChat(
        group: group,
        projectDirectory: windowState.projectDirectory,
        projectId: nil,
        modelContext: modelContext
    ) {
        expandedGroupIds.insert(group.id)
        windowState.selectedConversationId = convoId
    }
}
```

- [ ] **Step 3: Add `expandedGroupIds.insert(group.id)` to `selectOrCreateGroupChat`**

Find `selectOrCreateGroupChat` (around line 1707). The creation branch currently looks like:

```swift
private func selectOrCreateGroupChat(_ group: AgentGroup, in project: Project? = nil) {
    if let existing = conversationsForGroup(group, in: project).first(where: { !$0.isArchived }) {
        windowState.selectedConversationId = existing.id
    } else {
        let targetProject = project ?? sortedProjects.first(where: { $0.id == windowState.selectedProjectId })
        if let convoId = appState.startGroupChat(
            group: group,
            projectDirectory: targetProject?.rootPath ?? windowState.projectDirectory,
            projectId: targetProject?.id ?? windowState.selectedProjectId,
            modelContext: modelContext
        ) {
            windowState.selectedConversationId = convoId
        }
    }
}
```

Change the else branch to:

```swift
    } else {
        let targetProject = project ?? sortedProjects.first(where: { $0.id == windowState.selectedProjectId })
        if let convoId = appState.startGroupChat(
            group: group,
            projectDirectory: targetProject?.rootPath ?? windowState.projectDirectory,
            projectId: targetProject?.id ?? windowState.selectedProjectId,
            modelContext: modelContext
        ) {
            expandedGroupIds.insert(group.id)
            windowState.selectedConversationId = convoId
        }
    }
```

- [ ] **Step 4: Build to confirm no errors**

Product → Build (⌘B). Expect: Build Succeeded.

- [ ] **Step 5: Manual smoke test**

Run the app. Click the `+` button on a group in the Groups sidebar section, and also right-click a group and choose "Start Chat". Confirm both expand the group DisclosureGroup and select the new conversation.

- [ ] **Step 6: Commit**

```bash
git add Odyssey/Views/MainWindow/SidebarView.swift
git commit -m "fix: expand group section on new group session from sidebar"
```

---

### Task 3: Deferred retry for picker-originated sessions

**Files:**
- Modify: `Odyssey/Views/MainWindow/SidebarView.swift` (the `.onChange(of: windowState.selectedConversationId)` modifier in `sidebarList`, around line 301)

- [ ] **Step 1: Add deferred Task to `onChange` handler**

Find the modifier in `sidebarList` (inside the `List { ... }` block):

```swift
.onChange(of: windowState.selectedConversationId) { _, newValue in
    guard let selectedId = newValue else { return }
    handleConversationSelectionChange(selectedId)
}
```

Change to:

```swift
.onChange(of: windowState.selectedConversationId) { _, newValue in
    guard let selectedId = newValue else { return }
    handleConversationSelectionChange(selectedId)
    Task { @MainActor in handleConversationSelectionChange(selectedId) }
}
```

The immediate call handles already-existing conversations (no cost). The deferred `Task` fires after SwiftData's `@Query` refreshes, catching brand-new conversations created via `AgentPickerPopover` or `GroupPickerPopover` where the @Query hasn't updated yet.

- [ ] **Step 2: Build to confirm no errors**

Product → Build (⌘B). Expect: Build Succeeded.

- [ ] **Step 3: Manual smoke test**

Run the app. Use ⌘N (or the toolbar pencil icon) to open the Agent picker popover. Select an agent. Confirm:
- The agent's DisclosureGroup expands
- The new conversation is visible and selected

Do the same with ⌘⌥N for the Group picker.

- [ ] **Step 4: Commit**

```bash
git add Odyssey/Views/MainWindow/SidebarView.swift
git commit -m "fix: deferred Task retry in onChange to expand section for picker-created sessions"
```

---

### Task 4: Nil initial topic in `AgentPickerPopover`

**Files:**
- Modify: `Odyssey/Views/MainWindow/AgentPickerPopover.swift` (method `openThread(agent:)`, around line 245)

- [ ] **Step 1: Remove `topic` local variable and pass `nil` to `Conversation` initializer**

Find `openThread(agent:)`. It currently starts with:

```swift
private func openThread(agent: Agent?) {
    let mission = missionText.trimmingCharacters(in: .whitespacesAndNewlines)
    let topic = agent?.name ?? "Thread"
    let kind: ThreadKind = agent != nil ? .direct : .freeform

    let conversation = Conversation(
        topic: topic,
        projectId: projectId,
        threadKind: kind
    )
```

Change to:

```swift
private func openThread(agent: Agent?) {
    let mission = missionText.trimmingCharacters(in: .whitespacesAndNewlines)
    let kind: ThreadKind = agent != nil ? .direct : .freeform

    let conversation = Conversation(
        topic: nil,
        projectId: projectId,
        threadKind: kind
    )
```

- [ ] **Step 2: Build to confirm no errors**

Product → Build (⌘B). Expect: Build Succeeded.

- [ ] **Step 3: Commit**

```bash
git add Odyssey/Views/MainWindow/AgentPickerPopover.swift
git commit -m "fix: nil initial topic for agent picker sessions (enables auto-rename)"
```

---

### Task 5: Nil initial topic in `AppState.startGroupChat`

**Files:**
- Modify: `Odyssey/App/AppState.swift` (method `startGroupChat`, around line 477)

- [ ] **Step 1: Change interactive group chat topic to nil**

Find the `Conversation` creation inside `startGroupChat`. It currently reads:

```swift
let conversation = Conversation(
    topic: executionMode == .autonomous ? "\(group.name) — Autonomous" : group.name,
    projectId: projectId,
    threadKind: executionMode == .autonomous ? .autonomous : .group
)
```

Change to:

```swift
let conversation = Conversation(
    topic: executionMode == .autonomous ? "\(group.name) — Autonomous" : nil,
    projectId: projectId,
    threadKind: executionMode == .autonomous ? .autonomous : .group
)
```

Autonomous missions keep their descriptive name. Interactive group chats start with `nil` so auto-rename fires on first message.

- [ ] **Step 2: Build to confirm no errors**

Product → Build (⌘B). Expect: Build Succeeded.

- [ ] **Step 3: Commit**

```bash
git add Odyssey/App/AppState.swift
git commit -m "fix: nil initial topic for interactive group chats (enables auto-rename)"
```

---

### Task 6: Update `autoNameConversation` format for group chats

**Files:**
- Modify: `Odyssey/Views/MainWindow/ChatView.swift` (method `autoNameConversation`, around line 2966)

- [ ] **Step 1: Replace the topic-assignment line**

Find `autoNameConversation`. The last two lines currently read:

```swift
    let agentName = convo.primarySession?.agent?.name
    convo.topic = agentName.map { "\($0): \(truncated)" } ?? truncated
```

Replace those two lines with:

```swift
    let isGroupChat = convo.sourceGroupId != nil
    let prefix = isGroupChat ? nil : convo.primarySession?.agent?.name
    convo.topic = prefix.map { "\($0): \(truncated)" } ?? truncated
```

**Why:** For agent chats, topic becomes `"AgentName: first words of message"`. For group chats, `prefix` is nil so topic becomes just the truncated message — the group context is already shown by the DisclosureGroup label.

- [ ] **Step 2: Build to confirm no errors**

Product → Build (⌘B). Expect: Build Succeeded.

- [ ] **Step 3: Manual smoke test**

Run the app. Start a new agent chat via the picker (topic will be nil/"Untitled"). Send a first message. Confirm the sidebar row updates to `"AgentName: first few words"`.

Start a new group chat (topic nil/"Untitled"). Send a first message. Confirm the sidebar row updates to just the first few words (no agent name prefix).

- [ ] **Step 4: Commit**

```bash
git add Odyssey/Views/MainWindow/ChatView.swift
git commit -m "fix: omit agent-name prefix in auto-rename for group chats"
```

---

### Task 7: Add `onRename` to `AgentSidebarRowView`

**Files:**
- Modify: `Odyssey/Views/MainWindow/AgentSidebarRowView.swift`

- [ ] **Step 1: Add `onRename` property and context menu**

The full updated file (changes: add `var onRename` property, add `.contextMenu` on conversation rows):

```swift
import SwiftUI
import SwiftData

struct AgentSidebarRowView: View {
    let agent: Agent
    let conversations: [Conversation]
    @Binding var isExpanded: Bool
    let onNewChat: () -> Void
    let onSelectConversation: (Conversation) -> Void
    var onSelectAgent: (() -> Void)?
    var onRename: ((Conversation) -> Void)?    // NEW
    var selectedConversationId: UUID?
    var hasActiveSession: Bool = false

    private var isSelected: Bool {
        guard let selected = selectedConversationId else { return false }
        return conversations.contains { $0.id == selected }
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(conversations.prefix(10)) { conv in
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
                .accessibilityLabel("Open chat \(conv.topic ?? "Untitled")")
                .contextMenu {                          // NEW
                    Button("Rename\u{2026}") { onRename?(conv) }
                }
            }

        } label: {
            HStack {
                Button {
                    onSelectAgent?()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: agent.icon)
                            .foregroundStyle(Color.fromAgentColor(agent.color))
                        Text(agent.name)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .stableXrayId("sidebar.agentRow.\(agent.id.uuidString).selectButton")
                .accessibilityLabel("Open agent \(agent.name)")
                Spacer()
                if hasActiveSession {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 6, height: 6)
                        .stableXrayId("sidebar.agentRow.\(agent.id.uuidString).activityDot")
                }
                if !conversations.isEmpty {
                    Text("\(conversations.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }
                Button {
                    onNewChat()
                } label: {
                    Image(systemName: "plus")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .stableXrayId("sidebar.agentRow.\(agent.id.uuidString).newChatButton")
                .accessibilityLabel("New chat for \(agent.name)")
            }
            .stableXrayId("sidebar.agentRow.\(agent.id.uuidString)")
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}
```

- [ ] **Step 2: Build to confirm no errors**

Product → Build (⌘B). Expect: Build Succeeded (the `onRename` param is optional so existing callers don't need updating yet).

- [ ] **Step 3: Commit**

```bash
git add Odyssey/Views/MainWindow/AgentSidebarRowView.swift
git commit -m "feat: add onRename callback and context menu to AgentSidebarRowView"
```

---

### Task 8: Add `onRename` to `GroupSidebarRowView`

**Files:**
- Modify: `Odyssey/Views/GroupLibrary/GroupSidebarRowView.swift`

- [ ] **Step 1: Add `onRename` property and context menu**

The full updated file (changes: add `var onRename` property, add `.contextMenu` on conversation rows):

```swift
import SwiftUI
import SwiftData

struct GroupSidebarRowView: View {
    let group: AgentGroup
    let conversations: [Conversation]
    let allAgents: [Agent]
    @Binding var isExpanded: Bool
    let onNewChat: () -> Void
    let onNewAutonomousChat: (() -> Void)?
    let onSelectConversation: (Conversation) -> Void
    var onSelectGroup: (() -> Void)?
    var onEdit: (() -> Void)?
    var onDuplicate: (() -> Void)?
    var onRename: ((Conversation) -> Void)?    // NEW
    var selectedConversationId: UUID?
    var hasActiveSession: Bool = false

    private var isSelected: Bool {
        guard let selected = selectedConversationId else { return false }
        return conversations.contains { $0.id == selected }
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(conversations.prefix(10)) { conv in
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
                .contextMenu {                          // NEW
                    Button("Rename\u{2026}") { onRename?(conv) }
                }
            }
        } label: {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Text(group.icon)
                        .font(.body)
                        .frame(width: 22, height: 22)
                        .background(Color.fromAgentColor(group.color).opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 5))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(group.name)
                            .font(.body)
                            .lineLimit(1)
                        let memberNames = allAgents.filter { group.agentIds.contains($0.id) }.map(\.name).joined(separator: " · ")
                        if !memberNames.isEmpty {
                            Text(memberNames)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { onSelectGroup?() }

                Spacer()

                if hasActiveSession {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 6, height: 6)
                        .stableXrayId("sidebar.groupRow.\(group.id.uuidString).activityDot")
                }

                if !conversations.isEmpty {
                    Text("\(conversations.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }

                if group.autonomousCapable, let onAuto = onNewAutonomousChat {
                    Button { onAuto() } label: {
                        Image(systemName: "bolt")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                    .help("Start autonomous mission")
                    .accessibilityLabel("Start autonomous mission for \(group.name)")
                    .stableXrayId("sidebar.groupRow.\(group.id.uuidString).autonomousButton")
                }

                Button {
                    onNewChat()
                } label: {
                    Image(systemName: "plus")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New group thread with \(group.name)")
                .stableXrayId("sidebar.groupRow.\(group.id.uuidString).newChatButton")
            }
            .stableXrayId("sidebar.groupRow.\(group.id.uuidString)")
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}
```

- [ ] **Step 2: Build to confirm no errors**

Product → Build (⌘B). Expect: Build Succeeded.

- [ ] **Step 3: Commit**

```bash
git add Odyssey/Views/GroupLibrary/GroupSidebarRowView.swift
git commit -m "feat: add onRename callback and context menu to GroupSidebarRowView"
```

---

### Task 9: Wire `onRename` in `SidebarView`

**Files:**
- Modify: `Odyssey/Views/MainWindow/SidebarView.swift` (two sites: `agentSidebarRow`, `groupsSection`)

- [ ] **Step 1: Wire `onRename` in `agentSidebarRow`**

Find `agentSidebarRow` (around line 1214). Locate the `AgentSidebarRowView(...)` call and add the `onRename` argument after `hasActiveSession`:

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
    onSelectConversation: { conv in
        windowState.selectedConversationId = conv.id
    },
    onSelectAgent: {
        selectOrCreateAgentChat(agent)
    },
    onRename: { conv in                    // NEW
        renameText = conv.topic ?? ""
        renamingConversation = conv
    },
    selectedConversationId: windowState.selectedConversationId,
    hasActiveSession: agentHasActiveSession(agent)
)
```

- [ ] **Step 2: Wire `onRename` in `groupsSection`**

Find `groupsSection` (around line 1048). Locate the `GroupSidebarRowView(...)` call and add `onRename` after `onDuplicate`:

```swift
GroupSidebarRowView(
    group: group,
    conversations: conversationsForGroup(group),
    allAgents: agents,
    isExpanded: Binding(
        get: { expandedGroupIds.contains(group.id) },
        set: { expanded in
            if expanded { expandedGroupIds.insert(group.id) }
            else { expandedGroupIds.remove(group.id) }
        }
    ),
    onNewChat: {
        if let convoId = appState.startGroupChat(
            group: group,
            projectDirectory: windowState.projectDirectory,
            projectId: nil,
            modelContext: modelContext
        ) {
            expandedGroupIds.insert(group.id)
            windowState.selectedConversationId = convoId
        }
    },
    onNewAutonomousChat: (autonomousMissionsEnabled && group.autonomousCapable) ? {
        autonomousGroup = group
    } : nil,
    onSelectConversation: { conv in
        windowState.selectedConversationId = conv.id
    },
    onSelectGroup: {
        selectOrCreateGroupChat(group)
    },
    onEdit: { editingGroup = group },
    onDuplicate: { duplicateGroup(group) },
    onRename: { conv in                    // NEW
        renameText = conv.topic ?? ""
        renamingConversation = conv
    },
    selectedConversationId: windowState.selectedConversationId,
    hasActiveSession: groupHasActiveSession(group)
)
```

- [ ] **Step 3: Build to confirm no errors**

Product → Build (⌘B). Expect: Build Succeeded.

- [ ] **Step 4: Full manual smoke test**

Run the app and test all paths:

1. **Agent sidebar row `+`**: New session appears, agent section expands, conversation selected.
2. **Agent context menu "New Session"**: Same as above.
3. **Agent picker popover (⌘N)**: New session appears, agent section expands.
4. **Group sidebar row `+`**: New session appears, group section expands.
5. **Group context menu "Start Chat"**: Same as above.
6. **Group picker popover (⌘⌥N)**: New session appears, group section expands.
7. **Auto-rename (agent)**: Start agent chat, send first message → sidebar title becomes `"AgentName: first words"`.
8. **Auto-rename (group)**: Start group chat, send first message → sidebar title becomes just the first words.
9. **Manual rename (agent row)**: Right-click a conversation under an agent → "Rename…" appears → rename works.
10. **Manual rename (group row)**: Right-click a conversation under a group → "Rename…" appears → rename works.

- [ ] **Step 5: Commit**

```bash
git add Odyssey/Views/MainWindow/SidebarView.swift
git commit -m "feat: wire onRename to agent and group sidebar row views"
```
