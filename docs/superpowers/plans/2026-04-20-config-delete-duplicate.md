# Config Delete & Duplicate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Delete (with confirmation) and Duplicate actions to agents and groups in the Configuration settings tab — surfaced as hero header buttons and right-click context menu items.

**Architecture:** `ConfigurationSettingsTab` owns all state and SwiftData mutations. It passes `onDelete`/`onDuplicate` callbacks to `ConfigurationDetailView` for hero buttons, and adds `.contextMenu` directly to agent/group list rows. A `confirmationDialog` at the tab level handles delete confirmation.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, macOS 14+

---

## File Map

| File | Change |
|---|---|
| `Odyssey/Views/Settings/ConfigurationDetailView.swift` | Add `onDelete`/`onDuplicate` callbacks; add Duplicate + Delete hero buttons; add `isDestructive` param to `HeroButtonStyle` |
| `Odyssey/Views/Settings/ConfigurationSettingsTab.swift` | Add delete/duplicate logic, confirmation state, context menus on agent/group rows, tab-level edit sheets for context menu Edit |

---

## Task 1: Add callbacks and hero buttons to ConfigurationDetailView

**Files:**
- Modify: `Odyssey/Views/Settings/ConfigurationDetailView.swift`

- [ ] **Step 1: Add `onDelete` and `onDuplicate` callback properties to `ConfigurationDetailView`**

In `ConfigurationDetailView`, after `@State private var showingMCPEditor = false`, add:

```swift
// Callbacks (agents and groups only — nil hides the button)
var onDelete: (() -> Void)? = nil
var onDuplicate: (() -> Void)? = nil
```

- [ ] **Step 2: Add `isDestructive` parameter to `HeroButtonStyle`**

Replace the existing `HeroButtonStyle` at the bottom of the file:

```swift
private struct HeroButtonStyle: ButtonStyle {
    var isDestructive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                .white.opacity(configuration.isPressed ? 0.28 : 0.18),
                in: RoundedRectangle(cornerRadius: 7)
            )
            .foregroundStyle(isDestructive ? Color(red: 1, green: 0.55, blue: 0.55) : .white)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(.white.opacity(0.12))
            )
    }
}
```

- [ ] **Step 3: Add `heroDuplicateButton` and `heroDeleteButton` computed properties**

After the existing `heroEditButton` property, add:

```swift
private var heroDuplicateButton: some View {
    Button { onDuplicate?() } label: {
        Label("Duplicate", systemImage: "plus.square.on.square")
            .font(.system(size: 11, weight: .semibold))
    }
    .buttonStyle(HeroButtonStyle())
    .help("Duplicate this item")
    .accessibilityIdentifier("settings.configuration.heroDuplicateButton")
    .accessibilityLabel("Duplicate")
}

private var heroDeleteButton: some View {
    Button { onDelete?() } label: {
        Label("Delete", systemImage: "trash")
            .font(.system(size: 11, weight: .semibold))
    }
    .buttonStyle(HeroButtonStyle(isDestructive: true))
    .help("Delete this item")
    .accessibilityIdentifier("settings.configuration.heroDeleteButton")
    .accessibilityLabel("Delete")
}
```

- [ ] **Step 4: Show new buttons in the hero header**

In `heroSection`, find this `HStack`:

```swift
HStack(spacing: 6) {
    heroRevealButton
    if canEdit { heroEditButton }
}
```

Replace with:

```swift
HStack(spacing: 6) {
    heroRevealButton
    if canEdit { heroEditButton }
    if onDuplicate != nil { heroDuplicateButton }
    if onDelete != nil { heroDeleteButton }
}
```

- [ ] **Step 5: Build and verify**

```bash
cd /Users/shayco/Odyssey && make build-check
```

Expected: `✓ Build succeeded`

- [ ] **Step 6: Commit**

```bash
cd /Users/shayco/Odyssey
git add Odyssey/Views/Settings/ConfigurationDetailView.swift
git commit -m "feat(config): add duplicate/delete hero buttons to detail view"
```

---

## Task 2: Add logic, confirmation, and context menus to ConfigurationSettingsTab

**Files:**
- Modify: `Odyssey/Views/Settings/ConfigurationSettingsTab.swift`

- [ ] **Step 1: Add delete/duplicate/confirmation state properties**

In `ConfigurationSettingsTab`, after `@State private var showingNewMCP = false`, add:

```swift
@State private var itemToDelete: ConfigSelectedItem?
@State private var showingDeleteConfirmation = false
@State private var contextMenuAgentToEdit: Agent?
@State private var contextMenuGroupToEdit: AgentGroup?
```

- [ ] **Step 2: Add `deleteItem` and `duplicateItem` functions**

After the existing `handleNewItem()` function, add:

```swift
private func deleteItem(_ item: ConfigSelectedItem) {
    switch item {
    case .agent(let agent):
        for session in (agent.sessions ?? []) { modelContext.delete(session) }
        for template in (agent.promptTemplates ?? []) { modelContext.delete(template) }
        modelContext.delete(agent)
    case .group(let group):
        for template in (group.promptTemplates ?? []) { modelContext.delete(template) }
        modelContext.delete(group)
    default:
        return
    }
    try? modelContext.save()
    if selectedItem == item { selectedItem = nil }
}

private func duplicateItem(_ item: ConfigSelectedItem) {
    switch item {
    case .agent(let agent):
        let copy = Agent(
            name: "\(agent.name) Copy",
            agentDescription: agent.agentDescription,
            systemPrompt: agent.systemPrompt,
            provider: agent.provider,
            model: agent.model,
            icon: agent.icon,
            color: agent.color
        )
        copy.skillIds = agent.skillIds
        copy.extraMCPServerIds = agent.extraMCPServerIds
        copy.permissionSetId = agent.permissionSetId
        copy.maxTurns = agent.maxTurns
        copy.maxBudget = agent.maxBudget
        copy.defaultWorkingDirectory = agent.defaultWorkingDirectory
        copy.isResident = agent.isResident
        copy.showInSidebar = agent.showInSidebar
        modelContext.insert(copy)
        try? modelContext.save()
        selectedItem = .agent(copy)
    case .group(let group):
        let copy = AgentGroup(
            name: group.name + " Copy",
            groupDescription: group.groupDescription,
            icon: group.icon,
            color: group.color,
            groupInstruction: group.groupInstruction,
            defaultMission: group.defaultMission,
            agentIds: group.agentIds,
            sortOrder: group.sortOrder
        )
        copy.autoReplyEnabled = group.autoReplyEnabled
        copy.autonomousCapable = group.autonomousCapable
        copy.coordinatorAgentId = group.coordinatorAgentId
        copy.agentRolesJSON = group.agentRolesJSON
        copy.workflowJSON = group.workflowJSON
        modelContext.insert(copy)
        try? modelContext.save()
        selectedItem = .group(copy)
    default:
        break
    }
}

private func nameForDeleteItem(_ item: ConfigSelectedItem) -> String {
    switch item {
    case .agent(let a): return a.name
    case .group(let g): return g.name
    default: return "Item"
    }
}
```

- [ ] **Step 3: Pass callbacks to `ConfigurationDetailView` in `detailPane`**

Replace the existing `detailPane` computed property:

```swift
@ViewBuilder
private var detailPane: some View {
    if let item = selectedItem {
        let isAgentOrGroup: Bool = {
            switch item { case .agent, .group: return true; default: return false }
        }()
        ConfigurationDetailView(
            item: item,
            onDelete: isAgentOrGroup ? {
                itemToDelete = item
                showingDeleteConfirmation = true
            } : nil,
            onDuplicate: isAgentOrGroup ? { duplicateItem(item) } : nil
        )
    } else {
        emptyDetail
    }
}
```

- [ ] **Step 4: Add confirmation dialog and context-menu edit sheets to `body`**

In the `body` computed property, after the last existing `.sheet(isPresented: $showingNewMCP)` modifier and before `.onChange(of: selectedSection)`, add:

```swift
.confirmationDialog(
    "Delete \(itemToDelete.map { nameForDeleteItem($0) } ?? "Item")?",
    isPresented: $showingDeleteConfirmation,
    titleVisibility: .visible
) {
    Button("Delete", role: .destructive) {
        if let item = itemToDelete { deleteItem(item) }
        itemToDelete = nil
    }
    Button("Cancel", role: .cancel) { itemToDelete = nil }
} message: {
    Text("This action cannot be undone.")
}
.sheet(item: $contextMenuAgentToEdit) { agent in
    AgentCreationSheet(existingAgent: agent) { _ in contextMenuAgentToEdit = nil }
}
.sheet(item: $contextMenuGroupToEdit) { group in
    GroupEditorView(group: group)
}
```

- [ ] **Step 5: Add context menus to agent rows**

In `configItemList`, in the `.agents` case, the `itemRow` closure returns `ConfigListRow(...).tag(...)`. Add `.contextMenu` after `.tag(...)`:

Find this block (inside the `.agents` case):
```swift
return ConfigListRow(
    name: agent.name,
    icon: agent.icon,
    color: Color.fromAgentColor(agent.color),
    subtitle: subtitle,
    modelBadge: shortModel.isEmpty ? nil : shortModel,
    showPinDot: agent.isResident
)
.tag(ConfigSelectedItem.agent(agent))
```

Replace with:
```swift
return ConfigListRow(
    name: agent.name,
    icon: agent.icon,
    color: Color.fromAgentColor(agent.color),
    subtitle: subtitle,
    modelBadge: shortModel.isEmpty ? nil : shortModel,
    showPinDot: agent.isResident
)
.tag(ConfigSelectedItem.agent(agent))
.contextMenu {
    Button("Edit") { contextMenuAgentToEdit = agent }
    Button("Duplicate") { duplicateItem(.agent(agent)) }
    Divider()
    Button("Delete", role: .destructive) {
        itemToDelete = .agent(agent)
        showingDeleteConfirmation = true
    }
}
```

- [ ] **Step 6: Add context menus to group rows**

In the `.groups` case, find:
```swift
return ConfigListRow(
    name: group.name,
    icon: group.icon,
    color: Color.fromAgentColor(group.color),
    subtitle: subtitle
)
.tag(ConfigSelectedItem.group(group))
```

Replace with:
```swift
return ConfigListRow(
    name: group.name,
    icon: group.icon,
    color: Color.fromAgentColor(group.color),
    subtitle: subtitle
)
.tag(ConfigSelectedItem.group(group))
.contextMenu {
    Button("Edit") { contextMenuGroupToEdit = group }
    Button("Duplicate") { duplicateItem(.group(group)) }
    Divider()
    Button("Delete", role: .destructive) {
        itemToDelete = .group(group)
        showingDeleteConfirmation = true
    }
}
```

- [ ] **Step 7: Build and verify**

```bash
cd /Users/shayco/Odyssey && make build-check
```

Expected: `✓ Build succeeded`

- [ ] **Step 8: Commit**

```bash
cd /Users/shayco/Odyssey
git add Odyssey/Views/Settings/ConfigurationSettingsTab.swift
git commit -m "feat(config): add delete/duplicate with confirmation and context menus"
```

---

## Task 3: Manual smoke test

- [ ] **Step 1: Run the app**

```bash
open /Users/shayco/Odyssey/build/Build/Products/Debug/Odyssey.app
```

- [ ] **Step 2: Verify hero buttons**

1. Open Settings → Configuration → Agents
2. Select any agent
3. Verify "Duplicate" and "Delete" buttons appear in the hero header alongside "Reveal" and "Edit"
4. Click "Duplicate" — new "X Copy" agent should appear selected in the list
5. Select an agent, click "Delete" — confirmation dialog should appear with agent name, "Delete" and "Cancel"
6. Confirm delete — agent should be removed and selection cleared

- [ ] **Step 3: Verify context menu**

1. Right-click any agent row in the middle list
2. Verify menu shows: Edit / Duplicate / (divider) / Delete
3. Click "Edit" — AgentCreationSheet should open
4. Right-click a group row, verify same menu structure
5. Verify Skills, MCPs, Permissions rows have NO context menu

- [ ] **Step 4: Verify skills/MCPs/permissions show no new buttons**

Select a skill, MCP, or permission — hero header should show only "Reveal" (and "Edit" for editable items), no Duplicate or Delete buttons.

- [ ] **Step 5: Final commit if any fixes were needed**

```bash
cd /Users/shayco/Odyssey
git add -p
git commit -m "fix(config): <describe any fixes>"
```
