# Thread Creation Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the 860×720 NewSessionSheet modal with two lean compact popovers (agent picker + group picker), collapse the sidebar menu from three items to two, and move PromptTemplate access to the ChatView empty state as chips.

**Architecture:** Two new SwiftUI views (`AgentPickerPopover`, `GroupPickerPopover`) anchor to the "+ New" sidebar button via SwiftUI `.popover(isPresented:)` with local `@State` flags in `SidebarView`. Thread creation logic follows the same pattern as the existing `createBlankThread` / `createAgentThread` in `NewSessionSheet`. Template chips are added to the existing `chatEmptyState` in `ChatView`, gated on `conversation.messages.isEmpty`.

**Tech Stack:** SwiftUI, SwiftData (`@Query`, `modelContext`), macOS `.popover(isPresented:)`

---

## File Map

| Action | File |
| ------ | ---- |
| Create | `Odyssey/Views/MainWindow/AgentPickerPopover.swift` |
| Create | `Odyssey/Views/MainWindow/GroupPickerPopover.swift` |
| Modify | `Odyssey/Views/MainWindow/SidebarView.swift` |
| Modify | `Odyssey/Views/MainWindow/MainWindowView.swift` |
| Modify | `Odyssey/Views/MainWindow/ChatView.swift` |
| Modify | `Odyssey/Views/MainWindow/NewSessionSheet.swift` |

WindowState does **not** need new flags — popover visibility is local `@State` in `SidebarView`.

---

### Task 1: Update SidebarView menu + attach popovers

**Files:**

- Modify: `Odyssey/Views/MainWindow/SidebarView.swift`

- [ ] **Step 1: Add local popover state to SidebarView**

Find the `SidebarView` struct definition. Add two `@State` vars near the existing `@State` declarations at the top of the struct:

```swift
@State private var showAgentPopover = false
@State private var showGroupPopover = false
```

- [ ] **Step 2: Replace the utilitySection Menu**

Find `private var utilitySection: some View` (around line 354). Replace the `Menu` content — keeping the existing label styling intact — with two renamed buttons and remove the Quick Chat button:

```swift
private var utilitySection: some View {
    Section {
        Menu {
            Button {
                showAgentPopover = true
            } label: {
                Label("Chat with Agent", systemImage: "cpu")
            }
            .keyboardShortcut("n", modifiers: .command)

            Button {
                showGroupPopover = true
            } label: {
                Label("Chat with Group", systemImage: "person.3.fill")
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 18, height: 18)
                    .foregroundStyle(.primary)
                Text("New")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(SidebarChromeButtonModifier(tint: .accentColor))
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("Start a new chat with an agent or group")
        .xrayId("sidebar.utility.newMenu")
        .accessibilityLabel("New")
        .popover(isPresented: $showAgentPopover) {
            AgentPickerPopover(
                projectId: windowState.selectedProjectId,
                projectDirectory: windowState.projectDirectory,
                isPresented: $showAgentPopover
            )
            .environmentObject(appState)
            .environment(windowState)
        }
        .popover(isPresented: $showGroupPopover) {
            GroupPickerPopover(
                projectId: windowState.selectedProjectId,
                projectDirectory: windowState.projectDirectory,
                isPresented: $showGroupPopover
            )
            .environmentObject(appState)
            .environment(windowState)
        }
    }
}
```

> **Note:** Check the exact property name for the working directory on `WindowState` — search for `projectDirectory` or `currentProjectDirectory` in `WindowState.swift`. Use whichever is the public accessor.

- [ ] **Step 3: Remove createQuickChatFromSidebar and its ⌘⇧N binding**

Search for `createQuickChatFromSidebar` in `SidebarView.swift`. Delete the function definition and any `.keyboardShortcut("n", modifiers: [.command, .shift])` button that calls it.

Add ⌘⇧N to open the agent popover instead, inside the Menu:

```swift
Button {
    showAgentPopover = true
} label: {
    Label("Quick Chat", systemImage: "plus.message")
}
.keyboardShortcut("n", modifiers: [.command, .shift])
```

- [ ] **Step 4: Build — expect missing type errors**

```bash
xcodebuild -scheme Odyssey -destination 'platform=macOS,arch=arm64' build 2>&1 | grep "error:"
```

Expected: Errors for unknown types `AgentPickerPopover` and `GroupPickerPopover`. All other errors indicate a problem with step 2 or 3 — fix before continuing.

- [ ] **Step 5: Commit**

```bash
git add Odyssey/Views/MainWindow/SidebarView.swift
git commit -m "feat: rename sidebar menu items, attach agent/group popover placeholders"
```

---

### Task 2: Create AgentPickerPopover

**Files:**

- Create: `Odyssey/Views/MainWindow/AgentPickerPopover.swift`

- [ ] **Step 1: Create the file with structure, search bar, and agent list**

```swift
import SwiftUI
import SwiftData

struct AgentPickerPopover: View {
    let projectId: UUID?
    let projectDirectory: String
    @Binding var isPresented: Bool

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Environment(WindowState.self) private var windowState: WindowState

    @Query(sort: \Agent.name) private var allAgents: [Agent]
    @Query(sort: \Session.lastActiveAt, order: .reverse) private var recentSessions: [Session]

    @State private var searchText = ""
    @State private var missionText = ""
    @State private var showMission = false
    @FocusState private var searchFocused: Bool
    @FocusState private var missionFocused: Bool

    private var enabledAgents: [Agent] {
        allAgents.filter { $0.isEnabled }
    }

    private var filteredAgents: [Agent] {
        guard !searchText.isEmpty else { return enabledAgents }
        return enabledAgents.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var recentAgents: [Agent] {
        var seen = Set<UUID>()
        var result: [Agent] = []
        for session in recentSessions {
            guard let agent = session.agent,
                  agent.isEnabled,
                  !seen.contains(agent.id) else { continue }
            seen.insert(agent.id)
            result.append(agent)
            if result.count == 3 { break }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            if showMission { missionSection }
            noAgentRow
            Divider()
            if !recentAgents.isEmpty && searchText.isEmpty { recentSection }
            agentList
            Divider()
            footer
        }
        .frame(width: 260)
        .background(.background)
        .onAppear { searchFocused = true }
    }
}
```

- [ ] **Step 2: Add search bar, mission section, and no-agent row**

```swift
extension AgentPickerPopover {
    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            TextField("Search agents…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.background.secondary)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var missionSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("MISSION")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.purple)
                .padding(.horizontal, 10)
                .padding(.top, 8)
            TextEditor(text: $missionText)
                .font(.system(size: 12))
                .focused($missionFocused)
                .frame(height: 56)
                .padding(.horizontal, 8)
                .scrollContentBackground(.hidden)
                .background(Color.purple.opacity(0.08))
            Text("Select an agent below to start  ·  esc to cancel")
                .font(.system(size: 9))
                .foregroundStyle(.quaternary)
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
        }
        .background(Color.purple.opacity(0.06))
        .overlay(alignment: .bottom) { Divider() }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var noAgentRow: some View {
        Button { openThread(agent: nil) } label: {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3]))
                        .foregroundStyle(.quaternary)
                    Text("∅")
                        .font(.system(size: 10))
                        .foregroundStyle(.quaternary)
                }
                .frame(width: 20, height: 20)
                Text("No specialized agent")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("↵")
                    .font(.system(size: 10))
                    .foregroundStyle(.quaternary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.background.tertiary)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("RECENT")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.quaternary)
                .padding(.horizontal, 10)
                .padding(.top, 6)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(recentAgents) { agent in
                        Button { openThread(agent: agent) } label: {
                            HStack(spacing: 4) {
                                Image(systemName: agent.icon)
                                    .font(.system(size: 8))
                                    .foregroundStyle(Color.fromAgentColor(agent.color))
                                Text(agent.name)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.background.secondary)
                            .clipShape(Capsule())
                            .overlay(Capsule().strokeBorder(.quaternary, lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
            }
        }
        .overlay(alignment: .bottom) { Divider() }
    }

    private var agentList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredAgents) { agent in
                    Button { openThread(agent: agent) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: agent.icon)
                                .font(.system(size: 10))
                                .frame(width: 20, height: 20)
                                .background(Color.fromAgentColor(agent.color).opacity(0.15))
                                .foregroundStyle(Color.fromAgentColor(agent.color))
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(agent.name)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.primary)
                                if let model = agent.model {
                                    Text(model)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.quaternary)
                                }
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxHeight: 200)
    }

    private var footer: some View {
        HStack {
            Text("Click to start")
                .font(.system(size: 10))
                .foregroundStyle(.quaternary)
            Spacer()
            Button("") { toggleMission() }
                .keyboardShortcut(.return, modifiers: .command)
                .hidden()
            Text(showMission ? "⌘↵ hide mission" : "⌘↵ add mission")
                .font(.system(size: 10))
                .foregroundStyle(.quaternary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.background.tertiary)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}
```

- [ ] **Step 3: Add thread creation and mission toggle**

```swift
extension AgentPickerPopover {
    private func toggleMission() {
        withAnimation(.easeInOut(duration: 0.15)) {
            showMission.toggle()
        }
        if showMission { missionFocused = true }
    }

    private func openThread(agent: Agent?) {
        let mission = missionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let topic = agent?.name ?? "Thread"
        let kind: ThreadKind = agent != nil ? .direct : .freeform

        let conversation = Conversation(
            topic: topic,
            projectId: projectId,
            threadKind: kind
        )

        let userParticipant = Participant(type: .user, displayName: "You")
        userParticipant.conversation = conversation
        conversation.participants.append(userParticipant)

        let session = Session(
            agent: agent,
            mission: mission.isEmpty ? nil : mission,
            workingDirectory: projectDirectory
        )
        session.conversations = [conversation]
        conversation.sessions.append(session)

        let agentParticipant = Participant(
            type: .agentSession(sessionId: session.id),
            displayName: agent?.name ?? AgentDefaults.displayName(forProvider: session.provider)
        )
        agentParticipant.conversation = conversation
        conversation.participants.append(agentParticipant)

        modelContext.insert(session)
        modelContext.insert(conversation)
        try? modelContext.save()
        windowState.selectedConversationId = conversation.id
        isPresented = false
    }
}
```

- [ ] **Step 4: Build**

```bash
xcodebuild -scheme Odyssey -destination 'platform=macOS,arch=arm64' build 2>&1 | grep "error:"
```

Expected: Clean build. Fix any type-name mismatches (e.g. `Participant(type:displayName:)` init — verify against `Participant.swift`).

- [ ] **Step 5: Commit**

```bash
git add Odyssey/Views/MainWindow/AgentPickerPopover.swift
git commit -m "feat: add AgentPickerPopover with search, recent pills, no-agent row, mission toggle, thread creation"
```

---

### Task 3: Create GroupPickerPopover

**Files:**

- Create: `Odyssey/Views/MainWindow/GroupPickerPopover.swift`

- [ ] **Step 1: Create the file**

```swift
import SwiftUI
import SwiftData

struct GroupPickerPopover: View {
    let projectId: UUID?
    let projectDirectory: String
    @Binding var isPresented: Bool

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Environment(WindowState.self) private var windowState: WindowState

    @Query(sort: \AgentGroup.name) private var allGroups: [AgentGroup]
    @Query(sort: \Agent.name) private var allAgents: [Agent]

    @State private var searchText = ""
    @State private var missionText = ""
    @State private var showMission = false
    @FocusState private var searchFocused: Bool
    @FocusState private var missionFocused: Bool

    private var filteredGroups: [AgentGroup] {
        guard !searchText.isEmpty else { return allGroups }
        return allGroups.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            if showMission { missionSection }
            groupList
            Divider()
            footer
        }
        .frame(width: 260)
        .background(.background)
        .onAppear { searchFocused = true }
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            TextField("Search groups…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.background.secondary)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var missionSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("MISSION")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.purple)
                .padding(.horizontal, 10)
                .padding(.top, 8)
            TextEditor(text: $missionText)
                .font(.system(size: 12))
                .focused($missionFocused)
                .frame(height: 56)
                .padding(.horizontal, 8)
                .scrollContentBackground(.hidden)
                .background(Color.purple.opacity(0.08))
            Text("Select a group below to start  ·  esc to cancel")
                .font(.system(size: 9))
                .foregroundStyle(.quaternary)
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
        }
        .background(Color.purple.opacity(0.06))
        .overlay(alignment: .bottom) { Divider() }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var groupList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredGroups) { group in
                    Button { openGroupThread(group) } label: {
                        HStack(spacing: 8) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(Color.blue.opacity(0.12))
                                Image(systemName: "person.3.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.blue)
                            }
                            .frame(width: 28, height: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.name)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.primary)
                                // Show member agent color dots
                                let memberAgents = allAgents.filter { group.agentIds.contains($0.id) }
                                HStack(spacing: 3) {
                                    ForEach(memberAgents.prefix(4)) { agent in
                                        Circle()
                                            .fill(Color.fromAgentColor(agent.color))
                                            .frame(width: 6, height: 6)
                                    }
                                    Text("\(group.agentIds.count) agents")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.quaternary)
                                }
                            }
                            Spacer()
                            Text("↵")
                                .font(.system(size: 10))
                                .foregroundStyle(.quaternary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.background.tertiary)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxHeight: 240)
    }

    private var footer: some View {
        HStack {
            Text("Click to start")
                .font(.system(size: 10))
                .foregroundStyle(.quaternary)
            Spacer()
            Button("") { toggleMission() }
                .keyboardShortcut(.return, modifiers: .command)
                .hidden()
            Text(showMission ? "⌘↵ hide mission" : "⌘↵ add mission")
                .font(.system(size: 10))
                .foregroundStyle(.quaternary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.background.tertiary)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func toggleMission() {
        withAnimation(.easeInOut(duration: 0.15)) { showMission.toggle() }
        if showMission { missionFocused = true }
    }

    private func openGroupThread(_ group: AgentGroup) {
        let mission = missionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let convId = appState.startGroupChat(
            group: group,
            projectDirectory: projectDirectory,
            projectId: projectId,
            modelContext: modelContext,
            missionOverride: mission.isEmpty ? nil : mission
        ) else { return }
        windowState.selectedConversationId = convId
        isPresented = false
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild -scheme Odyssey -destination 'platform=macOS,arch=arm64' build 2>&1 | grep "error:"
```

Expected: Clean build.

- [ ] **Step 3: Commit**

```bash
git add Odyssey/Views/MainWindow/GroupPickerPopover.swift
git commit -m "feat: add GroupPickerPopover with search, group list, member dots, mission toggle"
```

---

### Task 4: Remove old sheet bindings from MainWindowView

**Files:**

- Modify: `Odyssey/Views/MainWindow/MainWindowView.swift`

- [ ] **Step 1: Find and delete the two sheet modifiers (lines ~175-180)**

```swift
// DELETE both of these:
.sheet(isPresented: $ws.showNewSessionSheet) {
    NewSessionSheet(initialStartKind: .agents)
}
.sheet(isPresented: $ws.showNewGroupThreadSheet) {
    NewSessionSheet(initialStartKind: .groups)
}
```

- [ ] **Step 2: Check for other references to the removed flags**

```bash
grep -rn "showNewSessionSheet\|showNewGroupThreadSheet" \
  /Users/shayco/Odyssey/Odyssey/ 2>/dev/null
```

Fix any remaining references (e.g. in keyboard shortcut handlers or context menus elsewhere in the codebase).

- [ ] **Step 3: Build**

```bash
xcodebuild -scheme Odyssey -destination 'platform=macOS,arch=arm64' build 2>&1 | grep "error:"
```

Expected: Clean build.

- [ ] **Step 4: Commit**

```bash
git add Odyssey/Views/MainWindow/MainWindowView.swift
git commit -m "feat: remove NewSessionSheet sheet bindings from MainWindowView"
```

---

### Task 5: Add PromptTemplate chips to ChatView empty state

**Files:**

- Modify: `Odyssey/Views/MainWindow/ChatView.swift`

- [ ] **Step 1: Add @Query for PromptTemplates**

In the `@Query` block in `ChatView` (near `allSkills`, `allMCPs`, around line 390+), add:

```swift
@Query private var allTemplates: [PromptTemplate]
```

- [ ] **Step 2: Add applicableTemplates computed property**

Add this alongside the other private computed properties in `ChatView`:

```swift
private var applicableTemplates: [PromptTemplate] {
    guard let conversation else { return [] }
    if let group = sourceGroup {
        return allTemplates
            .filter { $0.group?.id == group.id }
            .sorted { $0.sortOrder < $1.sortOrder }
    } else if let agent = primarySession?.agent {
        return allTemplates
            .filter { $0.agent?.id == agent.id }
            .sorted { $0.sortOrder < $1.sortOrder }
    }
    return []
}
```

- [ ] **Step 3: Add templateChipsView**

Add this `@ViewBuilder` to `ChatView`:

```swift
@ViewBuilder
private var templateChipsView: some View {
    let templates = applicableTemplates
    if !templates.isEmpty {
        VStack(spacing: 6) {
            Text("Templates")
                .font(captionFont)
                .fontWeight(.medium)
                .foregroundStyle(.tertiary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(templates.prefix(4))) { template in
                        Button {
                            inputText = template.prompt
                        } label: {
                            Text(template.name)
                                .font(.system(size: 12))
                                .foregroundStyle(.purple)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.purple.opacity(0.08))
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule().strokeBorder(Color.purple.opacity(0.25), lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    if templates.count > 4 {
                        Menu {
                            ForEach(Array(templates.dropFirst(4))) { template in
                                Button(template.name) {
                                    inputText = template.prompt
                                }
                            }
                        } label: {
                            Text("+\(templates.count - 4)")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(.background.secondary)
                                .clipShape(Capsule())
                                .overlay(Capsule().strokeBorder(.quaternary, lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .xrayId("chat.emptyState.templates")
    }
}
```

- [ ] **Step 4: Insert templateChipsView into chatEmptyState**

In the `chatEmptyState` computed property (around line 2093), find the `VStack(spacing: 16)` body. Insert `templateChipsView` **after** the agent/group header block and **before** the `let suggestions = emptyStateSuggestions` line:

```swift
@ViewBuilder
private var chatEmptyState: some View {
    VStack(spacing: 16) {
        // ... existing agent/group/freeform header block (unchanged) ...

        // NEW: template chips, only while thread has no messages
        if (conversation?.messages ?? []).isEmpty {
            templateChipsView
        }

        // existing suggestions
        let suggestions = emptyStateSuggestions
        VStack(spacing: 8) {
            // ... existing suggestion rows (unchanged) ...
        }
        .xrayId("chat.emptyState.suggestions")
    }
    .frame(maxWidth: .infinity)
    .padding(.top, 40)
}
```

- [ ] **Step 5: Build**

```bash
xcodebuild -scheme Odyssey -destination 'platform=macOS,arch=arm64' build 2>&1 | grep "error:"
```

Expected: Clean build.

- [ ] **Step 6: Commit**

```bash
git add Odyssey/Views/MainWindow/ChatView.swift
git commit -m "feat: add PromptTemplate chips to ChatView empty state for agent/group threads"
```

---

### Task 6: Remove TemplatePickerRow from NewSessionSheet

**Files:**

- Modify: `Odyssey/Views/MainWindow/NewSessionSheet.swift`

- [ ] **Step 1: Find all TemplatePickerRow usages**

```bash
grep -n "TemplatePickerRow\|availableTemplates\|templateOwnerLabel" \
  /Users/shayco/Odyssey/Odyssey/Views/MainWindow/NewSessionSheet.swift
```

- [ ] **Step 2: Delete the TemplatePickerRow call and its supporting state**

Remove:

- The `TemplatePickerRow(templates: availableTemplates, ...)` call site
- Any `@State` or computed var for `availableTemplates`
- Any computed var for `templateOwnerLabel`
- The `@Query private var allTemplates: [PromptTemplate]` line **only if** it has no other uses in the file

Search for remaining uses before deleting the `@Query`:

```bash
grep -n "allTemplates\|PromptTemplate" \
  /Users/shayco/Odyssey/Odyssey/Views/MainWindow/NewSessionSheet.swift
```

- [ ] **Step 3: Build**

```bash
xcodebuild -scheme Odyssey -destination 'platform=macOS,arch=arm64' build 2>&1 | grep "error:"
```

Expected: Clean build.

- [ ] **Step 4: Commit**

```bash
git add Odyssey/Views/MainWindow/NewSessionSheet.swift
git commit -m "feat: remove TemplatePickerRow from NewSessionSheet — templates now live in ChatView empty state"
```

---

### Task 7: End-to-end verification

- [ ] **Build and run in Xcode**

Open `Odyssey.xcodeproj` (or `.xcworkspace`) and run on macOS. Verify each point manually:

1. ⌘N opens the agent picker popover anchored to the "+ New" button — shows search field, "No specialized agent" row (dashed border, ∅), and agent list.
2. Clicking an agent immediately navigates to a new thread in ChatView — no modal appears.
3. Clicking "No specialized agent" creates a blank freeform thread and navigates to it.
4. ⌘↵ in the agent popover reveals the mission field with purple tint. Clicking an agent with mission text filled starts the thread with that mission.
5. ⌘⌥N opens the group popover — shows search and group list with member-agent dots.
6. Clicking a group starts a group thread immediately.
7. ⌘⇧N opens the agent popover.
8. Opening a brand-new agent thread (with templates defined for that agent in Settings → Templates) shows template chips in the center of the empty chat area.
9. Clicking a template chip fills the input bar with the template's prompt text.
10. After sending the first message, template chips no longer appear.
11. The old NewSessionSheet 860×720 modal no longer appears from any sidebar entry point.
12. Existing threads open and function normally — no regressions in ChatView message display or streaming.
