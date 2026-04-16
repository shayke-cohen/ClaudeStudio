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
    var onOpenLocalReference: ((String) -> Void)?
    /// When set, shows “Fork from here” in the context menu (chat bubbles only).
    var onForkFromHere: (() -> Void)?
    var onScheduleFromMessage: (() -> Void)?
    @Environment(\.appTextScale) private var appTextScale
    @State private var isHovered = false
    @State private var isCopied = false
    @State private var isThinkingExpanded = false
    @State private var mermaidHeight: CGFloat = 150

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

    private var captionFont: Font {
        .system(size: 12 * appTextScale)
    }

    private var captionMediumFont: Font {
        .system(size: 12 * appTextScale, weight: .medium)
    }

    private var caption2Font: Font {
        .system(size: 11 * appTextScale)
    }

    private var bodyFont: Font {
        .system(size: 14 * appTextScale)
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
            case .peerMessage:
                peerMessageCard
            case .delegation:
                delegationMessage
            case .blackboardUpdate:
                blackboardMessage
            case .taskEvent:
                taskEventCard
            case .workspaceEvent:
                workspaceEventCard
            case .agentInvite:
                agentInviteCard
            case .question:
                AnsweredQuestionBubble(message: message, agentAppearance: senderAppearance)
            case .richContent:
                richContentView
            }
        }
        .xrayId("messageBubble.\(message.type.rawValue).\(message.id.uuidString)")
    }

    @ViewBuilder
    private var richContentView: some View {
        let format = message.toolName ?? "html"
        let title = message.toolInput
        let content = message.text
        let maxHeight = Double(message.toolOutput ?? "800") ?? 800

        switch format {
        case "mermaid":
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "diagram.below.topbar")
                        .foregroundStyle(.purple)
                        .font(captionFont)
                    Text(title ?? "Diagram")
                        .font(captionFont)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        RichContentOpener.openMermaid(content, title: title)
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                            .font(captionFont)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Open in browser")
                    .accessibilityLabel("Open diagram in browser")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(.textBackgroundColor).opacity(0.4))
                Divider().opacity(0.3)
                MermaidDiagramView(source: content, measuredHeight: $mermaidHeight)
                    .frame(height: min(mermaidHeight, maxHeight))
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
            )
        case "markdown":
            VStack(alignment: .leading, spacing: 4) {
                if let title, !title.isEmpty {
                    Text(title)
                        .font(captionFont)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }
                MarkdownContent(text: content, onOpenLocalReference: onOpenLocalReference)
            }
        default:
            InlineHTMLCard(title: title, html: content, maxHeight: maxHeight)
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
                        Image(systemName: senderAppearance?.icon ?? "cpu")
                            .font(caption2Font)
                            .foregroundStyle(senderAppearance?.color ?? .purple)
                    }
                    Text(sender?.displayName ?? "Unknown")
                        .font(captionFont)
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
                .clipShape(RoundedRectangle(cornerRadius: isUser || senderAppearance != nil ? 12 : 0))
                .overlay(alignment: .topTrailing) {
                    if isHovered {
                        HStack(spacing: 4) {
                            Text(message.timestamp.formatted(.dateTime.hour().minute()))
                                .font(caption2Font)
                                .foregroundStyle(.tertiary)

                            Button {
                                copyMessage()
                            } label: {
                                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                                    .font(caption2Font)
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
                        .offset(x: 4, y: -20)
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
            if isUser, message.type == .chat, let schedule = onScheduleFromMessage {
                Button {
                    schedule()
                } label: {
                    Label("Schedule this mission", systemImage: "clock.badge")
                }
                .xrayId("messageBubble.schedule.\(message.id.uuidString)")
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
                .font(bodyFont)
                .textSelection(.enabled)
        } else {
            MarkdownContent(text: message.text, onOpenLocalReference: onOpenLocalReference)
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
                        .font(caption2Font)
                        .foregroundStyle(.indigo)
                    Text("Thinking")
                        .font(captionMediumFont)
                        .fontWeight(.medium)
                        .foregroundStyle(.indigo)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isThinkingExpanded ? 90 : 0))
                        .font(caption2Font)
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
                    .font(captionFont)
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
                .font(captionFont)
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
    private var peerMessageCard: some View {
        HStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("Peer Message")
                    .font(captionMediumFont)
                    .fontWeight(.medium)
                Text(message.text)
                    .font(captionFont)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(.blue.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var delegationMessage: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.right.circle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Delegated Task")
                    .font(captionMediumFont)
                    .fontWeight(.medium)
                Text(message.text)
                    .font(captionFont)
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
                    .font(captionMediumFont)
                    .fontWeight(.medium)
                Text(message.text)
                    .font(captionFont)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(.teal.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var taskEventCard: some View {
        HStack(spacing: 8) {
            Image(systemName: "checklist")
                .foregroundStyle(.purple)
            VStack(alignment: .leading, spacing: 2) {
                Text("Task")
                    .font(captionMediumFont)
                    .fontWeight(.medium)
                Text(message.text)
                    .font(captionFont)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(.purple.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var workspaceEventCard: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .foregroundStyle(.indigo)
            VStack(alignment: .leading, spacing: 2) {
                Text("Workspace")
                    .font(captionMediumFont)
                    .fontWeight(.medium)
                Text(message.text)
                    .font(captionFont)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(.indigo.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var agentInviteCard: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.badge.plus")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Agent Invited")
                    .font(captionMediumFont)
                    .fontWeight(.medium)
                Text(message.text)
                    .font(captionFont)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(.green.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
