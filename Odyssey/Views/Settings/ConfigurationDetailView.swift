import SwiftUI
import SwiftData

// MARK: - Detail view

struct ConfigurationDetailView: View {
    let item: ConfigSelectedItem

    @Query(sort: [SortDescriptor(\Agent.name)]) private var agents: [Agent]
    @Query(sort: [SortDescriptor(\Skill.name)]) private var skills: [Skill]
    @Query(sort: [SortDescriptor(\MCPServer.name)]) private var mcps: [MCPServer]

    @Environment(\.modelContext) private var modelContext
    @Environment(WindowState.self) private var windowState: WindowState

    // Editor sheet state
    @State private var showingAgentEditor = false
    @State private var showingGroupEditor = false
    @State private var showingSkillEditor = false
    @State private var showingMCPEditor = false

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
                    .accessibilityIdentifier("settings.configuration.heroResidentBadge")
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
        .accessibilityIdentifier("settings.configuration.heroHeader")
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
        .accessibilityIdentifier("settings.configuration.heroRevealButton")
    }

    private var heroEditButton: some View {
        Button { openEditor() } label: {
            Label("Edit", systemImage: "pencil")
                .font(.system(size: 11, weight: .semibold))
        }
        .buttonStyle(HeroButtonStyle())
        .help("Edit this item")
        .accessibilityIdentifier("settings.configuration.heroEditButton")
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
                            chip(label: trigger, color: .blue)
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
                    chip(label: mcp.transportKind.uppercased(), color: .secondary)
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

    // MARK: - Item name

    private var itemName: String {
        switch item {
        case .agent(let a): return a.name
        case .group(let g): return g.name
        case .skill(let s): return s.name
        case .mcp(let m): return m.name
        case .permission(let p): return p.name
        }
    }

    // MARK: - Edit / Reveal

    private var canEdit: Bool {
        if case .permission = item { return false }
        return true
    }

    private func revealInFinder() {
        let url: URL
        switch item {
        case .agent(let a):
            let slug = a.configSlug ?? ConfigFileManager.slugify(a.name)
            url = ConfigFileManager.configDirectory
                .appendingPathComponent("agents")
                .appendingPathComponent(slug)
        case .group(let g):
            let slug = g.configSlug ?? ConfigFileManager.slugify(g.name)
            url = ConfigFileManager.configDirectory
                .appendingPathComponent("groups")
                .appendingPathComponent(slug)
        case .skill(let s):
            let slug = s.configSlug ?? ConfigFileManager.slugify(s.name)
            url = ConfigFileManager.configDirectory
                .appendingPathComponent("skills")
                .appendingPathComponent(slug)
                .appendingPathExtension("md")
        case .mcp(let m):
            let slug = m.configSlug ?? ConfigFileManager.slugify(m.name)
            url = ConfigFileManager.configDirectory
                .appendingPathComponent("mcps")
                .appendingPathComponent(slug)
                .appendingPathExtension("json")
        case .permission(let p):
            let slug = p.configSlug ?? ConfigFileManager.slugify(p.name)
            url = ConfigFileManager.configDirectory
                .appendingPathComponent("permissions")
                .appendingPathComponent(slug)
                .appendingPathExtension("json")
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func openEditor() {
        switch item {
        case .agent: showingAgentEditor = true
        case .group: showingGroupEditor = true
        case .skill: showingSkillEditor = true
        case .mcp: showingMCPEditor = true
        case .permission: break // No editor defined yet
        }
    }

    // MARK: - Prompt helpers

    private func promptBlock(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(truncated(text, maxChars: 400))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(12)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func truncated(_ text: String, maxChars: Int) -> String {
        guard text.count > maxChars else { return text }
        return String(text.prefix(maxChars)) + "…"
    }

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
}

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
