import Foundation
import SwiftData

@Model
final class SharedWorkspace {
    var id: UUID
    var name: String
    var path: String
    var participantSessionIds: [UUID]
    var createdAt: Date

    init(name: String, path: String) {
        self.id = UUID()
        self.name = name
        self.path = path
        self.participantSessionIds = []
        self.createdAt = Date()
    }
}
