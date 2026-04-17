import SwiftUI
import SwiftData

/// Settings tab for managing prompt templates on agents and groups.
/// Templates live on disk at `~/.odyssey/config/prompt-templates/` — the UI is
/// a convenience layer on top of the file store, with `ConfigSyncService`
/// handling sync in both directions.
struct TemplatesSettingsTab: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState

    @Query(sort: [SortDescriptor(\Agent.name)]) private var agents: [Agent]
    @Query(sort: [SortDescriptor(\AgentGroup.sortOrder), SortDescriptor(\AgentGroup.name)]) private var groups: [AgentGroup]
    @Query private var allTemplates: [PromptTemplate]

    @State private var selectedOwner: OwnerKey?
    @State private var searchText: String = ""
    @State private var editingTemplate: PromptTemplate?
    @State private var showingNewSheet: Bool = false

    enum OwnerKey: Hashable, Identifiable {
        case agent(UUID)
        case group(UUID)

        var id: String {
            switch self {
            case .agent(let id): "agent-\(id)"
            case .group(let id): "group-\(id)"
            }
        }
    }

    private var enabledAgents: [Agent] {
        agents.filter(\.isEnabled).sorted { $0.name < $1.name }
    }

    private var enabledGroups: [AgentGroup] {
        groups.filter(\.isEnabled).sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            return lhs.name < rhs.name
        }
    }

    private var filteredAgents: [Agent] {
        guard !searchText.isEmpty else { return enabledAgents }
        let needle = searchText.lowercased()
        return enabledAgents.filter { $0.name.lowercased().contains(needle) }
    }

    private var filteredGroups: [AgentGroup] {
        guard !searchText.isEmpty else { return enabledGroups }
        let needle = searchText.lowercased()
        return enabledGroups.filter { $0.name.lowercased().contains(needle) }
    }

    private func templateCount(forAgent agent: Agent) -> Int {
        allTemplates.filter { $0.agent?.id == agent.id }.count
    }

    private func templateCount(forGroup group: AgentGroup) -> Int {
        allTemplates.filter { $0.group?.id == group.id }.count
    }

    private var selectedAgent: Agent? {
        guard case .agent(let id) = selectedOwner else { return nil }
        return enabledAgents.first { $0.id == id }
    }

    private var selectedGroup: AgentGroup? {
        guard case .group(let id) = selectedOwner else { return nil }
        return enabledGroups.first { $0.id == id }
    }

    private var templatesForSelection: [PromptTemplate] {
        let templates: [PromptTemplate]
        switch selectedOwner {
        case .agent(let id): templates = allTemplates.filter { $0.agent?.id == id }
        case .group(let id): templates = allTemplates.filter { $0.group?.id == id }
        case .none: templates = []
        }
        return templates.sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            return lhs.name < rhs.name
        }
    }

    private var selectionTitle: String {
        if let agent = selectedAgent { return agent.name }
        if let group = selectedGroup { return group.name }
        return "Templates"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ownerList
                .frame(width: 260)
            Divider()
            detailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            if selectedOwner == nil {
                selectedOwner = enabledAgents.first.map { .agent($0.id) }
                    ?? enabledGroups.first.map { .group($0.id) }
            }
        }
        .sheet(item: $editingTemplate) { template in
            PromptTemplateEditorSheet(
                mode: .edit(template),
                onSave: { updatedName, updatedPrompt in
                    updateTemplate(template, name: updatedName, prompt: updatedPrompt)
                    editingTemplate = nil
                },
                onCancel: { editingTemplate = nil }
            )
        }
        .sheet(isPresented: $showingNewSheet) {
            PromptTemplateCreationSheet(
                ownerAgent: selectedAgent,
                ownerGroup: selectedGroup,
                existingTemplate: nil
            ) { newTemplate in
                showingNewSheet = false
            }
        }
        .xrayId("settings.templates.root")
    }

    private var ownerList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .xrayId("settings.templates.searchField")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)

            Divider()

            List(selection: $selectedOwner) {
                if !filteredAgents.isEmpty {
                    Section("Agents") {
                        ForEach(filteredAgents) { agent in
                            ownerRow(
                                name: agent.name,
                                icon: agent.icon,
                                count: templateCount(forAgent: agent)
                            )
                            .tag(OwnerKey.agent(agent.id))
                            .xrayId("settings.templates.ownerRow.agent.\(agent.id.uuidString)")
                        }
                    }
                }
                if !filteredGroups.isEmpty {
                    Section("Groups") {
                        ForEach(filteredGroups) { group in
                            ownerRow(
                                name: group.name,
                                icon: "person.3",
                                count: templateCount(forGroup: group)
                            )
                            .tag(OwnerKey.group(group.id))
                            .xrayId("settings.templates.ownerRow.group.\(group.id.uuidString)")
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .xrayId("settings.templates.ownerList")
        }
    }

    @ViewBuilder
    private func ownerRow(name: String, icon: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: iconSystemName(icon))
                .frame(width: 18)
                .foregroundStyle(.secondary)
            Text(name)
                .lineLimit(1)
            Spacer()
            if count > 0 {
                Text("\(count)")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Agents use SF Symbol names already; groups pass in a fixed symbol. Strip any
    /// stray emoji characters that wouldn't resolve as SF Symbols.
    private func iconSystemName(_ raw: String) -> String {
        if raw.unicodeScalars.first.map({ CharacterSet.letters.contains($0) }) == true {
            return raw
        }
        return "person.crop.circle"
    }

    private var detailPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            detailHeader
            Divider()
            templatesList
            Divider()
            footer
        }
        .xrayId("settings.templates.detailPane")
    }

    private var detailHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(selectionTitle)
                .font(.title3.weight(.semibold))
            Text("Starter prompts available when you begin a chat with this \(selectedGroup != nil ? "group" : "agent").")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var templatesList: some View {
        if selectedOwner == nil {
            emptySelection
        } else if templatesForSelection.isEmpty {
            emptyTemplates
        } else {
            List {
                ForEach(templatesForSelection) { template in
                    templateRow(template)
                        .xrayId("settings.templates.templateRow.\(template.id.uuidString)")
                }
                .onMove(perform: moveTemplates)
            }
            .listStyle(.inset)
            .xrayId("settings.templates.list")
        }
    }

    @ViewBuilder
    private func templateRow(_ template: PromptTemplate) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                editingTemplate = template
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(template.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(previewLine(template.prompt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Edit template")
            .xrayId("settings.templates.editButton.\(template.id.uuidString)")
            .accessibilityLabel("Edit template")

            HStack(spacing: 6) {
                Button {
                    openInEditor(template)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.borderless)
                .help("Open in editor")
                .xrayId("settings.templates.openInEditorButton.\(template.id.uuidString)")
                .accessibilityLabel("Open in editor")

                Button(role: .destructive) {
                    deleteTemplate(template)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete template")
                .xrayId("settings.templates.deleteButton.\(template.id.uuidString)")
                .accessibilityLabel("Delete template")
            }
        }
        .padding(.vertical, 6)
    }

    private var emptySelection: some View {
        VStack(spacing: 10) {
            Image(systemName: "text.badge.plus")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("Select an agent or group to manage its templates.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyTemplates: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.plaintext")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("No templates yet for \(selectionTitle).")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button {
                showingNewSheet = true
            } label: {
                Label("Add your first template", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .xrayId("settings.templates.addFirstButton")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            Button {
                revealOnDisk()
            } label: {
                Label("Reveal on Disk", systemImage: "folder")
            }
            .buttonStyle(.borderless)
            .xrayId("settings.templates.revealButton")

            Spacer()

            Button {
                showingNewSheet = true
            } label: {
                Label("New Template", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedOwner == nil)
            .xrayId("settings.templates.addButton")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private func previewLine(_ prompt: String) -> String {
        let firstLine = prompt.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? prompt
        return firstLine.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Mutations

    private func updateTemplate(_ template: PromptTemplate, name: String, prompt: String) {
        template.name = name
        template.prompt = prompt
        template.updatedAt = Date()
        try? modelContext.save()
        appState.configSyncService?.writeBack(promptTemplate: template)
    }

    private func deleteTemplate(_ template: PromptTemplate) {
        appState.configSyncService?.deleteFile(forPromptTemplate: template)
        modelContext.delete(template)
        try? modelContext.save()
    }

    private func moveTemplates(from offsets: IndexSet, to destination: Int) {
        var ordered = templatesForSelection
        ordered.move(fromOffsets: offsets, toOffset: destination)
        for (index, template) in ordered.enumerated() {
            let newOrder = index + 1
            if template.sortOrder != newOrder {
                template.sortOrder = newOrder
                template.updatedAt = Date()
                appState.configSyncService?.writeBack(promptTemplate: template)
            }
        }
        try? modelContext.save()
    }

    private func revealOnDisk() {
        let url: URL
        switch selectedOwner {
        case .agent(let id):
            let agent = enabledAgents.first { $0.id == id }
            let slug = agent?.configSlug ?? ConfigFileManager.slugify(agent?.name ?? "")
            url = ConfigFileManager.promptTemplatesDirectory
                .appendingPathComponent("agents")
                .appendingPathComponent(slug)
        case .group(let id):
            let group = enabledGroups.first { $0.id == id }
            let slug = group?.configSlug ?? ConfigFileManager.slugify(group?.name ?? "")
            url = ConfigFileManager.promptTemplatesDirectory
                .appendingPathComponent("groups")
                .appendingPathComponent(slug)
        case .none:
            url = ConfigFileManager.promptTemplatesDirectory
        }

        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func openInEditor(_ template: PromptTemplate) {
        guard let slug = template.configSlug else { return }
        let fileURL = ConfigFileManager.promptTemplatesDirectory
            .appendingPathComponent(slug)
            .appendingPathExtension("md")
        NSWorkspace.shared.open(fileURL)
    }
}
