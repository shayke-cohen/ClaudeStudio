import Foundation

/// Builds `session.message` text for group chats: shared transcript delta + latest user line.
///
/// **Watermark policy:** `lastInjectedMessageId` tracks the last chat message already shown to a
/// session, whether via a persisted assistant reply or an explicit catch-up mark for a no-op
/// response. Parallel group waves may also provide an explicit transcript boundary so every
/// recipient sees the same frozen snapshot even while other replies are arriving.
enum GroupPromptBuilder {
    /// Rough cap for injected transcript (characters) to avoid huge prompts.
    static let maxInjectedCharacters = 120_000
    static let noReplySentinel = "<NO_REPLY>"

    // MARK: - Team Roster

    struct TeamMemberInfo {
        let name: String
        let description: String
        let role: GroupRole
    }

    static func buildTeamRoster(
        targetAgentName: String,
        teamMembers: [TeamMemberInfo]
    ) -> String {
        guard !teamMembers.isEmpty else { return "" }
        let lines = teamMembers.map { member in
            let roleLabel = member.role == .participant ? "" : " (\(member.role.displayName))"
            let desc = member.description.isEmpty ? "" : " — \(member.description)"
            return "- @\(member.name)\(roleLabel)\(desc)"
        }
        return "[Your Team]\nYou are @\(targetAgentName). The other agents in this group:\n\(lines.joined(separator: "\n"))\n---\n"
    }

    // MARK: - Communication Guidelines

    static let communicationGuidelines = """
    [Group Communication Protocol]
    Follow these rules:

    **Mentions**
    - Use @Name to address a specific agent. Use @all to address everyone.
    - When someone @mentions you by name: you MUST respond substantively. This is a direct request.
    - When @all is used: respond if you have relevant input.

    **When to speak**
    - If mentioned: always respond.
    - If not mentioned but you have relevant expertise: contribute briefly, stating why.
    - If not mentioned and the topic is outside your expertise: stay silent.

    **How to reply**
    - Keep replies focused and concise. One clear point per reply.
    - Use @Name when directing a question or request to a specific agent.
    - Do not repeat what another agent already said.

    **Deferring**
    - If another agent is better suited: "@OtherAgent this is more your area — can you handle this?"
    - Do not monopolize the conversation. Make your point and yield.

    **GitHub (when available)**
    - Use GitHub for durable artifacts that should survive this session: bugs, blockers, follow-up tasks, review requests, and implementation PRs.
    - Keep ephemeral coordination in Odyssey chat and on the blackboard.
    - Link issues and PRs in your messages so others can follow along.
    - Mention another agent in GitHub only when you are asking for a concrete action such as review, handoff, or follow-up.
    - When writing a substantive GitHub issue, PR description, or comment, add a short footer signature like: Posted by Odyssey agent: Coder
    ---

    """

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
        mentionedAll: Bool = false,
        routingMode: GroupRoutingMode = .broad,
        deliveryReason: GroupRoutingPlanner.UserDeliveryReason = .broad,
        transcriptBoundaryMessageId: UUID? = nil,
        allowNoReply: Bool = false,
        groupInstruction: String? = nil,
        role: GroupRole? = nil,
        teamMembers: [TeamMemberInfo] = []
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
            participants: participants,
            throughMessageId: transcriptBoundaryMessageId
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
        let rosterBlock = buildTeamRoster(targetAgentName: agentName, teamMembers: teamMembers)

        let mentionNote: String = {
            let names = highlightedMentionAgentNames
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !names.isEmpty || mentionedAll else { return "" }
            if mentionedAll {
                return "\nThe user addressed the whole group with @all. Reply if you can contribute something that materially advances the conversation or mission.\n"
            }
            let joined = names.joined(separator: ", ")
            return "\nThe user specifically mentioned by name: \(joined). Address them directly when appropriate.\n"
        }()
        let directlyMentioned = highlightedMentionAgentNames.contains {
            $0.caseInsensitiveCompare(agentName) == .orderedSame
        }
        let responseOnlyIfMaterial = "Reply only if you can add net-new information that materially advances the conversation or mission. If not, reply with exactly \(noReplySentinel) and nothing else."
        let deliveryInstruction: String = {
            switch deliveryReason {
            case .directMention:
                if directlyMentioned {
                    return "\nYou were directly @mentioned by the user. You MUST respond substantively.\n"
                }
                guard allowNoReply || routingMode == .mentionAware else { return "" }
                return "\nYou were not directly mentioned. \(responseOnlyIfMaterial)\n"
            case .broadcast:
                return "\nThe whole group was addressed. \(responseOnlyIfMaterial)\n"
            case .coordinatorLead:
                return "\nThe user did not mention anyone. You are receiving this turn first because you are the group's coordinator. You MUST respond substantively and help direct the next step.\n"
            case .implicitFallback:
                return "\nNo one was directly mentioned and no coordinator is set for this group. \(responseOnlyIfMaterial)\n"
            case .broad:
                guard allowNoReply else { return "" }
                return "\nYou were not directly mentioned. \(responseOnlyIfMaterial)\n"
            }
        }()
        return """
        \(instructionBlock)\(roleBlock)\(rosterBlock)\(communicationGuidelines)--- Group thread (new since your last reply) ---
        \(clipped)
        --- End ---
        \(mentionNote)
        You are @\(agentName). Respond to the latest user message in this group.
        \(deliveryInstruction)
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
        deliveryReason: GroupRoutingPlanner.PeerDeliveryReason = .generic,
        routingMode: GroupRoutingMode = .broad,
        allowNoReply: Bool = false,
        role: GroupRole? = nil,
        teamMembers: [TeamMemberInfo] = []
    ) -> String {
        let name = recipientSession.agent?.name ?? "Assistant"
        let body = peerMessageText.trimmingCharacters(in: .whitespacesAndNewlines)
        let shown = body.isEmpty ? "(empty)" : body

        let rosterBlock = buildTeamRoster(targetAgentName: name, teamMembers: teamMembers)

        let rolePrefix: String = {
            switch role {
            case .observer:
                return "You are @\(name) (observer)."
            case .scribe:
                return "You are @\(name) (scribe)."
            case .coordinator:
                return "You are @\(name) (coordinator)."
            default:
                return "You are @\(name)."
            }
        }()
        let roleSuffix: String = {
            switch role {
            case .observer:
                return " Only reply if you are directly addressed by name or have critical information."
            case .scribe:
                return " If this exchange contains a decision or outcome, record it to the blackboard. You may also reply briefly to the group."
            case .coordinator:
                return " Consider whether this changes the plan or requires redirecting the group. Reply if you have guidance."
            default:
                return ""
            }
        }()

        let roleInstruction: String
        switch deliveryReason {
        case .directMention:
            roleInstruction = "\(rolePrefix) Another participant directly @mentioned you. You MUST respond substantively.\(role == nil ? "" : roleSuffix)"
        case .broadcast:
            let suffix = (routingMode == .mentionAware || allowNoReply)
                ? " Reply only if you can add net-new information that materially advances the conversation or mission. If not, reply with exactly \(noReplySentinel) and nothing else."
                : " Reply if you have something substantive to add; stay concise."
            roleInstruction = "\(rolePrefix) Another participant addressed the whole group with @all.\(suffix)\(role == nil ? "" : roleSuffix)"
        case .generic:
            if role == nil && allowNoReply {
                roleInstruction = "\(rolePrefix) Another participant posted the above in this shared group. Reply only if you can add net-new information that materially advances the conversation or mission. If not, reply with exactly \(noReplySentinel) and nothing else."
            } else if role == nil {
                roleInstruction = "\(rolePrefix) Another participant posted the above in this shared group. You may reply to the whole group if you have something substantive to add; stay concise."
            } else {
                roleInstruction = "\(rolePrefix)\(roleSuffix)"
            }
        }

        return """
        \(rosterBlock)\(communicationGuidelines)--- Group chat: peer message ---
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

    static func buildSilentObserverContextPrompt(
        senderLabel: String,
        triggerText: String
    ) -> String {
        """
        [Silent observer context — do not reply]
        \(senderLabel): \(triggerText)
        """
    }

    static func senderDisplayLabel(for message: ConversationMessage, participants: [Participant]) -> String {
        senderLabel(for: message, participants: participants)
    }

    private static func deltaTranscriptLines(
        sortedChat: [ConversationMessage],
        lastInjectedMessageId: UUID?,
        participants: [Participant],
        throughMessageId: UUID?
    ) -> [String] {
        var startIndex = 0
        if let wid = lastInjectedMessageId,
           let idx = sortedChat.firstIndex(where: { $0.id == wid }) {
            startIndex = idx + 1
        } else if lastInjectedMessageId != nil {
            startIndex = 0
        }

        let endIndex: Int = {
            guard let throughMessageId else { return sortedChat.count - 1 }
            return sortedChat.firstIndex(where: { $0.id == throughMessageId }) ?? (sortedChat.count - 1)
        }()

        guard startIndex <= endIndex, startIndex < sortedChat.count else { return [] }

        return sortedChat[startIndex...endIndex].map { msg in
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
        case .remoteUser:
            return p.displayName
        case .remoteAgent:
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

    /// Call when a session consumed a prompt but intentionally produced no visible assistant reply.
    static func markSessionCaughtUp(session: Session, through message: ConversationMessage?) {
        session.lastInjectedMessageId = message?.id
    }

    static func isNoReplySentinel(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines) == noReplySentinel
    }
}
