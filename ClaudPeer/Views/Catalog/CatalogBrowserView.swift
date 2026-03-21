import SwiftData
import SwiftUI

struct CatalogBrowserView: View {
    enum CatalogTab: String, CaseIterable {
        case agents
        case skills
        case mcps

        var title: String {
            switch self {
            case .agents: return "Agents"
            case .skills: return "Skills"
            case .mcps: return "MCPs"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var selectedTab: CatalogTab = .agents
    @State private var searchText = ""
    @State private var selectedCategory = "All"
    @State private var listRevision = 0
    @State private var pendingAgentInstall: CatalogAgent?
    @State private var showAgentInstallConfirmation = false
    @State private var agentInstallAlertTitle = ""
    @State private var agentInstallAlertMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Catalog")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
            .padding()

            Picker("", selection: $selectedTab) {
                ForEach(CatalogTab.allCases, id: \.self) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            categoryChipsRow
                .padding(.vertical, 10)

            Divider()

            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220, maximum: 300), spacing: 16)],
                    spacing: 16
                ) {
                    switch selectedTab {
                    case .agents:
                        ForEach(filteredAgents) { agent in
                            agentCard(agent)
                        }
                    case .skills:
                        ForEach(filteredSkills) { skill in
                            skillCard(skill)
                        }
                    case .mcps:
                        ForEach(filteredMCPs) { mcp in
                            mcpCard(mcp)
                        }
                    }
                }
                .padding()
            }
        }
        // Present as .sheet with e.g. .frame(minWidth: 700, minHeight: 550) on the sheet content if needed.
        .alert(agentInstallAlertTitle, isPresented: $showAgentInstallConfirmation) {
            Button("Cancel", role: .cancel) {
                pendingAgentInstall = nil
            }
            Button("Install") {
                if let agent = pendingAgentInstall {
                    CatalogService.shared.installAgent(agent.catalogId, into: modelContext)
                    try? modelContext.save()
                    listRevision += 1
                }
                pendingAgentInstall = nil
            }
        } message: {
            Text(agentInstallAlertMessage)
        }
        .onChange(of: selectedTab) { _, _ in
            selectedCategory = "All"
        }
    }

    private var categoryChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryChip(title: "All", isSelected: selectedCategory == "All") {
                    selectedCategory = "All"
                }
                ForEach(currentCategories, id: \.self) { cat in
                    categoryChip(title: cat, isSelected: selectedCategory == cat) {
                        selectedCategory = cat
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private var currentCategories: [String] {
        switch selectedTab {
        case .agents: return CatalogService.shared.agentCategories()
        case .skills: return CatalogService.shared.skillCategories()
        case .mcps: return CatalogService.shared.mcpCategories()
        }
    }

    private func categoryChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var filteredAgents: [CatalogAgent] {
        _ = listRevision
        let base = CatalogService.shared.allAgents()
        return base.filter { matchesCategory($0.category) && matchesSearch($0.name, $0.description, $0.tags) }
    }

    private var filteredSkills: [CatalogSkill] {
        _ = listRevision
        let base = CatalogService.shared.allSkills()
        return base.filter { matchesCategory($0.category) && matchesSearch($0.name, $0.description, $0.tags) }
    }

    private var filteredMCPs: [CatalogMCP] {
        _ = listRevision
        let base = CatalogService.shared.allMCPs()
        return base.filter { matchesCategory($0.category) && matchesSearch($0.name, $0.description, $0.tags) }
    }

    private func matchesCategory(_ itemCategory: String) -> Bool {
        selectedCategory == "All" || itemCategory == selectedCategory
    }

    private func matchesSearch(_ name: String, _ description: String, _ tags: [String]) -> Bool {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return true }
        if name.lowercased().contains(q) { return true }
        if description.lowercased().contains(q) { return true }
        return tags.contains { $0.lowercased().contains(q) }
    }

    private func cardChrome<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(12)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
    }

    private func agentCard(_ agent: CatalogAgent) -> some View {
        let installed = CatalogService.shared.isAgentInstalled(agent.catalogId, context: modelContext)
        return cardChrome {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: agent.icon)
                        .font(.title2)
                        .foregroundStyle(Color.fromAgentColor(agent.color))
                    VStack(alignment: .leading) {
                        Text(agent.name)
                            .font(.headline)
                        Text(agent.model)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Text(agent.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                Divider()
                HStack {
                    Text("\(agent.requiredSkills.count) skills")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    installCapsule(
                        installed: installed,
                        install: { beginAgentInstall(agent) }
                    )
                }
            }
        }
        .contextMenu {
            if installed {
                Button("Uninstall", role: .destructive) {
                    CatalogService.shared.uninstallAgent(catalogId: agent.catalogId, context: modelContext)
                    try? modelContext.save()
                    listRevision += 1
                }
            } else {
                Button("Install") {
                    beginAgentInstall(agent)
                }
            }
        }
    }

    private func skillCard(_ skill: CatalogSkill) -> some View {
        let installed = CatalogService.shared.isSkillInstalled(skill.catalogId, context: modelContext)
        return cardChrome {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: skill.icon)
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading) {
                        Text(skill.name)
                            .font(.headline)
                        Text(skillMCPNeedsLine(skill))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Text(skill.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                Divider()
                HStack {
                    Text(skill.category)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    installCapsule(
                        installed: installed,
                        install: {
                            CatalogService.shared.installSkill(skill.catalogId, into: modelContext)
                            try? modelContext.save()
                            listRevision += 1
                        }
                    )
                }
            }
        }
        .contextMenu {
            if installed {
                Button("Uninstall", role: .destructive) {
                    CatalogService.shared.uninstallSkill(catalogId: skill.catalogId, context: modelContext)
                    try? modelContext.save()
                    listRevision += 1
                }
            } else {
                Button("Install") {
                    CatalogService.shared.installSkill(skill.catalogId, into: modelContext)
                    try? modelContext.save()
                    listRevision += 1
                }
            }
        }
    }

    private func skillMCPNeedsLine(_ skill: CatalogSkill) -> String {
        if skill.requiredMCPs.isEmpty {
            return "No MCPs needed"
        }
        let names = skill.requiredMCPs.map { CatalogService.shared.findMCP($0)?.name ?? $0 }
        return "Needs: " + names.joined(separator: ", ")
    }

    private func mcpCard(_ mcp: CatalogMCP) -> some View {
        let installed = CatalogService.shared.isMCPInstalled(mcp.catalogId, context: modelContext)
        return cardChrome {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: mcp.icon)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading) {
                        Text(mcp.name)
                            .font(.headline)
                        Text(mcp.transport.kind)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Text(mcp.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                Divider()
                HStack {
                    Text("Popularity \(mcp.popularity)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    installCapsule(
                        installed: installed,
                        install: {
                            CatalogService.shared.installMCP(mcp.catalogId, into: modelContext)
                            try? modelContext.save()
                            listRevision += 1
                        }
                    )
                }
            }
        }
        .contextMenu {
            if installed {
                Button("Uninstall", role: .destructive) {
                    CatalogService.shared.uninstallMCP(catalogId: mcp.catalogId, context: modelContext)
                    try? modelContext.save()
                    listRevision += 1
                }
            } else {
                Button("Install") {
                    CatalogService.shared.installMCP(mcp.catalogId, into: modelContext)
                    try? modelContext.save()
                    listRevision += 1
                }
            }
        }
    }

    @ViewBuilder
    private func installCapsule(installed: Bool, install: @escaping () -> Void) -> some View {
        if installed {
            Text("Installed")
                .font(.caption2)
                .fontWeight(.medium)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .foregroundStyle(.green)
                .background(Color.green.opacity(0.15))
                .clipShape(Capsule())
        } else {
            Button("Install", action: install)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
    }

    private func beginAgentInstall(_ agent: CatalogAgent) {
        let deps = CatalogService.shared.resolveDependencies(forAgent: agent, context: modelContext)
        agentInstallAlertTitle = "Install \(agent.name)?"
        var lines: [String] = []
        if !deps.skills.isEmpty || !deps.mcps.isEmpty {
            lines.append("This will also install:")
            if !deps.skills.isEmpty {
                lines.append("• \(deps.skills.count) skills")
            }
            if !deps.mcps.isEmpty {
                lines.append("• \(deps.mcps.count) MCPs")
            }
        } else if deps.missingSkillIds.isEmpty, deps.missingMCPIds.isEmpty {
            lines.append("No additional catalog skills or MCPs will be installed.")
        }
        if !deps.missingSkillIds.isEmpty || !deps.missingMCPIds.isEmpty {
            if !lines.isEmpty { lines.append("") }
            lines.append("Some catalog references are missing and will be skipped.")
        }
        if lines.isEmpty {
            lines.append("No additional catalog skills or MCPs will be installed.")
        }
        agentInstallAlertMessage = lines.joined(separator: "\n")
        pendingAgentInstall = agent
        showAgentInstallConfirmation = true
    }
}

#Preview {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: Agent.self,
        Skill.self,
        MCPServer.self,
        configurations: configuration
    )
    return CatalogBrowserView()
        .modelContainer(container)
}
