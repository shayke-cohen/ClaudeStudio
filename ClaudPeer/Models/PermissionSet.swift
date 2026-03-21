import Foundation
import SwiftData

@Model
final class PermissionSet {
    var id: UUID
    var name: String
    var allowRules: [String]
    var denyRules: [String]
    var additionalDirectories: [String]
    var permissionMode: String
    var createdAt: Date

    init(name: String, allowRules: [String] = [], denyRules: [String] = [], permissionMode: String = "default") {
        self.id = UUID()
        self.name = name
        self.allowRules = allowRules
        self.denyRules = denyRules
        self.additionalDirectories = []
        self.permissionMode = permissionMode
        self.createdAt = Date()
    }
}
