import SwiftUI

struct MessageBubble: View {
    let message: ConversationMessage
    let participants: [Participant]

    private var sender: Participant? {
        guard let senderId = message.senderParticipantId else { return nil }
        return participants.first { $0.id == senderId }
    }

    private var isUser: Bool {
        sender?.type == .user
    }

    var body: some View {
        switch message.type {
        case .chat:
            chatBubble
        case .toolCall, .toolResult:
            ToolCallView(message: message)
        case .system:
            systemMessage
        case .delegation:
            delegationMessage
        case .blackboardUpdate:
            blackboardMessage
        }
    }

    @ViewBuilder
    private var chatBubble: some View {
        HStack(alignment: .top, spacing: 8) {
            if isUser {
                Spacer(minLength: 60)
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                HStack(spacing: 4) {
                    if !isUser {
                        Image(systemName: "cpu")
                            .font(.caption2)
                            .foregroundStyle(.purple)
                    }
                    Text(sender?.displayName ?? "Unknown")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(message.timestamp.formatted(.dateTime.hour().minute()))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Text(message.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isUser ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                if message.isStreaming {
                    StreamingIndicator()
                }
            }

            if !isUser {
                Spacer(minLength: 60)
            }
        }
    }

    @ViewBuilder
    private var systemMessage: some View {
        HStack {
            Spacer()
            Text(message.text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .italic()
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(.quaternary)
                .clipShape(Capsule())
            Spacer()
        }
    }

    @ViewBuilder
    private var delegationMessage: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.right.circle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Delegated Task")
                    .font(.caption)
                    .fontWeight(.medium)
                Text(message.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var blackboardMessage: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.grid.2x2.fill")
                .foregroundStyle(.teal)
            VStack(alignment: .leading, spacing: 2) {
                Text("Blackboard Update")
                    .font(.caption)
                    .fontWeight(.medium)
                Text(message.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(.teal.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
