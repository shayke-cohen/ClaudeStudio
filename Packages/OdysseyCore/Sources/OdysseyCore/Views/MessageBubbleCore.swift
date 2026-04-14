// Sources/OdysseyCore/Views/MessageBubbleCore.swift
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// A cross-platform chat bubble view driven by `MessageWire`.
/// Used by the iOS target (Phase 4). The macOS target continues using
/// the full `MessageBubble` view that operates on `ConversationMessage`.
public struct MessageBubbleCore: View {
    public let message: MessageWire
    public let participants: [ParticipantWire]
    public var renderAdmonitions: Bool = true
    public var onOpenLocalReference: ((String) -> Void)? = nil

    @Environment(\.appTextScale) private var appTextScale
    @State private var isThinkingExpanded = false
    @State private var isCopied = false

    public init(
        message: MessageWire,
        participants: [ParticipantWire],
        renderAdmonitions: Bool = true,
        onOpenLocalReference: ((String) -> Void)? = nil
    ) {
        self.message = message
        self.participants = participants
        self.renderAdmonitions = renderAdmonitions
        self.onOpenLocalReference = onOpenLocalReference
    }

    private var sender: ParticipantWire? {
        guard let id = message.senderParticipantId else { return nil }
        return participants.first { $0.id == id }
    }

    private var isUser: Bool {
        sender.map { !$0.isAgent } ?? false
    }

    private var captionFont: Font { .system(size: 12 * appTextScale) }
    private var caption2Font: Font { .system(size: 11 * appTextScale) }
    private var bodyFont: Font { .system(size: 14 * appTextScale) }

    public var body: some View {
        Group {
            switch message.type {
            case "chat":
                chatBubble
            case "toolCall", "toolResult":
                toolCallCard
            case "system":
                systemMessage
            case "delegation":
                delegationCard
            case "blackboardUpdate":
                blackboardCard
            case "taskEvent":
                taskEventCard
            case "workspaceEvent":
                workspaceEventCard
            case "agentInvite":
                agentInviteCard
            default:
                chatBubble
            }
        }
    }

    @ViewBuilder
    private var chatBubble: some View {
        HStack(alignment: .top, spacing: 8) {
            if isUser { Spacer(minLength: 60) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(sender?.displayName ?? "Unknown")
                    .font(captionFont)
                    .foregroundStyle(.secondary)

                VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                    if !isUser, let thinking = message.thinkingText, !thinking.isEmpty {
                        thinkingSection(thinking)
                    }
                    if !message.text.isEmpty {
                        if isUser {
                            Text(message.text)
                                .font(bodyFont)
                                .textSelection(.enabled)
                        } else {
                            MarkdownContentCore(
                                text: message.text,
                                renderAdmonitions: renderAdmonitions,
                                onOpenLocalReference: onOpenLocalReference
                            )
                        }
                    }
                }
                .padding(.horizontal, isUser ? 12 : 0)
                .padding(.vertical, isUser ? 8 : 0)
                .background(isUser ? Color.accentColor.opacity(0.15) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: isUser ? 12 : 0))

                if message.isStreaming {
                    StreamingIndicator()
                }
            }
            if !isUser { Spacer(minLength: 60) }
        }
        .contextMenu {
            Button {
                copyMessage()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
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
                        .font(captionFont)
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
#if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.text, forType: .string)
#else
        UIPasteboard.general.string = message.text
#endif
        withAnimation { isCopied = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            withAnimation { isCopied = false }
        }
    }

    @ViewBuilder private var systemMessage: some View {
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

    @ViewBuilder private var toolCallCard: some View {
        HStack(spacing: 8) {
            Image(systemName: "wrench.and.screwdriver")
                .foregroundStyle(.gray)
            VStack(alignment: .leading, spacing: 2) {
                Text(message.toolName ?? "Tool")
                    .font(captionFont)
                    .fontWeight(.medium)
                if !message.text.isEmpty {
                    Text(message.text)
                        .font(captionFont)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
        .background(.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder private var delegationCard: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.right.circle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Delegated Task").font(captionFont).fontWeight(.medium)
                Text(message.text).font(captionFont).foregroundStyle(.secondary)
            }
        }
        .padding(8).background(.orange.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder private var blackboardCard: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.grid.2x2.fill").foregroundStyle(.teal)
            VStack(alignment: .leading, spacing: 2) {
                Text("Blackboard Update").font(captionFont).fontWeight(.medium)
                Text(message.text).font(captionFont).foregroundStyle(.secondary)
            }
        }
        .padding(8).background(.teal.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder private var taskEventCard: some View {
        HStack(spacing: 8) {
            Image(systemName: "checklist").foregroundStyle(.purple)
            VStack(alignment: .leading, spacing: 2) {
                Text("Task").font(captionFont).fontWeight(.medium)
                Text(message.text).font(captionFont).foregroundStyle(.secondary)
            }
        }
        .padding(8).background(.purple.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder private var workspaceEventCard: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill").foregroundStyle(.indigo)
            VStack(alignment: .leading, spacing: 2) {
                Text("Workspace").font(captionFont).fontWeight(.medium)
                Text(message.text).font(captionFont).foregroundStyle(.secondary)
            }
        }
        .padding(8).background(.indigo.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder private var agentInviteCard: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.badge.plus").foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Agent Invited").font(captionFont).fontWeight(.medium)
                Text(message.text).font(captionFont).foregroundStyle(.secondary)
            }
        }
        .padding(8).background(.green.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
