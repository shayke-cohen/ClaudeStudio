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
        self.originKind = "local"
        self.originPeerName = nil
        self.originRemoteId = nil
    }
}
