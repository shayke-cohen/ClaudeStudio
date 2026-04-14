import Foundation
import SwiftData

enum ParticipantType: Sendable, Hashable {
    case user
    case agentSession(sessionId: UUID)
    case remoteUser(userId: String, participantId: String, homeNodeId: String)
    case remoteAgent(participantId: String, homeNodeId: String, ownerUserId: String, agentName: String)
}

enum ParticipantRole: String, Codable, Sendable {
    case active
    case observer
    case silentObserver
}

@Model
final class Participant {
    var id: UUID
    var displayName: String
    var role: ParticipantRole
    var conversation: Conversation?

    // ParticipantType flattened for SwiftData
    var typeKind: String = "user"
    var typeSessionId: UUID?
    var typeParticipantId: String?
    var typeUserId: String?
    var typeHomeNodeId: String?
    var typeRemoteAgentName: String?
    var roomParticipantId: String?
    var roomUserId: String?
    var roomHomeNodeId: String?
    var isLocalParticipant: Bool = true
    var ownerDisplayName: String? = nil
    var isVerified: Bool = false
    var ownerPublicKeyData: Data? = nil
    var agentIdentityBundleJSON: String? = nil
    var matrixId: String? = nil
    private var membershipStatusRaw: String = SharedRoomMembershipStatus.active.rawValue

    @Transient
    var type: ParticipantType {
        get {
            switch typeKind {
            case "agentSession":
                return .agentSession(sessionId: typeSessionId ?? UUID())
            case "remoteUser":
                return .remoteUser(
                    userId: typeUserId ?? "",
                    participantId: typeParticipantId ?? "",
                    homeNodeId: typeHomeNodeId ?? ""
                )
            case "remoteAgent":
                return .remoteAgent(
                    participantId: typeParticipantId ?? "",
                    homeNodeId: typeHomeNodeId ?? "",
                    ownerUserId: typeUserId ?? "",
                    agentName: typeRemoteAgentName ?? displayName
                )
            default:
                return .user
            }
        }
        set {
            switch newValue {
            case .user:
                typeKind = "user"
                typeSessionId = nil
                typeParticipantId = nil
                typeUserId = nil
                typeHomeNodeId = nil
                typeRemoteAgentName = nil
                isLocalParticipant = true
            case .agentSession(let sessionId):
                typeKind = "agentSession"
                typeSessionId = sessionId
                typeParticipantId = nil
                typeUserId = nil
                typeHomeNodeId = nil
                typeRemoteAgentName = nil
                isLocalParticipant = true
            case .remoteUser(let userId, let participantId, let homeNodeId):
                typeKind = "remoteUser"
                typeSessionId = nil
                typeParticipantId = participantId
                typeUserId = userId
                typeHomeNodeId = homeNodeId
                typeRemoteAgentName = nil
                isLocalParticipant = false
            case .remoteAgent(let participantId, let homeNodeId, let ownerUserId, let agentName):
                typeKind = "remoteAgent"
                typeSessionId = nil
                typeParticipantId = participantId
                typeUserId = ownerUserId
                typeHomeNodeId = homeNodeId
                typeRemoteAgentName = agentName
                isLocalParticipant = false
            }
        }
    }

    var membershipStatus: SharedRoomMembershipStatus {
        get { SharedRoomMembershipStatus(rawValue: membershipStatusRaw) ?? .active }
        set { membershipStatusRaw = newValue.rawValue }
    }

    init(type: ParticipantType, displayName: String, role: ParticipantRole = .active) {
        self.id = UUID()
        self.displayName = displayName
        self.role = role
        self.typeKind = "user"
        self.typeSessionId = nil
        self.typeParticipantId = nil
        self.typeUserId = nil
        self.typeHomeNodeId = nil
        self.typeRemoteAgentName = nil
        self.roomParticipantId = nil
        self.roomUserId = nil
        self.roomHomeNodeId = nil
        self.isLocalParticipant = true
        self.membershipStatusRaw = SharedRoomMembershipStatus.active.rawValue
        self.type = type
    }
}
