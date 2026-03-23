import SwiftUI
import AppKit

struct AgentAppearance {
    let color: Color
    let icon: String
}

struct MessageBubble: View {
    let message: ConversationMessage
    let participants: [Participant]
    /// Per-participant appearance map for multi-agent conversations. `nil` for single-agent.
    var agentAppearances: [UUID: AgentAppearance]?
    var onTapAttachment: ((MessageAttachment) -> Void)?
    /// When set, shows “Fork from here” in the context menu (chat bubbles only).
    var onForkFromHere: (() -> Void)?
    @State private var isHovered = false
    @State private var isCopied = false
    @State private var isThinkingExpanded = false

    private var sender: Participant? {
        guard let senderId = message.senderParticipantId else { return nil }
        return participants.first { $0.id == senderId }
    }

    private var isUser: Bool {
        sender?.type == .user
    }

    private var senderAppearance: AgentAppearance? {
        guard let senderId = message.senderParticipantId else { return nil }
        return agentAppearances?[senderId]
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
        .xrayId("messageBubble.\(message.type.rawValue).\(message.id.uuidString)")
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
                        Image(systemName: senderAppearance?.icon ?? "cpu")
                            .font(.caption2)
                            .foregroundStyle(senderAppearance?.color ?? .purple)
                    }
                    Text(sender?.displayName ?? "Unknown")
                        .font(.caption)
                        .foregroundStyle(senderAppearance?.color ?? .secondary)
                        .xrayId("messageBubble.senderLabel.\(message.id.uuidString)")
                }

                VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                    if !isUser, let thinking = message.thinkingText, !thinking.isEmpty {
                        thinkingSection(thinking)
                    }
                    if !message.attachments.isEmpty {
                        attachmentGrid
                    }
                    if !message.text.isEmpty {
                        messageContent
                    }
                }
                .padding(.horizontal, isUser ? 12 : (senderAppearance != nil ? 10 : 0))
                .padding(.vertical, isUser ? 8 : (senderAppearance != nil ? 6 : 0))
                .background(isUser ? Color.accentColor.opacity(0.15) : (senderAppearance.map { $0.color.opacity(0.08) } ?? Color.clear))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .topTrailing) {
                    if isHovered {
                        HStack(spacing: 4) {
                            Text(message.timestamp.formatted(.dateTime.hour().minute()))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)

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
                            .xrayId("messageBubble.copyButton.\(message.id.uuidString)")
                            .accessibilityLabel("Copy message")
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .offset(x: 4, y: -12)
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
        .contextMenu {
            if message.type == .chat, let fork = onForkFromHere {
                Button {
                    fork()
                } label: {
                    Label("Fork from here", systemImage: "arrow.branch")
                }
                .xrayId("messageBubble.forkFromHere.\(message.id.uuidString)")
            }
            Button {
                copyMessage()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    @ViewBuilder
    private var attachmentGrid: some View {
        let attachments = message.attachments
        let columns = attachments.count == 1 ? 1 : 2
        let gridItems = Array(repeating: GridItem(.flexible(), spacing: 4), count: columns)

        LazyVGrid(columns: gridItems, spacing: 4) {
            ForEach(attachments) { attachment in
                AttachmentThumbnail(attachment: attachment)
                    .onTapGesture {
                        onTapAttachment?(attachment)
                    }
                    .xrayId("messageBubble.attachment.\(attachment.id.uuidString)")
            }
        }
        .frame(maxWidth: 300)
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

    @ViewBuilder
    private func thinkingSection(_ thinking: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isThinkingExpanded.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "brain")
                        .font(.caption2)
                        .foregroundStyle(.indigo)
                    Text("Thinking")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.indigo)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isThinkingExpanded ? 90 : 0))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
            }
            .buttonStyle(.plain)
            .xrayId("messageBubble.thinkingToggle.\(message.id.uuidString)")
            .accessibilityLabel(isThinkingExpanded ? "Collapse thinking" : "Expand thinking")

            if isThinkingExpanded {
                Divider()
                Text(thinking)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
                    .textSelection(.enabled)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxHeight: 200)
            }
        }
        .background(.indigo.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(.indigo.opacity(0.15), lineWidth: 0.5)
        )
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
