import Foundation

/// Builds `session.message` text for group chats: shared transcript delta + latest user line.
///
/// **Watermark policy:** `lastInjectedMessageId` advances when that session’s own assistant
/// message is persisted (`advanceWatermark`). Sessions that are waiting for the same user-turn
/// prompt are excluded from peer fan-out so their next `buildMessageText` delta already includes
/// prior agents’ new lines—no extra catch-up watermark is required.
enum GroupPromptBuilder {
    /// Rough cap for injected transcript (characters) to avoid huge prompts.
    static let maxInjectedCharacters = 120_000

    /// When only one agent session exists, send raw user text (legacy single-chat behavior).
    static func shouldUseGroupInjection(sessionCount: Int) -> Bool {
        sessionCount > 1
    }

    static func buildMessageText(
        conversation: Conversation,
        targetSession: Session,
        latestUserMessageText: String,
        participants: [Participant],
        highlightedMentionAgentNames: [String] = [],
        groupInstruction: String? = nil
    ) -> String {
        let sessionCount = conversation.sessions.count
        guard shouldUseGroupInjection(sessionCount: sessionCount) else {
            return latestUserMessageText
        }

        let sortedChat = conversation.messages
            .filter { $0.type == .chat }
            .sorted { lhs, rhs in
                if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
                return lhs.id.uuidString < rhs.id.uuidString
            }

        let deltaLines = deltaTranscriptLines(
            sortedChat: sortedChat,
            lastInjectedMessageId: targetSession.lastInjectedMessageId,
            participants: participants
        )

        let transcriptBody = deltaLines.joined(separator: "\n")
        let clipped = clipTranscript(transcriptBody)

        let instructionBlock: String = {
            guard let instr = groupInstruction,
                  !instr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
            return "[Group Context]\n\(instr)\n---\n"
        }()

        let agentName = targetSession.agent?.name ?? "Assistant"
        let mentionNote: String = {
            let names = highlightedMentionAgentNames
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !names.isEmpty else { return "" }
            let joined = names.joined(separator: ", ")
            return "\nThe user specifically mentioned by name: \(joined). Address them directly when appropriate.\n"
        }()
        return """
        \(instructionBlock)--- Group thread (new since your last reply) ---
        \(clipped)
        --- End ---
        \(mentionNote)
        You are \(agentName). Respond to the latest user message in this group.
        Latest user message:
        \"\"\"
        \(latestUserMessageText)
        \"\"\"
        """
    }

    /// Prompt for notifying another session when a peer posted in the group (`may_reply` policy).
    static func buildPeerNotifyPrompt(
        senderLabel: String,
        peerMessageText: String,
        recipientSession: Session
    ) -> String {
        let name = recipientSession.agent?.name ?? "Assistant"
        let body = peerMessageText.trimmingCharacters(in: .whitespacesAndNewlines)
        let shown = body.isEmpty ? "(empty)" : body
        return """
        --- Group chat: peer message ---
        \(senderLabel): \(shown)
        --- End ---

        You are \(name). Another participant posted the above in this shared group. You may reply to the whole group if you have something substantive to add; stay concise. If you have nothing useful to add, reply very briefly (e.g. that you have nothing to add).
        """
    }

    static func senderDisplayLabel(for message: ConversationMessage, participants: [Participant]) -> String {
        senderLabel(for: message, participants: participants)
    }

    private static func deltaTranscriptLines(
        sortedChat: [ConversationMessage],
        lastInjectedMessageId: UUID?,
        participants: [Participant]
    ) -> [String] {
        var startIndex = 0
        if let wid = lastInjectedMessageId,
           let idx = sortedChat.firstIndex(where: { $0.id == wid }) {
            startIndex = idx + 1
        } else if lastInjectedMessageId != nil {
            startIndex = 0
        }

        guard startIndex < sortedChat.count else { return [] }

        return sortedChat[startIndex...].map { msg in
            let label = senderLabel(for: msg, participants: participants)
            let body = msg.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return body.isEmpty ? "\(label): (empty)" : "\(label): \(body)"
        }
    }

    private static func senderLabel(for message: ConversationMessage, participants: [Participant]) -> String {
        guard let sid = message.senderParticipantId,
              let p = participants.first(where: { $0.id == sid }) else {
            return "Unknown"
        }
        switch p.type {
        case .user:
            return "[You]"
        case .agentSession:
            return p.displayName
        }
    }

    private static func clipTranscript(_ text: String) -> String {
        guard text.count > maxInjectedCharacters else { return text }
        let suffix = String(text.suffix(maxInjectedCharacters))
        return "… (truncated)\n" + suffix
    }

    /// Call after persisting an assistant `ConversationMessage` for this session.
    static func advanceWatermark(session: Session, assistantMessage: ConversationMessage) {
        session.lastInjectedMessageId = assistantMessage.id
    }
}
