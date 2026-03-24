import Foundation

enum GroupRole: String, CaseIterable, Sendable {
    case participant
    case coordinator
    case scribe
    case observer

    var displayName: String {
        switch self {
        case .participant: return "Participant"
        case .coordinator: return "Coordinator"
        case .scribe: return "Scribe"
        case .observer: return "Observer"
        }
    }

    var systemPromptSnippet: String {
        switch self {
        case .participant:
            return ""
        case .coordinator:
            return "You are the coordinator of this group. Direct the conversation, delegate tasks to team members, synthesize results, and ensure the group stays on track."
        case .scribe:
            return "You are the scribe. After each significant exchange, write a summary of decisions and outcomes to the blackboard using the blackboard_write tool. Keep the group's shared knowledge up to date."
        case .observer:
            return "You are an observer. Only speak when directly addressed by name or when you have critical information to add. Do not respond to every message."
        }
    }
}
