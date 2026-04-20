// OdysseyiOS/Protocol/SidecarProtocol.swift
// iOS-side sidecar wire protocol — a thin subset of the full Mac protocol.
// Only includes the commands and events needed by the iOS thin client.
import Foundation
import OdysseyCore

// MARK: - AgentConfig

/// Full configuration for a sidecar agent session.
struct AgentConfig: Codable, Sendable {
    let name: String
    let systemPrompt: String
    let allowedTools: [String]
    let mcpServers: [MCPServerConfig]
    var provider: String
    let model: String
    let maxTurns: Int?
    let maxBudget: Double?
    let maxThinkingTokens: Int?
    let workingDirectory: String
    let skills: [SkillContent]
    var interactive: Bool?
    var instancePolicy: String?
    var instancePolicyPoolMax: Int?

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

// MARK: - WireAttachment

struct WireAttachment: Codable, Sendable {
    let data: String
    let mediaType: String
    let fileName: String?
}

// MARK: - SessionBulkResumeEntry

struct SessionBulkResumeEntry: Codable, Sendable {
    let sessionId: String
    let claudeSessionId: String
    let agentConfig: AgentConfig
}

// MARK: - SidecarCommand

/// Commands sent from the iOS client to the Mac sidecar over WebSocket.
enum SidecarCommand: Sendable {
    case sessionCreate(conversationId: String, agentConfig: AgentConfig)
    case sessionMessage(sessionId: String, text: String, attachments: [WireAttachment] = [], planMode: Bool = false)
    case sessionResume(sessionId: String, claudeSessionId: String)
    case sessionPause(sessionId: String)
    case sessionFork(parentSessionId: String, childSessionId: String)
    case sessionBulkResume(sessions: [SessionBulkResumeEntry])
    case sessionUpdateMode(sessionId: String, interactive: Bool, instancePolicy: String?, instancePolicyPoolMax: Int?)
    case sessionUpdateCwd(sessionId: String, workingDirectory: String)
    case pairingHello(iosNpub: String, displayName: String)
    case conversationsList

    func encodeToJSON() throws -> Data {
        let encoder = JSONEncoder()
        switch self {
        case .sessionCreate(let conversationId, let agentConfig):
            return try encoder.encode(SessionCreateWire(type: "session.create", conversationId: conversationId, agentConfig: agentConfig))
        case .sessionMessage(let sessionId, let text, let attachments, let planMode):
            return try encoder.encode(SessionMessageWire(type: "session.message", sessionId: sessionId, text: text, attachments: attachments.isEmpty ? nil : attachments, planMode: planMode ? true : nil))
        case .sessionResume(let sessionId, let claudeSessionId):
            return try encoder.encode(SessionResumeWire(type: "session.resume", sessionId: sessionId, claudeSessionId: claudeSessionId))
        case .sessionPause(let sessionId):
            return try encoder.encode(SessionIdWire(type: "session.pause", sessionId: sessionId))
        case .sessionFork(let parentSessionId, let childSessionId):
            return try encoder.encode(SessionForkWire(type: "session.fork", sessionId: parentSessionId, childSessionId: childSessionId))
        case .sessionBulkResume(let sessions):
            return try encoder.encode(SessionBulkResumeWire(type: "session.bulkResume", sessions: sessions))
        case .sessionUpdateMode(let sessionId, let interactive, let instancePolicy, let instancePolicyPoolMax):
            return try encoder.encode(SessionUpdateModeWire(type: "session.updateMode", sessionId: sessionId, interactive: interactive, instancePolicy: instancePolicy, instancePolicyPoolMax: instancePolicyPoolMax))
        case .sessionUpdateCwd(let sessionId, let workingDirectory):
            return try encoder.encode(SessionUpdateCwdWire(type: "session.updateCwd", sessionId: sessionId, workingDirectory: workingDirectory))
        case .pairingHello(let iosNpub, let displayName):
            return try encoder.encode(PairingHelloWire(type: "pairing.hello", iosNpub: iosNpub, displayName: displayName))
        case .conversationsList:
            return try encoder.encode(TypeOnlyWire(type: "conversations.list"))
        }
    }
}

// MARK: - SidecarEvent

/// Events received from the Mac sidecar over WebSocket.
enum SidecarEvent: Sendable {
    case streamToken(sessionId: String, text: String)
    case streamThinking(sessionId: String, text: String)
    case streamToolCall(sessionId: String, tool: String, input: String)
    case streamToolResult(sessionId: String, tool: String, output: String)
    case sessionResult(sessionId: String, result: String, cost: Double, tokenCount: Int, toolCallCount: Int)
    case sessionError(sessionId: String, error: String)
    case sessionForked(parentSessionId: String, childSessionId: String)
    case sessionReused(originalSessionId: String, reusedSessionId: String)
    case streamImage(sessionId: String, imageData: String, mediaType: String, fileName: String?)
    case streamFileCard(sessionId: String, filePath: String, fileType: String, fileName: String)
    case connected
    case disconnected
    case pairingConfirmed
    case conversationsListResult(conversations: [ConversationSummaryWire])
    case other
}

// MARK: - IncomingWireMessage

/// Minimal incoming wire message decoder for events we care about on iOS.
struct IncomingWireMessage: Codable, Sendable {
    let type: String
    let sessionId: String?
    let text: String?
    let tool: String?
    let input: String?
    let output: String?
    let result: String?
    let cost: Double?
    let inputTokens: Int?
    let outputTokens: Int?
    let toolCallCount: Int?
    let error: String?
    let parentSessionId: String?
    let childSessionId: String?
    let originalSessionId: String?
    let reusedSessionId: String?
    let imageData: String?
    let mediaType: String?
    let filePath: String?
    let fileType: String?
    let fileName: String?
    let conversations: [ConversationSummaryWire]?

    func toEvent() -> SidecarEvent? {
        switch type {
        case "stream.token":
            guard let sid = sessionId, let t = text else { return nil }
            return .streamToken(sessionId: sid, text: t)
        case "stream.thinking":
            guard let sid = sessionId, let t = text else { return nil }
            return .streamThinking(sessionId: sid, text: t)
        case "stream.toolCall":
            guard let sid = sessionId, let t = tool else { return nil }
            return .streamToolCall(sessionId: sid, tool: t, input: input ?? "")
        case "stream.toolResult":
            guard let sid = sessionId, let t = tool else { return nil }
            return .streamToolResult(sessionId: sid, tool: t, output: output ?? "")
        case "session.result":
            guard let sid = sessionId else { return nil }
            let totalTokens = (inputTokens ?? 0) + (outputTokens ?? 0)
            return .sessionResult(sessionId: sid, result: result ?? "", cost: cost ?? 0,
                                  tokenCount: totalTokens, toolCallCount: toolCallCount ?? 0)
        case "session.error":
            guard let sid = sessionId else { return nil }
            return .sessionError(sessionId: sid, error: error ?? "Unknown error")
        case "session.forked":
            guard let p = parentSessionId, let c = childSessionId else { return nil }
            return .sessionForked(parentSessionId: p, childSessionId: c)
        case "session.reused":
            guard let orig = originalSessionId, let reused = reusedSessionId else { return nil }
            return .sessionReused(originalSessionId: orig, reusedSessionId: reused)
        case "stream.image":
            guard let sid = sessionId, let img = imageData, let mt = mediaType else { return nil }
            return .streamImage(sessionId: sid, imageData: img, mediaType: mt, fileName: fileName)
        case "stream.fileCard":
            guard let sid = sessionId, let fp = filePath, let ft = fileType, let fn = fileName else { return nil }
            return .streamFileCard(sessionId: sid, filePath: fp, fileType: ft, fileName: fn)
        case "pairing.confirmed":
            return .pairingConfirmed
        case "conversations.list.result":
            return .conversationsListResult(conversations: conversations ?? [])
        default:
            return .other
        }
    }
}

// MARK: - Private wire structs (encoding only)

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
    let planMode: Bool?
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

private struct SessionForkWire: Encodable {
    let type: String
    let sessionId: String
    let childSessionId: String
}

private struct SessionBulkResumeWire: Encodable {
    let type: String
    let sessions: [SessionBulkResumeEntry]
}

private struct SessionUpdateModeWire: Encodable {
    let type: String
    let sessionId: String
    let interactive: Bool
    let instancePolicy: String?
    let instancePolicyPoolMax: Int?
}

private struct SessionUpdateCwdWire: Encodable {
    let type: String
    let sessionId: String
    let workingDirectory: String
}

private struct PairingHelloWire: Encodable {
    let type: String
    let iosNpub: String
    let displayName: String
}

private struct TypeOnlyWire: Encodable {
    let type: String
}
