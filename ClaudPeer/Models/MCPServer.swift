import Foundation
import SwiftData

enum MCPTransport: Sendable, Hashable {
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
    var toolSchemas: String?
    var resourceSchemas: String?
    var status: MCPStatus
    var createdAt: Date

    // MCPTransport flattened for SwiftData
    var transportKind: String
    var transportCommand: String?
    var transportUrl: String?
    var transportArgsJSON: String?
    var transportEnvJSON: String?
    var transportHeadersJSON: String?

    @Transient
    var transport: MCPTransport {
        get {
            switch transportKind {
            case "stdio":
                let args = decodeJSON([String].self, from: transportArgsJSON) ?? []
                let env = decodeJSON([String: String].self, from: transportEnvJSON) ?? [:]
                return .stdio(command: transportCommand ?? "", args: args, env: env)
            default:
                let headers = decodeJSON([String: String].self, from: transportHeadersJSON) ?? [:]
                return .http(url: transportUrl ?? "", headers: headers)
            }
        }
        set {
            switch newValue {
            case .stdio(let command, let args, let env):
                transportKind = "stdio"
                transportCommand = command
                transportUrl = nil
                transportArgsJSON = encodeJSON(args)
                transportEnvJSON = encodeJSON(env)
                transportHeadersJSON = nil
            case .http(let url, let headers):
                transportKind = "http"
                transportCommand = nil
                transportUrl = url
                transportArgsJSON = nil
                transportEnvJSON = nil
                transportHeadersJSON = encodeJSON(headers)
            }
        }
    }

    init(name: String, serverDescription: String = "", transport: MCPTransport) {
        self.id = UUID()
        self.name = name
        self.serverDescription = serverDescription
        self.status = .available
        self.createdAt = Date()
        self.transportKind = "stdio"
        self.transportCommand = nil
        self.transportUrl = nil
        self.transportArgsJSON = nil
        self.transportEnvJSON = nil
        self.transportHeadersJSON = nil
        self.transport = transport
    }

    private func encodeJSON<T: Encodable>(_ value: T) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func decodeJSON<T: Decodable>(_ type: T.Type, from string: String?) -> T? {
        guard let string, let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
