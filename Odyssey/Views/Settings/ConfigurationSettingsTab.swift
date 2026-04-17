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

enum ConfigSelectedItem: Equatable {
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
    @State private var searchText: String = ""

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
            // Middle pane: item list
            itemListPane
                .frame(width: 200)
            Divider()
            // Right pane: detail
            detailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $showingNewAgent) {
            AgentEditorView(agent: nil) { newAgent in
                modelContext.insert(newAgent)
                do { try modelContext.save() } catch { print("ConfigurationSettingsTab: save failed: \(error)") }
                selectedItem = .agent(newAgent)
                showingNewAgent = false
            }
        }
        .sheet(isPresented: $showingNewGroup) {
            GroupEditorView(group: nil)
        }
        .sheet(isPresented: $showingNewSkill) {
            SkillEditorView(skill: nil) { newSkill in
                modelContext.insert(newSkill)
                do { try modelContext.save() } catch { print("ConfigurationSettingsTab: save failed: \(error)") }
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
            searchText = ""
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
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)

            Divider()

            configItemList

            Divider()

            if selectedSection != .templates && selectedSection != .permissions {
                Button {
                    handleNewItem()
                } label: {
                    Label("New \(selectedSection.title.dropLast(selectedSection.title.hasSuffix("s") ? 1 : 0))", systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .xrayId("settings.configuration.newItemButton")
            }
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
                    ConfigItemRow(
                        name: agent.name,
                        icon: agent.icon,
                        subtitle: "\(agent.provider) · \(agent.skillIds.count) skills"
                    )
                    .tag(ConfigSelectedItem.agent(agent))
                }
            )
        case .groups:
            ConfigItemList(
                items: filteredGroups,
                selectedItem: $selectedItem,
                itemRow: { group in
                    ConfigItemRow(
                        name: group.name,
                        icon: group.icon,
                        subtitle: "\(group.agentIds.count) members"
                    )
                    .tag(ConfigSelectedItem.group(group))
                }
            )
        case .skills:
            ConfigItemList(
                items: filteredSkills,
                selectedItem: $selectedItem,
                itemRow: { skill in
                    ConfigItemRow(
                        name: skill.name,
                        icon: "bolt",
                        subtitle: skill.category,
                        useSystemIcon: true
                    )
                    .tag(ConfigSelectedItem.skill(skill))
                }
            )
        case .mcps:
            ConfigItemList(
                items: filteredMCPs,
                selectedItem: $selectedItem,
                itemRow: { mcp in
                    ConfigItemRow(
                        name: mcp.name,
                        icon: "hammer",
                        subtitle: mcp.transportKind,
                        useSystemIcon: true
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
                    ConfigItemRow(
                        name: perm.name,
                        icon: "lock.shield",
                        subtitle: "\(perm.allowRules.count) allow · \(perm.denyRules.count) deny",
                        useSystemIcon: true
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

    private var filteredAgents: [Agent] {
        let all = agents.filter(\.isEnabled)
        guard !searchText.isEmpty else { return all }
        let needle = searchText.lowercased()
        return all.filter { $0.name.lowercased().contains(needle) }
    }

    private var filteredGroups: [AgentGroup] {
        let all = groups.filter(\.isEnabled)
        guard !searchText.isEmpty else { return all }
        let needle = searchText.lowercased()
        return all.filter { $0.name.lowercased().contains(needle) }
    }

    private var filteredSkills: [Skill] {
        let all = skills.filter(\.isEnabled)
        guard !searchText.isEmpty else { return all }
        let needle = searchText.lowercased()
        return all.filter { $0.name.lowercased().contains(needle) }
    }

    private var filteredMCPs: [MCPServer] {
        let all = mcps.filter(\.isEnabled)
        guard !searchText.isEmpty else { return all }
        let needle = searchText.lowercased()
        return all.filter { $0.name.lowercased().contains(needle) }
    }

    private var filteredPermissions: [PermissionSet] {
        guard !searchText.isEmpty else { return Array(permissions) }
        let needle = searchText.lowercased()
        return permissions.filter { $0.name.lowercased().contains(needle) }
    }

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

// MARK: - Row component

private struct ConfigItemRow: View {
    let name: String
    let icon: String
    let subtitle: String
    var useSystemIcon: Bool = false

    private var resolvedSystemIcon: String {
        if useSystemIcon { return icon }
        // Icon may be an emoji or SF Symbol name; fall back if it starts with an emoji
        if icon.unicodeScalars.first.map({ CharacterSet.letters.contains($0) }) == true {
            return icon
        }
        return "person.crop.circle"
    }

    var body: some View {
        HStack(spacing: 8) {
            if useSystemIcon || icon.unicodeScalars.first.map({ CharacterSet.letters.contains($0) }) == true {
                Image(systemName: resolvedSystemIcon)
                    .frame(width: 18)
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                Text(icon)
                    .frame(width: 18)
                    .font(.callout)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}
