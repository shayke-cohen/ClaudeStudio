import SwiftUI
import SwiftData

struct SidebarView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Conversation.startedAt, order: .reverse) private var conversations: [Conversation]
    @Query(sort: \Agent.name) private var agents: [Agent]
    @State private var searchText = ""

    var body: some View {
        List(selection: $appState.selectedConversationId) {
            activeSection
            recentSection
            agentsSection
        }
        .listStyle(.sidebar)
        .searchable(text: $searchText, prompt: "Search conversations...")
        .frame(minWidth: 220)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    appState.showAgentLibrary = true
                } label: {
                    Label("Manage Agents", systemImage: "slider.horizontal.3")
                }
            }
        }
    }

    @ViewBuilder
    private var activeSection: some View {
        let active = conversations.filter { $0.status == .active }
        if !active.isEmpty {
            Section("Active") {
                ForEach(filteredConversations(active)) { convo in
                    conversationRow(convo)
                        .tag(convo.id)
                }
            }
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        let closed = conversations.filter { $0.status == .closed }
        if !closed.isEmpty {
            Section("Recent") {
                ForEach(filteredConversations(Array(closed.prefix(20)))) { convo in
                    conversationRow(convo)
                        .tag(convo.id)
                }
            }
        }
    }

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
                .contextMenu {
                    Button("Start Session") {
                        startSession(with: agent)
                    }
                }
            }
        }
    }

    private func conversationRow(_ convo: Conversation) -> some View {
        HStack {
            conversationIcon(convo)
            VStack(alignment: .leading, spacing: 2) {
                Text(convo.topic ?? "Untitled")
                    .lineLimit(1)
                Text(participantNames(convo))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if convo.status == .active {
                Circle()
                    .fill(.green)
                    .frame(width: 6, height: 6)
            }
        }
    }

    @ViewBuilder
    private func conversationIcon(_ convo: Conversation) -> some View {
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

    private func participantNames(_ convo: Conversation) -> String {
        convo.participants.map(\.displayName).joined(separator: ", ")
    }

    private func filteredConversations(_ convos: [Conversation]) -> [Conversation] {
        if searchText.isEmpty { return convos }
        return convos.filter { convo in
            (convo.topic ?? "").localizedCaseInsensitiveContains(searchText) ||
            convo.participants.contains { $0.displayName.localizedCaseInsensitiveContains(searchText) }
        }
    }

    private func agentColor(_ color: String) -> Color {
        switch color {
        case "blue": return .blue
        case "red": return .red
        case "green": return .green
        case "purple": return .purple
        case "orange": return .orange
        case "yellow": return .yellow
        case "pink": return .pink
        default: return .accentColor
        }
    }

    private func policyBadge(_ policy: InstancePolicy) -> String {
        switch policy {
        case .singleton: return "1"
        case .pool(let max): return "\(max)"
        case .spawn: return ""
        }
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
