import Foundation
import SwiftData

enum AgentOrigin: Sendable, Hashable {
    case local
    case peer(peerName: String)
    case imported
    case builtin
}

enum AgentInstancePolicy: String, Codable, CaseIterable, Sendable {
    case agentDefault
    case spawn
    case singleton
    case pool

    var displayName: String {
        switch self {
        case .agentDefault: return "Agent Default"
        case .spawn: return "Spawn"
        case .singleton: return "Singleton"
        case .pool: return "Pool"
        }
    }
}

@Model
final class Agent {
    var id: UUID
    var name: String
    var agentDescription: String
    var systemPrompt: String
    var provider: String = ProviderSelection.system.rawValue
    var skillIds: [UUID]
    var extraMCPServerIds: [UUID]
    var permissionSetId: UUID?
    var catalogId: String?
    var model: String
    var maxTurns: Int?
    var maxBudget: Double?
    var maxThinkingTokens: Int?
    private var instancePolicyRaw: String?
    var instancePolicyPoolMax: Int?
    var icon: String
    var color: String

    // AgentOrigin flattened for SwiftData
    var originKind: String
    var originPeerName: String?
    /// The original UUID of the agent on the remote peer (used for duplicate import detection)
    var originRemoteId: UUID?

    var defaultWorkingDirectory: String?
    var isShared: Bool
    var isEnabled: Bool = true
    var configSlug: String?
    var createdAt: Date
    var updatedAt: Date
    var identityBundleJSON: String? = nil

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

    @Transient
    var instancePolicy: AgentInstancePolicy {
        get { AgentInstancePolicy(rawValue: instancePolicyRaw ?? "") ?? .agentDefault }
        set { instancePolicyRaw = newValue.rawValue }
    }

    @Transient
    var instancePolicyWireValue: String? {
        switch instancePolicy {
        case .agentDefault:
            return nil
        case .spawn, .singleton:
            return instancePolicy.rawValue
        case .pool:
            let max = max(1, instancePolicyPoolMax ?? 2)
            return "pool:\(max)"
        }
    }

    init(
        name: String,
        agentDescription: String = "",
        systemPrompt: String = "",
        provider: String = ProviderSelection.system.rawValue,
        model: String = AgentDefaults.inheritMarker,
        icon: String = "cpu",
        color: String = "blue"
    ) {
        self.id = UUID()
        self.name = name
        self.agentDescription = agentDescription
        self.systemPrompt = systemPrompt
        self.provider = provider
        self.skillIds = []
        self.extraMCPServerIds = []
        self.model = model
        self.catalogId = nil
        self.maxTurns = nil
        self.maxBudget = nil
        self.maxThinkingTokens = 10000
        self.instancePolicyRaw = AgentInstancePolicy.agentDefault.rawValue
        self.instancePolicyPoolMax = nil
        self.icon = icon
        self.color = color
        self.originKind = "local"
        self.originPeerName = nil
        self.originRemoteId = nil
        self.isShared = false
        self.isEnabled = true
        self.configSlug = nil
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
