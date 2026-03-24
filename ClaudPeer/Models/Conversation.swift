import Foundation
import SwiftData

enum ConversationStatus: String, Codable, Sendable {
    case active
    case closed
}

@Model
final class Conversation {
    var id: UUID
    var topic: String?
    var parentConversationId: UUID?
    var status: ConversationStatus
    var summary: String?
    var isPinned: Bool = false
    var isArchived: Bool = false
    var sourceGroupId: UUID?
    var startedAt: Date
    var closedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \Session.conversations)
    var sessions: [Session] = []

    @Relationship(deleteRule: .cascade, inverse: \Participant.conversation)
    var participants: [Participant] = []

    @Relationship(deleteRule: .cascade, inverse: \ConversationMessage.conversation)
    var messages: [ConversationMessage] = []

    init(topic: String? = nil, sessions: [Session] = []) {
        self.id = UUID()
        self.topic = topic
        self.status = .active
        self.isPinned = false
        self.isArchived = false
        self.startedAt = Date()
        self.sessions = sessions
    }

    /// First session by start time; used for inspector, delegate source, and single-agent UX.
    var primarySession: Session? {
        sessions.min(by: { $0.startedAt < $1.startedAt })
    }
}
