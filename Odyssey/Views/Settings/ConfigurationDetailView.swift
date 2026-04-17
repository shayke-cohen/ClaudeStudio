import SwiftUI
import SwiftData

// MARK: - Detail view

struct ConfigurationDetailView: View {
    let item: ConfigSelectedItem

    @Query(sort: [SortDescriptor(\Agent.name)]) private var agents: [Agent]
    @Query(sort: [SortDescriptor(\Skill.name)]) private var skills: [Skill]
    @Query(sort: [SortDescriptor(\MCPServer.name)]) private var mcps: [MCPServer]

    @Environment(\.modelContext) private var modelContext

    // Editor sheet state
    @State private var showingAgentEditor = false
    @State private var showingGroupEditor = false
    @State private var showingSkillEditor = false
    @State private var showingMCPEditor = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                Divider()
                chipsSection
                promptPreview
                Spacer(minLength: 0)
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                revealButton
                editButton
            }
        }
        .sheet(isPresented: $showingAgentEditor) {
            if case .agent(let agent) = item {
                AgentEditorView(agent: agent) { updated in
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
                SkillEditorView(skill: skill) { updated in
                    do { try modelContext.save() } catch { print("ConfigurationDetailView: save failed: \(error)") }
                    showingSkillEditor = false
                }
            }
        }
        .sheet(isPresented: $showingMCPEditor) {
            if case .mcp(let mcp) = item {
                MCPEditorView(mcp: mcp) { updated in
                    do { try modelContext.save() } catch { print("ConfigurationDetailView: save failed: \(error)") }
                    showingMCPEditor = false
                }
            }
        }
        .xrayId("settings.configuration.detail")
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 14) {
            itemIconView
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(itemName)
                    .font(.title2.weight(.semibold))
                    .lineLimit(2)
                Text(itemTypeLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var itemIconView: some View {
        switch item {
        case .agent(let agent):
            iconCircle(raw: agent.icon, color: agent.color)
        case .group(let group):
            iconCircle(raw: group.icon, color: group.color)
        case .skill:
            Image(systemName: "bolt.fill")
                .font(.title2)
                .frame(width: 44, height: 44)
                .background(Color.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(.yellow)
        case .mcp:
            Image(systemName: "hammer.fill")
                .font(.title2)
                .frame(width: 44, height: 44)
                .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(.orange)
        case .permission:
            Image(systemName: "lock.shield.fill")
                .font(.title2)
                .frame(width: 44, height: 44)
                .background(Color.blue.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(.blue)
        }
    }

    private func iconCircle(raw: String, color: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(namedColor(color).opacity(0.15))
                .frame(width: 44, height: 44)
            if raw.unicodeScalars.first.map({ CharacterSet.letters.contains($0) }) == true {
                Image(systemName: raw)
                    .font(.title3)
                    .foregroundStyle(namedColor(color))
            } else {
                Text(raw)
                    .font(.title3)
            }
        }
    }

    private var itemName: String {
        switch item {
        case .agent(let a): return a.name
        case .group(let g): return g.name
        case .skill(let s): return s.name
        case .mcp(let m): return m.name
        case .permission(let p): return p.name
        }
    }

    private var itemTypeLabel: String {
        switch item {
        case .agent(let a): return "Agent · \(a.provider)"
        case .group(let g): return "Group · \(g.agentIds.count) members"
        case .skill(let s): return "Skill · \(s.category)"
        case .mcp(let m): return "MCP Server · \(m.transportKind)"
        case .permission(let p): return "Permission Set · \(p.permissionMode)"
        }
    }

    // MARK: - Chips section

    @ViewBuilder
    private var chipsSection: some View {
        switch item {
        case .agent(let agent):
            agentChips(agent: agent)
        case .group(let group):
            groupChips(group: group)
        case .skill(let skill):
            skillChips(skill: skill)
        case .mcp(let mcp):
            mcpChips(mcp: mcp)
        case .permission(let perm):
            permissionChips(perm: perm)
        }
    }

    @ViewBuilder
    private func agentChips(agent: Agent) -> some View {
        let agentSkills = skills.filter { agent.skillIds.contains($0.id) }
        let agentMCPs = mcps.filter { agent.extraMCPServerIds.contains($0.id) }

        VStack(alignment: .leading, spacing: 10) {
            if !agentSkills.isEmpty {
                chipGroup(label: "Skills") {
                    ForEach(agentSkills) { skill in
                        chip(label: "⚡ \(skill.name)", color: .yellow)
                    }
                }
            }
            if !agentMCPs.isEmpty {
                chipGroup(label: "MCPs") {
                    ForEach(agentMCPs) { mcp in
                        chip(label: "🔧 \(mcp.name)", color: .orange)
                    }
                }
            }
            if agentSkills.isEmpty && agentMCPs.isEmpty {
                Text("No skills or MCPs attached.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func groupChips(group: AgentGroup) -> some View {
        let memberAgents = agents.filter { group.agentIds.contains($0.id) }
        let roles = group.agentRoles

        VStack(alignment: .leading, spacing: 10) {
            if !memberAgents.isEmpty {
                chipGroup(label: "Members") {
                    ForEach(memberAgents) { agent in
                        let role = roles[agent.id] ?? ""
                        let label = role.isEmpty ? agent.name : "\(agent.name) (\(role))"
                        chip(label: label, color: .blue)
                    }
                }
            } else {
                Text("No agents in this group.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func skillChips(skill: Skill) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            chip(label: skill.category, color: .purple)
            if !skill.triggers.isEmpty {
                chipGroup(label: "Triggers") {
                    ForEach(skill.triggers, id: \.self) { trigger in
                        chip(label: trigger, color: .teal)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func mcpChips(mcp: MCPServer) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            chip(label: mcp.transportKind.uppercased(), color: .orange)
            switch mcp.transport {
            case .stdio(let command, _, _):
                if !command.isEmpty {
                    Text(command)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            case .http(let url, _):
                if !url.isEmpty {
                    Text(url)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }

    @ViewBuilder
    private func permissionChips(perm: PermissionSet) -> some View {
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

    // MARK: - System prompt preview

    @ViewBuilder
    private var promptPreview: some View {
        switch item {
        case .agent(let agent) where !agent.systemPrompt.isEmpty:
            promptBlock(title: "System Prompt", text: agent.systemPrompt)
        case .group(let group) where !group.groupInstruction.isEmpty:
            promptBlock(title: "Group Instruction", text: group.groupInstruction)
        case .skill(let skill) where !skill.content.isEmpty:
            promptBlock(title: "Content", text: skill.content)
        default:
            EmptyView()
        }
    }

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

    // MARK: - Toolbar actions

    private var revealButton: some View {
        Button {
            revealInFinder()
        } label: {
            Label("Reveal in Finder", systemImage: "folder")
        }
        .help("Reveal config file in Finder")
        .xrayId("settings.configuration.detail.revealButton")
    }

    private var canEdit: Bool {
        if case .permission = item { return false }
        return true
    }

    private var editButton: some View {
        Button {
            openEditor()
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        .buttonStyle(.borderedProminent)
        .disabled(!canEdit)
        .help(canEdit ? "Edit this item" : "No editor available for this item type")
        .xrayId("settings.configuration.detail.editButton")
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

    private func namedColor(_ name: String) -> Color {
        switch name {
        case "red": return .red
        case "green": return .green
        case "blue": return .blue
        case "purple": return .purple
        case "orange": return .orange
        case "yellow": return .yellow
        case "pink": return .pink
        case "teal": return .teal
        case "indigo": return .indigo
        default: return .accentColor
        }
    }
}

