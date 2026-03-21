import SwiftUI
import SwiftData

struct InspectorView: View {
    let conversationId: UUID
    @Environment(\.modelContext) private var modelContext
    @Query private var allConversations: [Conversation]
    @EnvironmentObject private var appState: AppState
    @State private var editedTopic = ""
    @State private var isEditingTopic = false
    @FocusState private var topicFocused: Bool

    private var conversation: Conversation? {
        allConversations.first { $0.id == conversationId }
    }

    private var session: Session? {
        conversation?.session
    }

    private var agent: Agent? {
        session?.agent
    }

    private var liveInfo: AppState.SessionInfo? {
        appState.activeSessions[conversationId]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                conversationSection
                if session != nil {
                    sessionSection
                }
                if agent != nil {
                    agentSection
                }
            }
            .padding()
        }
        .accessibilityIdentifier("inspector.scrollView")
        .frame(minWidth: 220, idealWidth: 280)
    }

    // MARK: - Conversation Section

    @ViewBuilder
    private var conversationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Conversation", systemImage: "bubble.left.and.bubble.right")
                .font(.headline)

            if let convo = conversation {
                HStack {
                    Text("Topic")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .trailing)
                    if isEditingTopic {
                        TextField("Name", text: $editedTopic)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                            .focused($topicFocused)
                            .onSubmit { commitTopicRename() }
                            .onExitCommand { isEditingTopic = false }
                            .accessibilityIdentifier("inspector.topicField")
                    } else {
                        Text(convo.topic ?? "Untitled")
                            .font(.caption)
                            .lineLimit(2)
                            .accessibilityIdentifier("inspector.topicValue")
                        Button {
                            editedTopic = convo.topic ?? ""
                            isEditingTopic = true
                            topicFocused = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.caption2)
                        }
                        .buttonStyle(.borderless)
                        .help("Rename topic")
                        .accessibilityIdentifier("inspector.editTopicButton")
                        .accessibilityLabel("Rename topic")
                    }
                }

                HStack {
                    InfoRow(label: "Status", value: convo.status.rawValue.capitalized)
                    if convo.status == .active {
                        Button {
                            closeConversation(convo)
                        } label: {
                            Text("Close")
                                .font(.caption2)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .help("Close this conversation")
                        .accessibilityIdentifier("inspector.closeConversationButton")
                    }
                }

                InfoRow(label: "Participants", value: "\(convo.participants.count)")
                ForEach(convo.participants) { participant in
                    HStack {
                        participantIcon(participant)
                        Text(participant.displayName)
                            .font(.caption)
                    }
                    .padding(.leading, 8)
                }
                InfoRow(label: "Messages", value: "\(convo.messages.count)")
                InfoRow(label: "Started", value: convo.startedAt.formatted(.relative(presentation: .named)))
            }
        }
    }

    // MARK: - Session Section

    @ViewBuilder
    private var sessionSection: some View {
        if let session = session {
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Label("Session", systemImage: "terminal")
                    .font(.headline)

                InfoRow(label: "Status", value: session.status.rawValue.capitalized)

                sessionActionButtons(session)

                InfoRow(label: "Mode", value: session.mode.rawValue.capitalized)
                if let mission = session.mission {
                    InfoRow(label: "Mission", value: mission)
                }

                let liveTokens = liveInfo?.tokenCount ?? session.tokenCount
                let liveCost = liveInfo?.cost ?? session.totalCost
                InfoRow(label: "Tokens", value: formatNumber(liveTokens))
                InfoRow(label: "Cost", value: String(format: "$%.4f", liveCost))
                InfoRow(label: "Tool Calls", value: "\(session.toolCallCount)")
                if !session.workingDirectory.isEmpty {
                    InfoRow(label: "Working Dir", value: session.workingDirectory)
                }
            }
        }
    }

    @ViewBuilder
    private func sessionActionButtons(_ session: Session) -> some View {
        HStack(spacing: 8) {
            switch session.status {
            case .active:
                Button {
                    pauseCurrentSession()
                } label: {
                    Label("Pause", systemImage: "pause.fill")
                }
                .controlSize(.small)
                .help("Pause session")
                .accessibilityIdentifier("inspector.sessionPauseButton")

                Button(role: .destructive) {
                    stopCurrentSession()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .controlSize(.small)
                .help("Stop session")
                .accessibilityIdentifier("inspector.sessionStopButton")

            case .paused:
                Button {
                    resumeCurrentSession()
                } label: {
                    Label("Resume", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help("Resume session")
                .accessibilityIdentifier("inspector.sessionResumeButton")

            case .completed, .failed:
                Text(session.status == .completed ? "Session ended" : "Session failed")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .italic()
                    .accessibilityIdentifier("inspector.sessionTerminalStatus")
            }
        }
        .padding(.leading, 84)
    }

    // MARK: - Agent Section

    @ViewBuilder
    private var agentSection: some View {
        if let agent = agent {
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Label("Agent", systemImage: agent.icon)
                    .font(.headline)

                InfoRow(label: "Name", value: agent.name)
                InfoRow(label: "Model", value: agent.model)
                InfoRow(label: "Skills", value: "\(agent.skillIds.count)")
                InfoRow(label: "MCPs", value: "\(agent.extraMCPServerIds.count)")
                InfoRow(label: "Policy", value: policyLabel(agent.instancePolicy))

                Button {
                    appState.showAgentLibrary = true
                } label: {
                    Label("Open in Editor", systemImage: "arrow.up.forward.square")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.leading, 84)
                .help("Open agent in editor")
                .accessibilityIdentifier("inspector.openAgentEditorButton")
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func participantIcon(_ participant: Participant) -> some View {
        switch participant.type {
        case .user:
            Image(systemName: "person.fill")
                .foregroundStyle(.blue)
                .font(.caption)
        case .agentSession:
            Image(systemName: "cpu")
                .foregroundStyle(.purple)
                .font(.caption)
        }
    }

    private func policyLabel(_ policy: InstancePolicy) -> String {
        switch policy {
        case .spawn: return "Spawn"
        case .singleton: return "Singleton"
        case .pool(let max): return "Pool(\(max))"
        }
    }

    private func formatNumber(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    // MARK: - Actions

    private func commitTopicRename() {
        let name = editedTopic.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty, let convo = conversation {
            convo.topic = name
            try? modelContext.save()
        }
        isEditingTopic = false
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

    private func pauseCurrentSession() {
        guard let convo = conversation else { return }
        appState.sendToSidecar(.sessionPause(sessionId: convo.id.uuidString))
        convo.session?.status = .paused
        try? modelContext.save()
    }

    private func resumeCurrentSession() {
        guard let convo = conversation,
              let session = convo.session,
              let claudeSessionId = session.claudeSessionId else { return }
        appState.sendToSidecar(.sessionResume(sessionId: convo.id.uuidString, claudeSessionId: claudeSessionId))
        session.status = .active
        convo.status = .active
        try? modelContext.save()
    }

    private func stopCurrentSession() {
        guard let convo = conversation, let session = convo.session else { return }
        appState.sendToSidecar(.sessionPause(sessionId: convo.id.uuidString))
        session.status = .completed
        convo.status = .closed
        convo.closedAt = Date()
        try? modelContext.save()
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
            Text(value)
                .font(.caption)
                .lineLimit(2)
        }
        .accessibilityIdentifier("infoRow.\(label.lowercased().replacingOccurrences(of: " ", with: ""))")
        .accessibilityLabel("\(label): \(value)")
    }
}
