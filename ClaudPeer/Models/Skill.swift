import Foundation
import SwiftData

enum SkillSource: Codable, Sendable, Hashable {
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
    var source: SkillSource
    var version: String
    var createdAt: Date
    var updatedAt: Date

    init(name: String, skillDescription: String = "", category: String = "General", content: String = "") {
        self.id = UUID()
        self.name = name
        self.skillDescription = skillDescription
        self.category = category
        self.content = content
        self.triggers = []
        self.source = .custom
        self.version = "1.0"
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
