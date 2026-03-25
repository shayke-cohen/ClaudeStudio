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
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState

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
            .xrayId("workshop.tabPicker")

            TextField("Search \(selectedTab.rawValue.lowercased())...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .xrayId("workshop.searchField")

            Divider()

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
                                badges: [agent.model, "\(agent.skillIds.count) skills"],
                                entityId: agent.id.uuidString,
                                onToggleEnabled: {
                                    agent.isEnabled.toggle()
                                    try? modelContext.save()
                                    appState.configSyncService?.writeBack(agent: agent)
                                }
                            ) {
                                selectedEntityContext = agentContextString(agent)
                            }
                            .xrayId("workshop.agentRow.\(agent.id.uuidString)")
                            .contextMenu {
                                if let slug = agent.configSlug {
                                    Button("Restore Factory Default") {
                                        appState.configSyncService?.restoreFactoryDefault(entityType: "agents", slug: slug)
                                    }
                                    .xrayId("workshop.agentRow.restore.\(agent.id.uuidString)")
                                }
                            }
                        }
                    case .groups:
                        ForEach(filteredGroups) { group in
                            WorkshopEntityRow(
                                icon: group.icon,
                                color: group.color,
                                name: group.name,
                                subtitle: group.groupDescription,
                                isEnabled: group.isEnabled,
                                badges: ["\(group.agentIds.count) agents"],
                                entityId: group.id.uuidString,
                                onToggleEnabled: {
                                    group.isEnabled.toggle()
                                    try? modelContext.save()
                                    appState.configSyncService?.writeBack(group: group)
                                }
                            ) {
                                selectedEntityContext = groupContextString(group)
                            }
                            .xrayId("workshop.groupRow.\(group.id.uuidString)")
                            .contextMenu {
                                if let slug = group.configSlug {
                                    Button("Restore Factory Default") {
                                        appState.configSyncService?.restoreFactoryDefault(entityType: "groups", slug: slug)
                                    }
                                    .xrayId("workshop.groupRow.restore.\(group.id.uuidString)")
                                }
                            }
                        }
                    case .skills:
                        ForEach(filteredSkills) { skill in
                            WorkshopEntityRow(
                                icon: "book.fill",
                                color: "blue",
                                name: skill.name,
                                subtitle: skill.skillDescription,
                                isEnabled: skill.isEnabled,
                                badges: [skill.category, "v\(skill.version)"],
                                entityId: skill.id.uuidString,
                                onToggleEnabled: {
                                    skill.isEnabled.toggle()
                                    try? modelContext.save()
                                    appState.configSyncService?.writeBack(skill: skill)
                                }
                            ) {
                                selectedEntityContext = skillContextString(skill)
                            }
                            .xrayId("workshop.skillRow.\(skill.id.uuidString)")
                            .contextMenu {
                                if let slug = skill.configSlug {
                                    Button("Restore Factory Default") {
                                        appState.configSyncService?.restoreFactoryDefault(entityType: "skills", slug: slug)
                                    }
                                    .xrayId("workshop.skillRow.restore.\(skill.id.uuidString)")
                                }
                            }
                        }
                    case .mcps:
                        ForEach(filteredMCPs) { mcp in
                            WorkshopEntityRow(
                                icon: "server.rack",
                                color: "purple",
                                name: mcp.name,
                                subtitle: mcp.serverDescription,
                                isEnabled: mcp.isEnabled,
                                badges: [mcp.transportKind],
                                entityId: mcp.id.uuidString,
                                onToggleEnabled: {
                                    mcp.isEnabled.toggle()
                                    try? modelContext.save()
                                    appState.configSyncService?.writeBack(mcp: mcp)
                                }
                            ) {
                                selectedEntityContext = mcpContextString(mcp)
                            }
                            .xrayId("workshop.mcpRow.\(mcp.id.uuidString)")
                            .contextMenu {
                                if let slug = mcp.configSlug {
                                    Button("Restore Factory Default") {
                                        appState.configSyncService?.restoreFactoryDefault(entityType: "mcps", slug: slug)
                                    }
                                    .xrayId("workshop.mcpRow.restore.\(mcp.id.uuidString)")
                                }
                            }
                        }
                    case .permissions:
                        ForEach(filteredPermissions) { perm in
                            WorkshopEntityRow(
                                icon: "lock.shield.fill",
                                color: "orange",
                                name: perm.name,
                                subtitle: "\(perm.allowRules.count) allow, \(perm.denyRules.count) deny",
                                isEnabled: perm.isEnabled,
                                badges: [perm.permissionMode],
                                entityId: perm.id.uuidString,
                                onToggleEnabled: {
                                    perm.isEnabled.toggle()
                                    try? modelContext.save()
                                    appState.configSyncService?.writeBack(permission: perm)
                                }
                            ) {
                                selectedEntityContext = permContextString(perm)
                            }
                            .xrayId("workshop.permRow.\(perm.id.uuidString)")
                            .contextMenu {
                                if let slug = perm.configSlug {
                                    Button("Restore Factory Default") {
                                        appState.configSyncService?.restoreFactoryDefault(entityType: "permissions", slug: slug)
                                    }
                                    .xrayId("workshop.permRow.restore.\(perm.id.uuidString)")
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .xrayId("workshop.entityList")
        }
    }

    // MARK: - Tab counts

    private func countForTab(_ tab: WorkshopTab) -> Int {
        switch tab {
        case .agents: return agents.count
        case .groups: return groups.count
        case .skills: return skills.count
        case .mcps: return mcps.count
        case .permissions: return permissions.count
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

    // MARK: - Context strings

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
