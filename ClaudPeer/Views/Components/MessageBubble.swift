import SwiftUI

struct MessageBubble: View {
    let message: ConversationMessage
    let participants: [Participant]
    @State private var isHovered = false
    @State private var isCopied = false

    private var sender: Participant? {
        guard let senderId = message.senderParticipantId else { return nil }
        return participants.first { $0.id == senderId }
    }

    private var isUser: Bool {
        sender?.type == .user
    }

    var body: some View {
        Group {
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
        .accessibilityIdentifier("messageBubble.\(message.type.rawValue).\(message.id.uuidString)")
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
                        .accessibilityIdentifier("messageBubble.senderLabel.\(message.id.uuidString)")

                    if isHovered {
                        Text(message.timestamp.formatted(.dateTime.hour().minute()))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .transition(.opacity)
                    }
                }

                HStack(alignment: .top, spacing: 4) {
                    messageContent
                        .padding(.horizontal, isUser ? 12 : 0)
                        .padding(.vertical, isUser ? 8 : 0)
                        .background(isUser ? Color.accentColor.opacity(0.15) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    if isHovered {
                        Button {
                            copyMessage()
                        } label: {
                            Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                                .font(.caption2)
                                .foregroundStyle(isCopied ? .green : .secondary)
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.borderless)
                        .help("Copy message")
                        .accessibilityIdentifier("messageBubble.copyButton.\(message.id.uuidString)")
                        .accessibilityLabel("Copy message")
                        .transition(.opacity)
                    }
                }

                if message.isStreaming {
                    StreamingIndicator()
                }
            }

            if !isUser {
                Spacer(minLength: 60)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    @ViewBuilder
    private var messageContent: some View {
        if isUser {
            Text(message.text)
                .textSelection(.enabled)
        } else {
            MarkdownContent(text: message.text)
        }
    }

    private func copyMessage() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.text, forType: .string)
        withAnimation {
            isCopied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                isCopied = false
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
