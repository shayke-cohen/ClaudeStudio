import Foundation
import SwiftData

enum InstancePolicy: Sendable, Hashable {
    case spawn
    case singleton
    case pool(max: Int)
}

enum AgentOrigin: Sendable, Hashable {
    case local
    case peer(peerId: UUID)
    case imported
}

@Model
final class Agent {
    var id: UUID
    var name: String
    var agentDescription: String
    var systemPrompt: String
    var skillIds: [UUID]
    var mcpServerIds: [UUID]
    var permissionSetId: UUID?
    var model: String
    var maxTurns: Int?
    var maxBudget: Double?
    var icon: String
    var color: String

    // InstancePolicy flattened for SwiftData
    var instancePolicyKind: String
    var instancePolicyPoolMax: Int?

    // AgentOrigin flattened for SwiftData
    var originKind: String
    var originPeerId: UUID?

    var defaultWorkingDirectory: String?
    var githubRepo: String?
    var githubDefaultBranch: String?
    var isShared: Bool
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Session.agent)
    var sessions: [Session] = []

    @Transient
    var instancePolicy: InstancePolicy {
        get {
            switch instancePolicyKind {
            case "singleton": return .singleton
            case "pool": return .pool(max: instancePolicyPoolMax ?? 3)
            default: return .spawn
            }
        }
        set {
            switch newValue {
            case .spawn:
                instancePolicyKind = "spawn"
                instancePolicyPoolMax = nil
            case .singleton:
                instancePolicyKind = "singleton"
                instancePolicyPoolMax = nil
            case .pool(let max):
                instancePolicyKind = "pool"
                instancePolicyPoolMax = max
            }
        }
    }

    @Transient
    var origin: AgentOrigin {
        get {
            switch originKind {
            case "peer":
                return .peer(peerId: originPeerId ?? UUID())
            case "imported":
                return .imported
            default:
                return .local
            }
        }
        set {
            switch newValue {
            case .local:
                originKind = "local"
                originPeerId = nil
            case .peer(let peerId):
                originKind = "peer"
                originPeerId = peerId
            case .imported:
                originKind = "imported"
                originPeerId = nil
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
        self.mcpServerIds = []
        self.model = model
        self.maxTurns = nil
        self.maxBudget = nil
        self.icon = icon
        self.color = color
        self.instancePolicyKind = "spawn"
        self.instancePolicyPoolMax = nil
        self.originKind = "local"
        self.originPeerId = nil
        self.isShared = false
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
