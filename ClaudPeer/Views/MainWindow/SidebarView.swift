import SwiftUI
import SwiftData

struct SidebarView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Conversation.startedAt, order: .reverse) private var conversations: [Conversation]
    @Query(sort: \Agent.name) private var agents: [Agent]
    @Query(sort: \AgentGroup.sortOrder) private var groups: [AgentGroup]
    @Query(sort: \Session.startedAt, order: .reverse) private var allSessions: [Session]
    @State private var searchText = ""
    @State private var expandedAgentIds: Set<UUID> = []
    @State private var expandedGroupIds: Set<UUID> = []
    @State private var editingGroup: AgentGroup?
    @State private var autonomousGroup: AgentGroup?
    @State private var showAutoAssemble = false
    @State private var renamingConversation: Conversation?
    @State private var renameText = ""
    @State private var conversationToDelete: Conversation?
    @State private var showDeleteConfirmation = false
    @State private var showCatalog = false
    @State private var isArchivedExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $appState.selectedConversationId) {
                if conversations.isEmpty {
                    emptyState
                } else {
                    pinnedSection
                    activeSection
                    recentSection
                    archivedSection
                }
                groupsSection
                agentsSection
            }
            .listStyle(.sidebar)
            .searchable(text: $searchText, prompt: "Search conversations...")
            .xrayId("sidebar.conversationList")

            Divider()

            sidebarBottomBar
        }
        .frame(minWidth: 220)
        .sheet(isPresented: $showCatalog) {
            CatalogBrowserView()
                .frame(minWidth: 700, minHeight: 550)
        }
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
        .alert("Delete Conversation?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let convo = conversationToDelete {
                    if appState.selectedConversationId == convo.id {
                        appState.selectedConversationId = nil
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
    }

    // MARK: - Bottom Bar

    private var sidebarBottomBar: some View {
        HStack(spacing: 0) {
            Button {
                showCatalog = true
            } label: {
                Label("Catalog", systemImage: "square.grid.2x2")
                    .font(.caption)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .help("Browse catalog")
            .xrayId("sidebar.catalogButton")

            Divider()
                .frame(height: 16)

            Button {
                appState.showAgentLibrary = true
            } label: {
                Label("Agents", systemImage: "cpu")
                    .font(.caption)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .help("Agent library")
            .xrayId("sidebar.agentsButton")

            Divider()
                .frame(height: 16)

            Button {
                showAutoAssemble = true
            } label: {
                Image(systemName: "wand.and.stars")
                    .font(.caption)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .help("Auto-assemble team")
            .xrayId("sidebar.autoAssembleButton")

            Divider()
                .frame(height: 16)

            Button {
                appState.showNewSessionSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.caption)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .help("New session")
            .xrayId("sidebar.newSessionButton")
        }
        .padding(.vertical, 6)
        .background(.bar)
        .xrayId("sidebar.bottomBar")
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
                Text("No conversations yet")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Start chatting with an agent or create a freeform chat.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                Button {
                    appState.showNewSessionSheet = true
                } label: {
                    Label("New Session", systemImage: "plus.bubble")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help("Start a new session")
                .xrayId("sidebar.emptyState.newSessionButton")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    // MARK: - Pinned Section

    @ViewBuilder
    private var pinnedSection: some View {
        let pinned = rootConversations.filter { $0.isPinned && !$0.isArchived }
        if !pinned.isEmpty {
            Section("Pinned") {
                ForEach(filteredConversations(pinned)) { convo in
                    conversationTreeNode(convo, pinAction: "Unpin")
                }
            }
        }
    }

    // MARK: - Active Section

    @ViewBuilder
    private var activeSection: some View {
        let active = rootConversations.filter { $0.status == .active && !$0.isPinned && !$0.isArchived }
        if !active.isEmpty {
            Section("Active") {
                ForEach(filteredConversations(active)) { convo in
                    conversationTreeNode(convo, pinAction: "Pin")
                }
            }
        }
    }

    // MARK: - Recent Section

    @ViewBuilder
    private var recentSection: some View {
        let closed = rootConversations.filter { $0.status == .closed && !$0.isPinned && !$0.isArchived }
        if !closed.isEmpty {
            Section("Recent") {
                ForEach(filteredConversations(Array(closed.prefix(20)))) { convo in
                    conversationTreeNode(convo, pinAction: "Pin")
                }
            }
        }
    }

    // MARK: - Archived Section

    @ViewBuilder
    private var archivedSection: some View {
        let archived = rootConversations.filter { $0.isArchived }
        let visible = filteredConversations(archived)
        if !visible.isEmpty {
            Section {
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { isArchivedExpanded || !searchText.isEmpty },
                        set: { isArchivedExpanded = $0 }
                    )
                ) {
                    ForEach(visible) { convo in
                        conversationRow(convo)
                            .tag(convo.id)
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
                } label: {
                    Label("Archived (\(visible.count))", systemImage: "archivebox")
                        .foregroundStyle(.secondary)
                }
                .xrayId("sidebar.archivedSection")
            }
        }
    }

    // MARK: - Tree helpers

    private var rootConversations: [Conversation] {
        conversations.filter { $0.parentConversationId == nil }
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
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) { promptDelete(convo) } label: {
                    Label("Delete", systemImage: "trash")
                }
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
                        appState.startGroupChat(group: group, modelContext: modelContext)
                    },
                    onNewAutonomousChat: group.autonomousCapable ? {
                        autonomousGroup = group
                    } : nil,
                    onSelectConversation: { conv in
                        appState.selectedConversationId = conv.id
                    },
                    onSelectGroup: {
                        appState.pendingGroupId = group.id
                    },
                    onEdit: { editingGroup = group },
                    onDuplicate: { duplicateGroup(group) }
                )
                .contextMenu {
                    Button("Start Chat") {
                        appState.startGroupChat(group: group, modelContext: modelContext)
                    }
                    Button("Edit") { editingGroup = group }
                    Button("Duplicate") { duplicateGroup(group) }
                    Divider()
                    Button("Delete", role: .destructive) { deleteGroup(group) }
                }
            }
        } header: {
            HStack {
                Text("Groups")
                Spacer()
                Button {
                    appState.showGroupLibrary = true
                } label: {
                    Image(systemName: "plus")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sidebar.groupsAddButton")
            }
        }
        .accessibilityIdentifier("sidebar.groupsSection")
    }

    // MARK: - Agents Section

    @ViewBuilder
    private var agentsSection: some View {
        Section("Agents") {
            ForEach(agents.filter { $0.isEnabled }) { agent in
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
                        appState.selectedConversationId = conv.id
                    },
                    onSelectAgent: {
                        appState.pendingAgentId = agent.id
                    }
                )
                .contextMenu {
                    Button("Start Session") {
                        startSession(with: agent)
                    }
                    .xrayId("sidebar.agentRow.startSession.\(agent.id.uuidString)")
                }
            }
        }
    }

    // MARK: - Conversation Row

    private func conversationRow(_ convo: Conversation) -> some View {
        let activity = appState.conversationActivity(for: convo)
        return HStack(spacing: 8) {
            conversationIcon(convo)
            VStack(alignment: .leading, spacing: 2) {
                Text(convo.topic ?? "Untitled")
                    .lineLimit(1)
                    .font(.callout)
                HStack(spacing: 4) {
                    Text(relativeTime(convo.startedAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if let preview = lastMessagePreview(convo) {
                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        if let icon = preview.attachmentIcon {
                            Image(systemName: icon)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(preview.text)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                if case .working(let count) = activity.aggregate {
                    Text(count == 1 ? "Agent working\u{2026}" : "\(count) agents working\u{2026}")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                        .lineLimit(1)
                }
            }
            Spacer()
            SidebarActivityIndicator(
                summary: activity,
                conversationStatus: convo.status
            )
            .xrayId("sidebar.activityIndicator.\(convo.id.uuidString)")
        }
        .xrayId("sidebar.conversationRow.\(convo.id.uuidString)")
        .contextMenu {
            Button {
                renameText = convo.topic ?? ""
                renamingConversation = convo
            } label: {
                Label("Rename...", systemImage: "pencil")
            }
            Button { togglePin(convo) } label: {
                Label(convo.isPinned ? "Unpin" : "Pin", systemImage: convo.isPinned ? "pin.slash" : "pin")
            }
            Divider()
            if convo.status == .active {
                Button { closeConversation(convo) } label: {
                    Label("Close Session", systemImage: "stop.circle")
                }
            }
            Button { duplicateConversation(convo) } label: {
                Label("Duplicate", systemImage: "doc.on.doc")
            }
            if convo.isArchived {
                Button { unarchiveConversation(convo) } label: {
                    Label("Unarchive", systemImage: "tray.and.arrow.up")
                }
            } else {
                Button { archiveConversation(convo) } label: {
                    Label("Archive", systemImage: "archivebox")
                }
            }
            Divider()
            Button(role: .destructive) { promptDelete(convo) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Conversation Icon

    @ViewBuilder
    private func conversationIcon(_ convo: Conversation) -> some View {
        let hasUser = convo.participants.contains { $0.type == .user }
        let agentCount = convo.participants.filter {
            if case .agentSession = $0.type { return true }
            return false
        }.count
        let isChild = convo.parentConversationId != nil
        let isDelegation = convo.messages.contains { $0.type == .delegation }

        if let agent = convo.primarySession?.agent, hasUser {
            Image(systemName: agent.icon)
                .foregroundStyle(agentColor(agent.color))
                .font(.caption)
        } else if isDelegation {
            Image(systemName: "arrow.triangle.branch")
                .foregroundStyle(.orange)
                .font(.caption)
        } else if !hasUser && agentCount >= 2 {
            Image(systemName: "arrow.left.arrow.right")
                .foregroundStyle(.purple)
                .font(.caption)
        } else if !hasUser && isChild {
            Image(systemName: "bubble.left.and.bubble.right")
                .foregroundStyle(.purple)
                .font(.caption)
        } else if hasUser && agentCount > 1 {
            Image(systemName: "person.3.fill")
                .foregroundStyle(.blue)
                .font(.caption)
        } else if hasUser {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .foregroundStyle(.blue)
                .font(.caption)
        } else {
            Image(systemName: "bubble.left.and.bubble.right")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    // MARK: - Helpers

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func lastMessagePreview(_ convo: Conversation) -> (text: String, attachmentIcon: String?)? {
        let chatMessages = convo.messages
            .filter { $0.type == .chat }
            .sorted { $0.timestamp < $1.timestamp }
        guard let last = chatMessages.last else { return nil }
        let attachments = last.attachments
        let text = last.text.trimmingCharacters(in: .whitespacesAndNewlines)

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

    private func policyBadge(_ policy: InstancePolicy) -> String {
        switch policy {
        case .singleton: return "1"
        case .pool(let max): return "\(max)"
        case .spawn: return ""
        }
    }

    // MARK: - Agent Chat History

    private func conversationsForGroup(_ group: AgentGroup) -> [Conversation] {
        conversations.filter { $0.sourceGroupId == group.id }
    }

    private func conversationsForAgent(_ agent: Agent) -> [Conversation] {
        var seen = Set<UUID>()
        return allSessions
            .filter { $0.agent?.id == agent.id }
            .compactMap { $0.conversations.first }
            .filter { seen.insert($0.id).inserted }
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
        let newConvo = Conversation(topic: (convo.topic ?? "Untitled") + " (copy)")
        let userParticipant = Participant(type: .user, displayName: "You")
        userParticipant.conversation = newConvo
        newConvo.participants.append(userParticipant)

        for session in convo.sessions {
            guard let agent = session.agent else { continue }
            let newSession = Session(agent: agent, mode: session.mode)
            newSession.mission = session.mission
            newSession.workingDirectory = session.workingDirectory
            newSession.workspaceType = session.workspaceType
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
        appState.selectedConversationId = newConvo.id
    }

    private func startSession(with agent: Agent) {
        let session = Session(agent: agent, mode: .interactive)
        let conversation = Conversation(topic: agent.name, sessions: [session])
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
        appState.selectedConversationId = conversation.id
    }
}
