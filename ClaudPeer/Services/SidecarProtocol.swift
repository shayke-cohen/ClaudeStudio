import Foundation

enum SidecarCommand: Sendable {
    case sessionCreate(conversationId: String, agentConfig: AgentConfig)
    case sessionMessage(sessionId: String, text: String, attachments: [WireAttachment] = [])
    case sessionResume(sessionId: String, claudeSessionId: String)
    case sessionFork(sessionId: String)
    case sessionPause(sessionId: String)
    case agentRegister(agents: [AgentDefinitionWire])

    func encodeToJSON() throws -> Data {
        let encoder = JSONEncoder()
        switch self {
        case .sessionCreate(let conversationId, let agentConfig):
            return try encoder.encode(
                SessionCreateWire(type: "session.create", conversationId: conversationId, agentConfig: agentConfig)
            )
        case .sessionMessage(let sessionId, let text, let attachments):
            return try encoder.encode(
                SessionMessageWire(
                    type: "session.message",
                    sessionId: sessionId,
                    text: text,
                    attachments: attachments.isEmpty ? nil : attachments
                )
            )
        case .sessionResume(let sessionId, let claudeSessionId):
            return try encoder.encode(
                SessionResumeWire(type: "session.resume", sessionId: sessionId, claudeSessionId: claudeSessionId)
            )
        case .sessionFork(let sessionId):
            return try encoder.encode(
                SessionIdWire(type: "session.fork", sessionId: sessionId)
            )
        case .sessionPause(let sessionId):
            return try encoder.encode(
                SessionIdWire(type: "session.pause", sessionId: sessionId)
            )
        case .agentRegister(let agents):
            return try encoder.encode(
                AgentRegisterWire(type: "agent.register", agents: agents)
            )
        }
    }
}

struct AgentDefinitionWire: Codable, Sendable {
    let name: String
    let config: AgentConfig
    let instancePolicy: String
}

private struct AgentRegisterWire: Encodable {
    let type: String
    let agents: [AgentDefinitionWire]
}

private struct SessionCreateWire: Encodable {
    let type: String
    let conversationId: String
    let agentConfig: AgentConfig
}

private struct SessionMessageWire: Encodable {
    let type: String
    let sessionId: String
    let text: String
    let attachments: [WireAttachment]?
}

struct WireAttachment: Codable, Sendable {
    let data: String
    let mediaType: String
    let fileName: String?
}

private struct SessionResumeWire: Encodable {
    let type: String
    let sessionId: String
    let claudeSessionId: String
}

private struct SessionIdWire: Encodable {
    let type: String
    let sessionId: String
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
