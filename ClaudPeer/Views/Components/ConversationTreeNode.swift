import SwiftData
import SwiftUI

struct ConversationTreeNode: View {
    let conversation: Conversation
    let depth: Int
    let isSelected: Bool
    let onSelect: () -> Void
    @Query private var allConversations: [Conversation]

    private var children: [Conversation] {
        allConversations.filter { $0.parentConversationId == conversation.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button(action: onSelect) {
                HStack {
                    if depth > 0 {
                        ForEach(0..<depth, id: \.self) { _ in
                            Rectangle()
                                .fill(.quaternary)
                                .frame(width: 1)
                                .padding(.horizontal, 4)
                        }
                    }

                    Image(systemName: iconName)
                        .font(.caption2)
                        .foregroundStyle(iconColor)

                    Text(conversation.topic ?? "Chat")
                        .lineLimit(1)
                        .font(.callout)
                        .accessibilityIdentifier("conversationTree.topic.\(conversation.id.uuidString)")

                    Spacer()

                    if conversation.status == .active {
                        Circle()
                            .fill(.green)
                            .frame(width: 5, height: 5)
                    }
                }
                .padding(.vertical, 3)
                .padding(.horizontal, 4)
                .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("conversationTree.node.\(conversation.id.uuidString)")

            ForEach(children) { child in
                ConversationTreeNode(
                    conversation: child,
                    depth: depth + 1,
                    isSelected: false,
                    onSelect: {}
                )
            }
        }
    }

    private var iconName: String {
        let hasUser = conversation.participants.contains { $0.type == .user }
        if hasUser {
            return "bubble.left.and.bubble.right.fill"
        } else {
            return "arrow.left.arrow.right"
        }
    }

    private var iconColor: Color {
        let hasUser = conversation.participants.contains { $0.type == .user }
        return hasUser ? .blue : .purple
    }
}
