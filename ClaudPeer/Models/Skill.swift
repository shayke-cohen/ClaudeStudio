import Foundation
import SwiftData

enum SkillSource: Sendable, Hashable {
    case filesystem(path: String)
    case peer(peerId: UUID)
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

    // SkillSource flattened for SwiftData
    var sourceKind: String
    var sourceValue: String?

    @Transient
    var source: SkillSource {
        get {
            switch sourceKind {
            case "filesystem": return .filesystem(path: sourceValue ?? "")
            case "peer": return .peer(peerId: UUID(uuidString: sourceValue ?? "") ?? UUID())
            case "builtin": return .builtin
            default: return .custom
            }
        }
        set {
            switch newValue {
            case .filesystem(let path):
                sourceKind = "filesystem"
                sourceValue = path
            case .peer(let peerId):
                sourceKind = "peer"
                sourceValue = peerId.uuidString
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
        self.sourceKind = "custom"
        self.sourceValue = nil
    }
}
