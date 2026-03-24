import SwiftUI
import SwiftData

struct AgentSidebarRowView: View {
    let agent: Agent
    let conversations: [Conversation]
    @Binding var isExpanded: Bool
    let onNewChat: () -> Void
    let onSelectConversation: (Conversation) -> Void

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(conversations.prefix(10)) { conv in
                Button {
                    onSelectConversation(conv)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.left")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(conv.topic ?? "Untitled")
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Text(conv.startedAt, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sidebar.agentRow.\(agent.id.uuidString).chatRow.\(conv.id.uuidString)")
            }

            Button {
                onNewChat()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.caption2)
                    Text("New Chat")
                        .font(.caption)
                }
                .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("sidebar.agentRow.\(agent.id.uuidString).newChatButton")
        } label: {
            HStack {
                Image(systemName: agent.icon)
                    .foregroundStyle(Color.fromAgentColor(agent.color))
                Text(agent.name)
                Spacer()
                if !conversations.isEmpty {
                    Text("\(conversations.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }
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
        }
    }

    private func policyBadge(_ policy: InstancePolicy) -> String {
        switch policy {
        case .singleton: return "1"
        case .pool(let max): return "\(max)"
        case .spawn: return ""
        }
    }
}
