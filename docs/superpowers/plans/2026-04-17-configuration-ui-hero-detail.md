# Configuration UI — Hero Detail Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign the Settings › Configuration tab from a plain three-pane list into a modern "Hero Detail" layout with per-entity gradient hero headers, rich colored avatar list rows, and section-aware detail content.

**Architecture:** Three targeted file edits — a Color extension for gradient darkening, a full detail view redesign (gradient hero banner replaces plain icon + toolbar), and list row redesign (colored 28px avatar + model badge + pin dot). No new files, no model changes, no wire protocol changes. All existing functionality (Edit sheet, Reveal in Finder, chip navigation, deep-link routing) is preserved.

**Tech Stack:** SwiftUI, SwiftData, macOS 14+, AppKit (NSColor for HSB darkening), Swift 6 strict concurrency.

---

## File Structure

| File | Change |
|---|---|
| `Odyssey/Views/Components/ColorExtension.swift` | Add `func darkened(by:) -> Color` using NSColor HSB conversion |
| `Odyssey/Views/Settings/ConfigurationDetailView.swift` | Replace plain header + toolbar with gradient hero banner; restructure body to section-aware chips + body text + config rows; move Edit/Reveal into hero |
| `Odyssey/Views/Settings/ConfigurationSettingsTab.swift` | Replace `ConfigItemRow` with `ConfigListRow` (colored avatar, name, subtitle, model badge, pin dot); move "+ New" from list footer to list header |

---

### Task 1: Add `Color.darkened(by:)` to `ColorExtension.swift`

**Files:**
- Modify: `Odyssey/Views/Components/ColorExtension.swift`

**Context:** The gradient hero header needs a darkened end-stop. We extend `Color` with a method that converts to NSColor, adjusts HSB brightness, and returns a new SwiftUI Color. `import AppKit` is required because `NSColor` is AppKit-only on macOS.

- [ ] **Step 1: Replace the file contents**

```swift
import SwiftUI
import AppKit

extension Color {
    static func fromAgentColor(_ name: String) -> Color {
        switch name {
        case "blue":   return .blue
        case "red":    return .red
        case "green":  return .green
        case "purple": return .purple
        case "orange": return .orange
        case "yellow": return .yellow
        case "pink":   return .pink
        case "teal":   return .teal
        case "indigo": return .indigo
        case "gray":   return .gray
        default:       return .accentColor
        }
    }

    /// Returns this color with brightness reduced by `fraction` (0–1).
    /// Used to compute gradient end-stops for the hero header.
    func darkened(by fraction: Double = 0.25) -> Color {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        guard let ns = NSColor(self).usingColorSpace(.sRGB) else { return self }
        ns.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return Color(
            hue: Double(hue),
            saturation: Double(saturation),
            brightness: Double(brightness) * (1.0 - fraction),
            opacity: Double(alpha)
        )
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
xcodebuild -project Odyssey.xcodeproj -scheme Odyssey -configuration Debug build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD SUCCEEDED"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Odyssey/Views/Components/ColorExtension.swift
git commit -m "feat: add Color.darkened(by:) helper for gradient end-stop computation"
```

---

### Task 2: Redesign `ConfigurationDetailView` with gradient hero header

**Files:**
- Modify: `Odyssey/Views/Settings/ConfigurationDetailView.swift`

**Context:** Currently the view has a plain `header` var (44px icon + name), a `.toolbar { ToolbarItemGroup }` for Edit/Reveal, and a `ScrollView` wrapping all content. We're replacing this with: (1) a non-scrolling gradient hero banner at the top containing the avatar, name, meta-line, and buttons; (2) a scrollable body with section-aware chips, body text, and config rows.

`WindowState` is `@Observable` and injected via `.environment(ws)` at the project window level — accessible via `@Environment(WindowState.self)`. It provides `openConfiguration(section:slug:)` for chip navigation.

**Key model facts:**
- `Agent.instancePolicy` is a `@Transient` computed var of type `AgentInstancePolicy`; use `.displayName` for display.
- `AgentDefaults.inheritMarker` == `"system"` — this means "use system default model".
- `AgentGroup.roleFor(agentId:)` returns a `GroupRole` enum; `GroupRole.emoji` returns "👑"/"📋"/"👁"/"" for coordinator/scribe/observer/participant.
- `MCPServer.transport` is `MCPTransport` (either `.stdio(command, args, env)` or `.http(url, headers)`).
- Chips that navigate: skill/MCP/agent-name chips. Non-navigable: trigger-word chips, transport-tag chips.

- [ ] **Step 1: Add `@Environment(WindowState.self)` and restructure `body`**

Add the import and environment property, then replace the `body` property and its `.toolbar` block. This step also introduces stub computed vars (`heroSection`, `promptSection`, `configSection`) so the file compiles immediately. The stubs will be replaced in subsequent steps.

Add after line 13 (`@Environment(\.modelContext) private var modelContext`):

```swift
@Environment(WindowState.self) private var windowState: WindowState
```

Replace the entire `body` computed var (currently lines 21–69) with:

```swift
var body: some View {
    VStack(spacing: 0) {
        heroSection
        Divider()
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                chipsSection
                promptSection
                configSection
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .sheet(isPresented: $showingAgentEditor) {
        if case .agent(let agent) = item {
            AgentEditorView(agent: agent) { _ in
                do { try modelContext.save() } catch { print("ConfigurationDetailView: save failed: \(error)") }
                showingAgentEditor = false
            }
        }
    }
    .sheet(isPresented: $showingGroupEditor) {
        if case .group(let group) = item {
            GroupEditorView(group: group)
        }
    }
    .sheet(isPresented: $showingSkillEditor) {
        if case .skill(let skill) = item {
            SkillEditorView(skill: skill) { _ in
                do { try modelContext.save() } catch { print("ConfigurationDetailView: save failed: \(error)") }
                showingSkillEditor = false
            }
        }
    }
    .sheet(isPresented: $showingMCPEditor) {
        if case .mcp(let mcp) = item {
            MCPEditorView(mcp: mcp) { _ in
                do { try modelContext.save() } catch { print("ConfigurationDetailView: save failed: \(error)") }
                showingMCPEditor = false
            }
        }
    }
    .xrayId("settings.configuration.detail")
}

// Stub — replaced in Step 3
private var heroSection: some View { EmptyView() }
// Stub — replaced in Step 5
private var promptSection: some View { promptPreview }
// Stub — replaced in Step 6
private var configSection: some View { EmptyView() }
```

Build to verify the stubs compile:

```bash
xcodebuild -project Odyssey.xcodeproj -scheme Odyssey -configuration Debug build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD SUCCEEDED"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 2: Add hero color helpers**

Insert the following right after the four `@State private var showing...` declarations:

```swift
// MARK: - Hero colors

private var heroStartColor: Color {
    switch item {
    case .agent(let a): return Color.fromAgentColor(a.color)
    case .group(let g): return Color.fromAgentColor(g.color)
    case .skill:        return .green
    case .mcp:          return .orange
    case .permission:   return .indigo
    }
}

private var heroEndColor: Color {
    heroStartColor.darkened(by: 0.3)
}
```

- [ ] **Step 3: Replace the `heroSection` stub with the full gradient hero**

Find and replace the stub line `private var heroSection: some View { EmptyView() }` with:

```swift
// MARK: - Hero section

private var heroSection: some View {
    VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .top, spacing: 12) {
            heroAvatarView
            VStack(alignment: .leading, spacing: 3) {
                Text(itemName)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(itemMetaLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.65))
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                heroRevealButton
                if canEdit { heroEditButton }
            }
        }
        if shouldShowResidentBadge {
            Label("Resident", systemImage: "pin.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 5))
        }
    }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background {
        LinearGradient(
            colors: [heroStartColor, heroEndColor],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(.white.opacity(0.07))
                .frame(width: 140, height: 140)
                .offset(x: 40, y: -50)
        }
        .overlay(alignment: .bottomTrailing) {
            Circle()
                .fill(.white.opacity(0.05))
                .frame(width: 80, height: 80)
                .offset(x: -20, y: 25)
        }
        .clipped()
    }
    .xrayId("settings.configuration.heroHeader")
}

private var heroAvatarView: some View {
    ZStack {
        RoundedRectangle(cornerRadius: 12)
            .fill(.white.opacity(0.2))
            .frame(width: 44, height: 44)
        heroAvatarIcon
    }
}

@ViewBuilder
private var heroAvatarIcon: some View {
    switch item {
    case .agent(let a):
        if a.icon.unicodeScalars.first.map({ CharacterSet.letters.contains($0) }) == true {
            Image(systemName: a.icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
        } else {
            Text(a.icon).font(.system(size: 20))
        }
    case .group(let g):
        if g.icon.unicodeScalars.first.map({ CharacterSet.letters.contains($0) }) == true {
            Image(systemName: g.icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
        } else {
            Text(g.icon).font(.system(size: 20))
        }
    case .skill:
        Image(systemName: "bolt.fill")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.white)
    case .mcp:
        Image(systemName: "hammer.fill")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.white)
    case .permission:
        Image(systemName: "lock.shield.fill")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.white)
    }
}

private var heroRevealButton: some View {
    Button { revealInFinder() } label: {
        Label("Reveal", systemImage: "arrow.up.forward.square")
            .font(.system(size: 11, weight: .semibold))
    }
    .buttonStyle(HeroButtonStyle())
    .help("Reveal config file in Finder")
    .xrayId("settings.configuration.heroRevealButton")
}

private var heroEditButton: some View {
    Button { openEditor() } label: {
        Label("Edit", systemImage: "pencil")
            .font(.system(size: 11, weight: .semibold))
    }
    .buttonStyle(HeroButtonStyle())
    .help("Edit this item")
    .xrayId("settings.configuration.heroEditButton")
}

private var itemMetaLine: String {
    switch item {
    case .agent(let a):
        let model = a.model.contains("opus") ? "opus"
            : a.model.contains("sonnet") ? "sonnet"
            : a.model.contains("haiku") ? "haiku"
            : a.model == AgentDefaults.inheritMarker ? "default"
            : a.model
        var parts = ["Agent", model]
        if a.isResident { parts.append("resident") }
        return parts.joined(separator: " · ")
    case .group(let g):
        var parts = ["Group", "\(g.agentIds.count) agents"]
        if g.autonomousCapable { parts.append("autonomous") }
        return parts.joined(separator: " · ")
    case .skill(let s):
        return "Skill · \(s.category.isEmpty ? "Uncategorized" : s.category)"
    case .mcp(let m):
        return "MCP · \(m.transportKind)"
    case .permission:
        return "Permission Set"
    }
}

private var shouldShowResidentBadge: Bool {
    if case .agent(let a) = item { return a.isResident }
    return false
}
```

Add the button style **outside** `ConfigurationDetailView`, at the bottom of the file before the final `}` of the module:

```swift
// MARK: - Hero button style

private struct HeroButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                .white.opacity(configuration.isPressed ? 0.28 : 0.18),
                in: RoundedRectangle(cornerRadius: 7)
            )
            .foregroundStyle(.white)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(.white.opacity(0.12))
            )
    }
}
```

Build to verify:

```bash
xcodebuild -project Odyssey.xcodeproj -scheme Odyssey -configuration Debug build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD SUCCEEDED"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Rewrite `chipsSection` with section-aware content and navigation**

**First**, add `tappableChip` to the chip helpers section (right after the existing `chip(label:color:)` method — it's needed by the new chipsSection and defined permanently in Step 7):

```swift
private func tappableChip(label: String, color: Color, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(label)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
            .foregroundStyle(color.opacity(0.9))
    }
    .buttonStyle(.plain)
}
```

**Then**, replace the entire `chipsSection` computed var and all five chip methods (`agentChips`, `groupChips`, `skillChips`, `mcpChips`, `permissionChips`) with:

```swift
// MARK: - Chips section

@ViewBuilder
private var chipsSection: some View {
    switch item {
    case .agent(let agent):
        let agentSkills = skills.filter { agent.skillIds.contains($0.id) }
        let agentMCPs = mcps.filter { agent.extraMCPServerIds.contains($0.id) }
        if !agentSkills.isEmpty || !agentMCPs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if !agentSkills.isEmpty {
                    chipGroup(label: "Skills") {
                        ForEach(agentSkills) { skill in
                            tappableChip(label: "⚡ \(skill.name)", color: .green) {
                                windowState.openConfiguration(
                                    section: .skills,
                                    slug: skill.configSlug ?? ConfigFileManager.slugify(skill.name)
                                )
                            }
                        }
                    }
                }
                if !agentMCPs.isEmpty {
                    chipGroup(label: "MCPs") {
                        ForEach(agentMCPs) { mcp in
                            tappableChip(label: "🔧 \(mcp.name)", color: .orange) {
                                windowState.openConfiguration(
                                    section: .mcps,
                                    slug: mcp.configSlug ?? ConfigFileManager.slugify(mcp.name)
                                )
                            }
                        }
                    }
                }
            }
        }

    case .group(let group):
        let memberAgents = agents.filter { group.agentIds.contains($0.id) }
        if !memberAgents.isEmpty {
            chipGroup(label: "Members & Roles") {
                ForEach(memberAgents) { agent in
                    let role = group.roleFor(agentId: agent.id)
                    let prefix = role == .participant ? "" : "\(role.emoji) "
                    let suffix = role == .participant ? "" : " — \(role.displayName.lowercased())"
                    let label = "\(prefix)\(agent.name)\(suffix)"
                    let chipColor: Color = {
                        switch role {
                        case .coordinator: return .purple
                        case .scribe:      return .teal
                        case .observer:    return .yellow
                        case .participant: return .blue
                        }
                    }()
                    tappableChip(label: label, color: chipColor) {
                        windowState.openConfiguration(
                            section: .agents,
                            slug: agent.configSlug ?? ConfigFileManager.slugify(agent.name)
                        )
                    }
                }
            }
        } else {
            Text("No agents in this group.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }

    case .skill(let skill):
        VStack(alignment: .leading, spacing: 10) {
            if !skill.triggers.isEmpty {
                chipGroup(label: "Triggers") {
                    ForEach(skill.triggers, id: \.self) { trigger in
                        chip(label: trigger, color: .blue)   // display only, no navigation
                    }
                }
            }
            let usingAgents = agents.filter { $0.skillIds.contains(skill.id) }
            if !usingAgents.isEmpty {
                chipGroup(label: "Used by") {
                    ForEach(usingAgents) { agent in
                        tappableChip(label: "🤖 \(agent.name)", color: .green) {
                            windowState.openConfiguration(
                                section: .agents,
                                slug: agent.configSlug ?? ConfigFileManager.slugify(agent.name)
                            )
                        }
                    }
                }
            }
        }

    case .mcp(let mcp):
        VStack(alignment: .leading, spacing: 10) {
            chipGroup(label: "Transport") {
                chip(label: mcp.transportKind.uppercased(), color: .secondary)  // display only
            }
            let usingAgents = agents.filter { $0.extraMCPServerIds.contains(mcp.id) }
            if !usingAgents.isEmpty {
                chipGroup(label: "Used by") {
                    ForEach(usingAgents) { agent in
                        tappableChip(label: "🤖 \(agent.name)", color: .green) {
                            windowState.openConfiguration(
                                section: .agents,
                                slug: agent.configSlug ?? ConfigFileManager.slugify(agent.name)
                            )
                        }
                    }
                }
            }
        }

    case .permission(let perm):
        VStack(alignment: .leading, spacing: 10) {
            if !perm.allowRules.isEmpty {
                chipGroup(label: "Allow") {
                    ForEach(perm.allowRules, id: \.self) { rule in
                        chip(label: rule, color: .green)
                    }
                }
            }
            if !perm.denyRules.isEmpty {
                chipGroup(label: "Deny") {
                    ForEach(perm.denyRules, id: \.self) { rule in
                        chip(label: rule, color: .red)
                    }
                }
            }
            if perm.allowRules.isEmpty && perm.denyRules.isEmpty {
                Text("No rules defined.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
```

- [ ] **Step 5: Replace the `promptSection` stub with section-aware body text**

Find and replace the stub line `private var promptSection: some View { promptPreview }` with:

```swift
// MARK: - Body text section

@ViewBuilder
private var promptSection: some View {
    switch item {
    case .agent(let a) where !a.systemPrompt.isEmpty:
        promptBlock(title: "System Prompt", text: a.systemPrompt)
    case .group(let g) where !g.groupInstruction.isEmpty:
        promptBlock(title: "Group Instruction", text: g.groupInstruction)
    case .skill(let s) where !s.content.isEmpty:
        promptBlock(title: "Skill Content", text: s.content)
    case .mcp(let m):
        promptBlock(title: "Command", text: mcpCommandText(m))
    default:
        EmptyView()
    }
}

private func mcpCommandText(_ mcp: MCPServer) -> String {
    switch mcp.transport {
    case .stdio(let command, let args, let env):
        var lines = ["command: \(command)"]
        if !args.isEmpty {
            lines.append("args: [\(args.joined(separator: ", "))]")
        }
        if !env.isEmpty {
            lines.append("env:")
            for (k, v) in env.sorted(by: { $0.key < $1.key }) {
                lines.append("  \(k): \(v)")
            }
        }
        return lines.joined(separator: "\n")
    case .http(let url, let headers):
        var lines = ["url: \(url)"]
        if !headers.isEmpty {
            lines.append("headers:")
            for (k, v) in headers.sorted(by: { $0.key < $1.key }) {
                lines.append("  \(k): \(v)")
            }
        }
        return lines.joined(separator: "\n")
    }
}
```

- [ ] **Step 6: Replace the `configSection` stub with section-aware config rows**

Find and replace `private var configSection: some View { EmptyView() }` with:

```swift
// MARK: - Configuration rows

@ViewBuilder
private var configSection: some View {
    VStack(alignment: .leading, spacing: 8) {
        Text("Configuration")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
        VStack(spacing: 6) {
            configRows
        }
    }
}

@ViewBuilder
private var configRows: some View {
    switch item {
    case .agent(let a):
        let modelDisplay = a.model.contains("opus") ? "opus"
            : a.model.contains("sonnet") ? "sonnet"
            : a.model.contains("haiku") ? "haiku"
            : a.model == AgentDefaults.inheritMarker ? "system default"
            : a.model
        infoRow(key: "Model", value: modelDisplay)
        infoRow(key: "Max turns", value: a.maxTurns.map(String.init) ?? "∞")
        infoRow(key: "Max budget", value: a.maxBudget.map { String(format: "$%.2f", $0) } ?? "∞")
        infoRow(key: "Instance policy", value: a.instancePolicy.displayName)
        if let dir = a.defaultWorkingDirectory {
            infoRow(key: "Working directory", value: dir)
        }
    case .group(let g):
        infoRow(key: "Auto-reply", value: g.autoReplyEnabled ? "enabled" : "disabled")
        infoRow(key: "Autonomous", value: g.autonomousCapable ? "yes" : "no")
        if let coordId = g.coordinatorAgentId,
           let coordName = agents.first(where: { $0.id == coordId })?.name {
            infoRow(key: "Coordinator", value: coordName)
        }
        infoRow(key: "Members", value: "\(g.agentIds.count)")
    case .skill(let s):
        infoRow(key: "Category", value: s.category.isEmpty ? "—" : s.category)
        infoRow(key: "Agents using", value: "\(agents.filter { $0.skillIds.contains(s.id) }.count)")
        infoRow(key: "Source", value: s.sourceKind)
    case .mcp(let m):
        infoRow(key: "Transport", value: m.transportKind)
        infoRow(key: "Agents using", value: "\(agents.filter { $0.extraMCPServerIds.contains(m.id) }.count)")
    case .permission(let p):
        infoRow(key: "Mode", value: p.permissionMode)
        infoRow(key: "Allow rules", value: "\(p.allowRules.count)")
        infoRow(key: "Deny rules", value: "\(p.denyRules.count)")
    }
}

private func infoRow(key: String, value: String) -> some View {
    HStack {
        Text(key)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        Spacer()
        Text(value)
            .font(.system(size: 11, weight: .medium))
    }
}
```

- [ ] **Step 7: Tidy chip helpers and remove dead code**

Replace the `chipGroup` and `chip` helpers (currently lines ~398–417) with the versions below. `tappableChip` was already added in Step 4 — do not add it again, just ensure it's present:

```swift
// MARK: - Chip helpers

private func chipGroup<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
        FlowLayout(spacing: 6) {
            content()
        }
    }
}

private func chip(label: String, color: Color) -> some View {
    Text(label)
        .font(.caption.weight(.medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
        .foregroundStyle(color.opacity(0.9))
}

private func tappableChip(label: String, color: Color, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(label)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
            .foregroundStyle(color.opacity(0.9))
    }
    .buttonStyle(.plain)
}
```

Now delete these properties — they are no longer used (the file won't compile if any references remain, which would be a bug):
- `private var header: some View { ... }` — the entire `// MARK: - Header` section (the old `header`, `itemIconView`, `iconCircle(raw:color:)`, `itemTypeLabel`)
- `private var revealButton: some View { ... }` — replaced by `heroRevealButton`
- `private var editButton: some View { ... }` — replaced by `heroEditButton`
- `private var promptPreview: some View { ... }` — replaced by `promptSection`
- `private func namedColor(_ name: String) -> Color` — replaced by `Color.fromAgentColor`

Keep these (still used):
- `itemName` computed var — used in heroSection's `Text(itemName)`
- `canEdit` computed var — used in heroSection's `if canEdit { heroEditButton }`
- `revealInFinder()` function — called by `heroRevealButton`
- `openEditor()` function — called by `heroEditButton`
- `promptBlock(title:text:)` function — used by `promptSection`
- `truncated(_:maxChars:)` function — used by `promptBlock`

- [ ] **Step 8: Build to verify**

```bash
xcodebuild -project Odyssey.xcodeproj -scheme Odyssey -configuration Debug build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD SUCCEEDED"
```

Expected: `** BUILD SUCCEEDED **`

Fix any compiler errors. Common issues:
- "Use of unresolved identifier" → a helper was removed that's still referenced; check step 7 list.
- "Ambiguous use of" → there are two methods with the same name; check for leftover old methods.

- [ ] **Step 9: Commit**

```bash
git add Odyssey/Views/Settings/ConfigurationDetailView.swift
git commit -m "feat: redesign Configuration detail pane with gradient hero header and section-aware content"
```

---

### Task 3: Rich list rows and header in `ConfigurationSettingsTab`

**Files:**
- Modify: `Odyssey/Views/Settings/ConfigurationSettingsTab.swift`

**Context:** Replace the existing `ConfigItemRow` struct (plain icon + name + subtitle at lines 410–450) with a `ConfigListRow` that renders a colored 28px rounded-rect avatar, name, subtitle, optional model badge, and optional pin dot. Restructure `itemListPane` to show the section title and "+ New" button at the top (currently "+ New" is at the bottom of the pane).

Note: `configItemList` runs in the context of `ConfigurationSettingsTab`, which already has `@Query private var agents: [Agent]`, so group rows can compute member name subtitles directly.

- [ ] **Step 1: Replace `ConfigItemRow` with `ConfigListRow`**

Delete the entire `ConfigItemRow` struct (lines 410–450) and replace with:

```swift
// MARK: - Rich list row

private struct ConfigListRow: View {
    let name: String
    let icon: String
    let color: Color
    let subtitle: String
    var modelBadge: String? = nil
    var showPinDot: Bool = false

    var body: some View {
        HStack(spacing: 9) {
            avatarView
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let badge = modelBadge, !badge.isEmpty {
                badgeView(badge)
            }
            if showPinDot {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.vertical, 2)
    }

    private var avatarView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(color)
                .frame(width: 28, height: 28)
            if icon.unicodeScalars.first.map({ CharacterSet.letters.contains($0) }) == true {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            } else {
                Text(icon)
                    .font(.system(size: 13))
            }
        }
    }

    private func badgeView(_ model: String) -> some View {
        let (bg, fg) = badgeColors(model)
        return Text(model)
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(bg, in: RoundedRectangle(cornerRadius: 5))
            .foregroundStyle(fg)
    }

    private func badgeColors(_ model: String) -> (Color, Color) {
        if model.contains("opus")   { return (.blue.opacity(0.15),   .blue)   }
        if model.contains("sonnet") { return (.green.opacity(0.15),  .green)  }
        if model.contains("haiku")  { return (.purple.opacity(0.15), .purple) }
        return (.secondary.opacity(0.1), .secondary)
    }
}
```

- [ ] **Step 2: Restructure `itemListPane` — title + "+ New" at top, cleaner search field**

Replace the entire `itemListPane` computed var (lines 193–227):

```swift
private var itemListPane: some View {
    VStack(alignment: .leading, spacing: 0) {
        // Header: section title + "+ New" button
        HStack(alignment: .center) {
            Text(selectedSection.title)
                .font(.system(size: 13, weight: .bold))
            Spacer()
            if selectedSection != .templates && selectedSection != .permissions {
                Button { handleNewItem() } label: {
                    Text("+ New")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.accentColor)
                }
                .buttonStyle(.plain)
                .xrayId("settings.configuration.listNewButton")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 11)
        .padding(.bottom, 7)

        // Search field
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("Search \(selectedSection.title.lowercased())…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
        .xrayId("settings.configuration.listSearch")

        Divider()

        configItemList
    }
    .frame(maxHeight: .infinity)
}
```

- [ ] **Step 3: Update agent rows to use `ConfigListRow`**

In `configItemList`, replace the `.agents` case:

```swift
case .agents:
    ConfigItemList(
        items: filteredAgents,
        selectedItem: $selectedItem,
        itemRow: { agent in
            let skillCount = agent.skillIds.count
            let mcpCount = agent.extraMCPServerIds.count
            let subtitle: String = {
                var parts = ["\(skillCount) skill\(skillCount == 1 ? "" : "s")"]
                if mcpCount > 0 { parts.append("\(mcpCount) MCP\(mcpCount == 1 ? "" : "s")") }
                return parts.joined(separator: " · ")
            }()
            let shortModel: String = {
                if agent.model.contains("opus")   { return "opus"   }
                if agent.model.contains("sonnet") { return "sonnet" }
                if agent.model.contains("haiku")  { return "haiku"  }
                return agent.model == AgentDefaults.inheritMarker ? "" : String(agent.model.prefix(8))
            }()
            ConfigListRow(
                name: agent.name,
                icon: agent.icon,
                color: Color.fromAgentColor(agent.color),
                subtitle: subtitle,
                modelBadge: shortModel.isEmpty ? nil : shortModel,
                showPinDot: agent.isResident
            )
            .tag(ConfigSelectedItem.agent(agent))
        }
    )
```

- [ ] **Step 4: Update group rows**

Replace the `.groups` case:

```swift
case .groups:
    ConfigItemList(
        items: filteredGroups,
        selectedItem: $selectedItem,
        itemRow: { group in
            let memberNames = agents
                .filter { group.agentIds.contains($0.id) }
                .prefix(3)
                .map(\.name)
            let remaining = max(0, group.agentIds.count - 3)
            let subtitle: String = {
                guard !memberNames.isEmpty else { return "No members" }
                let joined = memberNames.joined(separator: " · ")
                return remaining > 0 ? "\(joined) +\(remaining) more" : joined
            }()
            ConfigListRow(
                name: group.name,
                icon: group.icon,
                color: Color.fromAgentColor(group.color),
                subtitle: subtitle
            )
            .tag(ConfigSelectedItem.group(group))
        }
    )
```

- [ ] **Step 5: Update skill rows**

Replace the `.skills` case:

```swift
case .skills:
    ConfigItemList(
        items: filteredSkills,
        selectedItem: $selectedItem,
        itemRow: { skill in
            let count = skill.triggers.count
            let subtitle = "\(skill.category.isEmpty ? "Uncategorized" : skill.category) · \(count) trigger\(count == 1 ? "" : "s")"
            ConfigListRow(
                name: skill.name,
                icon: "bolt.fill",
                color: .green,
                subtitle: subtitle
            )
            .tag(ConfigSelectedItem.skill(skill))
        }
    )
```

- [ ] **Step 6: Update MCP rows**

Replace the `.mcps` case:

```swift
case .mcps:
    ConfigItemList(
        items: filteredMCPs,
        selectedItem: $selectedItem,
        itemRow: { mcp in
            let desc = mcp.serverDescription.isEmpty
                ? mcp.transportKind
                : String(mcp.serverDescription.prefix(30))
            ConfigListRow(
                name: mcp.name,
                icon: "hammer.fill",
                color: .orange,
                subtitle: "\(mcp.transportKind) · \(desc)"
            )
            .tag(ConfigSelectedItem.mcp(mcp))
        }
    )
```

- [ ] **Step 7: Update permission rows**

Replace the `.permissions` case:

```swift
case .permissions:
    ConfigItemList(
        items: filteredPermissions,
        selectedItem: $selectedItem,
        itemRow: { perm in
            ConfigListRow(
                name: perm.name,
                icon: "lock.shield.fill",
                color: .indigo,
                subtitle: "\(perm.allowRules.count) allow · \(perm.denyRules.count) deny"
            )
            .tag(ConfigSelectedItem.permission(perm))
        }
    )
```

- [ ] **Step 8: Build to verify**

```bash
xcodebuild -project Odyssey.xcodeproj -scheme Odyssey -configuration Debug build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD SUCCEEDED"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 9: Commit**

```bash
git add Odyssey/Views/Settings/ConfigurationSettingsTab.swift
git commit -m "feat: redesign Configuration list pane with colored avatar rows and header"
```

---

## Manual Verification Checklist

Run the app (`⌘R` in Xcode) and verify:

1. Open Settings › Configuration — see hero gradient in detail pane
2. Select different agents — confirm gradient color updates to each agent's `color` field
3. Select a group — confirm gradient uses group's color
4. Select a Skill — confirm green gradient; "Triggers" chips are blue + non-tappable
5. Select an MCP — confirm orange gradient; "Transport" chip is non-tappable
6. Select a Permission — confirm indigo gradient; no Edit button shown
7. Tap a skill chip on an agent → Settings navigates to Skills › that skill
8. Tap an MCP chip on an agent → Settings navigates to MCPs › that MCP
9. Tap a "Used by" agent chip (in Skills/MCPs) → navigates to Agents › that agent
10. Resident agent shows "📌 Resident" badge in hero and blue pin dot in list row
11. Type in search field → list filters live; field clears when switching sections
12. "+ New" button is in the list header top-right (not at the bottom)
13. Model badge shows "opus"/"sonnet"/"haiku" with blue/green/purple tint in agent rows
14. Group rows show member names joined by " · " (max 3, then "+N more")
15. Skill rows show "{category} · N triggers"
16. MCP rows show "{transport} · {description}"
17. Templates section: `TemplatesSettingsTab` still renders correctly (no hero)
18. Both dark mode and light mode look correct — gradient is vivid in both
