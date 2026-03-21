import Foundation
import SwiftData

enum ParticipantType: Sendable, Hashable {
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
    var displayName: String
    var role: ParticipantRole
    var conversation: Conversation?

    // ParticipantType flattened for SwiftData
    var typeKind: String
    var typeSessionId: UUID?

    @Transient
    var type: ParticipantType {
        get {
            switch typeKind {
            case "agentSession":
                return .agentSession(sessionId: typeSessionId ?? UUID())
            default:
                return .user
            }
        }
        set {
            switch newValue {
            case .user:
                typeKind = "user"
                typeSessionId = nil
            case .agentSession(let sessionId):
                typeKind = "agentSession"
                typeSessionId = sessionId
            }
        }
    }

    init(type: ParticipantType, displayName: String, role: ParticipantRole = .active) {
        self.id = UUID()
        self.displayName = displayName
        self.role = role
        self.typeKind = "user"
        self.typeSessionId = nil
        self.type = type
    }
}
