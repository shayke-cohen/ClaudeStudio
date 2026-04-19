import Foundation
import SwiftData

enum MessageType: String, Codable, Sendable {
    case chat
    case toolCall
    case toolResult
    case system
    case delegation
    case blackboardUpdate
    case peerMessage
    case taskEvent
    case workspaceEvent
    case agentInvite
    case question
    case richContent
    case systemEvaluation

    var isPeerChannel: Bool {
        switch self {
        case .peerMessage, .delegation, .blackboardUpdate,
             .taskEvent, .workspaceEvent, .agentInvite:
            return true
        default:
            return false
        }
    }

    var peerChannelCategory: PeerChannelCategory? {
        switch self {
        case .peerMessage: return .messages
        case .delegation: return .delegations
        case .blackboardUpdate: return .blackboard
        case .taskEvent: return .tasks
        case .workspaceEvent: return .workspace
        case .agentInvite: return .invites
        default: return nil
        }
    }
}

enum PeerChannelCategory: String, CaseIterable, Sendable {
    case messages = "Messages"
    case delegations = "Delegations"
    case blackboard = "Blackboard"
    case tasks = "Tasks"
    case workspace = "Workspace"
    case invites = "Invites"

    var icon: String {
        switch self {
        case .messages: return "bubble.left.and.bubble.right.fill"
        case .delegations: return "arrow.right.circle.fill"
        case .blackboard: return "square.grid.2x2.fill"
        case .tasks: return "checklist"
        case .workspace: return "folder.fill"
        case .invites: return "person.badge.plus"
        }
    }
}

@Model
final class ConversationMessage {
    var id: UUID
    var senderParticipantId: UUID?
    var text: String
    var timestamp: Date
    var type: MessageType
    var toolName: String?
    var toolInput: String?
    var toolOutput: String?
    var thinkingText: String?
    var workflowStepIndex: Int?
    var isStreaming: Bool
    var roomMessageId: String?
    var roomRootMessageId: String?
    var roomParentMessageId: String?
    var roomOriginNodeId: String?
    var roomOriginParticipantId: String?
    var roomHostSequence: Int = 0
    private var roomDeliveryModeRaw: String?
    var conversation: Conversation?

    @Relationship(deleteRule: .nullify, inverse: \MessageAttachment.message)
    var attachments: [MessageAttachment] = []

    init(
        senderParticipantId: UUID? = nil,
        text: String,
        type: MessageType = .chat,
        conversation: Conversation? = nil
    ) {
        self.id = UUID()
        self.senderParticipantId = senderParticipantId
        self.text = text
        self.timestamp = Date()
        self.type = type
        self.isStreaming = false
        self.roomHostSequence = 0
        self.conversation = conversation
    }

    var roomDeliveryMode: SharedRoomMessageDeliveryMode? {
        get { roomDeliveryModeRaw.flatMap(SharedRoomMessageDeliveryMode.init(rawValue:)) }
        set { roomDeliveryModeRaw = newValue?.rawValue }
    }
}
