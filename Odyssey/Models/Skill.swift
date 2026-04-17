import Foundation
import SwiftData

enum SkillSource: Sendable, Hashable {
    case filesystem(path: String)
    case peer(peerName: String)
    case builtin
    case custom
}

@Model
final class Skill {
    var id: UUID
    var name: String
    var skillDescription: String
    var category: String
    var content: String
    var triggers: [String]
    var version: String
    var createdAt: Date
    var updatedAt: Date
    var mcpServerIds: [UUID]
    var catalogId: String?
    var isEnabled: Bool = true
    var configSlug: String?

    // SkillSource flattened for SwiftData
    // sourceKind defaults to "custom" for UI-created skills.
    // ConfigSyncService sets sourceKind="filesystem", configSlug, and sourceValue
    // when creating/updating skills from disk files.
    var sourceKind: String
    var sourceValue: String?

    @Transient
    var source: SkillSource {
        get {
            switch sourceKind {
            case "filesystem": return .filesystem(path: sourceValue ?? "")
            case "peer": return .peer(peerName: sourceValue ?? "Unknown")
            case "builtin": return .builtin
            default: return .custom
            }
        }
        set {
            switch newValue {
            case .filesystem(let path):
                sourceKind = "filesystem"
                sourceValue = path
            case .peer(let peerName):
                sourceKind = "peer"
                sourceValue = peerName
            case .builtin:
                sourceKind = "builtin"
                sourceValue = nil
            case .custom:
                sourceKind = "custom"
                sourceValue = nil
            }
        }
    }

    init(name: String, skillDescription: String = "", category: String = "General", content: String = "") {
        self.id = UUID()
        self.name = name
        self.skillDescription = skillDescription
        self.category = category
        self.content = content
        self.triggers = []
        self.version = "1.0"
        self.createdAt = Date()
        self.updatedAt = Date()
        self.mcpServerIds = []
        self.catalogId = nil
        self.isEnabled = true
        self.configSlug = nil
        self.sourceKind = "custom"
        self.sourceValue = nil
    }
}
