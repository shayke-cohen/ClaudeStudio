import Foundation
import SwiftData

enum MCPTransport: Codable, Sendable, Hashable {
    case stdio(command: String, args: [String], env: [String: String])
    case http(url: String, headers: [String: String])
}

enum MCPStatus: String, Codable, Sendable {
    case available
    case connected
    case error
}

@Model
final class MCPServer {
    var id: UUID
    var name: String
    var serverDescription: String
    var transport: MCPTransport
    var toolSchemas: String?
    var resourceSchemas: String?
    var status: MCPStatus
    var createdAt: Date

    init(name: String, serverDescription: String = "", transport: MCPTransport) {
        self.id = UUID()
        self.name = name
        self.serverDescription = serverDescription
        self.transport = transport
        self.status = .available
        self.createdAt = Date()
    }
}
