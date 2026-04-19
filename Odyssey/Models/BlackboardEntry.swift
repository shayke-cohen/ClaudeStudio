import Foundation
import SwiftData

@Model
final class BlackboardEntry {
    var id: UUID = UUID()
    var key: String = ""
    var value: String = ""
    var writtenBy: String = ""
    var workspaceId: UUID?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(key: String, value: String, writtenBy: String, workspaceId: UUID? = nil) {
        self.id = UUID()
        self.key = key
        self.value = value
        self.writtenBy = writtenBy
        self.workspaceId = workspaceId
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
