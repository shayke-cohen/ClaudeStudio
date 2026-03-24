import Foundation
import SwiftData

/// Generates per-agent activity summaries for group conversations.
@MainActor
enum GroupSummaryBuilder {

    struct AgentContribution: Identifiable {
        let id = UUID()
        let agentName: String
        let agentIcon: String
        let agentColor: String
        let messageCount: Int
        let toolCallCount: Int
        let keyActions: [String]
    }

    struct GroupSummary {
        let contributions: [AgentContribution]
        let totalMessages: Int
        let totalToolCalls: Int
        let duration: TimeInterval
    }

    static func buildSummary(conversation: Conversation) -> GroupSummary {
        let participants = conversation.participants
        let messages = conversation.messages.sorted { $0.timestamp < $1.timestamp }

        let agentParticipants = participants.filter {
            if case .agentSession = $0.type { return true }
            return false
        }

        var contributions: [AgentContribution] = []
        var totalMessages = 0
        var totalToolCalls = 0

        for participant in agentParticipants {
            let agentMessages = messages.filter { $0.senderParticipantId == participant.id }
            let chatMessages = agentMessages.filter { $0.type == .chat }
            let toolCalls = agentMessages.filter { $0.type == .toolCall }

            totalMessages += chatMessages.count
            totalToolCalls += toolCalls.count

            let keyActions: [String] = chatMessages.suffix(3).map { msg in
                let text = msg.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if text.count <= 80 { return text }
                return String(text.prefix(80)) + "..."
            }

            // Resolve agent info from session
            let session = conversation.sessions.first { s in
                if case .agentSession(let sid) = participant.type { return s.id == sid }
                return false
            }

            contributions.append(AgentContribution(
                agentName: participant.displayName,
                agentIcon: session?.agent?.icon ?? "cpu",
                agentColor: session?.agent?.color ?? "blue",
                messageCount: chatMessages.count,
                toolCallCount: toolCalls.count,
                keyActions: keyActions
            ))
        }

        let duration: TimeInterval = {
            guard let first = messages.first, let last = messages.last else { return 0 }
            return last.timestamp.timeIntervalSince(first.timestamp)
        }()

        return GroupSummary(
            contributions: contributions.sorted { $0.messageCount > $1.messageCount },
            totalMessages: totalMessages,
            totalToolCalls: totalToolCalls,
            duration: duration
        )
    }

    static func formatForStorage(_ summary: GroupSummary) -> String {
        var lines: [String] = ["Group Activity Summary"]
        lines.append("Duration: \(formatDuration(summary.duration))")
        lines.append("Total: \(summary.totalMessages) messages, \(summary.totalToolCalls) tool calls\n")

        for c in summary.contributions {
            lines.append("\(c.agentName): \(c.messageCount) messages, \(c.toolCallCount) tool calls")
            for action in c.keyActions {
                lines.append("  - \(action)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        if mins < 1 { return "\(Int(seconds))s" }
        if mins < 60 { return "\(mins)m" }
        return "\(mins / 60)h \(mins % 60)m"
    }
}
