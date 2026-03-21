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
    var startedAt: Date
    var closedAt: Date?
    var session: Session?

    @Relationship(deleteRule: .cascade, inverse: \Participant.conversation)
    var participants: [Participant] = []

    @Relationship(deleteRule: .cascade, inverse: \ConversationMessage.conversation)
    var messages: [ConversationMessage] = []

    init(topic: String? = nil, session: Session? = nil) {
        self.id = UUID()
        self.topic = topic
        self.status = .active
        self.startedAt = Date()
        self.session = session
    }
}
