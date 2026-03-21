import Foundation

enum SidecarCommand: Codable, Sendable {
    case sessionCreate(SessionCreatePayload)
    case sessionMessage(SessionMessagePayload)
    case sessionResume(SessionResumePayload)
    case sessionFork(SessionForkPayload)
    case sessionPause(SessionPausePayload)

    struct SessionCreatePayload: Codable, Sendable {
        let conversationId: String
        let agentConfig: AgentConfig
    }

    struct SessionMessagePayload: Codable, Sendable {
        let sessionId: String
        let text: String
    }

    struct SessionResumePayload: Codable, Sendable {
        let sessionId: String
        let claudeSessionId: String
    }

    struct SessionForkPayload: Codable, Sendable {
        let sessionId: String
    }

    struct SessionPausePayload: Codable, Sendable {
        let sessionId: String
    }

    var wireMessage: WireMessage {
        switch self {
        case .sessionCreate(let p):
            return WireMessage(type: "session.create", payload: p)
        case .sessionMessage(let p):
            return WireMessage(type: "session.message", payload: p)
        case .sessionResume(let p):
            return WireMessage(type: "session.resume", payload: p)
        case .sessionFork(let p):
            return WireMessage(type: "session.fork", payload: p)
        case .sessionPause(let p):
            return WireMessage(type: "session.pause", payload: p)
        }
    }
}

struct AgentConfig: Codable, Sendable {
    let name: String
    let systemPrompt: String
    let allowedTools: [String]
    let mcpServers: [MCPServerConfig]
    let model: String
    let maxTurns: Int?
    let maxBudget: Double?
    let workingDirectory: String
    let skills: [SkillContent]

    struct MCPServerConfig: Codable, Sendable {
        let name: String
        let command: String?
        let args: [String]?
        let env: [String: String]?
        let url: String?
    }

    struct SkillContent: Codable, Sendable {
        let name: String
        let content: String
    }
}

enum SidecarEvent: Sendable {
    case streamToken(sessionId: String, text: String)
    case streamToolCall(sessionId: String, tool: String, input: String)
    case streamToolResult(sessionId: String, tool: String, output: String)
    case sessionResult(sessionId: String, result: String, cost: Double)
    case sessionError(sessionId: String, error: String)
    case peerChat(channelId: String, from: String, message: String)
    case peerDelegate(from: String, to: String, task: String)
    case blackboardUpdate(key: String, value: String, writtenBy: String)
    case connected
    case disconnected
}

struct WireMessage: Codable, Sendable {
    let type: String
    let payload: AnyCodable

    init<T: Codable & Sendable>(type: String, payload: T) {
        self.type = type
        self.payload = AnyCodable(payload)
    }
}

struct AnyCodable: Codable, Sendable {
    let value: any Sendable

    init<T: Codable & Sendable>(_ value: T) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dict = try? container.decode([String: String].self) {
            value = dict
        } else if let str = try? container.decode(String.self) {
            value = str
        } else if let num = try? container.decode(Double.self) {
            value = num
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else {
            value = ""
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let v = value as? String { try container.encode(v) }
        else if let v = value as? Double { try container.encode(v) }
        else if let v = value as? Bool { try container.encode(v) }
        else if let v = value as? [String: String] { try container.encode(v) }
        else {
            let data = try JSONEncoder().encode(CodableWrapper(value))
            let str = String(data: data, encoding: .utf8) ?? "{}"
            try container.encode(str)
        }
    }

    private struct CodableWrapper: Encodable {
        let value: any Sendable
        init(_ value: any Sendable) { self.value = value }
        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            if let v = value as? any Encodable {
                try container.encode(AnyEncodableBox(v))
            }
        }
    }

    private struct AnyEncodableBox: Encodable {
        let base: any Encodable
        init(_ base: any Encodable) { self.base = base }
        func encode(to encoder: Encoder) throws {
            try base.encode(to: encoder)
        }
    }
}

struct IncomingWireMessage: Codable, Sendable {
    let type: String
    let sessionId: String?
    let text: String?
    let tool: String?
    let input: String?
    let output: String?
    let result: String?
    let cost: Double?
    let error: String?
    let channelId: String?
    let from: String?
    let to: String?
    let message: String?
    let task: String?
    let key: String?
    let value: String?
    let writtenBy: String?

    func toEvent() -> SidecarEvent? {
        switch type {
        case "stream.token":
            guard let sid = sessionId, let t = text else { return nil }
            return .streamToken(sessionId: sid, text: t)
        case "stream.toolCall":
            guard let sid = sessionId, let t = tool else { return nil }
            return .streamToolCall(sessionId: sid, tool: t, input: input ?? "")
        case "stream.toolResult":
            guard let sid = sessionId, let t = tool else { return nil }
            return .streamToolResult(sessionId: sid, tool: t, output: output ?? "")
        case "session.result":
            guard let sid = sessionId else { return nil }
            return .sessionResult(sessionId: sid, result: result ?? "", cost: cost ?? 0)
        case "session.error":
            guard let sid = sessionId else { return nil }
            return .sessionError(sessionId: sid, error: error ?? "Unknown error")
        case "peer.chat":
            guard let ch = channelId, let f = from, let m = message else { return nil }
            return .peerChat(channelId: ch, from: f, message: m)
        case "peer.delegate":
            guard let f = from, let t = to, let tk = task else { return nil }
            return .peerDelegate(from: f, to: t, task: tk)
        case "blackboard.update":
            guard let k = key, let v = value, let w = writtenBy else { return nil }
            return .blackboardUpdate(key: k, value: v, writtenBy: w)
        default:
            return nil
        }
    }
}
