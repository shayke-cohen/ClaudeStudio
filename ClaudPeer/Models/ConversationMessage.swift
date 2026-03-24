import Foundation
import SwiftData

enum MessageType: String, Codable, Sendable {
    case chat
    case toolCall
    case toolResult
    case system
    case delegation
    case blackboardUpdate
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
    var conversation: Conversation?

    @Relationship(deleteRule: .cascade, inverse: \MessageAttachment.message)
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
        self.conversation = conversation
    }
}
