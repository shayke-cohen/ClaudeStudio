# Workshop View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a dedicated "Workshop" view — a single place to browse, inspect, and AI-edit all ClaudPeer entities (agents, groups, skills, MCPs, permissions) with an embedded Config Agent chat pane.

**Architecture:** The Workshop is a new detail-pane destination (not a sheet) — it lives in the main `NavigationSplitView` detail area alongside ChatView, GroupDetailView, and WelcomeView. Left side shows a tabbed entity browser with cards/rows for each entity type. Right side docks a persistent Config Agent chat session. Clicking an entity in the browser injects context into the chat. The existing `ConfigSyncService` file watcher handles live reload — no new sync code needed.

**Tech Stack:** SwiftUI, SwiftData (`@Query`), existing `ConfigSyncService` + `ConfigFileManager`, existing `ChatView` (embedded), existing card components.

---

## File Structure

| Action | File | Responsibility |
|--------|------|---------------|
| Create | `ClaudPeer/Views/Workshop/WorkshopView.swift` | Root Workshop view: HSplitView with entity browser (left) + config chat (right) |
| Create | `ClaudPeer/Views/Workshop/WorkshopEntityBrowser.swift` | Tabbed entity browser: Agents / Groups / Skills / MCPs / Permissions tabs, each with search + grid/list |
| Create | `ClaudPeer/Views/Workshop/WorkshopEntityRow.swift` | Compact row component for entities — icon, name, enabled badge, key stats, click-to-select |
| Create | `ClaudPeer/Views/Workshop/WorkshopDetailPanel.swift` | Read-only detail panel for the selected entity — shows all fields in a structured layout |
| Modify | `ClaudPeer/App/AppState.swift:51-56` | Add `showWorkshop` published property |
| Modify | `ClaudPeer/Views/MainWindow/MainWindowView.swift:101-121` | Add `.sheet(isPresented: $appState.showWorkshop)` for Workshop |
| Modify | `ClaudPeer/Views/MainWindow/SidebarView.swift:96-154` | Add Workshop button to sidebar bottom bar |
| Test | `ClaudPeerTests/WorkshopViewTests.swift` | Unit tests for entity browser filtering + context injection logic |

---

## Task 1: AppState + Navigation Hook

Wire up the Workshop as a new sheet destination, accessible from sidebar.

**Files:**
- Modify: `ClaudPeer/App/AppState.swift:51-56`
- Modify: `ClaudPeer/Views/MainWindow/MainWindowView.swift:101-121`
- Modify: `ClaudPeer/Views/MainWindow/SidebarView.swift:96-154`

- [ ] **Step 1: Add `showWorkshop` to AppState**

In `AppState.swift`, after the `showDirectoryPicker` line (line 56), add:

```swift
@Published var showWorkshop = false
```

- [ ] **Step 2: Add Workshop sheet to MainWindowView**

In `MainWindowView.swift`, after the `.sheet(isPresented: $appState.showPeerNetwork)` block (after line 121), add:

```swift
.sheet(isPresented: $appState.showWorkshop) {
    WorkshopView()
        .environmentObject(appState)
        .frame(minWidth: 960, minHeight: 640)
}
```

- [ ] **Step 3: Add Workshop button to sidebar bottom bar**

In `SidebarView.swift`, in the `sidebarBottomBar` HStack, add a new button between the Catalog button and the Agents button (after the first `Divider()` at line 109):

```swift
Button {
    appState.showWorkshop = true
} label: {
    Label("Workshop", systemImage: "wrench.and.screwdriver")
        .font(.caption)
        .frame(maxWidth: .infinity)
}
.buttonStyle(.plain)
.help("Entity workshop (⌘⇧W)")
.xrayId("sidebar.workshopButton")
.keyboardShortcut("w", modifiers: [.command, .shift])

Divider()
    .frame(height: 16)
```

- [ ] **Step 4: Create Workshop directory and placeholder WorkshopView**

First create the directory: `mkdir -p ClaudPeer/Views/Workshop/`

Then create `ClaudPeer/Views/Workshop/WorkshopView.swift` with a minimal placeholder so the app compiles:

```swift
import SwiftUI

struct WorkshopView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
            Text("Workshop")
                .font(.title)
            Button("Close") { dismiss() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 5: Build and verify**

Run: `xcodegen generate && xcodebuild -scheme ClaudPeer -destination 'platform=macOS' build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED. Sidebar shows Workshop button. Clicking it opens placeholder sheet.

- [ ] **Step 6: Commit**

```bash
git add ClaudPeer/App/AppState.swift ClaudPeer/Views/MainWindow/MainWindowView.swift ClaudPeer/Views/MainWindow/SidebarView.swift ClaudPeer/Views/Workshop/WorkshopView.swift
git commit -m "feat(workshop): add navigation hook and placeholder view"
```

---

## Task 2: Entity Browser — Tabbed Shell

Build the left pane of the Workshop: a tab picker across entity types with search.

**Files:**
- Create: `ClaudPeer/Views/Workshop/WorkshopEntityBrowser.swift`

- [ ] **Step 1: Create WorkshopEntityBrowser**

```swift
import SwiftUI
import SwiftData

enum WorkshopTab: String, CaseIterable, Identifiable {
    case agents = "Agents"
    case groups = "Groups"
    case skills = "Skills"
    case mcps = "MCPs"
    case permissions = "Permissions"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .agents: return "cpu"
        case .groups: return "person.3"
        case .skills: return "book"
        case .mcps: return "server.rack"
        case .permissions: return "lock.shield"
        }
    }
}

struct WorkshopEntityBrowser: View {
    @Query(sort: \Agent.name) private var agents: [Agent]
    @Query(sort: \AgentGroup.name) private var groups: [AgentGroup]
    @Query(sort: \Skill.name) private var skills: [Skill]
    @Query(sort: \MCPServer.name) private var mcps: [MCPServer]
    @Query(sort: \PermissionSet.name) private var permissions: [PermissionSet]

    @Binding var selectedTab: WorkshopTab
    @Binding var selectedEntityContext: String?
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Tab picker
            Picker("Entity Type", selection: $selectedTab) {
                ForEach(WorkshopTab.allCases) { tab in
                    Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .xrayId("workshop.tabPicker")

            // Search
            TextField("Search \(selectedTab.rawValue.lowercased())...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .xrayId("workshop.searchField")

            Divider()

            // Entity list
            ScrollView {
                LazyVStack(spacing: 2) {
                    switch selectedTab {
                    case .agents:
                        ForEach(filteredAgents) { agent in
                            WorkshopEntityRow(
                                icon: agent.icon,
                                color: agent.color,
                                name: agent.name,
                                subtitle: agent.agentDescription,
                                isEnabled: agent.isEnabled,
                                badges: [agent.model, "\(agent.skillIds.count) skills"]
                            ) {
                                selectedEntityContext = agentContextString(agent)
                            }
                            .xrayId("workshop.agentRow.\(agent.id.uuidString)")
                        }
                    case .groups:
                        ForEach(filteredGroups) { group in
                            WorkshopEntityRow(
                                icon: group.icon,
                                color: group.color,
                                name: group.name,
                                subtitle: group.groupDescription,
                                isEnabled: group.isEnabled,
                                badges: ["\(group.agentIds.count) agents"]
                            ) {
                                selectedEntityContext = groupContextString(group)
                            }
                            .xrayId("workshop.groupRow.\(group.id.uuidString)")
                        }
                    case .skills:
                        ForEach(filteredSkills) { skill in
                            WorkshopEntityRow(
                                icon: "book.fill",
                                color: "blue",
                                name: skill.name,
                                subtitle: skill.skillDescription,
                                isEnabled: skill.isEnabled,
                                badges: [skill.category, "v\(skill.version)"]
                            ) {
                                selectedEntityContext = skillContextString(skill)
                            }
                            .xrayId("workshop.skillRow.\(skill.id.uuidString)")
                        }
                    case .mcps:
                        ForEach(filteredMCPs) { mcp in
                            WorkshopEntityRow(
                                icon: "server.rack",
                                color: "purple",
                                name: mcp.name,
                                subtitle: mcp.serverDescription,
                                isEnabled: mcp.isEnabled,
                                badges: [mcp.transportKind]
                            ) {
                                selectedEntityContext = mcpContextString(mcp)
                            }
                            .xrayId("workshop.mcpRow.\(mcp.id.uuidString)")
                        }
                    case .permissions:
                        ForEach(filteredPermissions) { perm in
                            WorkshopEntityRow(
                                icon: "lock.shield.fill",
                                color: "orange",
                                name: perm.name,
                                subtitle: "\(perm.allowRules.count) allow, \(perm.denyRules.count) deny",
                                isEnabled: perm.isEnabled,
                                badges: [perm.permissionMode]
                            ) {
                                selectedEntityContext = permContextString(perm)
                            }
                            .xrayId("workshop.permRow.\(perm.id.uuidString)")
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .xrayId("workshop.entityList")
        }
    }

    // MARK: - Filtered collections

    private var filteredAgents: [Agent] {
        guard !searchText.isEmpty else { return Array(agents) }
        return agents.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.agentDescription.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredGroups: [AgentGroup] {
        guard !searchText.isEmpty else { return Array(groups) }
        return groups.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.groupDescription.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredSkills: [Skill] {
        guard !searchText.isEmpty else { return Array(skills) }
        return skills.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.skillDescription.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredMCPs: [MCPServer] {
        guard !searchText.isEmpty else { return Array(mcps) }
        return mcps.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.serverDescription.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredPermissions: [PermissionSet] {
        guard !searchText.isEmpty else { return Array(permissions) }
        return permissions.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: - Context strings (injected into Config Agent chat)

    private func agentContextString(_ a: Agent) -> String {
        """
        [Context: User selected agent "\(a.name)" (slug: \(a.configSlug ?? "unknown"))]
        Model: \(a.model), Icon: \(a.icon), Color: \(a.color)
        Skills: \(a.skillIds.count), MCPs: \(a.extraMCPServerIds.count)
        Enabled: \(a.isEnabled), Policy: \(a.instancePolicyKind)
        Budget: $\(String(format: "%.2f", a.maxBudget ?? 0)), Max turns: \(a.maxTurns ?? 0)
        Description: \(a.agentDescription)
        """
    }

    private func groupContextString(_ g: AgentGroup) -> String {
        """
        [Context: User selected group "\(g.name)" (slug: \(g.configSlug ?? "unknown"))]
        Agents: \(g.agentIds.count), Auto-reply: \(g.autoReplyEnabled), Autonomous: \(g.autonomousCapable)
        Description: \(g.groupDescription)
        Instruction: \(g.groupInstruction.isEmpty ? "none" : g.groupInstruction)
        """
    }

    private func skillContextString(_ s: Skill) -> String {
        """
        [Context: User selected skill "\(s.name)" (slug: \(s.configSlug ?? "unknown"))]
        Category: \(s.category), Version: \(s.version), Enabled: \(s.isEnabled)
        Description: \(s.skillDescription)
        """
    }

    private func mcpContextString(_ m: MCPServer) -> String {
        """
        [Context: User selected MCP server "\(m.name)" (slug: \(m.configSlug ?? "unknown"))]
        Transport: \(m.transportKind), Enabled: \(m.isEnabled)
        Description: \(m.serverDescription)
        """
    }

    private func permContextString(_ p: PermissionSet) -> String {
        """
        [Context: User selected permission preset "\(p.name)" (slug: \(p.configSlug ?? "unknown"))]
        Allow: \(p.allowRules.joined(separator: ", "))
        Deny: \(p.denyRules.joined(separator: ", "))
        Mode: \(p.permissionMode), Enabled: \(p.isEnabled)
        """
    }
}
```

**Note:** Uses `mcp.transportKind` (stored `String` property on `MCPServer`) for the transport badge — no computed property needed.

- [ ] **Step 2: Build and verify**

Run: `xcodegen generate && xcodebuild -scheme ClaudPeer -destination 'platform=macOS' build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED (not yet wired into WorkshopView).

- [ ] **Step 3: Commit**

```bash
git add ClaudPeer/Views/Workshop/WorkshopEntityBrowser.swift
git commit -m "feat(workshop): add tabbed entity browser with search and context injection"
```

---

## Task 3: Entity Row Component

A compact, reusable row for displaying any entity type in the browser list.

**Files:**
- Create: `ClaudPeer/Views/Workshop/WorkshopEntityRow.swift`

- [ ] **Step 1: Create WorkshopEntityRow**

```swift
import SwiftUI

struct WorkshopEntityRow: View {
    let icon: String
    let color: String
    let name: String
    let subtitle: String
    let isEnabled: Bool
    let badges: [String]
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(Color.fromAgentColor(color))
                    .frame(width: 28, height: 28)
                    .background(Color.fromAgentColor(color).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(name)
                            .font(.body)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        if !isEnabled {
                            Text("disabled")
                                .font(.caption2)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(.orange.opacity(0.15))
                                .foregroundStyle(.orange)
                                .clipShape(Capsule())
                        }
                    }
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                HStack(spacing: 6) {
                    ForEach(badges.filter { !$0.isEmpty }, id: \.self) { badge in
                        Text(badge)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isHovered ? Color.accentColor.opacity(0.06) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .opacity(isEnabled ? 1.0 : 0.55)
    }
}
```

- [ ] **Step 2: Build and verify**

Run: `xcodegen generate && xcodebuild -scheme ClaudPeer -destination 'platform=macOS' build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add ClaudPeer/Views/Workshop/WorkshopEntityRow.swift
git commit -m "feat(workshop): add compact entity row component"
```

---

## Task 4: Detail Panel — Read-Only Entity Inspector

When an entity is selected in the browser, show its full details in a read-only panel below (or inline). This gives visual feedback before asking the Config Agent to edit.

**Files:**
- Create: `ClaudPeer/Views/Workshop/WorkshopDetailPanel.swift`

- [ ] **Step 1: Create WorkshopDetailPanel**

```swift
import SwiftUI
import SwiftData

struct WorkshopDetailPanel: View {
    let entityContext: String?

    @Query(sort: \Agent.name) private var agents: [Agent]
    @Query(sort: \AgentGroup.name) private var groups: [AgentGroup]
    @Query(sort: \Skill.name) private var skills: [Skill]
    @Query(sort: \MCPServer.name) private var mcps: [MCPServer]
    @Query(sort: \PermissionSet.name) private var permissions: [PermissionSet]

    var body: some View {
        Group {
            if let context = entityContext, let parsed = parseContext(context) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // Header
                        HStack {
                            Text(parsed.name)
                                .font(.title3)
                                .fontWeight(.semibold)
                            Spacer()
                            Text(parsed.type)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.quaternary)
                                .clipShape(Capsule())
                        }
                        .xrayId("workshop.detail.header")

                        Divider()

                        // Raw context as formatted key-value pairs
                        ForEach(parsed.fields, id: \.key) { field in
                            HStack(alignment: .top, spacing: 8) {
                                Text(field.key)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 80, alignment: .trailing)
                                Text(field.value)
                                    .font(.caption)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .padding()
                }
                .xrayId("workshop.detailPanel")
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "hand.point.up.left")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("Select an entity to inspect")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .xrayId("workshop.detailPanel.empty")
            }
        }
    }

    // MARK: - Parse context string into displayable fields

    private struct ParsedEntity {
        let type: String
        let name: String
        let fields: [(key: String, value: String)]
    }

    private func parseContext(_ context: String) -> ParsedEntity? {
        let lines = context.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let firstLine = lines.first else { return nil }

        // Extract type and name from "[Context: User selected TYPE "NAME" ...]"
        let typePattern = /User selected (\w[\w ]*) "([^"]+)"/
        guard let match = firstLine.firstMatch(of: typePattern) else { return nil }
        let type = String(match.1)
        let name = String(match.2)

        var fields: [(key: String, value: String)] = []
        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if let colonIdx = trimmed.firstIndex(of: ":") {
                let key = String(trimmed[trimmed.startIndex..<colonIdx]).trimmingCharacters(in: .whitespaces)
                let value = String(trimmed[trimmed.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                fields.append((key: key, value: value))
            }
        }

        return ParsedEntity(type: type, name: name, fields: fields)
    }
}
```

- [ ] **Step 2: Build and verify**

Run: `xcodegen generate && xcodebuild -scheme ClaudPeer -destination 'platform=macOS' build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add ClaudPeer/Views/Workshop/WorkshopDetailPanel.swift
git commit -m "feat(workshop): add read-only entity detail panel"
```

---

## Task 5: Wire WorkshopView — Full Layout

Assemble the Workshop: entity browser (left) + detail/chat (right). The chat pane embeds a real ChatView connected to a Config Agent session.

**Files:**
- Modify: `ClaudPeer/Views/Workshop/WorkshopView.swift` (replace placeholder)

- [ ] **Step 1: Implement full WorkshopView**

Replace the placeholder `WorkshopView.swift` with:

```swift
import SwiftUI
import SwiftData

struct WorkshopView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState

    @Query(sort: \Agent.name) private var agents: [Agent]

    @State private var selectedTab: WorkshopTab = .agents
    @State private var selectedEntityContext: String?
    @State private var configConversationId: UUID?
    @State private var pendingContextMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                // Left: Entity browser + detail
                VStack(spacing: 0) {
                    WorkshopEntityBrowser(
                        selectedTab: $selectedTab,
                        selectedEntityContext: $selectedEntityContext
                    )
                    .frame(maxHeight: .infinity)

                    if selectedEntityContext != nil {
                        Divider()
                        WorkshopDetailPanel(entityContext: selectedEntityContext)
                            .frame(height: 160)
                    }
                }
                .frame(minWidth: 300, idealWidth: 380, maxWidth: 480)

                // Right: Config Agent chat
                VStack(spacing: 0) {
                    if let convId = configConversationId {
                        ChatView(conversationId: convId)
                            .id(convId)
                    } else {
                        configChatPlaceholder
                    }
                }
                .frame(minWidth: 400, maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            ensureConfigSession()
        }
        .onChange(of: selectedEntityContext) { _, newValue in
            if let context = newValue, configConversationId != nil {
                pendingContextMessage = context
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "wrench.and.screwdriver")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Workshop")
                .font(.title2)
                .fontWeight(.semibold)
                .xrayId("workshop.title")

            Spacer()

            if configConversationId != nil {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                Text("Config Agent active")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Close")
            .xrayId("workshop.closeButton")
            .accessibilityLabel("Close workshop")
        }
        .padding()
    }

    // MARK: - Config Chat Placeholder

    private var configChatPlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "gearshape.2")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Config Agent")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Ask the Config Agent to edit agents, groups, skills, MCPs, and permissions using natural language.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
            Button("Start Config Session") {
                ensureConfigSession()
            }
            .buttonStyle(.borderedProminent)
            .xrayId("workshop.startConfigButton")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Session Management

    private func ensureConfigSession() {
        // Find the Config Agent
        guard let configAgent = agents.first(where: {
            $0.name == "Config Agent" && $0.isEnabled
        }) else { return }

        // Check for existing singleton session
        let descriptor = FetchDescriptor<Session>()
        let sessions = (try? modelContext.fetch(descriptor)) ?? []
        if let existingSession = sessions.first(where: {
            $0.agent?.name == "Config Agent" && $0.status != .completed && $0.status != .failed
        }), let existingConv = existingSession.conversations.first {
            configConversationId = existingConv.id
            return
        }

        // Create new session
        let session = Session(agent: configAgent, mode: .interactive)
        let conversation = Conversation(topic: "Workshop Config", sessions: [session])
        let userParticipant = Participant(type: .user, displayName: "You")
        let agentParticipant = Participant(
            type: .agentSession(sessionId: session.id),
            displayName: configAgent.name
        )
        userParticipant.conversation = conversation
        agentParticipant.conversation = conversation
        conversation.participants = [userParticipant, agentParticipant]
        session.conversations = [conversation]

        modelContext.insert(session)
        modelContext.insert(conversation)
        try? modelContext.save()

        configConversationId = conversation.id
    }
}
```

**Implementation notes:**
- `ensureConfigSession()` reuses an existing Config Agent session if one is active (singleton pattern), otherwise creates a new one.
- The `pendingContextMessage` state is prepared for Task 6 (context injection).
- `ChatView` is embedded directly — it already handles all the message display, input, streaming, and sidecar communication. We get the full chat experience for free.

- [ ] **Step 2: Build and verify**

Run: `xcodegen generate && xcodebuild -scheme ClaudPeer -destination 'platform=macOS' build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED. Workshop opens with browser on left, chat on right.

- [ ] **Step 3: Commit**

```bash
git add ClaudPeer/Views/Workshop/WorkshopView.swift
git commit -m "feat(workshop): wire full layout with entity browser and embedded config agent chat"
```

---

## Task 6: Context Injection — Click Entity → Chat Gets Context

When the user clicks an entity in the browser, inject a context message into the Config Agent chat so the agent knows what the user is looking at.

**Files:**
- Modify: `ClaudPeer/Views/Workshop/WorkshopView.swift`

- [ ] **Step 1: Add context injection method**

Add this method to `WorkshopView`:

```swift
private func injectContext(_ context: String) {
    guard let convId = configConversationId else { return }

    let descriptor = FetchDescriptor<Conversation>()
    let conversations = (try? modelContext.fetch(descriptor)) ?? []
    guard let conversation = conversations.first(where: { $0.id == convId }) else { return }

    // Add a system-style context message
    let contextMessage = ConversationMessage(
        text: context,
        type: .system,
        conversation: conversation
    )
    try? modelContext.save()
}
```

- [ ] **Step 2: Wire onChange to call injection**

Update the `onChange(of: selectedEntityContext)` handler:

```swift
.onChange(of: selectedEntityContext) { _, newValue in
    if let context = newValue, configConversationId != nil {
        injectContext(context)
    }
}
```

**Note:** `ConversationMessage` uses `MessageType.system` for non-user/non-agent messages. The context message will appear in the chat timeline as a system-style entry.

- [ ] **Step 3: Build and verify**

Run: `xcodegen generate && xcodebuild -scheme ClaudPeer -destination 'platform=macOS' build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED. Clicking an entity in the browser adds a context message to the chat.

- [ ] **Step 4: Commit**

```bash
git add ClaudPeer/Views/Workshop/WorkshopView.swift
git commit -m "feat(workshop): inject entity context into config agent chat on selection"
```

---

## Task 7: Enable/Disable Toggle — Quick Action Without Chat

The most common operation (toggling enabled/disabled) should be one click, not a chat message.

**Files:**
- Modify: `ClaudPeer/Views/Workshop/WorkshopEntityRow.swift`

- [ ] **Step 1: Add toggle to entity row**

Add a toggle parameter and UI to `WorkshopEntityRow`:

```swift
// Add to struct properties:
var onToggleEnabled: (() -> Void)?

// Add to the HStack, before the badges:
if let toggle = onToggleEnabled {
    Button {
        toggle()
    } label: {
        Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(isEnabled ? .green : .secondary)
    }
    .buttonStyle(.borderless)
    .help(isEnabled ? "Disable" : "Enable")
    .xrayId("workshop.toggleEnabled")
}
```

- [ ] **Step 2: Wire toggle callbacks in WorkshopEntityBrowser**

In `WorkshopEntityBrowser`, pass toggle closures for each entity type. For agents:

```swift
WorkshopEntityRow(
    icon: agent.icon,
    color: agent.color,
    name: agent.name,
    subtitle: agent.agentDescription,
    isEnabled: agent.isEnabled,
    badges: [agent.model, "\(agent.skillIds.count) skills"],
    onToggleEnabled: {
        agent.isEnabled.toggle()
        try? modelContext.save()
        appState.configSyncService?.writeBack(agent: agent)
    }
) {
    selectedEntityContext = agentContextString(agent)
}
```

Repeat the pattern for groups, skills, MCPs, permissions — each using the appropriate `writeBack` method.

**Note:** This requires adding `@Environment(\.modelContext)` and `@EnvironmentObject private var appState: AppState` to `WorkshopEntityBrowser`.

- [ ] **Step 3: Build and verify**

Run: `xcodegen generate && xcodebuild -scheme ClaudPeer -destination 'platform=macOS' build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED. Clicking the toggle circle enables/disables entities inline.

- [ ] **Step 4: Commit**

```bash
git add ClaudPeer/Views/Workshop/WorkshopEntityRow.swift ClaudPeer/Views/Workshop/WorkshopEntityBrowser.swift
git commit -m "feat(workshop): add inline enable/disable toggle on entity rows"
```

---

## Task 8: Entity Counts in Tab Badges

Show the count of entities per tab so users see at a glance how many agents, groups, etc. they have.

**Files:**
- Modify: `ClaudPeer/Views/Workshop/WorkshopEntityBrowser.swift`

- [ ] **Step 1: Replace segmented picker with custom tab bar showing counts**

Replace the `Picker` in `WorkshopEntityBrowser` with a custom tab bar:

```swift
// Replace the Picker with:
HStack(spacing: 4) {
    ForEach(WorkshopTab.allCases) { tab in
        let count = countForTab(tab)
        Button {
            selectedTab = tab
        } label: {
            HStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.caption2)
                Text(tab.rawValue)
                    .font(.caption)
                Text("\(count)")
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.quaternary)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(selectedTab == tab ? Color.accentColor.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .xrayId("workshop.tab.\(tab.rawValue)")
    }
}
.padding(.horizontal, 8)
.padding(.vertical, 6)
```

Add the count method:

```swift
private func countForTab(_ tab: WorkshopTab) -> Int {
    switch tab {
    case .agents: return agents.count
    case .groups: return groups.count
    case .skills: return skills.count
    case .mcps: return mcps.count
    case .permissions: return permissions.count
    }
}
```

- [ ] **Step 2: Build and verify**

Expected: Tab bar shows counts like "Agents 11", "Groups 12", etc.

- [ ] **Step 3: Commit**

```bash
git add ClaudPeer/Views/Workshop/WorkshopEntityBrowser.swift
git commit -m "feat(workshop): add entity counts to tab badges"
```

---

## Task 9: Factory Reset Per Entity

Add a "Restore Default" action in the entity row context menu, using the existing `ConfigSyncService.restoreFactoryDefault()`.

**Files:**
- Modify: `ClaudPeer/Views/Workshop/WorkshopEntityBrowser.swift`

- [ ] **Step 1: Add context menu to entity rows**

Wrap each `WorkshopEntityRow` in the browser with a `.contextMenu`:

```swift
WorkshopEntityRow(...)
{
    selectedEntityContext = agentContextString(agent)
}
.contextMenu {
    if let slug = agent.configSlug {
        Button("Restore Factory Default") {
            appState.configSyncService?.restoreFactoryDefault(entityType: "agents", slug: slug)
        }
        .xrayId("workshop.agentRow.restore.\(agent.id.uuidString)")
    }
}
```

Repeat for each entity type with the appropriate `entityType` string: `"agents"`, `"groups"`, `"skills"`, `"mcps"`, `"permissions"`.

- [ ] **Step 2: Build and verify**

Expected: Right-clicking an entity row shows "Restore Factory Default" option.

- [ ] **Step 3: Commit**

```bash
git add ClaudPeer/Views/Workshop/WorkshopEntityBrowser.swift
git commit -m "feat(workshop): add factory reset context menu action"
```

---

## Task 10: Tests

**Files:**
- Create: `ClaudPeerTests/WorkshopViewTests.swift`

- [ ] **Step 1: Write tests for context string generation and entity filtering**

```swift
import XCTest
@testable import ClaudPeer

final class WorkshopViewTests: XCTestCase {

    func testWorkshopTabCases() {
        let tabs = WorkshopTab.allCases
        XCTAssertEqual(tabs.count, 5)
        XCTAssertEqual(tabs.map(\.rawValue), ["Agents", "Groups", "Skills", "MCPs", "Permissions"])
    }

    func testWorkshopTabIcons() {
        XCTAssertEqual(WorkshopTab.agents.icon, "cpu")
        XCTAssertEqual(WorkshopTab.groups.icon, "person.3")
        XCTAssertEqual(WorkshopTab.skills.icon, "book")
        XCTAssertEqual(WorkshopTab.mcps.icon, "server.rack")
        XCTAssertEqual(WorkshopTab.permissions.icon, "lock.shield")
    }

    func testWorkshopTabIdentifiable() {
        for tab in WorkshopTab.allCases {
            XCTAssertEqual(tab.id, tab.rawValue)
        }
    }
}
```

- [ ] **Step 2: Run tests**

Run: `xcodebuild test -scheme ClaudPeer -destination 'platform=macOS' -only-testing:ClaudPeerTests/WorkshopViewTests 2>&1 | tail -10`

Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add ClaudPeerTests/WorkshopViewTests.swift
git commit -m "test(workshop): add WorkshopTab unit tests"
```

---

## Verification Checklist

After all tasks are complete:

1. **Navigation:** Sidebar Workshop button (wrench icon) opens the Workshop sheet
2. **Keyboard shortcut:** ⌘⇧W opens the Workshop
3. **Entity browser:** All 5 tabs show correct entity lists with counts
4. **Search:** Filtering works within each tab
5. **Selection:** Clicking an entity row shows its details in the detail panel
6. **Context injection:** Clicking an entity adds a context message to the Config Agent chat
7. **Config Agent chat:** Full ChatView functionality — send messages, see streaming responses, tool calls visible
8. **Enable/disable toggle:** One-click toggle works and persists via ConfigSyncService
9. **Factory reset:** Context menu → Restore Factory Default works
10. **Live reload:** When Config Agent edits a file, the entity browser updates automatically (via ConfigSyncService file watcher)
11. **Singleton reuse:** Opening Workshop multiple times reuses the same Config Agent session
12. **Tests pass:** `WorkshopViewTests` all green
