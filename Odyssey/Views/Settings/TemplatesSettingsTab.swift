import SwiftUI
import SwiftData

/// Settings tab for managing prompt templates on agents, groups, and projects.
/// Templates live on disk at `~/.odyssey/config/prompt-templates/` — the UI is
/// a convenience layer on top of the file store, with `ConfigSyncService`
/// handling sync in both directions.
struct TemplatesSettingsTab: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState

    @Query(sort: [SortDescriptor(\Agent.name)]) private var agents: [Agent]
    @Query(sort: [SortDescriptor(\AgentGroup.sortOrder), SortDescriptor(\AgentGroup.name)]) private var groups: [AgentGroup]
    @Query private var allTemplates: [PromptTemplate]

    @State private var selectedOwner: OwnerKey?
    @State private var searchText: String = ""
    @State private var editingTemplate: PromptTemplate?
    @State private var showingNewSheet: Bool = false
    @State private var showingLibrarySheet: Bool = false

    enum OwnerKey: Hashable, Identifiable {
        case agent(UUID)
        case group(UUID)
        case projectTemplates

        var id: String {
            switch self {
            case .agent(let id): "agent-\(id)"
            case .group(let id): "group-\(id)"
            case .projectTemplates: "project-templates"
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

    private var globalProjectTemplateCount: Int {
        allTemplates.filter { $0.isGlobalProjectTemplate }.count
    }

    private var selectedAgent: Agent? {
        guard case .agent(let id) = selectedOwner else { return nil }
        return enabledAgents.first { $0.id == id }
    }

    private var selectedGroup: AgentGroup? {
        guard case .group(let id) = selectedOwner else { return nil }
        return enabledGroups.first { $0.id == id }
    }

    private var isProjectTemplatesSelected: Bool {
        selectedOwner == .projectTemplates
    }

    private var templatesForSelection: [PromptTemplate] {
        let templates: [PromptTemplate]
        switch selectedOwner {
        case .agent(let id): templates = allTemplates.filter { $0.agent?.id == id }
        case .group(let id): templates = allTemplates.filter { $0.group?.id == id }
        case .projectTemplates: templates = allTemplates.filter { $0.isGlobalProjectTemplate }
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
        if isProjectTemplatesSelected { return "Project Templates" }
        return "Templates"
    }

    private var selectionKindNoun: String {
        if selectedGroup != nil { return "group" }
        if isProjectTemplatesSelected { return "project" }
        return "agent"
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
                    ?? .projectTemplates
            }
        }
        .sheet(item: $editingTemplate) { template in
            PromptTemplateCreationSheet(
                ownerAgent: selectedAgent,
                ownerGroup: selectedGroup,
                isGlobalProjectTemplate: isProjectTemplatesSelected,
                existingTemplate: template
            ) { _ in
                editingTemplate = nil
            }
        }
        .sheet(isPresented: $showingNewSheet) {
            PromptTemplateCreationSheet(
                ownerAgent: selectedAgent,
                ownerGroup: selectedGroup,
                isGlobalProjectTemplate: isProjectTemplatesSelected,
                existingTemplate: nil
            ) { _ in
                showingNewSheet = false
            }
        }
        .sheet(isPresented: $showingLibrarySheet) {
            if isProjectTemplatesSelected {
                AddFromLibrarySheet { selectedEntries in
                    addLibraryTemplates(selectedEntries)
                    showingLibrarySheet = false
                } onCancel: {
                    showingLibrarySheet = false
                }
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
                                tint: .secondary,
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
                                tint: .secondary,
                                count: templateCount(forGroup: group)
                            )
                            .tag(OwnerKey.group(group.id))
                            .xrayId("settings.templates.ownerRow.group.\(group.id.uuidString)")
                        }
                    }
                }
                Section("Projects") {
                    ownerRow(
                        name: "Project Templates",
                        icon: "sparkles",
                        tint: .purple,
                        count: globalProjectTemplateCount
                    )
                    .tag(OwnerKey.projectTemplates)
                    .xrayId("settings.templates.ownerRow.projectTemplates")
                }
            }
            .listStyle(.sidebar)
            .xrayId("settings.templates.ownerList")
        }
    }

    @ViewBuilder
    private func ownerRow(name: String, icon: String, tint: Color, count: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: iconSystemName(icon))
                .frame(width: 18)
                .foregroundStyle(tint)
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
            if isProjectTemplatesSelected {
                Text("Prompts available in any project chat via the sparkles button or context menu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Starter prompts available when you begin a chat with this \(selectionKindNoun).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
                    duplicateTemplate(template)
                } label: {
                    Image(systemName: "plus.square.on.square")
                }
                .buttonStyle(.borderless)
                .help("Duplicate template")
                .xrayId("settings.templates.duplicateButton.\(template.id.uuidString)")
                .accessibilityLabel("Duplicate template")

                Button {
                    revealTemplateInFinder(template)
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help("Reveal in Finder")
                .xrayId("settings.templates.revealInFinderButton.\(template.id.uuidString)")
                .accessibilityLabel("Reveal in Finder")

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
        .contextMenu {
            Button("Edit") { editingTemplate = template }
            Button("Duplicate") { duplicateTemplate(template) }
            Divider()
            Button("Reveal in Finder") { revealTemplateInFinder(template) }
            Button("Open in Editor") { openInEditor(template) }
            Divider()
            Button("Delete", role: .destructive) { deleteTemplate(template) }
        }
    }

    private var emptySelection: some View {
        VStack(spacing: 10) {
            Image(systemName: "text.badge.plus")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("Select an agent, group, or project to manage its templates.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var emptyTemplates: some View {
        if isProjectTemplatesSelected {
            projectEmptyTemplates
        } else {
            agentOrGroupEmptyTemplates
        }
    }

    private var agentOrGroupEmptyTemplates: some View {
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

    private var projectEmptyTemplates: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            VStack(spacing: 4) {
                Text("No project templates yet.")
                    .bold()
                Text("Add your own or start from the built-in library.")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .multilineTextAlignment(.center)

            HStack(spacing: 10) {
                Button {
                    showingNewSheet = true
                } label: {
                    Label("New Template", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .xrayId("settings.templates.addFirstButton")

                Button {
                    showingLibrarySheet = true
                } label: {
                    Label("Add from library", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .xrayId("settings.templates.addFromLibraryButton")
            }
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

            if isProjectTemplatesSelected && !templatesForSelection.isEmpty {
                Button {
                    showingLibrarySheet = true
                } label: {
                    Label("Add from library", systemImage: "sparkles")
                }
                .buttonStyle(.bordered)
                .xrayId("settings.templates.addFromLibraryFooterButton")
                .accessibilityLabel("Add from library")
            }

            Button {
                showingNewSheet = true
            } label: {
                Label("New Template", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedOwner == nil)
            .keyboardShortcut("n", modifiers: .command)
            .xrayId("settings.templates.addButton")
            .appXrayTapProxy(id: "settings.templates.addButton") { showingNewSheet = true }
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

    private func duplicateTemplate(_ template: PromptTemplate) {
        let copySlug: String?
        if template.isGlobalProjectTemplate {
            let slug = ConfigFileManager.uniquePromptTemplateSlug(
                baseName: "\(template.name) Copy",
                ownerKind: .projects,
                ownerSlug: "_"
            )
            copySlug = "projects/_/\(slug)"
        } else {
            copySlug = nil
        }
        let copy = PromptTemplate(
            name: "\(template.name) Copy",
            prompt: template.prompt,
            sortOrder: template.sortOrder + 1,
            agent: template.agent,
            group: template.group,
            project: template.project,
            configSlug: copySlug
        )
        modelContext.insert(copy)
        try? modelContext.save()
        appState.configSyncService?.writeBack(promptTemplate: copy)
    }

    private func revealTemplateInFinder(_ template: PromptTemplate) {
        guard let slug = template.configSlug else { return }
        let fileURL = ConfigFileManager.promptTemplatesDirectory
            .appendingPathComponent(slug)
            .appendingPathExtension("md")
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
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
        case .projectTemplates:
            url = ConfigFileManager.promptTemplatesDirectory
                .appendingPathComponent("projects")
                .appendingPathComponent("_")
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

    // MARK: - Library Import

    private func addLibraryTemplates(_ entries: [ProjectTemplateLibrary.Entry]) {
        let existingCount = globalProjectTemplateCount

        for (index, entry) in entries.enumerated() {
            let templateSlug = ConfigFileManager.uniquePromptTemplateSlug(
                baseName: entry.name,
                ownerKind: .projects,
                ownerSlug: "_"
            )
            let configSlug = "projects/_/\(templateSlug)"
            let template = PromptTemplate(
                name: entry.name,
                prompt: entry.prompt,
                sortOrder: existingCount + index + 1,
                isBuiltin: true,
                agent: nil,
                group: nil,
                project: nil,
                configSlug: configSlug
            )
            modelContext.insert(template)
            appState.configSyncService?.writeBack(promptTemplate: template)
        }
        try? modelContext.save()
    }
}

// MARK: - AddFromLibrarySheet

private struct AddFromLibrarySheet: View {
    let onAdd: ([ProjectTemplateLibrary.Entry]) -> Void
    let onCancel: () -> Void

    @State private var selectedIds: Set<String> = []

    private var selectedEntries: [ProjectTemplateLibrary.Entry] {
        ProjectTemplateLibrary.all.filter { selectedIds.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            list
            Divider()
            footer
        }
        .frame(minWidth: 480, minHeight: 460)
        .xrayId("templates.addFromLibrarySheet.root")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Starter Templates")
                .font(.title3.weight(.semibold))
                .xrayId("templates.addFromLibrarySheet.title")
            Text("Select prompts to add to your project templates library.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

    private var list: some View {
        List {
            ForEach(ProjectTemplateLibrary.all) { entry in
                row(entry)
                    .xrayId("templates.addFromLibrarySheet.row.\(entry.id)")
            }
        }
        .listStyle(.inset)
    }

    @ViewBuilder
    private func row(_ entry: ProjectTemplateLibrary.Entry) -> some View {
        Toggle(isOn: Binding(
            get: { selectedIds.contains(entry.id) },
            set: { newValue in
                if newValue {
                    selectedIds.insert(entry.id)
                } else {
                    selectedIds.remove(entry.id)
                }
            }
        )) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.name)
                    .font(.body.weight(.medium))
                Text(shortDescription(entry.prompt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .toggleStyle(.checkbox)
        .padding(.vertical, 4)
    }

    private func shortDescription(_ prompt: String) -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 60 { return trimmed }
        let idx = trimmed.index(trimmed.startIndex, offsetBy: 60)
        return String(trimmed[..<idx]) + "\u{2026}"
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") {
                onCancel()
            }
            .keyboardShortcut(.cancelAction)
            .xrayId("templates.addFromLibrarySheet.cancelButton")

            Button(addButtonLabel) {
                onAdd(selectedEntries)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedIds.isEmpty)
            .keyboardShortcut(.defaultAction)
            .xrayId("templates.addFromLibrarySheet.addButton")
        }
        .padding()
    }

    private var addButtonLabel: String {
        let n = selectedIds.count
        if n == 0 { return "Add Templates" }
        if n == 1 { return "Add 1 Template" }
        return "Add \(n) Templates"
    }
}
