import Foundation
import SwiftData

enum AgentOrigin: Sendable, Hashable {
    case local
    case peer(peerName: String)
    case imported
    case builtin
}

@Model
final class Agent {
    var id: UUID
    var name: String
    var agentDescription: String
    var systemPrompt: String
    var skillIds: [UUID]
    var extraMCPServerIds: [UUID]
    var permissionSetId: UUID?
    var catalogId: String?
    var model: String
    var maxTurns: Int?
    var maxBudget: Double?
    var maxThinkingTokens: Int?
    var icon: String
    var color: String

    // AgentOrigin flattened for SwiftData
    var originKind: String
    var originPeerName: String?
    /// The original UUID of the agent on the remote peer (used for duplicate import detection)
    var originRemoteId: UUID?

    var defaultWorkingDirectory: String?
    var githubRepo: String?
    var githubDefaultBranch: String?
    var githubAutoCreateBranch: Bool
    var isShared: Bool
    var isEnabled: Bool = true
    var configSlug: String?
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Session.agent)
    var sessions: [Session] = []

    @Transient
    var origin: AgentOrigin {
        get {
            switch originKind {
            case "peer":
                return .peer(peerName: originPeerName ?? "Unknown")
            case "imported":
                return .imported
            case "builtin":
                return .builtin
            default:
                return .local
            }
        }
        set {
            switch newValue {
            case .local:
                originKind = "local"
                originPeerName = nil
            case .peer(let peerName):
                originKind = "peer"
                originPeerName = peerName
            case .imported:
                originKind = "imported"
                originPeerName = nil
            case .builtin:
                originKind = "builtin"
                originPeerName = nil
            }
        }
    }

    init(
        name: String,
        agentDescription: String = "",
        systemPrompt: String = "",
        model: String = "sonnet",
        icon: String = "cpu",
        color: String = "blue"
    ) {
        self.id = UUID()
        self.name = name
        self.agentDescription = agentDescription
        self.systemPrompt = systemPrompt
        self.skillIds = []
        self.extraMCPServerIds = []
        self.model = model
        self.catalogId = nil
        self.maxTurns = nil
        self.maxBudget = nil
        self.maxThinkingTokens = 10000
        self.icon = icon
        self.color = color
        self.originKind = "local"
        self.originPeerName = nil
        self.originRemoteId = nil
        self.githubAutoCreateBranch = false
        self.isShared = false
        self.isEnabled = true
        self.configSlug = nil
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
