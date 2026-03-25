import SwiftUI
import SwiftData

struct WorkshopView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState

    @Query(sort: \Agent.name) private var agents: [Agent]

    @State private var selectedTab: WorkshopTab = .agents
    @State private var selectedEntityContext: String?
    @State private var configConversationId: UUID?
    @State private var pendingContextMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                // Left: Entity browser + detail
                VStack(spacing: 0) {
                    WorkshopEntityBrowser(
                        selectedTab: $selectedTab,
                        selectedEntityContext: $selectedEntityContext
                    )
                    .frame(maxHeight: .infinity)

                    if selectedEntityContext != nil {
                        Divider()
                        WorkshopDetailPanel(entityContext: selectedEntityContext)
                            .frame(height: 160)
                    }
                }
                .frame(minWidth: 300, idealWidth: 380, maxWidth: 480)

                // Right: Config Agent chat
                VStack(spacing: 0) {
                    if let convId = configConversationId {
                        ChatView(conversationId: convId)
                            .id(convId)
                    } else {
                        configChatPlaceholder
                    }
                }
                .frame(minWidth: 400, maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            ensureConfigSession()
        }
        .onChange(of: selectedEntityContext) { _, newValue in
            if let context = newValue, configConversationId != nil {
                pendingContextMessage = context
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "wrench.and.screwdriver")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Workshop")
                .font(.title2)
                .fontWeight(.semibold)
                .xrayId("workshop.title")

            Spacer()

            if configConversationId != nil {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                Text("Config Agent active")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Close")
            .xrayId("workshop.closeButton")
            .accessibilityLabel("Close workshop")
        }
        .padding()
    }

    // MARK: - Config Chat Placeholder

    private var configChatPlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "gearshape.2")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Config Agent")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Ask the Config Agent to edit agents, groups, skills, MCPs, and permissions using natural language.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
            Button("Start Config Session") {
                ensureConfigSession()
            }
            .buttonStyle(.borderedProminent)
            .xrayId("workshop.startConfigButton")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Session Management

    private func ensureConfigSession() {
        // Find the Config Agent
        guard let configAgent = agents.first(where: {
            $0.name == "Config Agent" && $0.isEnabled
        }) else { return }

        // Check for existing singleton session
        let descriptor = FetchDescriptor<Session>()
        let sessions = (try? modelContext.fetch(descriptor)) ?? []
        if let existingSession = sessions.first(where: {
            $0.agent?.name == "Config Agent" && $0.status != .completed && $0.status != .failed
        }), let existingConv = existingSession.conversations.first {
            configConversationId = existingConv.id
            return
        }

        // Create new session
        let session = Session(agent: configAgent, mode: .interactive)
        let conversation = Conversation(topic: "Workshop Config", sessions: [session])
        let userParticipant = Participant(type: .user, displayName: "You")
        let agentParticipant = Participant(
            type: .agentSession(sessionId: session.id),
            displayName: configAgent.name
        )
        userParticipant.conversation = conversation
        agentParticipant.conversation = conversation
        conversation.participants = [userParticipant, agentParticipant]
        session.conversations = [conversation]

        modelContext.insert(session)
        modelContext.insert(conversation)
        try? modelContext.save()

        configConversationId = conversation.id
    }
}
