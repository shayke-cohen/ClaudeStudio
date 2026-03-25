import SwiftUI
import SwiftData

struct GroupSidebarRowView: View {
    let group: AgentGroup
    let agentCount: Int
    let conversations: [Conversation]
    let allAgents: [Agent]
    @Binding var isExpanded: Bool
    let onNewChat: () -> Void
    let onNewAutonomousChat: (() -> Void)?
    let onSelectConversation: (Conversation) -> Void
    var onSelectGroup: (() -> Void)?
    var onEdit: (() -> Void)?
    var onDuplicate: (() -> Void)?
    var selectedConversationId: UUID?

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
                .accessibilityIdentifier("sidebar.groupRow.\(group.id.uuidString).chatRow.\(conv.id.uuidString)")
            }
        } label: {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Text(group.icon)
                        .font(.body)
                        .frame(width: 22, height: 22)
                        .background(Color.fromAgentColor(group.color).opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 5))

                    Text(group.name)
                        .font(.body)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
                .onTapGesture { onSelectGroup?() }

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

                if group.autonomousCapable, let onAuto = onNewAutonomousChat {
                    Button { onAuto() } label: {
                        Image(systemName: "bolt")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                    .help("Start autonomous mission")
                    .accessibilityIdentifier("sidebar.groupRow.\(group.id.uuidString).autonomousButton")
                }

                Button {
                    onNewChat()
                } label: {
                    Image(systemName: "plus")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sidebar.groupRow.\(group.id.uuidString).newChatButton")
            }
            .accessibilityIdentifier("sidebar.groupRow.\(group.id.uuidString)")
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}
