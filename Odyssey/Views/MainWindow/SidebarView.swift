import SwiftUI
import SwiftData
import AppKit

enum SidebarBottomBarItem: String, CaseIterable, Identifiable {
    case schedules = "Schedules"
    case agents = "Agents"
    case autoAssemble = "Auto-assemble"
    case newSession = "New session"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .schedules: "clock.badge"
        case .agents: "cpu"
        case .autoAssemble: "wand.and.stars"
        case .newSession: "plus"
        }
    }

    var helpText: String {
        switch self {
        case .schedules: "Scheduled missions (⌘⇧S)"
        case .agents: "Agent library"
        case .autoAssemble: "Auto-assemble team"
        case .newSession: "New session"
        }
    }

    var xrayId: String {
        switch self {
        case .schedules: "sidebar.schedulesButton"
        case .agents: "sidebar.agentsButton"
        case .autoAssemble: "sidebar.autoAssembleButton"
        case .newSession: "sidebar.newSessionButton"
        }
    }

    /// Whether this item shows a text label alongside its icon.
    /// Items with text labels participate in the adaptive icon-only collapse via `ViewThatFits`.
    var hasTextLabel: Bool {
        switch self {
        case .schedules, .agents: true
        case .autoAssemble, .newSession: false
        }
    }

    /// Items that show text labels and collapse to icon-only when space is constrained.
    static var adaptiveItems: [SidebarBottomBarItem] {
        allCases.filter(\.hasTextLabel)
    }

    /// Items that always display as icon-only.
    static var iconOnlyItems: [SidebarBottomBarItem] {
        allCases.filter { !$0.hasTextLabel }
    }
}

private struct SidebarChromeButtonModifier: ViewModifier {
    let tint: Color
    var emphasize: Bool = false

    func body(content: Content) -> some View {
        content
            .foregroundStyle(emphasize ? tint : .secondary)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(emphasize ? tint.opacity(0.12) : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(emphasize ? tint.opacity(0.16) : Color.primary.opacity(0.05), lineWidth: 1)
            )
    }
}

enum SidebarConversationMetadata {
    static func isDelegationThread(_ convo: Conversation) -> Bool {
        convo.threadKind == .delegation
    }

    static func lastMessagePreview(_ convo: Conversation) -> (text: String, attachmentIcon: String?)? {
        let latestMessage = (convo.messages ?? [])
            .max(by: { $0.timestamp < $1.timestamp })
        guard let latestMessage else { return nil }

        let attachments = latestMessage.attachments ?? []
        let text = latestMessage.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasImages = !attachments.isEmpty && attachments.contains { $0.isImage }
        let hasDocs = !attachments.isEmpty && attachments.contains { $0.isDocument }

        let icon: String? = {
            guard !attachments.isEmpty else { return nil }
            if hasImages && hasDocs { return "paperclip" }
            if hasDocs { return "doc.text" }
            return "photo"
        }()

        if text.isEmpty && !attachments.isEmpty {
            let count = attachments.count
            let label: String
            if hasImages && !hasDocs {
                label = count == 1 ? "Image" : "\(count) Images"
            } else if hasDocs && !hasImages {
                label = count == 1 ? "File" : "\(count) Files"
            } else {
                label = "\(count) Attachments"
            }
            return (text: label, attachmentIcon: icon)
        }

        let preview: String
        if text.count <= 40 {
            preview = text
        } else {
            let cutoff = text.index(text.startIndex, offsetBy: 40)
            preview = String(text[..<cutoff]) + "..."
        }
        return preview.isEmpty ? nil : (text: preview, attachmentIcon: icon)
    }
}

private struct GlobalScheduleEditRequest: Identifiable {
    let id = UUID()
    let schedule: ScheduledMission?
    let draft: ScheduledMissionDraft
}

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState: WindowState
    @Environment(\.modelContext) private var modelContext
    @AppStorage(FeatureFlags.showAdvancedKey, store: AppSettings.store) private var masterFlag = false
    @AppStorage(FeatureFlags.autoAssembleKey, store: AppSettings.store) private var autoAssembleFlag = false
    @AppStorage(FeatureFlags.autonomousMissionsKey, store: AppSettings.store) private var autonomousMissionsFlag = false
    @AppStorage("sidebar.showArchivedProjectSection") private var showsArchivedProjectSection = false
    @AppStorage("sidebar.showProjectSchedulesSection") private var showsProjectSchedulesSection = false
    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]
    @Query(sort: \Conversation.startedAt, order: .reverse) private var conversations: [Conversation]
    @Query(sort: \Agent.name) private var agents: [Agent]
    @Query(sort: \AgentGroup.sortOrder) private var groups: [AgentGroup]
    @Query(sort: \ScheduledMission.updatedAt, order: .reverse) private var schedules: [ScheduledMission]
    @Query(sort: \PromptTemplate.sortOrder) private var allTemplates: [PromptTemplate]
    @State private var expandedAgentIds: Set<UUID> = []
    @State private var expandedGroupIds: Set<UUID> = []
    @State private var expandedArchivedAgentIds: Set<UUID> = []
    @State private var expandedArchivedGroupIds: Set<UUID> = []
    @State private var showingAgentScheduleEditor = false
    @State private var agentScheduleDraft = ScheduledMissionDraft(
        name: "",
        targetKind: .agent,
        projectDirectory: "",
        promptTemplate: ""
    )
    @State private var editingGroup: AgentGroup?
    @State private var showingGroupScheduleEditor = false
    @State private var groupScheduleDraft = ScheduledMissionDraft(
        name: "",
        targetKind: .group,
        projectDirectory: "",
        promptTemplate: ""
    )
    @State private var autonomousGroup: AgentGroup?
    @State private var showAutoAssemble = false
    @State private var showAgentCreation = false
    @State private var showGroupCreation = false
    @State private var showAgentBrowseSheet = false
    @State private var showGroupBrowseSheet = false
    @State private var renamingConversation: Conversation?
    @State private var renameText = ""
    @State private var renamingProject: Project?
    @State private var projectRenameText = ""
    @State private var conversationToDelete: Conversation?
    @State private var showDeleteConfirmation = false
    @State private var projectToArchiveThreads: Project?
    @State private var projectToRemove: Project?
    @State private var scheduleToDelete: ScheduledMission?
    @State private var scheduleForHistory: ScheduledMission?
    @State private var isPinnedExpanded = true
    @State private var isActiveExpanded = true
    @State private var isHistoryExpanded = false
    @State private var isArchivedExpanded = false
    @State private var hoveredProjectId: UUID?
    @State private var hoveredConversationId: UUID?
    @State private var expandedProjectIds: Set<UUID> = []
    @AppStorage("sidebar.agentsExpanded") private var isAgentsSectionExpanded: Bool = true
    @AppStorage("sidebar.groupsExpanded") private var isGroupsSectionExpanded: Bool = true
    @AppStorage("sidebar.pinnedExpanded") private var isPinnedSectionExpanded: Bool = true
    @AppStorage("sidebar.schedulesExpanded") private var isSchedulesSectionExpanded: Bool = true
    @AppStorage("sidebar.projectsExpanded") private var isProjectsSectionExpanded: Bool = true
    @AppStorage("sidebar.allSchedulesExpanded") private var isAllSchedulesExpanded: Bool = false
    @State private var globalScheduleEditRequest: GlobalScheduleEditRequest?
    @State private var cachedSortedProjects: [Project] = []
    @State private var cachedPinnedProjects: [Project] = []
    @State private var cachedResidentAgents: [Agent] = []
    @State private var cachedNonResidentAgents: [Agent] = []
    @State private var cachedResidentGroups: [AgentGroup] = []
    @State private var cachedNonResidentGroups: [AgentGroup] = []
    @State private var conversationToAgentIndex: [UUID: UUID] = [:]
    @State private var cachedActiveAgentIds: Set<UUID> = []
    @State private var cachedActiveGroupIds: Set<UUID> = []
    @State private var agentsWithConversations: Set<UUID> = []
    @State private var groupsWithConversations: Set<UUID> = []
    @State private var sessionIdToAgentId: [UUID: UUID] = [:]
    @State private var conversationIndexRebuildTask: Task<Void, Never>?

    private var autoAssembleEnabled: Bool { FeatureFlags.isEnabled(FeatureFlags.autoAssembleKey) || (masterFlag && autoAssembleFlag) }
    private var autonomousMissionsEnabled: Bool { FeatureFlags.isEnabled(FeatureFlags.autonomousMissionsKey) || (masterFlag && autonomousMissionsFlag) }

    var body: some View {
        sidebarWithSheets
            .background {
                // Isolated observer: subscribes to sessionActivity WITHOUT invalidating the main sidebar body
                ActiveSessionObserver(
                    activeAgentIds: $cachedActiveAgentIds,
                    activeGroupIds: $cachedActiveGroupIds,
                    sessionIdToAgentId: sessionIdToAgentId,
                    groups: groups
                )
            }
            .alert("Rename Conversation", isPresented: Binding(
                get: { renamingConversation != nil },
                set: { if !$0 { renamingConversation = nil } }
            )) {
                TextField("Name", text: $renameText)
                Button("Rename") {
                    if let convo = renamingConversation, !renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        convo.topic = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                        try? modelContext.save()
                    }
                    renamingConversation = nil
                }
                Button("Cancel", role: .cancel) { renamingConversation = nil }
            }
            .alert("Rename Project", isPresented: Binding(
                get: { renamingProject != nil },
                set: { if !$0 { renamingProject = nil } }
            )) {
                TextField("Name", text: $projectRenameText)
                Button("Rename") {
                    let trimmed = projectRenameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let project = renamingProject, !trimmed.isEmpty {
                        project.name = trimmed
                        try? modelContext.save()
                        if windowState.selectedProjectId == project.id {
                            windowState.selectProject(project, preserveSelection: true)
                        }
                    }
                    renamingProject = nil
                }
                Button("Cancel", role: .cancel) { renamingProject = nil }
            }
            .alert("Delete Conversation?", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    if let convo = conversationToDelete {
                        if windowState.selectedConversationId == convo.id {
                            windowState.selectedConversationId = nil
                        }
                        appState.clearSessionActivity(for: (convo.sessions ?? []).map(\.id.uuidString))
                        modelContext.delete(convo)
                        try? modelContext.save()
                    }
                    conversationToDelete = nil
                }
                Button("Cancel", role: .cancel) { conversationToDelete = nil }
            } message: {
                Text("This conversation and all its messages will be permanently deleted.")
            }
            .alert("Archive all threads?", isPresented: Binding(
                get: { projectToArchiveThreads != nil },
                set: { if !$0 { projectToArchiveThreads = nil } }
            )) {
                Button("Archive", role: .destructive) {
                    if let project = projectToArchiveThreads {
                        archiveThreads(in: project)
                    }
                    projectToArchiveThreads = nil
                }
                Button("Cancel", role: .cancel) { projectToArchiveThreads = nil }
            } message: {
                if let project = projectToArchiveThreads {
                    Text("All threads in \(project.name) will be moved to Archived.")
                }
            }
            .alert("Remove Project?", isPresented: Binding(
                get: { projectToRemove != nil },
                set: { if !$0 { projectToRemove = nil } }
            )) {
                Button("Remove", role: .destructive) {
                    if let project = projectToRemove {
                        removeProject(project)
                    }
                    projectToRemove = nil
                }
                Button("Cancel", role: .cancel) { projectToRemove = nil }
            } message: {
                if let project = projectToRemove {
                    Text("Remove \(project.name) from the sidebar and delete its local threads, tasks, and schedules. Project files on disk will stay untouched.")
                }
            }
            .alert("Delete Schedule?", isPresented: Binding(
                get: { scheduleToDelete != nil },
                set: { if !$0 { scheduleToDelete = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    if let schedule = scheduleToDelete {
                        deleteGlobalSchedule(schedule)
                    }
                    scheduleToDelete = nil
                }
                Button("Cancel", role: .cancel) { scheduleToDelete = nil }
            } message: {
                if let schedule = scheduleToDelete {
                    Text("\"\(schedule.name)\" will be permanently deleted.")
                }
            }
            .focusedSceneValue(\.addProjectAction, AddProjectAction { addProjectFolder() })
    }

    private var sidebarWithSheets: some View {
        sidebarList
            .background {
                // Hidden keyboard-shortcut triggers for New Agent / New Group
                Button("") { showAgentCreation = true }
                    .keyboardShortcut("a", modifiers: [.command, .option])
                    .hidden()
                Button("") { showGroupCreation = true }
                    .keyboardShortcut("g", modifiers: [.command, .option])
                    .hidden()
                // ⌘⌥U — open Ulysses from anywhere
                Button("") {
                    if let ulysses = agents.first(where: { $0.name == "Ulysses" && $0.isEnabled }) {
                        selectOrCreateAgentChat(ulysses)
                    }
                }
                .keyboardShortcut("u", modifiers: [.command, .option])
                .hidden()
            }
            .sheet(item: $editingGroup) { group in
                GroupEditorView(group: group)
            }
            .sheet(item: $autonomousGroup) { group in
                AutonomousMissionSheet(group: group)
                    .environment(appState)
            }
            .sheet(isPresented: $showAutoAssemble) {
                AutoAssembleSheet()
                    .environment(appState)
            }
            .sheet(isPresented: $showAgentCreation) {
                AgentCreationSheet { _ in
                    showAgentCreation = false
                }
                .environment(appState)
            }
            .sheet(isPresented: $showGroupCreation) {
                GroupEditorView(group: nil)
                    .environment(appState)
            }
            .sheet(isPresented: $showAgentBrowseSheet) {
                AgentBrowseSheet(
                    initialTab: .agents,
                    projectId: windowState.selectedProjectId,
                    projectDirectory: windowState.projectDirectory
                )
                .environment(appState)
                .environment(windowState)
            }
            .sheet(isPresented: $showGroupBrowseSheet) {
                AgentBrowseSheet(
                    initialTab: .groups,
                    projectId: windowState.selectedProjectId,
                    projectDirectory: windowState.projectDirectory
                )
                .environment(appState)
                .environment(windowState)
            }
            .sheet(isPresented: $showingAgentScheduleEditor) {
                ScheduleEditorView(schedule: nil, draft: agentScheduleDraft)
                    .environment(appState)
                    .environment(\.modelContext, modelContext)
            }
            .sheet(isPresented: $showingGroupScheduleEditor) {
                ScheduleEditorView(schedule: nil, draft: groupScheduleDraft)
                    .environment(appState)
                    .environment(\.modelContext, modelContext)
            }
            .sheet(item: $globalScheduleEditRequest) { req in
                ScheduleEditorView(schedule: req.schedule, draft: req.draft)
                    .environment(appState)
                    .environment(\.modelContext, modelContext)
            }
            .sheet(item: $scheduleForHistory) { schedule in
                ScheduleHistorySheet(schedule: schedule)
                    .environment(appState)
                    .environment(windowState)
            }
            .onChange(of: windowState.sidebarRevealConversationId) { _, convId in
                guard let convId else { return }
                expandForReveal(convId)
                windowState.sidebarRevealConversationId = nil
            }
            .onChange(of: appState.showAgentCreationSheet) { _, show in
                if show { showAgentCreation = true; appState.showAgentCreationSheet = false }
            }
            .onChange(of: appState.showGroupCreationSheet) { _, show in
                if show { showGroupCreation = true; appState.showGroupCreationSheet = false }
            }
            .onAppear {
                rebuildProjectCache()
                rebuildAgentCaches()
                rebuildGroupCaches()
                rebuildConversationIndex()
            }
            .onChange(of: projects.count) { _, _ in rebuildProjectCache() }
            .onChange(of: projects.map { $0.isPinned }) { _, _ in rebuildProjectCache() }
            .onChange(of: agents.count) { _, _ in
                rebuildAgentCaches()
                rebuildConversationIndex()
            }
            .onChange(of: agents.map { $0.showInSidebar }) { _, _ in rebuildAgentCaches() }
            .onChange(of: agents.map { $0.isResident }) { _, _ in rebuildAgentCaches() }
            .onChange(of: groups.count) { _, _ in rebuildGroupCaches() }
            .onChange(of: groups.map { $0.showInSidebar }) { _, _ in rebuildGroupCaches() }
            .onChange(of: groups.map { $0.isResident }) { _, _ in rebuildGroupCaches() }
            .onChange(of: conversations.count) { _, _ in scheduleConversationIndexRebuild() }
            .onChange(of: appState.createdSessions.count) { _, _ in
                scheduleConversationIndexRebuild()
            }
    }

    private var searchText: String { appState.sidebarSearchText }

    private var sidebarList: some View {
        @Bindable var ws = windowState
        @Bindable var as_ = appState
        return List {
            globalUtilitiesSection

            pinnedSection

            agentsSection

            groupsSection

            if sortedProjects.isEmpty {
                emptyState
            } else {
                Section {
                    if isProjectsSectionExpanded {
                        ForEach(sortedProjects) { project in
                            projectRows(project)
                        }
                    }
                } header: {
                    projectsHeader
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $as_.sidebarSearchText, prompt: "Search threads…")
        .xrayId("sidebar.conversationList")
        .onAppear {
            if let selectedProjectId = windowState.selectedProjectId {
                expandedProjectIds.insert(selectedProjectId)
            }
            rebuildProjectCache()
            rebuildAgentCaches()
            rebuildGroupCaches()
        }
        .onChange(of: projects.count) { _, _ in rebuildProjectCache() }
        .onChange(of: agents.count) { _, _ in rebuildAgentCaches() }
        .onChange(of: agents.map { $0.showInSidebar }) { _, _ in rebuildAgentCaches() }
        .onChange(of: windowState.selectedConversationId) { _, newValue in
            guard let selectedId = newValue else { return }
            handleConversationSelectionChange(selectedId)
            Task { @MainActor in handleConversationSelectionChange(selectedId) }
        }
        .frame(minWidth: 280)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    ws.openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
                .xrayId("mainWindow.settingsButton")
                .accessibilityLabel("Settings")
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    ws.showScheduleLibrary = true
                } label: {
                    Image(systemName: "clock")
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .help("Schedules (⌘⇧S)")
                .xrayId("sidebar.schedulesButton")
                .accessibilityLabel("Schedules")
            }
            ToolbarItem(placement: .automatic) {
                ZStack {
                    Button("") { }
                        .frame(width: 0, height: 0).opacity(0)
                        .popover(isPresented: $ws.showAgentPicker, arrowEdge: .bottom) {
                            AgentPickerPopover(
                                projectId: nil,
                                projectDirectory: "",
                                isPresented: $ws.showAgentPicker
                            )
                            .environment(appState)
                            .environment(windowState)
                        }
                    Button("") { }
                        .frame(width: 0, height: 0).opacity(0)
                        .popover(isPresented: $ws.showGroupPicker, arrowEdge: .bottom) {
                            GroupPickerPopover(
                                projectId: nil,
                                projectDirectory: "",
                                isPresented: $ws.showGroupPicker
                            )
                            .environment(appState)
                            .environment(windowState)
                        }
                    Button("") { ws.showAgentPicker = true }
                        .keyboardShortcut("n", modifiers: .command)
                        .frame(width: 0, height: 0).opacity(0)
                    Button("") { ws.showGroupPicker = true }
                        .keyboardShortcut("n", modifiers: [.command, .option])
                        .frame(width: 0, height: 0).opacity(0)
                    Button("") { ws.showAgentPicker = true }
                        .keyboardShortcut("n", modifiers: [.command, .shift])
                        .frame(width: 0, height: 0).opacity(0)
                    Menu {
                        Button { ws.showAgentPicker = true } label: {
                            Label("Chat with Agent", systemImage: "cpu")
                        }
                        Button { ws.showGroupPicker = true } label: {
                            Label("Chat with Group", systemImage: "person.3.fill")
                        }
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("New chat (⌘N)")
                    .xrayId("sidebar.newMenu")
                    .accessibilityLabel("New")
                }
            }
        }
    }


    private var sortedProjects: [Project] { cachedSortedProjects }
    private var ulyssesAgent: Agent? { agents.first { $0.name == "Ulysses" && $0.isEnabled } }
    private var residentAgents: [Agent] { cachedResidentAgents }
    private var nonResidentAgents: [Agent] { cachedNonResidentAgents }
    private var residentGroups: [AgentGroup] { cachedResidentGroups }
    private var nonResidentGroups: [AgentGroup] { cachedNonResidentGroups }

    private func rebuildProjectCache() {
        let byDate: (Project, Project) -> Bool = { $0.createdAt > $1.createdAt }
        cachedPinnedProjects = projects.filter { $0.isPinned }.sorted(by: byDate)
        cachedSortedProjects = projects.filter { !$0.isPinned }.sorted(by: byDate)
    }

    private func rebuildAgentCaches() {
        let ulyssesId = agents.first { $0.name == "Ulysses" }?.id
        cachedResidentAgents = agents.filter { $0.isEnabled && $0.isResident && $0.id != ulyssesId }.sorted { $0.name < $1.name }
        cachedNonResidentAgents = agents.filter { $0.isEnabled && !$0.isResident && $0.id != ulyssesId && agentsWithConversations.contains($0.id) }.sorted { $0.name < $1.name }
    }

    private func rebuildGroupCaches() {
        cachedResidentGroups = groups.filter { $0.isEnabled && $0.isResident }.sorted { $0.name < $1.name }
        cachedNonResidentGroups = groups.filter { $0.isEnabled && !$0.isResident && groupsWithConversations.contains($0.id) }.sorted { $0.name < $1.name }
    }

    private func scheduleConversationIndexRebuild() {
        conversationIndexRebuildTask?.cancel()
        conversationIndexRebuildTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            rebuildConversationIndex()
        }
    }

    private func rebuildConversationIndex() {
        let descriptor = FetchDescriptor<Session>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        guard let sessions = try? modelContext.fetch(descriptor) else { return }
        var index: [UUID: UUID] = [:]
        var sessionAgentMap: [UUID: UUID] = [:]
        for session in sessions {
            guard let agentId = session.agent?.id else { continue }
            sessionAgentMap[session.id] = agentId
            for convo in (session.conversations ?? []) {
                index[convo.id] = agentId
            }
        }
        conversationToAgentIndex = index
        sessionIdToAgentId = sessionAgentMap
        agentsWithConversations = Set(index.values)
        groupsWithConversations = Set(conversations.compactMap(\.sourceGroupId))
        rebuildAgentCaches()
        rebuildGroupCaches()
    }

    private var projectsHeader: some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isProjectsSectionExpanded.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isProjectsSectionExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Projects")
                        .font(.headline.weight(.semibold))
                }
            }
            .buttonStyle(.plain)
            Spacer()
            Button {
                addProjectFolder()
            } label: {
                Image(systemName: "plus")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .help("Add project folder")
            .xrayId("sidebar.projectsHeader.addProject")
            .accessibilityLabel("Add project folder")
        }
    }

    // MARK: - Bottom Bar

    private var sidebarBottomBar: some View {
        ViewThatFits(in: .horizontal) {
            sidebarBottomBarButtons
            sidebarBottomBarButtons
                .labelStyle(.iconOnly)
        }
        .padding(.vertical, 6)
        .background(.bar)
        .xrayId("sidebar.bottomBar")
    }

    private var sidebarBottomBarButtons: some View {
        HStack(spacing: 0) {
            let schedules = SidebarBottomBarItem.schedules
            Button {
                windowState.showScheduleLibrary = true
            } label: {
                Label(schedules.rawValue, systemImage: schedules.icon)
                    .fixedSize(horizontal: true, vertical: false)
                    .font(.caption)
                    .frame(minHeight: 24)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .help(schedules.helpText)
            .xrayId(schedules.xrayId)
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .accessibilityLabel(schedules.helpText)

            Divider()
                .frame(height: 16)

            let agents = SidebarBottomBarItem.agents
            Button {
                windowState.openConfiguration(section: .agents)
            } label: {
                Label(agents.rawValue, systemImage: agents.icon)
                    .fixedSize(horizontal: true, vertical: false)
                    .font(.caption)
                    .frame(minHeight: 24)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .help(agents.helpText)
            .xrayId(agents.xrayId)
            .accessibilityLabel(agents.helpText)

            if autoAssembleEnabled {
                Divider()
                    .frame(height: 16)

                let autoAssemble = SidebarBottomBarItem.autoAssemble
                Button {
                    showAutoAssemble = true
                } label: {
                    Image(systemName: autoAssemble.icon)
                        .font(.caption)
                        .frame(width: 24, height: 24)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .help(autoAssemble.helpText)
                .xrayId(autoAssemble.xrayId)
                .accessibilityLabel(autoAssemble.helpText)
                .contentShape(Rectangle())
            }

            Divider()
                .frame(height: 16)

            let newSession = SidebarBottomBarItem.newSession
            Button {
                windowState.showAgentPicker = true
            } label: {
                Image(systemName: newSession.icon)
                    .font(.caption)
                    .frame(width: 24, height: 24)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .help(newSession.helpText)
            .xrayId(newSession.xrayId)
            .accessibilityLabel(newSession.helpText)
            .contentShape(Rectangle())
        }
    }

    // MARK: - Projects

    @ViewBuilder
    private func projectRows(_ project: Project) -> some View {
        HStack(spacing: 4) {
            Image(systemName: expandedProjectIds.contains(project.id) ? "chevron.down" : "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 12)
                .accessibilityHidden(true)
                .onTapGesture { toggleProjectExpansion(project) }
            projectHeaderRow(project)
        }

        if expandedProjectIds.contains(project.id) {
            projectThreadRows(project)
            if showsProjectSchedulesSection {
                projectIndentedRow {
                    projectSchedulesSection(project)
                }
            }
        }
    }

    private func projectHeaderRow(_ project: Project) -> some View {
        let isSelectedProject = windowState.selectedProjectId == project.id
        let isHoveredProject = hoveredProjectId == project.id
        let showsProjectActions = isSelectedProject || isHoveredProject
        let tint = projectTint(project)

        return HStack(spacing: 8) {
            sidebarSymbolBadge(
                symbol: project.icon,
                tint: tint,
                size: 28,
                cornerRadius: 9,
                emphasize: isSelectedProject
            )
            HStack(spacing: 6) {
                Text(project.name)
                    .font(isSelectedProject ? .headline.weight(.semibold) : .headline.weight(.medium))
                    .lineLimit(1)
                    .layoutPriority(1)

                if !project.rootPath.isEmpty {
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)

                    Text(project.rootPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if project.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint.opacity(isSelectedProject ? 0.9 : 0.7))
                    .accessibilityHidden(true)
            }

            if showsProjectActions {
                projectActionsMenu(for: project)
                Button {
                    createQuickChat(in: project)
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .modifier(SidebarChromeButtonModifier(tint: tint, emphasize: isSelectedProject))
                .buttonStyle(.plain)
                .help("Start new thread in \(project.name)")
                .xrayId("sidebar.projectNewThread.\(project.id.uuidString)")
                .accessibilityLabel("Start new thread in \(project.name)")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            toggleProjectExpansion(project)
        }
        .onHover { isHovering in
            hoveredProjectId = isHovering ? project.id : nil
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    isSelectedProject
                    ? AnyShapeStyle(
                        LinearGradient(
                            colors: [tint.opacity(0.18), tint.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    : AnyShapeStyle(Color.primary.opacity(0.04))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isSelectedProject ? tint.opacity(0.22) : Color.primary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: isSelectedProject ? tint.opacity(0.10) : .clear, radius: 12, y: 6)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                projectToArchiveThreads = project
            } label: {
                Image(systemName: "archivebox")
            }
            .help("Archive Threads")
            .tint(.indigo)

            Button(role: .destructive) {
                projectToRemove = project
            } label: {
                Image(systemName: "trash")
            }
            .help("Remove")
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                createQuickChat(in: project)
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .help("New Thread")
            .tint(tint)

            Button {
                openProjectInFinder(project)
            } label: {
                Image(systemName: "folder")
            }
            .help("Open in Finder")
            .tint(.blue)
        }
        .xrayId("sidebar.projectRow.\(project.id.uuidString)")
    }

    @ViewBuilder
    private func projectThreadRows(_ project: Project) -> some View {
        let liveThreads = rootConversations(in: project)
            .filter { !$0.isArchived }
            .sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned {
                    return lhs.isPinned && !rhs.isPinned
                }
                return lhs.startedAt > rhs.startedAt
            }
        let pinnedThreads = filteredConversations(liveThreads.filter(\.isPinned))
        let activeThreads = filteredConversations(Array(liveThreads.filter { !$0.isPinned }.prefix(10)))
        let historyThreads = filteredConversations(Array(liveThreads.filter { !$0.isPinned }.dropFirst(10)))
        let archivedThreads = filteredConversations(rootConversations(in: project).filter(\.isArchived))

        if liveThreads.isEmpty {
            projectIndentedRow {
                Text("No threads")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        } else {
            projectThreadBucket(
                title: "Pinned (\(pinnedThreads.count))",
                symbol: "pin.fill",
                isExpanded: Binding(
                    get: { isPinnedExpanded || !searchText.isEmpty },
                    set: { isPinnedExpanded = $0 }
                ),
                conversations: pinnedThreads,
                pinAction: "Unpin",
                xrayId: "sidebar.pinnedSection"
            )

            projectThreadBucket(
                title: "Active (\(activeThreads.count))",
                symbol: "bolt.fill",
                isExpanded: Binding(
                    get: { isActiveExpanded || !searchText.isEmpty },
                    set: { isActiveExpanded = $0 }
                ),
                conversations: activeThreads,
                pinAction: "Pin",
                xrayId: "sidebar.activeSection"
            )

            projectThreadBucket(
                title: "History (\(historyThreads.count))",
                symbol: "clock.arrow.circlepath",
                isExpanded: Binding(
                    get: { isHistoryExpanded || !searchText.isEmpty },
                    set: { isHistoryExpanded = $0 }
                ),
                conversations: historyThreads,
                pinAction: "Pin",
                xrayId: "sidebar.historySection"
            )
        }

        if showsArchivedProjectSection && !archivedThreads.isEmpty {
            projectArchivedRows(archivedThreads)
        }
    }

    @ViewBuilder
    private func projectThreadBucket(
        title: String,
        symbol: String,
        isExpanded: Binding<Bool>,
        conversations: [Conversation],
        pinAction: String,
        xrayId: String
    ) -> some View {
        if !conversations.isEmpty {
            let expanded = isExpanded.wrappedValue || !searchText.isEmpty

            projectIndentedRow {
                Button {
                    if searchText.isEmpty {
                        isExpanded.wrappedValue.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Label(title, systemImage: symbol)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .xrayId(xrayId)
            }

            if expanded {
                ForEach(conversations) { convo in
                    projectIndentedRow {
                        conversationTreeNode(convo, pinAction: pinAction)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func projectArchivedRows(_ archivedThreads: [Conversation]) -> some View {
        let isExpanded = isArchivedExpanded || !searchText.isEmpty

        projectIndentedRow {
            Button {
                if searchText.isEmpty {
                    isArchivedExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Label("Archived (\(archivedThreads.count))", systemImage: "archivebox")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .xrayId("sidebar.archivedSection")
        }

        if isExpanded {
            ForEach(archivedThreads) { convo in
                projectIndentedRow {
                    conversationRow(convo)
                        .tag(convo.id)
                        .contentShape(Rectangle())
                        .onTapGesture { selectConversation(convo) }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) { promptDelete(convo) } label: {
                                Image(systemName: "trash")
                            }
                            .help("Delete")
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button { unarchiveConversation(convo) } label: {
                                Image(systemName: "tray.and.arrow.up")
                            }
                            .help("Unarchive")
                            .tint(.blue)
                        }
                }
            }
        }
    }

    private func projectIndentedRow<Content: View>(
        bottomPadding: CGFloat = 2,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(.leading, 18)
            .padding(.trailing, 4)
            .padding(.bottom, bottomPadding)
    }

    private func projectActionsMenu(for project: Project) -> some View {
        Menu {
            Button {
                openProjectInFinder(project)
            } label: {
                Label("Open in Finder", systemImage: "folder")
            }

            Button {
                toggleProjectPin(project)
            } label: {
                Label(project.isPinned ? "Unpin project" : "Pin project", systemImage: project.isPinned ? "pin.slash" : "pin")
            }

            Button {
                beginRename(project)
            } label: {
                Label("Edit name", systemImage: "pencil")
            }

            Button {
                projectToArchiveThreads = project
            } label: {
                Label("Archive threads", systemImage: "archivebox")
            }

            let globalTemplates = allTemplates.filter { $0.isGlobalProjectTemplate }
            if !globalTemplates.isEmpty {
                Menu("Run Template\u{2026}") {
                    ForEach(globalTemplates) { template in
                        Button(template.name) {
                            runProjectTemplate(template, in: project)
                        }
                        .xrayId("sidebar.projectRow.runTemplate.\(project.id.uuidString).\(template.id.uuidString)")
                    }
                }
                .xrayId("sidebar.projectRow.runTemplateMenu.\(project.id.uuidString)")
                Divider()
            }

            Button {
                showsArchivedProjectSection.toggle()
            } label: {
                Label(
                    showsArchivedProjectSection ? "Hide archived section" : "Show archived section",
                    systemImage: showsArchivedProjectSection ? "eye.slash" : "archivebox"
                )
            }
            .xrayId("sidebar.projectActions.toggleArchived.\(project.id.uuidString)")

            Button {
                showsProjectSchedulesSection.toggle()
            } label: {
                Label(
                    showsProjectSchedulesSection ? "Hide schedules section" : "Show schedules section",
                    systemImage: showsProjectSchedulesSection ? "eye.slash" : "clock"
                )
            }
            .xrayId("sidebar.projectActions.toggleSchedules.\(project.id.uuidString)")

            Divider()

            Button(role: .destructive) {
                projectToRemove = project
            } label: {
                Label("Remove", systemImage: "xmark")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .modifier(SidebarChromeButtonModifier(tint: projectTint(project), emphasize: windowState.selectedProjectId == project.id))
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Project actions")
        .xrayId("sidebar.projectActions.\(project.id.uuidString)")
        .accessibilityLabel("Project actions for \(project.name)")
    }

    @ViewBuilder
    private func projectSchedulesSection(_ project: Project) -> some View {
        let projectSchedules = schedulesForProject(project)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("Schedules", systemImage: "clock")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Open") {
                    windowState.selectProject(project, preserveSelection: true)
                    windowState.showScheduleLibrary = true
                }
                .buttonStyle(.plain)
                .font(.caption2)
                .foregroundStyle(projectTint(project))
            }

            if projectSchedules.isEmpty {
                Text("No schedules")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(projectSchedules.prefix(4)) { schedule in
                    HStack(spacing: 8) {
                        sidebarSymbolBadge(symbol: "clock", tint: projectTint(project), size: 22, cornerRadius: 7)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(schedule.name)
                                .font(.caption)
                                .lineLimit(1)
                            Text(schedule.nextRunAt?.formatted(date: .omitted, time: .shortened) ?? "Not scheduled")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer(minLength: 8)
                        Text(scheduleRuleLabel(schedule))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(sidebarPanelBackground)
        .overlay(sidebarPanelStroke)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "folder.badge.plus")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
                Text("No projects yet")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Add a folder to create your first project workspace.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                Button {
                    addProjectFolder()
                } label: {
                    Label("Add Project", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help("Add a project folder")
                .xrayId("sidebar.emptyState.addProjectButton")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    // MARK: - Tree helpers

    private func rootConversations(in project: Project) -> [Conversation] {
        conversations.filter { $0.parentConversationId == nil && $0.projectId == project.id }
    }

    private func activeConversations(in project: Project) -> [Conversation] {
        rootConversations(in: project)
            .filter { !$0.isArchived }
            .sorted { $0.startedAt > $1.startedAt }
    }

    private func childConversations(of parent: Conversation) -> [Conversation] {
        conversations
            .filter { $0.parentConversationId == parent.id }
            .sorted { $0.startedAt < $1.startedAt }
    }

    @ViewBuilder
    private func conversationTreeNode(_ convo: Conversation, pinAction: String) -> some View {
        let children = childConversations(of: convo)
        if children.isEmpty {
            conversationRow(convo)
                .tag(convo.id)
                .contentShape(Rectangle())
                .onTapGesture { selectConversation(convo) }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) { promptDelete(convo) } label: {
                        Image(systemName: "trash")
                    }
                    .help("Delete")
                    Button { archiveConversation(convo) } label: {
                        Image(systemName: "archivebox")
                    }
                    .help("Archive")
                    .tint(.indigo)
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button { togglePin(convo) } label: {
                        Image(systemName: convo.isPinned ? "pin.slash" : "pin")
                    }
                    .help(pinAction)
                    .tint(.yellow)
                }
        } else {
            DisclosureGroup {
                ForEach(children) { child in
                    childConversationRow(child)
                }
            } label: {
                conversationRow(convo)
                    .tag(convo.id)
                    .contentShape(Rectangle())
                    .onTapGesture { selectConversation(convo) }
            }
            .tag(convo.id)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) { promptDelete(convo) } label: {
                    Image(systemName: "trash")
                }
                .help("Delete")
                Button { archiveConversation(convo) } label: {
                    Image(systemName: "archivebox")
                }
                .help("Archive")
                .tint(.indigo)
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button { togglePin(convo) } label: {
                    Image(systemName: convo.isPinned ? "pin.slash" : "pin")
                }
                .help(pinAction)
                .tint(.yellow)
            }
        }
    }

    @ViewBuilder
    private func childConversationRow(_ convo: Conversation) -> some View {
        conversationRow(convo)
            .tag(convo.id)
            .contentShape(Rectangle())
            .onTapGesture { selectConversation(convo) }
    }

    // MARK: - Groups Section

    @ViewBuilder
    private func groupSidebarRow(_ group: AgentGroup, isPinned: Bool = false) -> some View {
        GroupSidebarRowView(
            group: group,
            conversations: conversationsForGroup(group),
            archivedConversations: archivedConversationsForGroup(group),
            allAgents: agents,
            isExpanded: Binding(
                get: { expandedGroupIds.contains(group.id) },
                set: { expanded in
                    if expanded { expandedGroupIds.insert(group.id) }
                    else { expandedGroupIds.remove(group.id) }
                }
            ),
            onNewChat: {
                if let convoId = appState.startGroupChat(
                    group: group,
                    projectDirectory: "",
                    projectId: nil,
                    modelContext: modelContext
                ) {
                    expandedGroupIds.insert(group.id)
                    windowState.selectedConversationId = convoId
                }
            },
            onNewAutonomousChat: (autonomousMissionsEnabled && group.autonomousCapable) ? {
                autonomousGroup = group
            } : nil,
            onSelectConversation: { conv in windowState.selectedConversationId = conv.id },
            onSelectGroup: { selectOrCreateGroupChat(group) },
            onEdit: { editingGroup = group },
            onRename: { conv in renameText = conv.topic ?? ""; renamingConversation = conv },
            selectedConversationId: windowState.selectedConversationId,
            hasActiveSession: groupHasActiveSession(group),
            onDeleteConversation: { conv in promptDelete(conv) },
            projects: projects,
            onNewSessionInProject: { project in selectOrCreateGroupChat(group, in: project) },
            isPinned: isPinned,
            onTogglePin: {
                group.isResident.toggle()
                try? modelContext.save()
                rebuildGroupCaches()
            },
            onHideFromSidebar: {
                group.showInSidebar = false
                try? modelContext.save()
                rebuildGroupCaches()
            },
            onScheduleMission: {
                groupScheduleDraft = ScheduledMissionDraft(
                    name: "\(group.name) schedule",
                    targetKind: .group,
                    projectDirectory: "",
                    promptTemplate: group.defaultMission ?? ""
                )
                groupScheduleDraft.targetGroupId = group.id
                showingGroupScheduleEditor = true
            },
            onViewSessionHistory: {
                if expandedGroupIds.contains(group.id) { expandedGroupIds.remove(group.id) }
                else { expandedGroupIds.insert(group.id) }
            },
            onCloseConversation: { conv in closeConversation(conv) },
            isArchivedExpanded: Binding(
                get: { expandedArchivedGroupIds.contains(group.id) },
                set: { expanded in
                    if expanded { expandedArchivedGroupIds.insert(group.id) }
                    else { expandedArchivedGroupIds.remove(group.id) }
                }
            )
        )
    }

    @ViewBuilder
    private var groupsSection: some View {
        Section {
            if isGroupsSectionExpanded {
                // Groups with conversation history — shown directly
                ForEach(nonResidentGroups) { group in
                    groupSidebarRow(group, isPinned: false)
                }

                // 3. Library hint for groups with no history
                let inLibraryCount = groups.filter { $0.isEnabled && !$0.isResident && !groupsWithConversations.contains($0.id) }.count
                if inLibraryCount > 0 {
                    Button {
                        showGroupBrowseSheet = true
                    } label: {
                        Text("\(inLibraryCount) more in library →")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("sidebar.groupsLibraryHint")
                }
            }
        } header: {
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isGroupsSectionExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isGroupsSectionExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("Groups")
                            .font(.headline.weight(.semibold))
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                Button {
                    showGroupCreation = true
                } label: {
                    Image(systemName: "plus")
                        .font(.caption.weight(.semibold))
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .appXrayTapProxy(id: "sidebar.groupsAddButton") { appState.showGroupCreationSheet = true }
                .stableXrayId("sidebar.groupsAddButton")
                .accessibilityLabel("Add group")
            }
        }
        .stableXrayId("sidebar.groupsSection")
    }

    // MARK: - Agents Section

    private var agentsSectionHeader: some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isAgentsSectionExpanded.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isAgentsSectionExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Agents")
                        .font(.headline.weight(.semibold))
                }
            }
            .buttonStyle(.plain)
            Spacer()
            Button {
                showAgentCreation = true
            } label: {
                Image(systemName: "plus")
                    .font(.caption.weight(.semibold))
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .appXrayTapProxy(id: "sidebar.agentsSection.addButton") { appState.showAgentCreationSheet = true }
            .stableXrayId("sidebar.agentsSection.addButton")
            .accessibilityLabel("Add agent")
        }
    }

    @ViewBuilder
    private var globalUtilitiesSection: some View {
        Section {
            if isSchedulesSectionExpanded {
                ForEach(schedules) { schedule in
                    globalScheduleRow(schedule)
                }
            }
        } header: {
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isSchedulesSectionExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isSchedulesSectionExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("Schedules")
                            .font(.headline.weight(.semibold))
                    }
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button { createNewGlobalSchedule() } label: {
                        Label("New Schedule", systemImage: "plus")
                    }
                    Divider()
                    Button { windowState.showScheduleLibrary = true } label: {
                        Label("Open Schedule Library", systemImage: "clock.badge")
                    }
                }
                Spacer()
                Button {
                    createNewGlobalSchedule()
                } label: {
                    Image(systemName: "plus")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New schedule")
                .help("New schedule")
            }
        }
        .stableXrayId("sidebar.globalUtilitiesSection")
    }

    @ViewBuilder
    private func globalScheduleRow(_ schedule: ScheduledMission) -> some View {
        Button {
            openGlobalScheduleEditor(schedule)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text(schedule.name)
                        .font(.callout)
                        .lineLimit(1)
                    Text(schedule.isEnabled
                         ? (schedule.nextRunAt?.formatted(date: .omitted, time: .shortened) ?? "Not scheduled")
                         : "Disabled")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 4)
                if schedule.isEnabled {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.leading, 18)
        }
        .buttonStyle(.plain)
        .stableXrayId("sidebar.globalScheduleRow.\(schedule.id.uuidString)")
        .contextMenu {
            Button { openGlobalScheduleEditor(schedule) } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button { appState.runScheduledMissionNow(schedule.id, windowState: windowState) } label: {
                Label("Run Now", systemImage: "play.fill")
            }
            if let convId = schedule.targetConversationId,
               conversations.contains(where: { $0.id == convId }) {
                Button {
                    windowState.selectedConversationId = convId
                } label: {
                    Label("Go to Last Session", systemImage: "bubble.left")
                }
            }
            Button { scheduleForHistory = schedule } label: {
                Label("View History", systemImage: "clock.arrow.circlepath")
            }
            Divider()
            Button { toggleGlobalSchedule(schedule) } label: {
                Label(schedule.isEnabled ? "Disable" : "Enable",
                      systemImage: schedule.isEnabled ? "pause.circle" : "play.circle")
            }
            Button { duplicateGlobalSchedule(schedule) } label: {
                Label("Duplicate", systemImage: "doc.on.doc")
            }
            Button { duplicateAndEditGlobalSchedule(schedule) } label: {
                Label("Duplicate & Edit", systemImage: "doc.on.doc.fill")
            }
            Divider()
            Button(role: .destructive) { scheduleToDelete = schedule } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func createNewGlobalSchedule() {
        var draft = ScheduledMissionDraft(projectDirectory: "")
        draft.projectId = windowState.selectedProjectId
        globalScheduleEditRequest = GlobalScheduleEditRequest(schedule: nil, draft: draft)
    }

    private func openGlobalScheduleEditor(_ schedule: ScheduledMission) {
        globalScheduleEditRequest = GlobalScheduleEditRequest(
            schedule: schedule,
            draft: ScheduledMissionDraft(schedule: schedule)
        )
    }

    private func toggleGlobalSchedule(_ schedule: ScheduledMission) {
        schedule.isEnabled.toggle()
        appState.syncScheduledMission(schedule)
    }

    private func duplicateGlobalSchedule(_ schedule: ScheduledMission) {
        let copy = ScheduledMission(
            name: "\(schedule.name) Copy",
            targetKind: schedule.targetKind,
            projectDirectory: schedule.projectDirectory,
            promptTemplate: schedule.promptTemplate
        )
        copy.projectId = schedule.projectId
        copy.isEnabled = false
        copy.targetAgentId = schedule.targetAgentId
        copy.targetGroupId = schedule.targetGroupId
        copy.targetProjectId = schedule.targetProjectId
        copy.runMode = schedule.runMode
        copy.cadenceKind = schedule.cadenceKind
        copy.intervalHours = schedule.intervalHours
        copy.localHour = schedule.localHour
        copy.localMinute = schedule.localMinute
        copy.daysOfWeek = schedule.daysOfWeek
        copy.runWhenAppClosed = schedule.runWhenAppClosed
        copy.usesAutonomousMode = schedule.usesAutonomousMode
        modelContext.insert(copy)
        try? modelContext.save()
        appState.syncScheduledMission(copy)
    }

    private func duplicateAndEditGlobalSchedule(_ schedule: ScheduledMission) {
        let copy = ScheduledMission(
            name: "\(schedule.name) Copy",
            targetKind: schedule.targetKind,
            projectDirectory: schedule.projectDirectory,
            promptTemplate: schedule.promptTemplate
        )
        copy.projectId = schedule.projectId
        copy.isEnabled = false
        copy.targetAgentId = schedule.targetAgentId
        copy.targetGroupId = schedule.targetGroupId
        copy.targetProjectId = schedule.targetProjectId
        copy.runMode = schedule.runMode
        copy.cadenceKind = schedule.cadenceKind
        copy.intervalHours = schedule.intervalHours
        copy.localHour = schedule.localHour
        copy.localMinute = schedule.localMinute
        copy.daysOfWeek = schedule.daysOfWeek
        copy.runWhenAppClosed = schedule.runWhenAppClosed
        copy.usesAutonomousMode = schedule.usesAutonomousMode
        modelContext.insert(copy)
        try? modelContext.save()
        appState.syncScheduledMission(copy)
        openGlobalScheduleEditor(copy)
    }

    private func deleteGlobalSchedule(_ schedule: ScheduledMission) {
        appState.removeScheduledMission(schedule)
        modelContext.delete(schedule)
        try? modelContext.save()
    }

    @ViewBuilder
    private var pinnedSection: some View {
        let hasPinned = ulyssesAgent != nil || !residentAgents.isEmpty || !residentGroups.isEmpty || !cachedPinnedProjects.isEmpty
        if hasPinned {
            Section {
                if isPinnedSectionExpanded {
                    if let ulysses = ulyssesAgent {
                        agentSidebarRow(ulysses, isPinned: true)
                    }
                    ForEach(residentAgents) { agent in
                        agentSidebarRow(agent, isPinned: true)
                    }
                    ForEach(residentGroups) { group in
                        groupSidebarRow(group, isPinned: true)
                    }
                    ForEach(cachedPinnedProjects) { project in
                        projectRows(project)
                    }
                }
            } header: {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isPinnedSectionExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isPinnedSectionExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("Pinned")
                            .font(.headline.weight(.semibold))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sidebar.pinnedSection.header")
            }
            .stableXrayId("sidebar.pinnedSection")
        }
    }

    @ViewBuilder
    private var agentsSection: some View {
        Section {
            if isAgentsSectionExpanded {
                // Agents with conversation history — shown directly
                ForEach(nonResidentAgents) { agent in
                    agentSidebarRow(agent, isPinned: false)
                }

                // 3. Library hint for agents with no history
                let inLibraryCount = agents.filter { $0.isEnabled && !$0.isResident && !agentsWithConversations.contains($0.id) }.count
                if inLibraryCount > 0 {
                    Button {
                        showAgentBrowseSheet = true
                    } label: {
                        Text("\(inLibraryCount) more in library →")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("sidebar.agentsLibraryHint")
                }
            }
        } header: {
            agentsSectionHeader
        }
        .stableXrayId("sidebar.agentsSection")
    }

    @ViewBuilder
    private func agentSidebarRow(_ agent: Agent, isPinned: Bool) -> some View {
        AgentSidebarRowView(
            agent: agent,
            conversations: conversationsForAgent(agent),
            archivedConversations: archivedConversationsForAgent(agent),
            isExpanded: Binding(
                get: { expandedAgentIds.contains(agent.id) },
                set: { expanded in
                    if expanded { expandedAgentIds.insert(agent.id) }
                    else { expandedAgentIds.remove(agent.id) }
                }
            ),
            onNewChat: { startSession(with: agent) },
            onSelectConversation: { conv in
                windowState.selectedConversationId = conv.id
            },
            onSelectAgent: {
                selectOrCreateAgentChat(agent)
            },
            onRename: { conv in
                renameText = conv.topic ?? ""
                renamingConversation = conv
            },
            selectedConversationId: windowState.selectedConversationId,
            hasActiveSession: agentHasActiveSession(agent),
            onDeleteConversation: { conv in promptDelete(conv) },
            isPinned: isPinned,
            projects: projects,
            onNewSessionInProject: { project in startSession(with: agent, in: project) },
            onTogglePin: {
                agent.isResident.toggle()
                try? modelContext.save()
                rebuildAgentCaches()
            },
            onHideFromSidebar: {
                agent.showInSidebar = false
                try? modelContext.save()
                rebuildAgentCaches()
            },
            onScheduleMission: {
                agentScheduleDraft = ScheduledMissionDraft(
                    name: "\(agent.name) schedule",
                    targetKind: .agent,
                    projectDirectory: "",
                    promptTemplate: ""
                )
                agentScheduleDraft.targetAgentId = agent.id
                showingAgentScheduleEditor = true
            },
            onViewSessionHistory: {
                if expandedAgentIds.contains(agent.id) {
                    expandedAgentIds.remove(agent.id)
                } else {
                    expandedAgentIds.insert(agent.id)
                }
            },
            onCloseConversation: { conv in closeConversation(conv) },
            isArchivedExpanded: Binding(
                get: { expandedArchivedAgentIds.contains(agent.id) },
                set: { expanded in
                    if expanded { expandedArchivedAgentIds.insert(agent.id) }
                    else { expandedArchivedAgentIds.remove(agent.id) }
                }
            )
        )
    }

    // MARK: - Conversation Row

    private func conversationRow(_ convo: Conversation) -> some View {
        let isHovered = hoveredConversationId == convo.id
        let isSelected = windowState.selectedConversationId == convo.id
        let showsConversationMenu = isHovered || isSelected

        return HStack(spacing: 8) {
            if convo.isUnread {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 8, height: 8)
                    .stableXrayId("sidebar.unreadBadge.\(convo.id.uuidString)")
            }
            sidebarSymbolBadge(
                symbol: conversationIconDescriptor(convo).symbol,
                tint: conversationIconDescriptor(convo).color,
                size: 24,
                cornerRadius: 8
            )

            HStack(spacing: 4) {
                Text(convo.topic ?? "Untitled")
                    .lineLimit(1)
                    .font(convo.isUnread ? .callout.bold() : .callout)
                    .layoutPriority(1)

                Text("·")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)

                Text(relativeTime(convo.startedAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                if let preview = lastMessagePreview(convo) {
                    Text("·")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)

                    if let icon = preview.attachmentIcon {
                        Image(systemName: icon)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Text(preview.text)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsConversationMenu {
                Menu {
                    conversationMenuContent(convo)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .xrayId("sidebar.moreMenu.\(convo.id.uuidString)")
                .accessibilityLabel("More options for \(convo.topic ?? "this thread")")
            }
            ThreadActivityIndicator(conversation: convo)
            .xrayId("sidebar.activityIndicator.\(convo.id.uuidString)")
            if let result = appState.idleResults[convo.id.uuidString] {
                Image(systemName: result.status.icon)
                    .font(.system(size: 10))
                    .foregroundStyle(result.status.color)
                    .xrayId("sidebar.conversationRow.\(convo.id.uuidString).idleStatusIcon")
                    .accessibilityLabel(result.status.label)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05), lineWidth: 1)
        )
        .onHover { isHovering in
            hoveredConversationId = isHovering ? convo.id : nil
        }
        .xrayId("sidebar.conversationRow.\(convo.id.uuidString)")
        .contextMenu {
            conversationMenuContent(convo)
        }
    }

    @ViewBuilder
    private func conversationMenuContent(_ convo: Conversation) -> some View {
        Button {
            renameText = convo.topic ?? ""
            renamingConversation = convo
        } label: {
            Label("Rename\u{2026}", systemImage: "pencil")
        }
        .xrayId("sidebar.conversationContext.rename.\(convo.id.uuidString)")
        Button { togglePin(convo) } label: {
            Label(convo.isPinned ? "Unpin" : "Pin", systemImage: convo.isPinned ? "pin.slash" : "pin")
        }
        .xrayId("sidebar.conversationContext.pin.\(convo.id.uuidString)")
        Button { toggleUnread(convo) } label: {
            Label(convo.isUnread ? "Mark as Read" : "Mark as Unread",
                  systemImage: convo.isUnread ? "envelope.open" : "envelope.badge")
        }
        .xrayId("sidebar.conversationContext.unread.\(convo.id.uuidString)")
        if let project = projectForConversation(convo) {
            Button { openProjectInFinder(project) } label: {
                Label("Open Project Folder", systemImage: "folder")
            }
            .xrayId("sidebar.conversationContext.openProject.\(convo.id.uuidString)")
        }
        Divider()
        if convo.status == .active {
            Button { closeConversation(convo) } label: {
                Label("Close Session", systemImage: "stop.circle")
            }
            .xrayId("sidebar.conversationContext.close.\(convo.id.uuidString)")
        }
        if convo.isArchived {
            Button { unarchiveConversation(convo) } label: {
                Label("Unarchive", systemImage: "tray.and.arrow.up")
            }
            .xrayId("sidebar.conversationContext.unarchive.\(convo.id.uuidString)")
        } else {
            Button { archiveConversation(convo) } label: {
                Label("Archive", systemImage: "archivebox")
            }
            .xrayId("sidebar.conversationContext.archive.\(convo.id.uuidString)")
        }
        Divider()
        Button(role: .destructive) { promptDelete(convo) } label: {
            Label("Delete", systemImage: "trash")
        }
        .xrayId("sidebar.conversationContext.delete.\(convo.id.uuidString)")
    }

    // MARK: - Conversation Icon

    private func conversationIconDescriptor(_ convo: Conversation) -> (symbol: String, color: Color) {
        let hasUser = (convo.participants ?? []).contains { $0.type == .user }
        let agentCount = (convo.participants ?? []).filter {
            if case .agentSession = $0.type { return true }
            return false
        }.count
        let isChild = convo.parentConversationId != nil
        let isDelegation = SidebarConversationMetadata.isDelegationThread(convo)

        if let agent = convo.primarySession?.agent, hasUser {
            return (agent.icon, agentColor(agent.color))
        } else if isDelegation {
            return ("arrow.triangle.branch", .orange)
        } else if !hasUser && agentCount >= 2 {
            return ("arrow.left.arrow.right", .purple)
        } else if !hasUser && isChild {
            return ("bubble.left.and.bubble.right", .purple)
        } else if hasUser && agentCount > 1 {
            return ("bubble.left.and.bubble.right.fill", .teal)
        } else if hasUser {
            return ("bubble.left.and.bubble.right.fill", .blue)
        } else {
            return ("bubble.left.and.bubble.right", .secondary)
        }
    }

    // MARK: - Helpers

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func lastMessagePreview(_ convo: Conversation) -> (text: String, attachmentIcon: String?)? {
        SidebarConversationMetadata.lastMessagePreview(convo)
    }

    private func filteredConversations(_ convos: [Conversation]) -> [Conversation] {
        if searchText.isEmpty { return convos }
        return convos.filter { convo in
            (convo.topic ?? "").localizedCaseInsensitiveContains(searchText) ||
            (convo.participants ?? []).contains { $0.displayName.localizedCaseInsensitiveContains(searchText) }
        }
    }

    private func agentColor(_ color: String) -> Color {
        Color.fromAgentColor(color)
    }

    private func projectTint(_ project: Project) -> Color {
        agentColor(project.color)
    }

    private var sidebarPanelBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.thinMaterial)
    }

    private var sidebarPanelStroke: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
    }

    @ViewBuilder
    private func sidebarSymbolBadge(
        symbol: String,
        tint: Color,
        size: CGFloat,
        cornerRadius: CGFloat,
        emphasize: Bool = false
    ) -> some View {
        let backgroundOpacity = emphasize ? 0.18 : 0.12
        let strokeOpacity = emphasize ? 0.22 : 0.14

        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(backgroundOpacity), tint.opacity(backgroundOpacity * 0.45)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(tint.opacity(strokeOpacity), lineWidth: 1)
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
    }

    private func scheduleRuleLabel(_ schedule: ScheduledMission) -> String {
        if schedule.cadenceKind == .hourlyInterval {
            return "Hourly"
        }
        if !schedule.daysOfWeek.isEmpty {
            return "Weekly"
        }
        return "Daily"
    }

    // MARK: - Activity State

    private func agentHasActiveSession(_ agent: Agent, in project: Project? = nil) -> Bool {
        cachedActiveAgentIds.contains(agent.id)
    }

    private func groupHasActiveSession(_ group: AgentGroup, in project: Project? = nil) -> Bool {
        cachedActiveGroupIds.contains(group.id)
    }

    // MARK: - Agent Chat History

    private func inGlobalScope(_ convo: Conversation, project: Project?) -> Bool {
        if convo.threadKind == .scheduled { return project == nil }
        guard let p = project else { return convo.projectId == nil }
        return convo.projectId == p.id
    }

    private func conversationsForGroup(_ group: AgentGroup, in project: Project? = nil) -> [Conversation] {
        conversations.filter { $0.sourceGroupId == group.id && !$0.isArchived && inGlobalScope($0, project: project) }
    }

    private func archivedConversationsForGroup(_ group: AgentGroup, in project: Project? = nil) -> [Conversation] {
        conversations.filter { $0.sourceGroupId == group.id && $0.isArchived && inGlobalScope($0, project: project) }
    }

    private func conversationsForAgent(_ agent: Agent, in project: Project? = nil) -> [Conversation] {
        conversations.filter { conv in
            conversationToAgentIndex[conv.id] == agent.id
                && conv.sourceGroupId == nil
                && !conv.isArchived
                && inGlobalScope(conv, project: project)
        }
    }

    private func archivedConversationsForAgent(_ agent: Agent, in project: Project? = nil) -> [Conversation] {
        conversations.filter { conv in
            conversationToAgentIndex[conv.id] == agent.id
                && conv.sourceGroupId == nil
                && conv.isArchived
                && inGlobalScope(conv, project: project)
        }
    }

    private func expandForReveal(_ conversationId: UUID) {
        guard let convo = conversations.first(where: { $0.id == conversationId }) else { return }
        let isArchived = convo.isArchived

        if let groupId = convo.sourceGroupId {
            expandedGroupIds.insert(groupId)
            if isArchived { expandedArchivedGroupIds.insert(groupId) }
            return
        }

        if let agentId = conversationToAgentIndex[conversationId] {
            expandedAgentIds.insert(agentId)
            if isArchived { expandedArchivedAgentIds.insert(agentId) }
        }
    }

    private func schedulesForProject(_ project: Project) -> [ScheduledMission] {
        schedules.filter { $0.projectId == project.id }
    }

    private func conversationsForProject(_ project: Project) -> [Conversation] {
        conversations.filter { $0.projectId == project.id && $0.sourceGroupId == nil }
    }

    private func projectForConversation(_ convo: Conversation) -> Project? {
        guard let projectId = convo.projectId else { return nil }
        return projects.first(where: { $0.id == projectId })
    }

    // MARK: - Group Actions

    private func deleteGroup(_ group: AgentGroup) {
        modelContext.delete(group)
        try? modelContext.save()
    }

    // MARK: - Actions

    private func togglePin(_ convo: Conversation) {
        convo.isPinned.toggle()
        try? modelContext.save()
    }

    private func toggleProjectPin(_ project: Project) {
        project.isPinned.toggle()
        try? modelContext.save()
        rebuildProjectCache()
    }

    private func toggleUnread(_ convo: Conversation) {
        convo.isUnread.toggle()
        try? modelContext.save()
    }

    private func archiveConversation(_ convo: Conversation) {
        convo.isArchived = true
        convo.isPinned = false
        try? modelContext.save()
    }

    private func unarchiveConversation(_ convo: Conversation) {
        convo.isArchived = false
        try? modelContext.save()
    }

    private func closeConversation(_ convo: Conversation) {
        convo.status = .closed
        convo.closedAt = Date()
        let sessionKeys = (convo.sessions ?? []).map(\.id.uuidString)
        for session in (convo.sessions ?? []) {
            appState.sendToSidecar(.sessionPause(sessionId: session.id.uuidString))
            session.status = .paused
        }
        appState.clearSessionActivity(for: sessionKeys)
        try? modelContext.save()
    }

    private func promptDelete(_ convo: Conversation) {
        conversationToDelete = convo
        showDeleteConfirmation = true
    }

    private func duplicateConversation(_ convo: Conversation) {
        let newConvo = Conversation(
            topic: (convo.topic ?? "Untitled") + " (copy)",
            projectId: convo.projectId,
            threadKind: convo.threadKind
        )
        newConvo.routingMode = convo.routingMode
        let userParticipant = Participant(type: .user, displayName: "You")
        userParticipant.conversation = newConvo
        newConvo.participants = (newConvo.participants ?? []) + [userParticipant]

        for session in (convo.sessions ?? []) {
            guard let agent = session.agent else { continue }
            let newSession = Session(agent: agent, mode: session.mode)
            newSession.mission = session.mission
            newSession.workingDirectory = session.workingDirectory
            newConvo.sessions = (newConvo.sessions ?? []) + [newSession]
            newSession.conversations = [newConvo]

            let agentParticipant = Participant(
                type: .agentSession(sessionId: newSession.id),
                displayName: agent.name
            )
            agentParticipant.conversation = newConvo
            newConvo.participants = (newConvo.participants ?? []) + [agentParticipant]
            modelContext.insert(newSession)
        }

        modelContext.insert(newConvo)
        try? modelContext.save()
        windowState.selectedConversationId = newConvo.id
    }

    private func duplicateGroup(_ group: AgentGroup) {
        let copy = AgentGroup(
            name: group.name + " (copy)",
            groupDescription: group.groupDescription,
            icon: group.icon,
            color: group.color,
            groupInstruction: group.groupInstruction,
            defaultMission: group.defaultMission,
            agentIds: group.agentIds,
            sortOrder: group.sortOrder + 1
        )
        copy.autonomousCapable = group.autonomousCapable
        copy.autoReplyEnabled = group.autoReplyEnabled
        copy.coordinatorAgentId = group.coordinatorAgentId
        copy.agentRolesJSON = group.agentRolesJSON
        copy.workflowJSON = group.workflowJSON
        modelContext.insert(copy)
        try? modelContext.save()
    }

    private func selectConversation(_ convo: Conversation) {
        if let projectId = convo.projectId {
            windowState.selectProject(id: projectId, preserveSelection: true)
        }
        windowState.selectedGroupId = nil
        windowState.selectedConversationId = convo.id
        if convo.isUnread {
            convo.isUnread = false
            try? modelContext.save()
        }
    }

    private func selectOrCreateAgentChat(_ agent: Agent, in project: Project? = nil) {
        if let existing = conversationsForAgent(agent, in: project).first(where: { !$0.isArchived }) {
            windowState.selectedConversationId = existing.id
        } else {
            startSession(with: agent, in: project)
        }
    }

    private func selectOrCreateGroupChat(_ group: AgentGroup, in project: Project? = nil) {
        if let existing = conversationsForGroup(group, in: project).first(where: { !$0.isArchived }) {
            windowState.selectedConversationId = existing.id
        } else {
            // Only use project context when one was explicitly passed (group nested under a project).
            // Never inherit windowState — independent groups use their own home dir as project root.
            if let convoId = appState.startGroupChat(
                group: group,
                projectDirectory: project?.rootPath ?? "",
                projectId: project?.id,
                modelContext: modelContext
            ) {
                expandedGroupIds.insert(group.id)
                windowState.selectedConversationId = convoId
            }
        }
    }

    private func startSession(with agent: Agent, in project: Project? = nil) {
        // Only scope to a project when one was explicitly passed in; never inherit
        // windowState.selectedProjectId for agent-initiated sessions so the conversation
        // appears in the Agents sidebar section, not a project section.
        let targetProject = project
        let session = Session(agent: agent, mode: .interactive)
        if session.workingDirectory.isEmpty {
            if let project = targetProject {
                // Project context wins — agent works in the project root, not its home dir
                session.workingDirectory = (project.rootPath as NSString).expandingTildeInPath
            } else if let residentDir = agent.defaultWorkingDirectory, !residentDir.isEmpty {
                // No project — agent's home dir is its project root
                session.workingDirectory = (residentDir as NSString).expandingTildeInPath
            } else if !windowState.projectDirectory.isEmpty {
                session.workingDirectory = (windowState.projectDirectory as NSString).expandingTildeInPath
            }
        }
        let conversation = Conversation(
            topic: nil,
            sessions: [session],
            projectId: targetProject?.id,
            threadKind: .direct
        )
        let userParticipant = Participant(type: .user, displayName: "You")
        let agentParticipant = Participant(
            type: .agentSession(sessionId: session.id),
            displayName: agent.name
        )
        userParticipant.conversation = conversation
        agentParticipant.conversation = conversation
        conversation.participants = [userParticipant, agentParticipant]
        session.conversations = [conversation]

        modelContext.insert(session)
        modelContext.insert(conversation)
        // Show the UI immediately — defer blocking save and vault prep
        expandedAgentIds.insert(agent.id)
        windowState.selectedConversationId = conversation.id
        Task { @MainActor in
            try? modelContext.save()
            // Vault prep is independent of which directory won — a resident agent always
            // gets its memory vault initialised wherever it works.
            if let residentDir = agent.defaultWorkingDirectory, !residentDir.isEmpty {
                ResidentAgentSupport.prepareVaultForSession(
                    in: (residentDir as NSString).expandingTildeInPath,
                    agentName: agent.name
                )
            }
        }
    }

    private func createQuickChat(in project: Project) {
        let conversation = Conversation(
            topic: "New Thread",
            projectId: project.id,
            threadKind: .freeform
        )
        let userParticipant = Participant(type: .user, displayName: "You")
        userParticipant.conversation = conversation
        conversation.participants = (conversation.participants ?? []) + [userParticipant]

        modelContext.insert(conversation)
        // Show the UI immediately — defer blocking SQLite save
        expandedProjectIds.insert(project.id)
        windowState.selectProject(project, preserveSelection: true)
        windowState.selectedConversationId = conversation.id
        Task { @MainActor in try? modelContext.save() }
    }

    private func runProjectTemplate(_ template: PromptTemplate, in project: Project) {
        let conversation = Conversation(
            topic: template.name,
            projectId: project.id,
            threadKind: .freeform
        )
        let userParticipant = Participant(type: .user, displayName: "You")
        userParticipant.conversation = conversation
        conversation.participants = (conversation.participants ?? []) + [userParticipant]

        modelContext.insert(conversation)
        try? modelContext.save()

        expandedProjectIds.insert(project.id)
        windowState.selectProject(project, preserveSelection: true)
        windowState.pendingTemplatePrompt = PendingTemplatePrompt(
            conversationId: conversation.id,
            text: template.prompt
        )
        windowState.selectedConversationId = conversation.id
    }

    private func toggleProjectExpansion(_ project: Project) {
        windowState.selectProject(project)
        if expandedProjectIds.contains(project.id) {
            expandedProjectIds.remove(project.id)
        } else {
            expandedProjectIds.insert(project.id)
        }
    }

    private func openProjectInFinder(_ project: Project) {
        let url = URL(fileURLWithPath: project.rootPath)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func beginRename(_ project: Project) {
        projectRenameText = project.name
        renamingProject = project
    }

    private func archiveThreads(in project: Project) {
        for conversation in conversationsForProject(project) where !conversation.isArchived {
            conversation.isArchived = true
        }
        try? modelContext.save()
    }

    private func removeProject(_ project: Project) {
        let projectConversations = conversationsForProject(project)
        let projectSchedules = schedulesForProject(project)
        let fallbackProject = sortedProjects.first(where: { $0.id != project.id })

        Task { @MainActor in
            for conversation in projectConversations where conversation.worktreePath != nil {
                await WorktreeManager.removeWorktree(for: conversation, projectDirectory: project.rootPath)
            }

            if projectConversations.contains(where: { $0.id == windowState.selectedConversationId }) {
                windowState.selectedConversationId = nil
            }

            if windowState.selectedProjectId == project.id {
                if let fallbackProject {
                    windowState.selectProject(fallbackProject)
                } else {
                    windowState.clearProjectSelection()
                }
            }

            appState.clearSessionActivity(
                for: projectConversations.flatMap { ($0.sessions ?? []).map(\.id.uuidString) }
            )

            for schedule in projectSchedules {
                modelContext.delete(schedule)
            }
            for conversation in projectConversations {
                modelContext.delete(conversation)
            }
            modelContext.delete(project)
            expandedProjectIds.remove(project.id)
            try? modelContext.save()
        }
    }

    private func addProjectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Project"
        panel.message = "Choose a project folder to add to the sidebar"

        if panel.runModal() == .OK, let url = panel.url {
            let project = ProjectRecords.upsertProject(at: url.path, in: modelContext)
            RecentDirectories.add(project.rootPath)
            InstanceConfig.userDefaults.set(project.rootPath, forKey: AppSettings.instanceWorkingDirectoryKey)
            expandedProjectIds.insert(project.id)
            windowState.selectProject(project)
        }
    }

    private func handleConversationSelectionChange(_ selectedId: UUID) {
        if let conv = conversations.first(where: { $0.id == selectedId }), let projectId = conv.projectId {
            windowState.selectProject(id: projectId, preserveSelection: true)
            expandedProjectIds.insert(projectId)
        } else if let conv = conversations.first(where: { $0.id == selectedId }), conv.projectId == nil {
            if let agent = agents.first(where: { conversationsForAgent($0).contains { $0.id == selectedId } }) {
                expandedAgentIds.insert(agent.id)
            } else if let group = groups.first(where: { conversationsForGroup($0).contains { $0.id == selectedId } }) {
                expandedGroupIds.insert(group.id)
            }
        }
    }
}

// MARK: - Add Resident Sheet

/// Standalone sheet with its own @Query. The presenting view must pass `.modelContainer(modelContext.container)`
/// on the sheet content so @Query gets the correct container on macOS (environment may not propagate otherwise).
private struct AddResidentSheet: View {
    @Query(sort: \Agent.name)
    private var allAgents: [Agent]

    private var nonResidents: [Agent] {
        allAgents.filter { $0.isEnabled && !$0.isResident }
    }

    @Environment(\.modelContext) private var ctx

    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            List(nonResidents) { agent in
                Button {
                    agent.isResident = true
                    // Auto-assign home folder if not already set
                    if agent.defaultWorkingDirectory == nil || agent.defaultWorkingDirectory!.isEmpty {
                        agent.defaultWorkingDirectory = Agent.defaultHomePath(for: agent.name)
                    }
                    let expanded = (agent.defaultWorkingDirectory! as NSString).expandingTildeInPath
                    ResidentAgentSupport.seedVaultIfNeeded(in: expanded, agentName: agent.name)
                    try? ctx.save()
                } label: {
                    HStack(spacing: 10) {
                        let tint = Color.fromAgentColor(agent.color)
                        ZStack {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(tint.opacity(0.12))
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(tint.opacity(0.14), lineWidth: 1)
                            Image(systemName: agent.icon)
                                .font(.system(size: 28 * 0.42, weight: .semibold))
                                .foregroundStyle(tint)
                        }
                        .frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(agent.name).font(.body)
                            if let dir = agent.defaultWorkingDirectory {
                                Text(dir).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer()
                        Image(systemName: "plus.circle").foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .accessibilityIdentifier("addResidentSheet.list")
            .navigationTitle("Add to Residents")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { onDone() }
                }
            }
            .overlay {
                if nonResidents.isEmpty {
                    ContentUnavailableView(
                        "All agents are Residents",
                        systemImage: "person.crop.circle.badge.checkmark"
                    )
                }
            }
        }
        .frame(minWidth: 400, minHeight: 400)
    }
}

// MARK: - Isolated Observer (avoids subscribing SidebarView body to sessionActivity)

/// Invisible view that observes `appState.sessionActivity` in isolation.
/// Changes to activity state only rebuild the cached sets via @Binding —
/// they do NOT invalidate the main SidebarView body.
private struct ActiveSessionObserver: View {
    @Environment(AppState.self) private var appState
    @Binding var activeAgentIds: Set<UUID>
    @Binding var activeGroupIds: Set<UUID>
    let sessionIdToAgentId: [UUID: UUID]
    let groups: [AgentGroup]

    @Query(sort: \Session.startedAt, order: .reverse) private var allSessions: [Session]
    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .onChange(of: appState.sessionActivity) { _, _ in
                debounceTask?.cancel()
                debounceTask = Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    rebuild()
                }
            }
            .onAppear { rebuild() }
    }

    private func rebuild() {
        var agentIds = Set<UUID>()
        var groupIds = Set<UUID>()
        let groupAgentSets = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, Set($0.agentIds)) })
        for session in allSessions {
            let key = session.id.uuidString
            guard appState.sessionActivity[key]?.isActive == true else { continue }
            guard let agentId = sessionIdToAgentId[session.id] else { continue }
            agentIds.insert(agentId)
            for (gid, memberIds) in groupAgentSets where memberIds.contains(agentId) {
                groupIds.insert(gid)
            }
        }
        if agentIds != activeAgentIds { activeAgentIds = agentIds }
        if groupIds != activeGroupIds { activeGroupIds = groupIds }
    }
}

