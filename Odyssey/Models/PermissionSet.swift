import Foundation
import SwiftData

@Model
final class PermissionSet {
    var id: UUID = UUID()
    var name: String = ""
    var allowRules: [String] = []
    var denyRules: [String] = []
    var additionalDirectories: [String] = []
    var permissionMode: String = "default"
    var isEnabled: Bool = true
    var configSlug: String?
    var createdAt: Date = Date()

    init(name: String, allowRules: [String] = [], denyRules: [String] = [], permissionMode: String = "default") {
        self.id = UUID()
        self.name = name
        self.allowRules = allowRules
        self.denyRules = denyRules
        self.additionalDirectories = []
        self.permissionMode = permissionMode
        self.isEnabled = true
        self.configSlug = nil
        self.createdAt = Date()
    }
}
