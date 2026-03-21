import SwiftUI
import SwiftData

struct InspectorView: View {
    let conversationId: UUID
    @Query private var allConversations: [Conversation]
    @EnvironmentObject private var appState: AppState

    private var conversation: Conversation? {
        allConversations.first { $0.id == conversationId }
    }

    private var session: Session? {
        conversation?.session
    }

    private var agent: Agent? {
        session?.agent
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
        .frame(minWidth: 220, idealWidth: 260)
    }

    @ViewBuilder
    private var conversationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Conversation", systemImage: "bubble.left.and.bubble.right")
                .font(.headline)

            if let convo = conversation {
                InfoRow(label: "Status", value: convo.status.rawValue.capitalized)
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

    @ViewBuilder
    private var sessionSection: some View {
        if let session = session {
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Label("Session", systemImage: "terminal")
                    .font(.headline)

                InfoRow(label: "Status", value: session.status.rawValue.capitalized)
                InfoRow(label: "Mode", value: session.mode.rawValue.capitalized)
                if let mission = session.mission {
                    InfoRow(label: "Mission", value: mission)
                }
                InfoRow(label: "Tokens", value: "\(session.tokenCount)")
                InfoRow(label: "Cost", value: String(format: "$%.4f", session.totalCost))
                InfoRow(label: "Tool Calls", value: "\(session.toolCallCount)")
                if !session.workingDirectory.isEmpty {
                    InfoRow(label: "Working Dir", value: session.workingDirectory)
                }
            }
        }
    }

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
                InfoRow(label: "MCPs", value: "\(agent.mcpServerIds.count)")
                InfoRow(label: "Policy", value: policyLabel(agent.instancePolicy))
            }
        }
    }

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
    }
}
