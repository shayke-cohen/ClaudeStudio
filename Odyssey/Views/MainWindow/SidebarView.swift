import SwiftUI
import SwiftData
import AppKit

enum SidebarBottomBarItem: String, CaseIterable, Identifiable {
    case catalog = "Discover"
    case workshop = "Workshop"
    case schedules = "Schedules"
    case agents = "Agents"
    case autoAssemble = "Auto-assemble"
    case newSession = "New session"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .catalog: "square.grid.2x2"
        case .workshop: "wrench.and.screwdriver"
        case .schedules: "clock.badge"
        case .agents: "cpu"
        case .autoAssemble: "wand.and.stars"
        case .newSession: "plus"
        }
    }

    var helpText: String {
        switch self {
        case .catalog: "Open discover"
        case .workshop: "Entity workshop (⌘⇧W)"
        case .schedules: "Scheduled missions (⌘⇧S)"
        case .agents: "Agent library"
        case .autoAssemble: "Auto-assemble team"
        case .newSession: "New session"
        }
    }

    var xrayId: String {
        switch self {
        case .catalog: "sidebar.catalogButton"
        case .workshop: "sidebar.workshopButton"
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
        case .catalog, .workshop, .schedules, .agents: true
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
        let latestMessage = convo.messages
            .sorted { $0.timestamp < $1.timestamp }
            .last
        guard let latestMessage else { return nil }

        let attachments = latestMessage.attachments
        let text = latestMessage.text.trimmingCharacters(in: .whitespacesAndNewlines)

        let icon: String? = {
            guard !attachments.isEmpty else { return nil }
            let hasImages = attachments.contains { $0.isImage }
            let hasDocs = attachments.contains { $0.isDocument }
            if hasImages && hasDocs { return "paperclip" }
            if hasDocs { return "doc.text" }
            return "photo"
        }()

        if text.isEmpty && !attachments.isEmpty {
            let count = attachments.count
            let hasImages = attachments.contains { $0.isImage }
            let hasDocs = attachments.contains { $0.isDocument }
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

struct SidebarView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(WindowState.self) private var windowState: WindowState
    @Environment(\.modelContext) private var modelContext
    @AppStorage(FeatureFlags.showAdvancedKey, store: AppSettings.store) private var masterFlag = false
    @AppStorage(FeatureFlags.workshopKey, store: AppSettings.store) private var workshopFlag = false
    @AppStorage(FeatureFlags.autoAssembleKey, store: AppSettings.store) private var autoAssembleFlag = false
    @AppStorage(FeatureFlags.autonomousMissionsKey, store: AppSettings.store) private var autonomousMissionsFlag = false
    @AppStorage("sidebar.showArchivedProjectSection") private var showsArchivedProjectSection = false
    @AppStorage("sidebar.showProjectTasksSection") private var showsProjectTasksSection = false
    @AppStorage("sidebar.showProjectSchedulesSection") private var showsProjectSchedulesSection = false
    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]
    @Query(sort: \Conversation.startedAt, order: .reverse) private var conversations: [Conversation]
    @Query(sort: \Agent.name) private var agents: [Agent]
    @Query(sort: \AgentGroup.sortOrder) private var groups: [AgentGroup]
    @Query(sort: \Session.startedAt, order: .reverse) private var allSessions: [Session]
    @Query(sort: \TaskItem.createdAt, order: .reverse) private var taskItems: [TaskItem]
    @Query(sort: \ScheduledMission.updatedAt, order: .reverse) private var schedules: [ScheduledMission]
    @State private var searchText = ""
    @State private var isTasksExpanded = true
    @State private var isCompletedTasksExpanded = false
    @State private var showTaskCreation = false
    @State private var editingTask: TaskItem?
    @State private var expandedAgentIds: Set<UUID> = []
    @State private var expandedGroupIds: Set<UUID> = []
    @State private var editingGroup: AgentGroup?
    @State private var autonomousGroup: AgentGroup?
    @State private var showAutoAssemble = false
    @State private var renamingConversation: Conversation?
    @State private var renameText = ""
    @State private var renamingProject: Project?
    @State private var projectRenameText = ""
    @State private var conversationToDelete: Conversation?
    @State private var showDeleteConfirmation = false
    @State private var projectToArchiveThreads: Project?
    @State private var projectToRemove: Project?
    @State private var isPinnedExpanded = true
    @State private var isActiveExpanded = true
    @State private var isHistoryExpanded = false
    @State private var isArchivedExpanded = false
    @State private var hoveredProjectId: UUID?
    @State private var hoveredConversationId: UUID?
    @State private var expandedProjectIds: Set<UUID> = []
    @State private var expandedResidentIds: Set<UUID> = []
    @State private var isResidentActiveExpanded = true
    @State private var isResidentHistoryExpanded = false
    @AppStorage("sidebar.residentsExpanded") private var isResidentsSectionExpanded: Bool = true
    @AppStorage("sidebar.nonResidentAgentsExpanded") private var isNonResidentAgentsExpanded: Bool = false
    @AppStorage("sidebar.projectsExpanded") private var isProjectsSectionExpanded: Bool = true

    private var workshopEnabled: Bool { FeatureFlags.isEnabled(FeatureFlags.workshopKey) || (masterFlag && workshopFlag) }
    private var autoAssembleEnabled: Bool { FeatureFlags.isEnabled(FeatureFlags.autoAssembleKey) || (masterFlag && autoAssembleFlag) }
    private var autonomousMissionsEnabled: Bool { FeatureFlags.isEnabled(FeatureFlags.autonomousMissionsKey) || (masterFlag && autonomousMissionsFlag) }

    var body: some View {
        @Bindable var ws = windowState
        List {
            utilitySection

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
        .searchable(text: $searchText, prompt: "Search threads…")
        .xrayId("sidebar.conversationList")
        .onAppear {
            if let selectedProjectId = windowState.selectedProjectId {
                expandedProjectIds.insert(selectedProjectId)
            }
        }
        .onChange(of: windowState.selectedConversationId) { _, newValue in
            guard let selectedId = newValue else { return }
            if let selectedConversation = conversations.first(where: { $0.id == selectedId }),
               let projectId = selectedConversation.projectId {
                windowState.selectProject(id: projectId, preserveSelection: true)
                expandedProjectIds.insert(projectId)
            } else if let task = taskItems.first(where: { $0.id == selectedId }) {
                if let convId = task.conversationId {
                    DispatchQueue.main.async {
                        windowState.selectedConversationId = convId
                    }
                } else {
                    DispatchQueue.main.async {
                        windowState.selectedConversationId = nil
                        editingTask = task
                    }
                }
            }
        }
        .frame(minWidth: 240)
        .sheet(item: $editingGroup) { group in
            GroupEditorView(group: group)
        }
        .sheet(item: $autonomousGroup) { group in
            AutonomousMissionSheet(group: group)
                .environmentObject(appState)
        }
        .sheet(isPresented: $showAutoAssemble) {
            AutoAssembleSheet()
                .environmentObject(appState)
        }
        .sheet(isPresented: $showTaskCreation) {
            TaskCreationSheet()
                .environmentObject(appState)
        }
        .sheet(item: $editingTask) { task in
            TaskEditSheet(task: task)
                .environmentObject(appState)
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
                    appState.clearSessionActivity(for: convo.sessions.map(\.id.uuidString))
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
    }

    private var sortedProjects: [Project] {
        projects.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned && !rhs.isPinned
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private var residentAgents: [Agent] {
        agents.filter { $0.isEnabled && $0.isResident }
            .sorted { $0.name < $1.name }
    }

    private var nonResidentAgents: [Agent] {
        agents.filter { $0.isEnabled && !$0.isResident }
            .sorted { $0.name < $1.name }
    }

    // MARK: - Global Utilities

    private var utilitySection: some View {
        Section {
            Menu {
                Button {
                    windowState.showNewSessionSheet = true
                } label: {
                    Label("New Thread", systemImage: "plus.bubble")
                }
                .keyboardShortcut("n", modifiers: .command)

                Button {
                    windowState.showNewGroupThreadSheet = true
                } label: {
                    Label("Group Thread", systemImage: "bubble.left.and.bubble.right.fill")
                }
                .keyboardShortcut("n", modifiers: [.command, .option])

                Button {
                    createQuickChatFromSidebar()
                } label: {
                    Label("Quick Chat", systemImage: "plus.message")
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .medium))
                        .frame(width: 18, height: 18)
                        .foregroundStyle(.primary)

                    Text("New")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .modifier(SidebarChromeButtonModifier(tint: .accentColor))
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("Create a new thread, group thread, or quick chat")
            .xrayId("sidebar.utility.newMenu")
            .accessibilityLabel("New")

            Button {
                windowState.openLibrary()
            } label: {
                Label("Library", systemImage: "books.vertical")
            }
            .buttonStyle(.plain)
            .appXrayTapProxy(id: "sidebar.utility.library") {
                windowState.openLibrary()
            }

            Button {
                addProjectFolder()
            } label: {
                Label("Add Project", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.plain)
            .appXrayTapProxy(id: "sidebar.utility.addProject") {
                addProjectFolder()
            }
        }
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

    // MARK: - Resident Agents

    private var residentAgentsHeader: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isResidentsSectionExpanded.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isResidentsSectionExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Residents")
                    .font(.headline.weight(.semibold))
            }
        }
        .buttonStyle(.plain)
        .xrayId("sidebar.residentAgents.header")
    }

    private var addResidentSheet: some View {
        AddResidentSheet(onDone: { appState.showAddResidentSheet = false })
    }

    @ViewBuilder
    private func residentRows(_ agent: Agent) -> some View {
        residentAgentHeaderRow(agent)
        if expandedResidentIds.contains(agent.id) {
            residentChatRows(agent)
        }
    }

    private func residentAgentHeaderRow(_ agent: Agent) -> some View {
        let isExpanded = expandedResidentIds.contains(agent.id)
        let hasActive = agentHasActiveSession(agent)
        let hasPastChats = !conversationsForAgent(agent).isEmpty
        let tint = Color.fromAgentColor(agent.color)

        return HStack(spacing: 8) {
            sidebarSymbolBadge(symbol: agent.icon, tint: tint, size: 32, cornerRadius: 11)
            Text(agent.name)
                .font(.headline.weight(.medium))
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 8)
            Circle()
                .fill(hasActive ? Color.green : (hasPastChats ? Color.secondary.opacity(0.5) : Color.secondary.opacity(0.2)))
                .frame(width: 7, height: 7)
            Button {
                startResidentSession(with: agent)
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 22, height: 22)
            }
            .modifier(SidebarChromeButtonModifier(tint: tint))
            .buttonStyle(.plain)
            .help("New chat with \(agent.name)")
            .accessibilityLabel("New chat with \(agent.name)")
            .accessibilityIdentifier("resident.\(agent.name.lowercased()).newChat")
            .appXrayTapProxy(id: "resident.\(agent.name.lowercased()).newChat") {
                startResidentSession(with: agent)
            }
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 12)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if expandedResidentIds.contains(agent.id) {
                expandedResidentIds.remove(agent.id)
            } else {
                expandedResidentIds.insert(agent.id)
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .contextMenu {
            Button("New Chat") { startResidentSession(with: agent) }
            Divider()
            Button("Edit Agent") { windowState.openLibrary(.build, buildSection: .agents) }
            Divider()
            Button("Remove from Residents", role: .destructive) {
                agent.isResident = false
                try? modelContext.save()
            }
        }
        .xrayId("sidebar.residentAgentRow.\(agent.id.uuidString)")
    }

    @ViewBuilder
    private func residentChatRows(_ agent: Agent) -> some View {
        let allConvos = conversationsForAgent(agent)
            .filter { !$0.isArchived }
            .sorted { $0.startedAt > $1.startedAt }
        let activeConvos = filteredConversations(Array(allConvos.prefix(5)))
        let historyConvos = filteredConversations(Array(allConvos.dropFirst(5)))

        if allConvos.isEmpty {
            residentIndentedRow {
                Text("No chats yet")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        } else {
            residentChatBucket(
                title: "Active (\(activeConvos.count))",
                symbol: "bolt.fill",
                isExpanded: Binding(
                    get: { isResidentActiveExpanded || !searchText.isEmpty },
                    set: { isResidentActiveExpanded = $0 }
                ),
                conversations: activeConvos
            )
            if !historyConvos.isEmpty {
                residentChatBucket(
                    title: "History (\(historyConvos.count))",
                    symbol: "clock.arrow.circlepath",
                    isExpanded: Binding(
                        get: { isResidentHistoryExpanded || !searchText.isEmpty },
                        set: { isResidentHistoryExpanded = $0 }
                    ),
                    conversations: historyConvos
                )
            }
        }
    }

    @ViewBuilder
    private func residentChatBucket(
        title: String,
        symbol: String,
        isExpanded: Binding<Bool>,
        conversations: [Conversation]
    ) -> some View {
        if !conversations.isEmpty {
            let expanded = isExpanded.wrappedValue || !searchText.isEmpty
            residentIndentedRow {
                Button {
                    if searchText.isEmpty { isExpanded.wrappedValue.toggle() }
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
            }
            if expanded {
                ForEach(conversations) { convo in
                    residentIndentedRow {
                        conversationRow(convo)
                            .tag(convo.id)
                            .contentShape(Rectangle())
                            .onTapGesture { selectConversation(convo) }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) { promptDelete(convo) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button { archiveConversation(convo) } label: {
                                    Label("Archive", systemImage: "archivebox")
                                }
                                .tint(.indigo)
                            }
                    }
                    .xrayId("sidebar.residentChatRow.\(convo.id.uuidString)")
                }
            }
        }
    }

    private func residentIndentedRow<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(.leading, 18)
            .padding(.trailing, 4)
            .padding(.bottom, 2)
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
            let catalog = SidebarBottomBarItem.catalog
            Button {
                windowState.openLibrary(.discover)
            } label: {
                Label(catalog.rawValue, systemImage: catalog.icon)
                    .fixedSize(horizontal: true, vertical: false)
                    .font(.caption)
                    .frame(minHeight: 24)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .help(catalog.helpText)
            .xrayId(catalog.xrayId)
            .accessibilityLabel(catalog.helpText)

            if workshopEnabled {
                Divider()
                    .frame(height: 16)

                let workshop = SidebarBottomBarItem.workshop
                Button {
                    windowState.showWorkshop = true
                } label: {
                    Label(workshop.rawValue, systemImage: workshop.icon)
                        .fixedSize(horizontal: true, vertical: false)
                        .font(.caption)
                        .frame(minHeight: 24)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .help(workshop.helpText)
                .xrayId(workshop.xrayId)
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .accessibilityLabel(workshop.helpText)
            }

            Divider()
                .frame(height: 16)

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
                windowState.openLibrary(.build, buildSection: .agents)
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
                windowState.showNewSessionSheet = true
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
        projectHeaderRow(project)

        if expandedProjectIds.contains(project.id) {
            projectThreadRows(project)
            if showsProjectTasksSection {
                projectIndentedRow {
                    projectTasksSection(project)
                }
            }
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
                size: 32,
                cornerRadius: 11,
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
                Label("Archive Threads", systemImage: "archivebox")
            }
            .tint(.indigo)

            Button(role: .destructive) {
                projectToRemove = project
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                createQuickChat(in: project)
            } label: {
                Label("New Thread", systemImage: "square.and.pencil")
            }
            .tint(tint)

            Button {
                openProjectInFinder(project)
            } label: {
                Label("Open in Finder", systemImage: "folder")
            }
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
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button { unarchiveConversation(convo) } label: {
                                Label("Unarchive", systemImage: "tray.and.arrow.up")
                            }
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

            Divider()

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
                showsProjectTasksSection.toggle()
            } label: {
                Label(
                    showsProjectTasksSection ? "Hide tasks section" : "Show tasks section",
                    systemImage: showsProjectTasksSection ? "eye.slash" : "checklist"
                )
            }
            .xrayId("sidebar.projectActions.toggleTasks.\(project.id.uuidString)")

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
    private func projectTasksSection(_ project: Project) -> some View {
        let tasks = tasksForProject(project)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("Tasks", systemImage: "checklist")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    windowState.selectProject(project)
                    showTaskCreation = true
                } label: {
                    Image(systemName: "plus")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .modifier(SidebarChromeButtonModifier(tint: projectTint(project)))
                .accessibilityLabel("Add task to \(project.name)")
                .xrayId("sidebar.projectTasksAdd.\(project.id.uuidString)")
            }

            if tasks.isEmpty {
                Text("No tasks")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(tasks.prefix(6)) { task in
                    taskRow(task)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(sidebarPanelBackground)
        .overlay(sidebarPanelStroke)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                    windowState.openLibrary()
                } label: {
                    Label("Open Library", systemImage: "books.vertical")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help("Browse reusable tools")
                .xrayId("sidebar.emptyState.newSessionButton")
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
                        Label("Delete", systemImage: "trash")
                    }
                    Button { archiveConversation(convo) } label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                    .tint(.indigo)
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button { togglePin(convo) } label: {
                        Label(pinAction, systemImage: convo.isPinned ? "pin.slash" : "pin")
                    }
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
                    Label("Delete", systemImage: "trash")
                }
                Button { archiveConversation(convo) } label: {
                    Label("Archive", systemImage: "archivebox")
                }
                .tint(.indigo)
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button { togglePin(convo) } label: {
                    Label(pinAction, systemImage: convo.isPinned ? "pin.slash" : "pin")
                }
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

    // MARK: - Tasks Section

    @ViewBuilder
    private var tasksSection: some View {
        let activeTasks = taskItems.filter { $0.status != .done && $0.status != .failed }
        let completedTasks = taskItems.filter { $0.status == .done || $0.status == .failed }

        if !taskItems.isEmpty || true { // Always show section for the [+] button
            Section {
                DisclosureGroup(isExpanded: $isTasksExpanded) {
                    // In Progress
                    ForEach(taskItems.filter { $0.status == .inProgress }) { task in
                        taskRow(task)
                    }
                    // Ready
                    ForEach(taskItems.filter { $0.status == .ready }) { task in
                        taskRow(task)
                    }
                    // Blocked
                    ForEach(taskItems.filter { $0.status == .blocked }) { task in
                        taskRow(task)
                    }
                    // Backlog
                    ForEach(taskItems.filter { $0.status == .backlog }) { task in
                        taskRow(task)
                    }
                    // Completed (foldable)
                    if !completedTasks.isEmpty {
                        DisclosureGroup(isExpanded: $isCompletedTasksExpanded) {
                            ForEach(completedTasks) { task in
                                taskRow(task)
                            }
                        } label: {
                            Text("Completed (\(completedTasks.count))")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                } label: {
                    HStack {
                        Label("Task Board (\(activeTasks.count))", systemImage: "checklist")
                        Spacer()
                        Button {
                            showTaskCreation = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.caption)
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut("t", modifiers: [.command, .shift])
                        .xrayId("sidebar.tasksAddButton")
                        .accessibilityLabel("Add task")
                        .contentShape(Rectangle())
                    }
                }
            }
            .stableXrayId("sidebar.tasksSection")
        }
    }

    @ViewBuilder
    private func taskRow(_ task: TaskItem) -> some View {
        HStack(spacing: 6) {
            sidebarSymbolBadge(
                symbol: taskStatusDescriptor(task.status).symbol,
                tint: taskStatusDescriptor(task.status).color,
                size: 22,
                cornerRadius: 7
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .lineLimit(1)
                    .font(.callout)
                HStack(spacing: 4) {
                    statusBadge(task.status)
                    priorityBadge(task.priority)
                    if let assignedAgentName = task.assignedAgentName
                        ?? task.assignedAgentId.flatMap({ agentId in agents.first(where: { $0.id == agentId })?.name }) {
                        Text(assignedAgentName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            if task.conversationId != nil {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        // Use task.id as tag — intercepted by onChange to redirect
        .tag(task.id)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
        .stableXrayId("sidebar.taskRow.\(task.id.uuidString)")
        .contextMenu { taskContextMenu(for: task) }
    }

    @ViewBuilder
    private func taskContextMenu(for task: TaskItem) -> some View {
        switch task.status {
        case .backlog:
            Button("Edit Task...") { editingTask = task }
                .xrayId("sidebar.taskContext.edit.\(task.id.uuidString)")
            Button("Mark as Ready") { appState.updateTaskStatus(task, status: .ready) }
                .xrayId("sidebar.taskContext.markReady.\(task.id.uuidString)")
            Button("Run with Orchestrator") {
                appState.runTaskWithOrchestrator(task, modelContext: modelContext, windowState: windowState)
            }
            .xrayId("sidebar.taskContext.runOrchestrator.\(task.id.uuidString)")
            Divider()
            Button("Delete", role: .destructive) {
                modelContext.delete(task)
                try? modelContext.save()
            }
            .xrayId("sidebar.taskContext.delete.\(task.id.uuidString)")
        case .ready:
            Button("Edit Task...") { editingTask = task }
                .xrayId("sidebar.taskContext.edit.\(task.id.uuidString)")
            Button("Run with Orchestrator") {
                appState.runTaskWithOrchestrator(task, modelContext: modelContext, windowState: windowState)
            }
            .xrayId("sidebar.taskContext.runOrchestrator.\(task.id.uuidString)")
            Button("Move to Backlog") { appState.updateTaskStatus(task, status: .backlog) }
                .xrayId("sidebar.taskContext.moveBacklog.\(task.id.uuidString)")
            Divider()
            Button("Delete", role: .destructive) {
                modelContext.delete(task)
                try? modelContext.save()
            }
            .xrayId("sidebar.taskContext.delete.\(task.id.uuidString)")
        case .inProgress:
            if task.conversationId != nil {
                Button("Go to Conversation") {
                    windowState.selectedConversationId = task.conversationId
                }
                .xrayId("sidebar.taskContext.goToConversation.\(task.id.uuidString)")
            }
            Button("Pause") { appState.updateTaskStatus(task, status: .blocked) }
                .xrayId("sidebar.taskContext.pause.\(task.id.uuidString)")
            Divider()
            Button("Cancel & Delete", role: .destructive) {
                modelContext.delete(task)
                try? modelContext.save()
            }
            .xrayId("sidebar.taskContext.cancelDelete.\(task.id.uuidString)")
        case .blocked:
            if task.conversationId != nil {
                Button("Go to Conversation") {
                    windowState.selectedConversationId = task.conversationId
                }
                .xrayId("sidebar.taskContext.goToConversation.\(task.id.uuidString)")
            }
            Button("Resume") { appState.updateTaskStatus(task, status: .inProgress) }
                .xrayId("sidebar.taskContext.resume.\(task.id.uuidString)")
            Divider()
            Button("Cancel & Delete", role: .destructive) {
                modelContext.delete(task)
                try? modelContext.save()
            }
            .xrayId("sidebar.taskContext.cancelDelete.\(task.id.uuidString)")
        case .done, .failed:
            if task.conversationId != nil {
                Button("Go to Conversation") {
                    windowState.selectedConversationId = task.conversationId
                }
                .xrayId("sidebar.taskContext.goToConversation.\(task.id.uuidString)")
            }
            Button("Retry") { appState.updateTaskStatus(task, status: .ready) }
                .xrayId("sidebar.taskContext.retry.\(task.id.uuidString)")
            Divider()
            Button("Delete", role: .destructive) {
                modelContext.delete(task)
                try? modelContext.save()
            }
            .xrayId("sidebar.taskContext.delete.\(task.id.uuidString)")
        }
    }

    @ViewBuilder
    private func taskStatusIcon(_ status: TaskStatus) -> some View {
        let descriptor = taskStatusDescriptor(status)
        Image(systemName: descriptor.symbol)
            .foregroundStyle(descriptor.color)
    }

    @ViewBuilder
    private func statusBadge(_ status: TaskStatus) -> some View {
        let (label, color): (String, Color) = switch status {
        case .backlog: ("Backlog", .gray)
        case .ready: ("Ready", .blue)
        case .inProgress: ("In Progress", .orange)
        case .done: ("Done", .green)
        case .failed: ("Failed", .red)
        case .blocked: ("Blocked", .yellow)
        }
        Text(label)
            .font(.caption2)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .foregroundStyle(color)
            .background(color.opacity(0.15))
            .cornerRadius(3)
    }

    private func priorityBadge(_ priority: TaskPriority) -> some View {
        Text(priority.rawValue.capitalized)
            .font(.caption2)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(priorityColor(priority).opacity(0.2))
            .cornerRadius(3)
    }

    private func priorityColor(_ priority: TaskPriority) -> Color {
        switch priority {
        case .low: .gray
        case .medium: .blue
        case .high: .orange
        case .critical: .red
        }
    }

    // MARK: - Groups Section

    @ViewBuilder
    private var groupsSection: some View {
        Section {
            ForEach(groups.filter { $0.isEnabled }) { group in
                GroupSidebarRowView(
                    group: group,
                    agentCount: group.agentIds.compactMap { id in agents.first { $0.id == id } }.count,
                    conversations: conversationsForGroup(group),
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
                            projectDirectory: windowState.projectDirectory,
                            projectId: windowState.selectedProjectId,
                            modelContext: modelContext
                        ) {
                            windowState.selectedConversationId = convoId
                        }
                    },
                    onNewAutonomousChat: (autonomousMissionsEnabled && group.autonomousCapable) ? {
                        autonomousGroup = group
                    } : nil,
                    onSelectConversation: { conv in
                        windowState.selectedConversationId = conv.id
                    },
                    onSelectGroup: {
                        selectOrCreateGroupChat(group)
                    },
                    onEdit: { editingGroup = group },
                    onDuplicate: { duplicateGroup(group) },
                    selectedConversationId: windowState.selectedConversationId,
                    hasActiveSession: groupHasActiveSession(group)
                )
                .contextMenu {
                    Button("Start Chat") {
                        if let convoId = appState.startGroupChat(
                            group: group,
                            projectDirectory: windowState.projectDirectory,
                            projectId: windowState.selectedProjectId,
                            modelContext: modelContext
                        ) {
                            windowState.selectedConversationId = convoId
                        }
                    }
                    .xrayId("sidebar.groupContext.startChat.\(group.id.uuidString)")
                    Button("Edit") { editingGroup = group }
                        .xrayId("sidebar.groupContext.edit.\(group.id.uuidString)")
                    Button("Duplicate") { duplicateGroup(group) }
                        .xrayId("sidebar.groupContext.duplicate.\(group.id.uuidString)")
                    Divider()
                    Button("Open in Configuration") {
                        windowState.openLibrary(.build)
                    }
                    .xrayId("sidebar.groupContext.openConfig.\(group.id.uuidString)")
                    Divider()
                    Button("Delete", role: .destructive) { deleteGroup(group) }
                        .xrayId("sidebar.groupContext.delete.\(group.id.uuidString)")
                }
            }
        } header: {
            HStack {
                Text("Groups")
                Spacer()
                Button {
                    windowState.openLibrary(.build, buildSection: .groups)
                } label: {
                    Image(systemName: "plus")
                        .font(.caption)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .xrayId("sidebar.groupsAddButton")
                .accessibilityLabel("Add group")
                .contentShape(Rectangle())
            }
        }
        .stableXrayId("sidebar.groupsSection")
    }

    // MARK: - Agents Section

    private var agentsSectionHeader: some View {
        HStack {
            Text("Agents")
            Spacer()
            Button {
                // Opens Configuration settings — stub: open agents library for now
                windowState.openLibrary(.build, buildSection: .agents)
            } label: {
                Image(systemName: "plus")
                    .font(.caption)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .xrayId("sidebar.agentsSection.addButton")
            .accessibilityLabel("Add agent")
            .contentShape(Rectangle())
        }
    }

    @ViewBuilder
    private var agentsSection: some View {
        Section {
            // 1. Resident (pinned) agents — always shown
            ForEach(residentAgents) { agent in
                agentSidebarRow(agent, isPinned: true)
            }

            // 2. Non-resident agents — collapsed under "N more agents..."
            if !nonResidentAgents.isEmpty {
                if isNonResidentAgentsExpanded {
                    ForEach(nonResidentAgents) { agent in
                        agentSidebarRow(agent, isPinned: false)
                    }
                }
                Button {
                    isNonResidentAgentsExpanded.toggle()
                } label: {
                    Label(
                        isNonResidentAgentsExpanded
                            ? "Show fewer"
                            : "\u{25B8} \(nonResidentAgents.count) more agent\(nonResidentAgents.count == 1 ? "" : "s")\u{2026}",
                        systemImage: isNonResidentAgentsExpanded ? "chevron.up" : "chevron.down"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .xrayId("sidebar.agents.showMore")
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
            selectedConversationId: windowState.selectedConversationId,
            hasActiveSession: agentHasActiveSession(agent)
        )
        .contextMenu {
            Button("New Session") {
                startSession(with: agent)
            }
            .xrayId("sidebar.agentRow.newSession.\(agent.id.uuidString)")
            Divider()
            Button(isPinned ? "Unpin from Sidebar" : "Pin to Sidebar") {
                agent.isResident = !isPinned
                try? modelContext.save()
            }
            .xrayId("sidebar.agentRow.togglePin.\(agent.id.uuidString)")
            Divider()
            Button("Open in Configuration") {
                windowState.openLibrary(.build)
            }
            .xrayId("sidebar.agentRow.openConfig.\(agent.id.uuidString)")
        }
    }

    // MARK: - Conversation Row

    private func conversationRow(_ convo: Conversation) -> some View {
        let activity = appState.conversationActivity(for: convo)
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
            SidebarActivityIndicator(
                summary: activity,
                conversationStatus: convo.status
            )
            .xrayId("sidebar.activityIndicator.\(convo.id.uuidString)")
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
        Button { duplicateConversation(convo) } label: {
            Label("Duplicate", systemImage: "doc.on.doc")
        }
        .xrayId("sidebar.conversationContext.duplicate.\(convo.id.uuidString)")
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
        let hasUser = convo.participants.contains { $0.type == .user }
        let agentCount = convo.participants.filter {
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
            convo.participants.contains { $0.displayName.localizedCaseInsensitiveContains(searchText) }
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

    private func taskStatusDescriptor(_ status: TaskStatus) -> (symbol: String, color: Color) {
        switch status {
        case .backlog:
            return ("circle.dotted", .gray)
        case .ready:
            return ("circle", .blue)
        case .inProgress:
            return ("circle.fill", .orange)
        case .done:
            return ("checkmark.circle.fill", .green)
        case .failed:
            return ("xmark.circle.fill", .red)
        case .blocked:
            return ("exclamationmark.circle.fill", .yellow)
        }
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
        for conversation in conversationsForAgent(agent, in: project) {
            for session in conversation.sessions where session.agent?.id == agent.id {
                let key = session.id.uuidString
                if appState.sessionActivity[key]?.isActive == true {
                    return true
                }
            }
        }
        return false
    }

    private func groupHasActiveSession(_ group: AgentGroup, in project: Project? = nil) -> Bool {
        for conversation in conversationsForGroup(group, in: project) {
            for session in conversation.sessions {
                let key = session.id.uuidString
                if appState.sessionActivity[key]?.isActive == true {
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Agent Chat History

    private func conversationsForGroup(_ group: AgentGroup, in project: Project? = nil) -> [Conversation] {
        conversations.filter {
            $0.sourceGroupId == group.id && (project == nil || $0.projectId == project?.id)
        }
    }

    private func conversationsForAgent(_ agent: Agent, in project: Project? = nil) -> [Conversation] {
        var seen = Set<UUID>()
        return allSessions
            .filter { $0.agent?.id == agent.id }
            .compactMap { $0.conversations.first }
            .filter { project == nil || $0.projectId == project?.id }
            .filter { seen.insert($0.id).inserted }
    }

    private func tasksForProject(_ project: Project) -> [TaskItem] {
        taskItems.filter { $0.projectId == project.id }
    }

    private func schedulesForProject(_ project: Project) -> [ScheduledMission] {
        schedules.filter { $0.projectId == project.id }
    }

    private func conversationsForProject(_ project: Project) -> [Conversation] {
        let agentSessionConversationIds = Set(
            allSessions
                .filter { $0.agent != nil }
                .flatMap { $0.conversations.map { $0.id } }
        )
        return conversations.filter {
            $0.projectId == project.id
            && $0.sourceGroupId == nil
            && !agentSessionConversationIds.contains($0.id)
        }
    }

    private func projectForConversation(_ convo: Conversation) -> Project? {
        guard let projectId = convo.projectId else { return nil }
        return projects.first(where: { $0.id == projectId })
    }

    // MARK: - Group Actions

    private func duplicateGroup(_ group: AgentGroup) {
        let copy = AgentGroup(
            name: "\(group.name) Copy",
            groupDescription: group.groupDescription,
            icon: group.icon,
            color: group.color,
            groupInstruction: group.groupInstruction,
            defaultMission: group.defaultMission,
            agentIds: group.agentIds,
            sortOrder: groups.count
        )
        modelContext.insert(copy)
        try? modelContext.save()
    }

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
        let sessionKeys = convo.sessions.map(\.id.uuidString)
        for session in convo.sessions {
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
        newConvo.participants.append(userParticipant)

        for session in convo.sessions {
            guard let agent = session.agent else { continue }
            let newSession = Session(agent: agent, mode: session.mode)
            newSession.mission = session.mission
            newSession.workingDirectory = session.workingDirectory
            newConvo.sessions.append(newSession)
            newSession.conversations = [newConvo]

            let agentParticipant = Participant(
                type: .agentSession(sessionId: newSession.id),
                displayName: agent.name
            )
            agentParticipant.conversation = newConvo
            newConvo.participants.append(agentParticipant)
            modelContext.insert(newSession)
        }

        modelContext.insert(newConvo)
        try? modelContext.save()
        windowState.selectedConversationId = newConvo.id
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
            let targetProject = project ?? sortedProjects.first(where: { $0.id == windowState.selectedProjectId })
            if let convoId = appState.startGroupChat(
                group: group,
                projectDirectory: targetProject?.rootPath ?? windowState.projectDirectory,
                projectId: targetProject?.id ?? windowState.selectedProjectId,
                modelContext: modelContext
            ) {
                windowState.selectedConversationId = convoId
            }
        }
    }

    private func startSession(with agent: Agent, in project: Project? = nil) {
        let targetProject = project ?? sortedProjects.first(where: { $0.id == windowState.selectedProjectId })
        let session = Session(agent: agent, mode: .interactive)
        if session.workingDirectory.isEmpty {
            // Resident agents (defaultWorkingDirectory set) run in their own home folder;
            // everyone else runs in the project root.
            let fallback = targetProject?.rootPath ?? windowState.projectDirectory
            if let residentDir = agent.defaultWorkingDirectory, !residentDir.isEmpty {
                session.workingDirectory = residentDir
            } else if !fallback.isEmpty {
                session.workingDirectory = fallback
            }
        }
        let conversation = Conversation(
            topic: agent.name,
            sessions: [session],
            projectId: targetProject?.id ?? windowState.selectedProjectId,
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
        try? modelContext.save()
        windowState.selectedConversationId = conversation.id
    }

    private func startResidentSession(with agent: Agent) {
        // Always ensure a home folder is set — never fall back to the project directory
        if agent.defaultWorkingDirectory == nil || agent.defaultWorkingDirectory!.isEmpty {
            agent.defaultWorkingDirectory = Agent.defaultHomePath(for: agent.name)
            try? modelContext.save()
        }
        let homeDir = agent.defaultWorkingDirectory!
        let expandedPath = (homeDir as NSString).expandingTildeInPath
        let session = Session(agent: agent, mode: .interactive)
        session.workingDirectory = expandedPath
        let conversation = Conversation(
            topic: agent.name,
            sessions: [session],
            projectId: nil,
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
        try? modelContext.save()

        expandedResidentIds.insert(agent.id)
        windowState.selectedConversationId = conversation.id

        ResidentAgentSupport.seedMemoryFileIfNeeded(in: expandedPath, agentName: agent.name)
    }

    private func createQuickChat(in project: Project) {
        let conversation = Conversation(
            topic: "New Thread",
            projectId: project.id,
            threadKind: .freeform
        )
        let userParticipant = Participant(type: .user, displayName: "You")
        userParticipant.conversation = conversation
        conversation.participants.append(userParticipant)

        modelContext.insert(conversation)
        try? modelContext.save()

        expandedProjectIds.insert(project.id)
        windowState.selectProject(project, preserveSelection: true)
        windowState.selectedConversationId = conversation.id
    }

    private func createQuickChatFromSidebar() {
        if let selectedProject = sortedProjects.first(where: { $0.id == windowState.selectedProjectId }) {
            createQuickChat(in: selectedProject)
            return
        }

        if let firstProject = sortedProjects.first {
            createQuickChat(in: firstProject)
            return
        }

        let conversation = Conversation(
            topic: "New Thread",
            projectId: nil,
            threadKind: .freeform
        )
        let userParticipant = Participant(type: .user, displayName: "You")
        userParticipant.conversation = conversation
        conversation.participants.append(userParticipant)

        modelContext.insert(conversation)
        try? modelContext.save()
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
        let projectTasks = tasksForProject(project)
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
                for: projectConversations.flatMap { $0.sessions.map(\.id.uuidString) }
            )

            for schedule in projectSchedules {
                modelContext.delete(schedule)
            }
            for task in projectTasks {
                modelContext.delete(task)
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
                    ResidentAgentSupport.seedMemoryFileIfNeeded(in: expanded, agentName: agent.name)
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

