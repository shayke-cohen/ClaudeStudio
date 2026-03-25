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

enum WorkspaceType: Sendable, Hashable {
    case explicit(path: String)
    case agentDefault
    case githubClone(repoUrl: String)
    case ephemeral
    case shared(workspaceId: UUID)
    case worktree(repoUrl: String, branch: String)
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
    var parentSessionId: UUID?
    var pid: Int?
    var startedAt: Date
    var lastActiveAt: Date
    var tokenCount: Int
    var totalCost: Double
    var toolCallCount: Int

    // WorkspaceType flattened for SwiftData
    var workspaceTypeKind: String
    var workspaceTypeValue: String?

    /// Filesystem path of a git worktree created for this session (used for cleanup).
    var worktreePath: String?

    /// Watermark for group transcript injection: last `ConversationMessage.id` included in a prompt to this session.
    var lastInjectedMessageId: UUID?

    /// Inverse is declared on `Conversation.sessions`; omitting `inverse` here avoids a SwiftData macro cycle (SDK 26).
    @Relationship(deleteRule: .nullify)
    var conversations: [Conversation] = []

    @Transient
    var workspaceType: WorkspaceType {
        get {
            switch workspaceTypeKind {
            case "explicit": return .explicit(path: workspaceTypeValue ?? "")
            case "agentDefault": return .agentDefault
            case "githubClone": return .githubClone(repoUrl: workspaceTypeValue ?? "")
            case "shared":
                return .shared(workspaceId: UUID(uuidString: workspaceTypeValue ?? "") ?? UUID())
            case "worktree":
                let parts = (workspaceTypeValue ?? "").split(separator: "\n", maxSplits: 1).map(String.init)
                return .worktree(repoUrl: parts.first ?? "", branch: parts.count > 1 ? parts[1] : "")
            default: return .ephemeral
            }
        }
        set {
            switch newValue {
            case .explicit(let path):
                workspaceTypeKind = "explicit"
                workspaceTypeValue = path
            case .agentDefault:
                workspaceTypeKind = "agentDefault"
                workspaceTypeValue = nil
            case .githubClone(let repoUrl):
                workspaceTypeKind = "githubClone"
                workspaceTypeValue = repoUrl
            case .ephemeral:
                workspaceTypeKind = "ephemeral"
                workspaceTypeValue = nil
            case .shared(let workspaceId):
                workspaceTypeKind = "shared"
                workspaceTypeValue = workspaceId.uuidString
            case .worktree(let repoUrl, let branch):
                workspaceTypeKind = "worktree"
                workspaceTypeValue = "\(repoUrl)\n\(branch)"
            }
        }
    }

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
        self.startedAt = Date()
        self.lastActiveAt = Date()
        self.tokenCount = 0
        self.totalCost = 0
        self.toolCallCount = 0
        self.workspaceTypeKind = "ephemeral"
        self.workspaceTypeValue = nil
        self.workspaceType = workspaceType
        self.lastInjectedMessageId = nil
    }
}
