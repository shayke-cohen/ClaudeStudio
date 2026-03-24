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
        groupInstruction: String? = nil,
        role: GroupRole? = nil
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

        let roleBlock: String = {
            guard let role, role != .participant else { return "" }
            return "[Your Role: \(role.displayName)]\n\(role.systemPromptSnippet)\n---\n"
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
        \(instructionBlock)\(roleBlock)--- Group thread (new since your last reply) ---
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
        recipientSession: Session,
        role: GroupRole? = nil
    ) -> String {
        let name = recipientSession.agent?.name ?? "Assistant"
        let body = peerMessageText.trimmingCharacters(in: .whitespacesAndNewlines)
        let shown = body.isEmpty ? "(empty)" : body

        let roleInstruction: String
        switch role {
        case .observer:
            roleInstruction = "You are \(name) (observer). Only reply if you are directly addressed by name or have critical information. Otherwise reply very briefly that you have nothing to add."
        case .scribe:
            roleInstruction = "You are \(name) (scribe). If this exchange contains a decision or outcome, record it to the blackboard. You may also reply briefly to the group."
        case .coordinator:
            roleInstruction = "You are \(name) (coordinator). Consider whether this changes the plan or requires redirecting the group. Reply if you have guidance."
        default:
            roleInstruction = "You are \(name). Another participant posted the above in this shared group. You may reply to the whole group if you have something substantive to add; stay concise. If you have nothing useful to add, reply very briefly (e.g. that you have nothing to add)."
        }

        return """
        --- Group chat: peer message ---
        \(senderLabel): \(shown)
        --- End ---

        \(roleInstruction)
        """
    }

    // MARK: - Workflow Step Prompt

    static func buildWorkflowStepPrompt(
        step: WorkflowStep,
        stepIndex: Int,
        totalSteps: Int,
        userMessage: String,
        previousStepOutput: String?,
        groupInstruction: String? = nil,
        role: GroupRole? = nil
    ) -> String {
        var parts: [String] = []

        if let instr = groupInstruction, !instr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("[Group Context]\n\(instr)\n---")
        }

        if let role, role != .participant {
            parts.append("[Your Role: \(role.displayName)]\n\(role.systemPromptSnippet)\n---")
        }

        let label = step.stepLabel ?? "Step \(stepIndex + 1)"
        parts.append("[Workflow Step \(stepIndex + 1)/\(totalSteps): \(label)]")
        parts.append("Your task: \(step.instruction)")

        if let prev = previousStepOutput, !prev.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let clipped = prev.count > maxInjectedCharacters ? String(prev.suffix(maxInjectedCharacters)) : prev
            parts.append("\n[Previous step output]:\n\(clipped)")
        }

        parts.append("\n[User's original request]:\n\"\"\"\n\(userMessage)\n\"\"\"")

        return parts.joined(separator: "\n")
    }

    // MARK: - Autonomous Coordinator Prompt

    static func buildCoordinatorPrompt(
        mission: String,
        teamAgents: [(name: String, description: String)],
        groupInstruction: String?
    ) -> String {
        var parts: [String] = []

        if let instr = groupInstruction, !instr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("[Group Context]\n\(instr)\n---")
        }

        parts.append("[Autonomous Mission]")
        parts.append("You are the coordinator of an autonomous agent team. Your mission:")
        parts.append("\"\"\"\n\(mission)\n\"\"\"")

        parts.append("\nYour team:")
        for agent in teamAgents {
            parts.append("- \(agent.name): \(agent.description)")
        }

        parts.append("""

        Instructions:
        - Use peer_delegate_task to assign specific tasks to team members.
        - Use peer_receive_messages to check for completed work.
        - Use blackboard_write to record decisions and progress.
        - Coordinate the team to accomplish the mission efficiently.
        - When all tasks are complete, write a final summary and include "MISSION COMPLETE" in your response.
        """)

        return parts.joined(separator: "\n")
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
