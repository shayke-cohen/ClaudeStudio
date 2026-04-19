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
    var id: UUID = UUID()
    var name: String = ""
    var agentDescription: String = ""
    var systemPrompt: String = ""
    var provider: String = ProviderSelection.system.rawValue
    var skillIds: [UUID] = []
    var extraMCPServerIds: [UUID] = []
    var permissionSetId: UUID?
    var catalogId: String?
    var model: String = ""
    var maxTurns: Int?
    var maxBudget: Double?
    var maxThinkingTokens: Int?
    private var instancePolicyRaw: String?
    var instancePolicyPoolMax: Int?
    var icon: String = "cpu"
    var color: String = "blue"

    // AgentOrigin flattened for SwiftData
    var originKind: String = "local"
    var originPeerName: String?
    /// The original UUID of the agent on the remote peer (used for duplicate import detection)
    var originRemoteId: UUID?

    var defaultWorkingDirectory: String?
    var isResident: Bool = false
    var isShared: Bool = false
    var isEnabled: Bool = true
    var showInSidebar: Bool = true
    var configSlug: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var identityBundleJSON: String? = nil

    @Relationship(deleteRule: .nullify, inverse: \Session.agent)
    var sessions: [Session]? = nil

    @Relationship(deleteRule: .nullify, inverse: \PromptTemplate.agent)
    var promptTemplates: [PromptTemplate]? = nil

    static func defaultHomePath(for name: String) -> String {
        let slug = name
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "~/.odyssey/residents/\(slug.isEmpty ? "agent" : slug)"
    }

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
        self.defaultWorkingDirectory = Agent.defaultHomePath(for: name)
        self.isResident = false
        self.isShared = false
        self.isEnabled = true
        self.showInSidebar = true
        self.configSlug = nil
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
