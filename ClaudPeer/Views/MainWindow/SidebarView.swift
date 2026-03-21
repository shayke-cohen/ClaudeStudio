import SwiftUI
import SwiftData

struct SidebarView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Conversation.startedAt, order: .reverse) private var conversations: [Conversation]
    @Query(sort: \Agent.name) private var agents: [Agent]
    @State private var searchText = ""
    @State private var renamingConversation: Conversation?
    @State private var renameText = ""
    @State private var conversationToDelete: Conversation?
    @State private var showDeleteConfirmation = false
    @State private var showCatalog = false
    @State private var showSkillLibrary = false
    @State private var showMCPLibrary = false

    var body: some View {
        List(selection: $appState.selectedConversationId) {
            if conversations.isEmpty {
                emptyState
            } else {
                pinnedSection
                activeSection
                recentSection
            }
            agentsSection
        }
        .listStyle(.sidebar)
        .searchable(text: $searchText, prompt: "Search conversations...")
        .accessibilityIdentifier("sidebar.conversationList")
        .frame(minWidth: 220)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showCatalog = true
                } label: {
                    Label("Browse Catalog", systemImage: "square.grid.2x2")
                }
                .help("Browse catalog")
                .accessibilityIdentifier("sidebar.catalogButton")

                Button {
                    showSkillLibrary = true
                } label: {
                    Label("Installed Skills", systemImage: "book.fill")
                }
                .help("Installed skills")
                .accessibilityIdentifier("sidebar.skillsButton")

                Button {
                    showMCPLibrary = true
                } label: {
                    Label("Installed MCPs", systemImage: "server.rack")
                }
                .help("Installed MCPs")
                .accessibilityIdentifier("sidebar.mcpsButton")

                Button {
                    appState.showAgentLibrary = true
                } label: {
                    Label("Manage Agents", systemImage: "slider.horizontal.3")
                }
                .help("Manage agents")
                .accessibilityIdentifier("sidebar.manageAgentsButton")
            }
        }
        .sheet(isPresented: $showCatalog) {
            CatalogBrowserView()
                .frame(minWidth: 700, minHeight: 550)
        }
        .sheet(isPresented: $showSkillLibrary) {
            SkillLibraryView()
                .frame(minWidth: 600, minHeight: 450)
        }
        .sheet(isPresented: $showMCPLibrary) {
            MCPLibraryView()
                .frame(minWidth: 600, minHeight: 450)
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
                .accessibilityIdentifier("sidebar.emptyState.newSessionButton")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    // MARK: - Pinned Section

    @ViewBuilder
    private var pinnedSection: some View {
        let pinned = conversations.filter { $0.isPinned }
        if !pinned.isEmpty {
            Section("Pinned") {
                ForEach(filteredConversations(pinned)) { convo in
                    conversationRow(convo)
                        .tag(convo.id)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) { promptDelete(convo) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button { togglePin(convo) } label: {
                                Label("Unpin", systemImage: "pin.slash")
                            }
                            .tint(.yellow)
                        }
                }
            }
        }
    }

    // MARK: - Active Section

    @ViewBuilder
    private var activeSection: some View {
        let active = conversations.filter { $0.status == .active && !$0.isPinned }
        if !active.isEmpty {
            Section("Active") {
                ForEach(filteredConversations(active)) { convo in
                    conversationRow(convo)
                        .tag(convo.id)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) { promptDelete(convo) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button { togglePin(convo) } label: {
                                Label("Pin", systemImage: "pin")
                            }
                            .tint(.yellow)
                        }
                }
            }
        }
    }

    // MARK: - Recent Section

    @ViewBuilder
    private var recentSection: some View {
        let closed = conversations.filter { $0.status == .closed && !$0.isPinned }
        if !closed.isEmpty {
            Section("Recent") {
                ForEach(filteredConversations(Array(closed.prefix(20)))) { convo in
                    conversationRow(convo)
                        .tag(convo.id)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) { promptDelete(convo) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button { togglePin(convo) } label: {
                                Label("Pin", systemImage: "pin")
                            }
                            .tint(.yellow)
                        }
                }
            }
        }
    }

    // MARK: - Agents Section

    @ViewBuilder
    private var agentsSection: some View {
        Section("Agents") {
            ForEach(agents) { agent in
                HStack {
                    Image(systemName: agent.icon)
                        .foregroundStyle(agentColor(agent.color))
                    Text(agent.name)
                    Spacer()
                    if agent.instancePolicy != .spawn {
                        Text(policyBadge(agent.instancePolicy))
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.quaternary)
                            .clipShape(Capsule())
                    }
                }
                .accessibilityIdentifier("sidebar.agentRow.\(agent.id.uuidString)")
                .contextMenu {
                    Button("Start Session") {
                        startSession(with: agent)
                    }
                    .accessibilityIdentifier("sidebar.agentRow.startSession.\(agent.id.uuidString)")
                }
            }
        }
    }

    // MARK: - Conversation Row

    private func conversationRow(_ convo: Conversation) -> some View {
        HStack(spacing: 8) {
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
                        Text(preview)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
            if convo.status == .active {
                Circle()
                    .fill(.green)
                    .frame(width: 6, height: 6)
                    .accessibilityLabel("Active")
            }
        }
        .accessibilityIdentifier("sidebar.conversationRow.\(convo.id.uuidString)")
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
            Divider()
            Button(role: .destructive) { promptDelete(convo) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Conversation Icon

    @ViewBuilder
    private func conversationIcon(_ convo: Conversation) -> some View {
        if let agent = convo.session?.agent {
            Image(systemName: agent.icon)
                .foregroundStyle(agentColor(agent.color))
                .font(.caption)
        } else {
            let hasUser = convo.participants.contains { $0.type == .user }
            let agentCount = convo.participants.filter {
                if case .agentSession = $0.type { return true }
                return false
            }.count

            if hasUser && agentCount > 1 {
                Image(systemName: "person.3.fill")
                    .foregroundStyle(.blue)
                    .font(.caption)
            } else if hasUser {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .foregroundStyle(.blue)
                    .font(.caption)
            } else {
                Image(systemName: "arrow.left.arrow.right")
                    .foregroundStyle(.purple)
                    .font(.caption)
            }
        }
    }

    // MARK: - Helpers

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func lastMessagePreview(_ convo: Conversation) -> String? {
        let chatMessages = convo.messages
            .filter { $0.type == .chat }
            .sorted { $0.timestamp < $1.timestamp }
        guard let last = chatMessages.last else { return nil }
        let text = last.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count <= 40 { return text }
        let cutoff = text.index(text.startIndex, offsetBy: 40)
        return String(text[..<cutoff]) + "..."
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

    // MARK: - Actions

    private func togglePin(_ convo: Conversation) {
        convo.isPinned.toggle()
        try? modelContext.save()
    }

    private func closeConversation(_ convo: Conversation) {
        convo.status = .closed
        convo.closedAt = Date()
        if let session = convo.session {
            appState.sendToSidecar(.sessionPause(sessionId: convo.id.uuidString))
            session.status = .paused
        }
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

        if let session = convo.session, let agent = session.agent {
            let newSession = Session(agent: agent, mode: session.mode)
            newSession.mission = session.mission
            newSession.workingDirectory = session.workingDirectory
            newSession.workspaceType = session.workspaceType
            newConvo.session = newSession
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
        let conversation = Conversation(topic: agent.name, session: session)
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
