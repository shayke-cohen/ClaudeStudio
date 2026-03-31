import Foundation
import SwiftData

enum ThreadKind: String, Codable, CaseIterable, Sendable {
    case direct
    case group
    case freeform
    case autonomous
    case delegation
    case scheduled
}

enum ConversationStatus: String, Codable, Sendable {
    case active
    case closed
}

@Model
final class Project {
    var id: UUID
    var name: String
    var rootPath: String
    var canonicalRootPath: String
    var createdAt: Date
    var lastOpenedAt: Date
    var icon: String
    var color: String
    var pinnedAgentIds: [UUID]
    var pinnedGroupIds: [UUID]

    init(
        name: String,
        rootPath: String,
        canonicalRootPath: String,
        icon: String = "folder",
        color: String = "blue"
    ) {
        let now = Date()
        self.id = UUID()
        self.name = name
        self.rootPath = rootPath
        self.canonicalRootPath = canonicalRootPath
        self.createdAt = now
        self.lastOpenedAt = now
        self.icon = icon
        self.color = color
        self.pinnedAgentIds = []
        self.pinnedGroupIds = []
    }
}

@Model
final class Conversation {
    var id: UUID
    var topic: String?
    var projectId: UUID?
    private var threadKindRaw: String?
    var parentConversationId: UUID?
    var status: ConversationStatus
    var summary: String?
    var isPinned: Bool = false
    var isArchived: Bool = false
    var sourceGroupId: UUID?
    var workflowCurrentStep: Int?
    var workflowCompletedSteps: [Int]?
    var isUnread: Bool = false
    var isAutonomous: Bool = false
    var planModeEnabled: Bool = false
    var selectiveRepliesEnabled: Bool = false
    var worktreePath: String?
    var worktreeBranch: String?
    var startedAt: Date
    var closedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \Session.conversations)
    var sessions: [Session] = []

    @Relationship(deleteRule: .cascade, inverse: \Participant.conversation)
    var participants: [Participant] = []

    @Relationship(deleteRule: .cascade, inverse: \ConversationMessage.conversation)
    var messages: [ConversationMessage] = []

    init(
        topic: String? = nil,
        sessions: [Session] = [],
        projectId: UUID? = nil,
        threadKind: ThreadKind = .direct
    ) {
        self.id = UUID()
        self.topic = topic
        self.projectId = projectId
        self.threadKindRaw = threadKind.rawValue
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

    var threadKind: ThreadKind {
        get { ThreadKind(rawValue: threadKindRaw ?? "") ?? .freeform }
        set { threadKindRaw = newValue.rawValue }
    }
}
