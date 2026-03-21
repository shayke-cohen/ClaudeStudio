import Foundation
import SwiftData

enum PeerStatus: String, Codable, Sendable {
    case discovered
    case connected
    case disconnected
}

@Model
final class Peer {
    var id: UUID
    var displayName: String
    var hostName: String
    var port: Int
    var lastSeen: Date
    var sharedAgentCount: Int
    var sharedSkillCount: Int
    var status: PeerStatus
    var createdAt: Date

    init(displayName: String, hostName: String, port: Int = 0) {
        self.id = UUID()
        self.displayName = displayName
        self.hostName = hostName
        self.port = port
        self.lastSeen = Date()
        self.sharedAgentCount = 0
        self.sharedSkillCount = 0
        self.status = .discovered
        self.createdAt = Date()
    }
}
