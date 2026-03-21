import Foundation
import SwiftData

enum ParticipantType: Codable, Sendable, Hashable {
    case user
    case agentSession(sessionId: UUID)
}

enum ParticipantRole: String, Codable, Sendable {
    case active
    case observer
}

@Model
final class Participant {
    var id: UUID
    var type: ParticipantType
    var displayName: String
    var role: ParticipantRole
    var conversation: Conversation?

    init(type: ParticipantType, displayName: String, role: ParticipantRole = .active) {
        self.id = UUID()
        self.type = type
        self.displayName = displayName
        self.role = role
    }
}
