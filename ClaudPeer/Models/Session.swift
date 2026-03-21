import Foundation
import SwiftData

enum SessionStatus: String, Codable, Sendable {
    case active
    case paused
    case completed
    case failed
}

enum SessionMode: String, Codable, Sendable {
    case interactive
    case autonomous
    case worker
}

enum WorkspaceType: Codable, Sendable, Hashable {
    case explicit(path: String)
    case agentDefault
    case githubClone(repoUrl: String)
    case ephemeral
    case shared(workspaceId: UUID)
}

@Model
final class Session {
    var id: UUID
    var claudeSessionId: String?
    var agent: Agent?
    var mission: String?
    var githubIssue: String?
    var status: SessionStatus
    var mode: SessionMode
    var workingDirectory: String
    var workspaceType: WorkspaceType
    var parentSessionId: UUID?
    var pid: Int?
    var startedAt: Date
    var lastActiveAt: Date
    var tokenCount: Int
    var totalCost: Double
    var toolCallCount: Int

    @Relationship(deleteRule: .cascade, inverse: \Conversation.session)
    var conversations: [Conversation] = []

    init(
        agent: Agent?,
        mission: String? = nil,
        mode: SessionMode = .interactive,
        workingDirectory: String = "",
        workspaceType: WorkspaceType = .ephemeral
    ) {
        self.id = UUID()
        self.agent = agent
        self.mission = mission
        self.status = .active
        self.mode = mode
        self.workingDirectory = workingDirectory
        self.workspaceType = workspaceType
        self.startedAt = Date()
        self.lastActiveAt = Date()
        self.tokenCount = 0
        self.totalCost = 0
        self.toolCallCount = 0
    }
}
