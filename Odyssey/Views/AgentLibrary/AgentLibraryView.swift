import SwiftUI
import SwiftData

struct AgentLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @Environment(WindowState.self) private var windowState: WindowState
    @Query(sort: \Agent.name) private var agents: [Agent]
    @State private var searchText = ""
    @State private var filterOrigin: AgentOriginFilter = .all
    @State private var showingNewAgent = false
    @State private var showingFromPrompt = false
    @State private var editingAgent: Agent?
    @State private var showCatalog = false
    let showsDismissButton: Bool

    init(showsDismissButton: Bool = true) {
        self.showsDismissButton = showsDismissButton
    }

    enum AgentOriginFilter: String, CaseIterable {
        case all = "All"
        case mine = "Mine"
        case shared = "Shared"
    }

    private var filteredAgents: [Agent] {
        agents.filter { agent in
            let matchesSearch = searchText.isEmpty ||
                agent.name.localizedCaseInsensitiveContains(searchText) ||
                agent.agentDescription.localizedCaseInsensitiveContains(searchText)
            let matchesFilter: Bool
            switch filterOrigin {
            case .all: matchesFilter = true
            case .mine: matchesFilter = agent.origin == .local || agent.origin == .builtin
            case .shared:
                if case .peer = agent.origin { matchesFilter = true }
                else if agent.origin == .imported { matchesFilter = true }
                else { matchesFilter = false }
            }
            return matchesSearch && matchesFilter
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if agents.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 16)
                    ], spacing: 16) {
                        ForEach(filteredAgents) { agent in
                            AgentCardView(agent: agent, onStart: {
                                startSession(with: agent)
                            }) {
                                editingAgent = agent
                            }
                            .xrayId("agentLibrary.card.\(agent.id.uuidString)")
                            .contextMenu {
                                Button("Edit") {
                                    editingAgent = agent
                                }
                                .xrayId("agentLibrary.card.context.edit.\(agent.id.uuidString)")
                                Button("Duplicate") { duplicateAgent(agent) }
                                    .xrayId("agentLibrary.card.context.duplicate.\(agent.id.uuidString)")
                                Divider()
                                Button("Open in Finder") { revealAgentInFinder(agent) }
                                    .xrayId("agentLibrary.card.context.openInFinder.\(agent.id.uuidString)")
                                Button("Open in Editor") { openAgentInEditor(agent) }
                                    .xrayId("agentLibrary.card.context.openInEditor.\(agent.id.uuidString)")
                                Divider()
                                Button("Delete", role: .destructive) { deleteAgent(agent) }
                                    .xrayId("agentLibrary.card.context.delete.\(agent.id.uuidString)")
                            }
                        }
                    }
                    .padding()
                }
                .xrayId("agentLibrary.agentGrid")
            }
        }
        .sheet(item: $editingAgent) { agent in
            AgentCreationSheet(existingAgent: agent) { _ in
                editingAgent = nil
            }
        }
        .sheet(isPresented: $showingNewAgent) {
            AgentCreationSheet { _ in
                showingNewAgent = false
            }
        }
        .sheet(isPresented: $showingFromPrompt) {
            AgentCreationSheet { _ in
                showingFromPrompt = false
            }
        }
        .sheet(isPresented: $showCatalog) {
            CatalogBrowserView()
                .frame(minWidth: 700, minHeight: 550)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 24)
            Image(systemName: "person.3.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No agents installed yet")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Browse the catalog to find agents, skills, and MCP servers to get started.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            Button {
                showCatalog = true
            } label: {
                Text("Browse Catalog")
            }
            .buttonStyle(.borderedProminent)
            .xrayId("agentLibrary.emptyState.browseCatalogButton")
            Text("or")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Button("Create Custom Agent") {
                showingNewAgent = true
            }
            .xrayId("agentLibrary.emptyState.createAgentButton")
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var header: some View {
        HStack {
            Text("Agent Library")
                .font(.title2)
                .fontWeight(.semibold)
                .xrayId("agentLibrary.title")
            Spacer()

            Picker("Filter", selection: $filterOrigin) {
                ForEach(AgentOriginFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
            .xrayId("agentLibrary.originFilter")

            TextField("Search...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
                .xrayId("agentLibrary.searchField")

            Button {
                showingFromPrompt = true
            } label: {
                Label("From Prompt", systemImage: "wand.and.stars")
            }
            .help("Create agent from a natural language description")
            .xrayId("agentLibrary.fromPromptButton")

            Button {
                showingNewAgent = true
            } label: {
                Label("New Agent", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .help("Create a new agent")
            .xrayId("agentLibrary.newAgentButton")

            Button {
                showCatalog = true
            } label: {
                Label("Catalog", systemImage: "square.grid.2x2")
            }
            .help("Browse catalog")
            .xrayId("agentLibrary.catalogButton")

            if showsDismissButton {
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Close")
                .xrayId("agentLibrary.closeButton")
                .accessibilityLabel("Close")
            }
        }
        .padding()
    }

    private func duplicateAgent(_ agent: Agent) {
        let copy = Agent(
            name: "\(agent.name) Copy",
            agentDescription: agent.agentDescription,
            systemPrompt: agent.systemPrompt,
            provider: agent.provider,
            model: agent.model,
            icon: agent.icon,
            color: agent.color
        )
        copy.skillIds = agent.skillIds
        copy.extraMCPServerIds = agent.extraMCPServerIds
        copy.permissionSetId = agent.permissionSetId
        copy.maxTurns = agent.maxTurns
        copy.maxBudget = agent.maxBudget
        copy.defaultWorkingDirectory = agent.defaultWorkingDirectory
        modelContext.insert(copy)
        try? modelContext.save()
    }

    private func deleteAgent(_ agent: Agent) {
        modelContext.delete(agent)
        try? modelContext.save()
    }

    private func revealAgentInFinder(_ agent: Agent) {
        let slug = agent.configSlug ?? ConfigFileManager.slugify(agent.name)
        let dir = ConfigFileManager.agentsDirectory.appendingPathComponent(slug)
        NSWorkspace.shared.activateFileViewerSelecting([dir])
    }

    private func openAgentInEditor(_ agent: Agent) {
        let slug = agent.configSlug ?? ConfigFileManager.slugify(agent.name)
        let dir = ConfigFileManager.agentsDirectory.appendingPathComponent(slug)
        NSWorkspace.shared.open(dir)
    }

    private func startSession(with agent: Agent) {
        let session = Session(agent: agent, mode: .interactive)
        if let agentDir = agent.defaultWorkingDirectory, !agentDir.isEmpty {
            session.workingDirectory = NSString(string: agentDir).expandingTildeInPath
        } else if !windowState.projectDirectory.isEmpty {
            session.workingDirectory = windowState.projectDirectory
        }
        let conversation = Conversation(
            topic: agent.name,
            sessions: [session],
            projectId: windowState.selectedProjectId,
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
        dismiss()
    }
}
