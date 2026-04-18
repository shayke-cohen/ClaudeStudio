import SwiftUI
import SwiftData

// MARK: - Section enum

enum ConfigSection: String, CaseIterable, Identifiable {
    case agents, groups, skills, mcps, templates, permissions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .agents: "Agents"
        case .groups: "Groups"
        case .skills: "Skills"
        case .mcps: "MCPs"
        case .templates: "Templates"
        case .permissions: "Permissions"
        }
    }

    var icon: String {
        switch self {
        case .agents: "person.crop.circle"
        case .groups: "person.2"
        case .skills: "bolt"
        case .mcps: "hammer"
        case .templates: "text.document"
        case .permissions: "lock.shield"
        }
    }
}

// MARK: - Selected item wrapper

enum ConfigSelectedItem: Equatable, Hashable {
    case agent(Agent)
    case group(AgentGroup)
    case skill(Skill)
    case mcp(MCPServer)
    case permission(PermissionSet)

    static func == (lhs: ConfigSelectedItem, rhs: ConfigSelectedItem) -> Bool {
        switch (lhs, rhs) {
        case (.agent(let a), .agent(let b)): return a.id == b.id
        case (.group(let a), .group(let b)): return a.id == b.id
        case (.skill(let a), .skill(let b)): return a.id == b.id
        case (.mcp(let a), .mcp(let b)): return a.id == b.id
        case (.permission(let a), .permission(let b)): return a.id == b.id
        default: return false
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .agent(let a): hasher.combine(0); hasher.combine(a.id)
        case .group(let g): hasher.combine(1); hasher.combine(g.id)
        case .skill(let s): hasher.combine(2); hasher.combine(s.id)
        case .mcp(let m): hasher.combine(3); hasher.combine(m.id)
        case .permission(let p): hasher.combine(4); hasher.combine(p.id)
        }
    }
}

// MARK: - Main Tab View

struct ConfigurationSettingsTab: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\Agent.name)]) private var agents: [Agent]
    @Query(sort: [SortDescriptor(\AgentGroup.name)]) private var groups: [AgentGroup]
    @Query(sort: [SortDescriptor(\Skill.name)]) private var skills: [Skill]
    @Query(sort: [SortDescriptor(\MCPServer.name)]) private var mcps: [MCPServer]
    @Query(sort: [SortDescriptor(\PermissionSet.name)]) private var permissions: [PermissionSet]

    @State private var selectedSection: ConfigSection = .agents
    @State private var selectedItem: ConfigSelectedItem?

    private let initialSlug: String?

    init(initialSection: ConfigSection? = nil, initialSlug: String? = nil) {
        _selectedSection = State(initialValue: initialSection ?? .agents)
        self.initialSlug = initialSlug
    }

    // Creation sheet state
    @State private var showingNewAgent = false
    @State private var showingNewGroup = false
    @State private var showingNewSkill = false
    @State private var showingNewMCP = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left pane: section list
            sectionPane
                .frame(width: 130)
            Divider()
            if selectedSection == .templates {
                // Templates has its own full-featured view
                TemplatesSettingsTab()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Middle pane: item list
                itemListPane
                    .frame(width: 200)
                Divider()
                // Right pane: detail
                detailPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showingNewAgent) {
            AgentCreationSheet { newAgent in
                selectedItem = .agent(newAgent)
                showingNewAgent = false
            }
        }
        .sheet(isPresented: $showingNewGroup) {
            GroupEditorView(group: nil)
        }
        .sheet(isPresented: $showingNewSkill) {
            SkillCreationSheet { newSkill in
                selectedItem = .skill(newSkill)
                showingNewSkill = false
            }
        }
        .sheet(isPresented: $showingNewMCP) {
            MCPEditorView(mcp: nil) { newMCP in
                modelContext.insert(newMCP)
                do { try modelContext.save() } catch { print("ConfigurationSettingsTab: save failed: \(error)") }
                selectedItem = .mcp(newMCP)
                showingNewMCP = false
            }
        }
        .onChange(of: selectedSection) { _, _ in
            selectedItem = nil
        }
        .onAppear {
            guard let slug = initialSlug else { return }
            switch selectedSection {
            case .agents:
                if let match = agents.first(where: { $0.configSlug == slug }) { selectedItem = .agent(match) }
            case .groups:
                if let match = groups.first(where: { $0.configSlug == slug }) { selectedItem = .group(match) }
            case .skills:
                if let match = skills.first(where: { $0.configSlug == slug }) { selectedItem = .skill(match) }
            case .mcps:
                if let match = mcps.first(where: { $0.configSlug == slug }) { selectedItem = .mcp(match) }
            case .permissions:
                if let match = permissions.first(where: { $0.configSlug == slug }) { selectedItem = .permission(match) }
            case .templates:
                break
            }
        }
        .xrayId("settings.configuration.root")
    }

    // MARK: - Left pane

    private var sectionPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(ConfigSection.allCases, selection: $selectedSection) { section in
                Label(section.title, systemImage: section.icon)
                    .tag(section)
            }
            .listStyle(.sidebar)

            Divider()

            Button {
                NSWorkspace.shared.open(ConfigFileManager.configDirectory)
            } label: {
                Label("Config Folder", systemImage: "folder")
                    .font(.caption)
                    .lineLimit(1)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .xrayId("settings.configuration.openConfigFolder")
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Middle pane

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
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.configuration.listNewButton")
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 11)
            .padding(.bottom, 7)

            Divider()

            configItemList
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var configItemList: some View {
        switch selectedSection {
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
                    return ConfigListRow(
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
                    return ConfigListRow(
                        name: group.name,
                        icon: group.icon,
                        color: Color.fromAgentColor(group.color),
                        subtitle: subtitle
                    )
                    .tag(ConfigSelectedItem.group(group))
                }
            )
        case .skills:
            ConfigItemList(
                items: filteredSkills,
                selectedItem: $selectedItem,
                itemRow: { skill in
                    let count = skill.triggers.count
                    let subtitle = "\(skill.category.isEmpty ? "Uncategorized" : skill.category) · \(count) trigger\(count == 1 ? "" : "s")"
                    return ConfigListRow(
                        name: skill.name,
                        icon: "bolt.fill",
                        color: .green,
                        subtitle: subtitle
                    )
                    .tag(ConfigSelectedItem.skill(skill))
                }
            )
        case .mcps:
            ConfigItemList(
                items: filteredMCPs,
                selectedItem: $selectedItem,
                itemRow: { mcp in
                    let desc = mcp.serverDescription.isEmpty ? nil : String(mcp.serverDescription.prefix(30))
                    let subtitle = desc.map { "\(mcp.transportKind) · \($0)" } ?? mcp.transportKind
                    return ConfigListRow(
                        name: mcp.name,
                        icon: "hammer.fill",
                        color: .orange,
                        subtitle: subtitle
                    )
                    .tag(ConfigSelectedItem.mcp(mcp))
                }
            )
        case .templates:
            templatesRedirect
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
        }
    }

    private var templatesRedirect: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.document")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("Templates are managed in the Templates settings section.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Right pane

    @ViewBuilder
    private var detailPane: some View {
        if let item = selectedItem {
            ConfigurationDetailView(item: item)
        } else {
            emptyDetail
        }
    }

    private var emptyDetail: some View {
        VStack(spacing: 12) {
            Image(systemName: selectedSection.icon)
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Select a \(selectedSection.title.lowercased().hasSuffix("s") ? String(selectedSection.title.lowercased().dropLast()) : selectedSection.title.lowercased()) to view details.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .xrayId("settings.configuration.emptyDetail")
    }

    // MARK: - Filtered items

    private var filteredAgents: [Agent] { agents.filter(\.isEnabled) }
    private var filteredGroups: [AgentGroup] { groups.filter(\.isEnabled) }
    private var filteredSkills: [Skill] { skills.filter(\.isEnabled) }
    private var filteredMCPs: [MCPServer] { mcps.filter(\.isEnabled) }
    private var filteredPermissions: [PermissionSet] { Array(permissions) }

    // MARK: - Actions

    private func handleNewItem() {
        switch selectedSection {
        case .agents: showingNewAgent = true
        case .groups: showingNewGroup = true
        case .skills: showingNewSkill = true
        case .mcps: showingNewMCP = true
        case .templates, .permissions: break
        }
    }
}

// MARK: - Generic list helper

private struct ConfigItemList<Item: Identifiable, Row: View>: View {
    let items: [Item]
    @Binding var selectedItem: ConfigSelectedItem?
    let itemRow: (Item) -> Row

    var body: some View {
        List(items, selection: $selectedItem) { item in
            itemRow(item)
        }
        .listStyle(.sidebar)
    }
}

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
