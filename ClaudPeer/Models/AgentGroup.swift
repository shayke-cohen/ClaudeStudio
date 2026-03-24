import Foundation
import SwiftData

enum AgentGroupOrigin: Sendable, Hashable {
    case local
    case peer(peerName: String)
    case imported
    case builtin
}

@Model
final class AgentGroup {
    var id: UUID
    var name: String
    var groupDescription: String
    var icon: String
    var color: String
    var groupInstruction: String
    var defaultMission: String?
    var agentIds: [UUID]
    var sortOrder: Int
    var createdAt: Date

    // Feature: Auto-Reply toggle
    var autoReplyEnabled: Bool
    // Feature: Autonomous mode
    var autonomousCapable: Bool
    var coordinatorAgentId: UUID?
    // Feature: Roles — JSON-encoded {uuid-string: role-name}
    var agentRolesJSON: String?
    // Feature: Workflow — JSON-encoded [WorkflowStep]
    var workflowJSON: String?

    // AgentGroupOrigin flattened for SwiftData
    var originKind: String
    var originPeerName: String?
    /// The original UUID of the group on the remote peer (used for duplicate import detection)
    var originRemoteId: UUID?

    @Transient
    var origin: AgentGroupOrigin {
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
    var agentRoles: [UUID: String] {
        get {
            guard let json = agentRolesJSON,
                  let data = json.data(using: .utf8),
                  let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
            return Dictionary(uniqueKeysWithValues: dict.compactMap { k, v in
                UUID(uuidString: k).map { ($0, v) }
            })
        }
        set {
            let stringDict = Dictionary(uniqueKeysWithValues: newValue.map { ($0.key.uuidString, $0.value) })
            agentRolesJSON = (try? String(data: JSONEncoder().encode(stringDict), encoding: .utf8))
        }
    }

    @Transient
    var workflow: [WorkflowStep]? {
        get {
            guard let json = workflowJSON,
                  let data = json.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode([WorkflowStep].self, from: data)
        }
        set {
            guard let steps = newValue else { workflowJSON = nil; return }
            workflowJSON = (try? String(data: JSONEncoder().encode(steps), encoding: .utf8))
        }
    }

    func roleFor(agentId: UUID) -> GroupRole {
        GroupRole(rawValue: agentRoles[agentId] ?? "") ?? .participant
    }

    init(
        name: String,
        groupDescription: String = "",
        icon: String = "👥",
        color: String = "blue",
        groupInstruction: String = "",
        defaultMission: String? = nil,
        agentIds: [UUID] = [],
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.groupDescription = groupDescription
        self.icon = icon
        self.color = color
        self.groupInstruction = groupInstruction
        self.defaultMission = defaultMission
        self.agentIds = agentIds
        self.sortOrder = sortOrder
        self.createdAt = Date()
        self.autoReplyEnabled = true
        self.autonomousCapable = false
        self.coordinatorAgentId = nil
        self.agentRolesJSON = nil
        self.workflowJSON = nil
        self.originKind = "local"
        self.originPeerName = nil
        self.originRemoteId = nil
    }
}
