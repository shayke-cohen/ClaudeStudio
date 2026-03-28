import SwiftUI
import SwiftData

struct AgentSidebarRowView: View {
    let agent: Agent
    let conversations: [Conversation]
    @Binding var isExpanded: Bool
    let onNewChat: () -> Void
    let onSelectConversation: (Conversation) -> Void
    var onSelectAgent: (() -> Void)?
    var selectedConversationId: UUID?
    var hasActiveSession: Bool = false

    private var isSelected: Bool {
        guard let selected = selectedConversationId else { return false }
        return conversations.contains { $0.id == selected }
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(conversations.prefix(10)) { conv in
                Button {
                    onSelectConversation(conv)
                } label: {
                    HStack(spacing: 6) {
                        if conv.isUnread {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 6, height: 6)
                        }
                        Image(systemName: "bubble.left")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(conv.topic ?? "Untitled")
                            .font(conv.isUnread ? .caption.bold() : .caption)
                            .lineLimit(1)
                        Spacer()
                        Text(conv.startedAt, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sidebar.agentRow.\(agent.id.uuidString).chatRow.\(conv.id.uuidString)")
                .accessibilityLabel("Open chat \(conv.topic ?? "Untitled")")
            }

        } label: {
            HStack {
                Button {
                    onSelectAgent?()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: agent.icon)
                            .foregroundStyle(Color.fromAgentColor(agent.color))
                        Text(agent.name)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sidebar.agentRow.\(agent.id.uuidString).selectButton")
                .accessibilityLabel("Open agent \(agent.name)")
                Spacer()
                if hasActiveSession {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 6, height: 6)
                        .accessibilityIdentifier("sidebar.agentRow.\(agent.id.uuidString).activityDot")
                }
                if !conversations.isEmpty {
                    Text("\(conversations.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }
                Button {
                    onNewChat()
                } label: {
                    Image(systemName: "plus")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sidebar.agentRow.\(agent.id.uuidString).newChatButton")
                .accessibilityLabel("New chat for \(agent.name)")
            }
            .accessibilityIdentifier("sidebar.agentRow.\(agent.id.uuidString)")
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}
