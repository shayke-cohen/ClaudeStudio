import Foundation

enum SidecarCommand: Sendable {
    case sessionCreate(conversationId: String, agentConfig: AgentConfig)
    case sessionMessage(sessionId: String, text: String, attachments: [WireAttachment] = [], planMode: Bool = false)
    case sessionResume(sessionId: String, claudeSessionId: String)
    case sessionBulkResume(sessions: [SessionBulkResumeEntry])
    case sessionFork(parentSessionId: String, childSessionId: String)
    case sessionPause(sessionId: String)
    case agentRegister(agents: [AgentDefinitionWire])
    case delegateTask(sessionId: String, toAgent: String, task: String, context: String?, waitForResult: Bool)
    case peerRegister(name: String, endpoint: String, agents: [AgentDefinitionWire])
    case peerRemove(name: String)
    case generateAgent(requestId: String, prompt: String, availableSkills: [SkillCatalogEntry], availableMCPs: [MCPCatalogEntry])
    case questionAnswer(sessionId: String, questionId: String, answer: String, selectedOptions: [String]?)
    case confirmationAnswer(sessionId: String, confirmationId: String, approved: Bool, modifiedAction: String?)
    case sessionUpdateCwd(sessionId: String, workingDirectory: String)

    func encodeToJSON() throws -> Data {
        let encoder = JSONEncoder()
        switch self {
        case .sessionCreate(let conversationId, let agentConfig):
            return try encoder.encode(
                SessionCreateWire(type: "session.create", conversationId: conversationId, agentConfig: agentConfig)
            )
        case .sessionMessage(let sessionId, let text, let attachments, let planMode):
            return try encoder.encode(
                SessionMessageWire(
                    type: "session.message",
                    sessionId: sessionId,
                    text: text,
                    attachments: attachments.isEmpty ? nil : attachments,
                    planMode: planMode ? true : nil
                )
            )
        case .sessionResume(let sessionId, let claudeSessionId):
            return try encoder.encode(
                SessionResumeWire(type: "session.resume", sessionId: sessionId, claudeSessionId: claudeSessionId)
            )
        case .sessionBulkResume(let sessions):
            return try encoder.encode(
                SessionBulkResumeWire(type: "session.bulkResume", sessions: sessions)
            )
        case .sessionFork(let parentSessionId, let childSessionId):
            return try encoder.encode(
                SessionForkWire(type: "session.fork", sessionId: parentSessionId, childSessionId: childSessionId)
            )
        case .sessionPause(let sessionId):
            return try encoder.encode(
                SessionIdWire(type: "session.pause", sessionId: sessionId)
            )
        case .agentRegister(let agents):
            return try encoder.encode(
                AgentRegisterWire(type: "agent.register", agents: agents)
            )
        case .delegateTask(let sessionId, let toAgent, let task, let context, let waitForResult):
            return try encoder.encode(
                DelegateTaskWire(type: "delegate.task", sessionId: sessionId, toAgent: toAgent, task: task, context: context, waitForResult: waitForResult)
            )
        case .peerRegister(let name, let endpoint, let agents):
            return try encoder.encode(
                PeerRegisterWire(type: "peer.register", name: name, endpoint: endpoint, agents: agents)
            )
        case .peerRemove(let name):
            return try encoder.encode(
                PeerRemoveWire(type: "peer.remove", name: name)
            )
        case .generateAgent(let requestId, let prompt, let skills, let mcps):
            return try encoder.encode(
                GenerateAgentWire(type: "generate.agent", requestId: requestId, prompt: prompt, availableSkills: skills, availableMCPs: mcps)
            )
        case .questionAnswer(let sessionId, let questionId, let answer, let selectedOptions):
            return try encoder.encode(
                QuestionAnswerWire(type: "session.questionAnswer", sessionId: sessionId, questionId: questionId, answer: answer, selectedOptions: selectedOptions)
            )
        case .confirmationAnswer(let sessionId, let confirmationId, let approved, let modifiedAction):
            return try encoder.encode(
                ConfirmationAnswerWire(type: "session.confirmationAnswer", sessionId: sessionId, confirmationId: confirmationId, approved: approved, modifiedAction: modifiedAction)
            )
        case .sessionUpdateCwd(let sessionId, let workingDirectory):
            return try encoder.encode(
                SessionUpdateCwdWire(type: "session.updateCwd", sessionId: sessionId, workingDirectory: workingDirectory)
            )
        }
    }
}

struct AgentDefinitionWire: Codable, Sendable {
    let name: String
    let config: AgentConfig
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
    let planMode: Bool?
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

struct SessionBulkResumeEntry: Codable, Sendable {
    let sessionId: String
    let claudeSessionId: String
    let agentConfig: AgentConfig
}

private struct SessionBulkResumeWire: Encodable {
    let type: String
    let sessions: [SessionBulkResumeEntry]
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

private struct SessionUpdateCwdWire: Encodable {
    let type: String
    let sessionId: String
    let workingDirectory: String
}

private struct DelegateTaskWire: Encodable {
    let type: String
    let sessionId: String
    let toAgent: String
    let task: String
    let context: String?
    let waitForResult: Bool
}

private struct PeerRegisterWire: Encodable {
    let type: String
    let name: String
    let endpoint: String
    let agents: [AgentDefinitionWire]
}

private struct PeerRemoveWire: Encodable {
    let type: String
    let name: String
}

private struct QuestionAnswerWire: Encodable {
    let type: String
    let sessionId: String
    let questionId: String
    let answer: String
    let selectedOptions: [String]?
}

private struct ConfirmationAnswerWire: Encodable {
    let type: String
    let sessionId: String
    let confirmationId: String
    let approved: Bool
    let modifiedAction: String?
}

private struct GenerateAgentWire: Encodable {
    let type: String
    let requestId: String
    let prompt: String
    let availableSkills: [SkillCatalogEntry]
    let availableMCPs: [MCPCatalogEntry]
}

struct SkillCatalogEntry: Codable, Sendable {
    let id: String
    let name: String
    let description: String
    let category: String
}

struct MCPCatalogEntry: Codable, Sendable {
    let id: String
    let name: String
    let description: String
}

struct GeneratedAgentSpec: Codable, Sendable {
    let name: String
    let description: String
    let systemPrompt: String
    let model: String
    let icon: String
    let color: String
    let matchedSkillIds: [String]
    let matchedMCPIds: [String]
    let maxTurns: Int?
    let maxBudget: Double?
}

struct AgentConfig: Codable, Sendable {
    let name: String
    let systemPrompt: String
    let allowedTools: [String]
    let mcpServers: [MCPServerConfig]
    let model: String
    let maxTurns: Int?
    let maxBudget: Double?
    let maxThinkingTokens: Int?
    let workingDirectory: String
    let skills: [SkillContent]
    var interactive: Bool?

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
    case streamThinking(sessionId: String, text: String)
    case streamToolCall(sessionId: String, tool: String, input: String)
    case streamToolResult(sessionId: String, tool: String, output: String)
    case sessionResult(sessionId: String, result: String, cost: Double, tokenCount: Int, toolCallCount: Int)
    case sessionError(sessionId: String, error: String)
    case peerChat(channelId: String, from: String, message: String)
    case peerDelegate(from: String, to: String, task: String)
    case blackboardUpdate(key: String, value: String, writtenBy: String)
    case sessionForked(parentSessionId: String, childSessionId: String)
    case streamImage(sessionId: String, imageData: String, mediaType: String, fileName: String?)
    case streamFileCard(sessionId: String, filePath: String, fileType: String, fileName: String)
    case sessionReused(originalSessionId: String, reusedSessionId: String)
    case generatedAgent(requestId: String, spec: GeneratedAgentSpec)
    case generateAgentError(requestId: String, error: String)
    case agentQuestion(sessionId: String, questionId: String, question: String, options: [QuestionOption]?, multiSelect: Bool, isPrivate: Bool, inputType: String?, inputConfig: QuestionInputConfig?)
    case agentConfirmation(sessionId: String, confirmationId: String, action: String, reason: String, riskLevel: String, details: String?)
    case streamRichContent(sessionId: String, format: String, title: String?, content: String, height: Int?)
    case streamProgress(sessionId: String, progressId: String, title: String, steps: [ProgressStep])
    case streamSuggestions(sessionId: String, suggestions: [SuggestionItem])
    case connected
    case disconnected
}

struct QuestionOption: Codable, Sendable, Identifiable {
    let label: String
    let description: String?
    var id: String { label }
}

struct QuestionInputConfig: Codable, Sendable {
    let maxRating: Int?
    let ratingLabels: [String]?
    let min: Double?
    let max: Double?
    let step: Double?
    let unit: String?
    let fields: [FormFieldConfig]?
}

struct FormFieldConfig: Codable, Sendable, Identifiable {
    let name: String
    let label: String
    let type: String  // "text", "number", "toggle"
    let placeholder: String?
    let required: Bool?
    var id: String { name }
}

struct ProgressStep: Codable, Sendable, Identifiable {
    let label: String
    let status: String
    var id: String { label }
}

struct SuggestionItem: Codable, Sendable, Identifiable {
    let label: String
    let message: String?
    var id: String { label }
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
    let inputTokens: Int?
    let outputTokens: Int?
    let numTurns: Int?
    let toolCallCount: Int?
    let error: String?
    let channelId: String?
    let from: String?
    let to: String?
    let message: String?
    let task: String?
    let key: String?
    let value: String?
    let writtenBy: String?
    let parentSessionId: String?
    let childSessionId: String?
    let originalSessionId: String?
    let reusedSessionId: String?
    let imageData: String?
    let mediaType: String?
    let filePath: String?
    let fileType: String?
    let fileName: String?
    let requestId: String?
    let spec: GeneratedAgentSpec?
    let questionId: String?
    let question: String?
    let options: [QuestionOption]?
    let multiSelect: Bool?
    let `private`: Bool?
    let inputType: String?
    let inputConfig: QuestionInputConfig?
    let confirmationId: String?
    let action: String?
    let reason: String?
    let riskLevel: String?
    let details: String?
    let format: String?
    let title: String?
    let content: String?
    let height: Int?
    let progressId: String?
    let steps: [ProgressStep]?
    let suggestions: [SuggestionItem]?

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
        case "peer.chat":
            guard let ch = channelId, let f = from, let m = message else { return nil }
            return .peerChat(channelId: ch, from: f, message: m)
        case "peer.delegate":
            guard let f = from, let t = to, let tk = task else { return nil }
            return .peerDelegate(from: f, to: t, task: tk)
        case "blackboard.update":
            guard let k = key, let v = value, let w = writtenBy else { return nil }
            return .blackboardUpdate(key: k, value: v, writtenBy: w)
        case "session.reused":
            guard let orig = originalSessionId, let reused = reusedSessionId else { return nil }
            return .sessionReused(originalSessionId: orig, reusedSessionId: reused)
        case "session.forked":
            guard let p = parentSessionId, let c = childSessionId else { return nil }
            return .sessionForked(parentSessionId: p, childSessionId: c)
        case "stream.image":
            guard let sid = sessionId, let img = imageData, let mt = mediaType else { return nil }
            return .streamImage(sessionId: sid, imageData: img, mediaType: mt, fileName: fileName)
        case "stream.fileCard":
            guard let sid = sessionId, let fp = filePath, let ft = fileType, let fn = fileName else { return nil }
            return .streamFileCard(sessionId: sid, filePath: fp, fileType: ft, fileName: fn)
        case "generate.agent.result":
            guard let rid = requestId, let s = spec else { return nil }
            return .generatedAgent(requestId: rid, spec: s)
        case "generate.agent.error":
            guard let rid = requestId else { return nil }
            return .generateAgentError(requestId: rid, error: error ?? "Unknown error")
        case "agent.question":
            guard let sid = sessionId, let qid = questionId, let q = question else { return nil }
            return .agentQuestion(sessionId: sid, questionId: qid, question: q, options: options, multiSelect: multiSelect ?? false, isPrivate: `private` ?? true, inputType: inputType, inputConfig: inputConfig)
        case "agent.confirmation":
            guard let sid = sessionId, let cid = confirmationId, let act = action, let rsn = reason, let rl = riskLevel else { return nil }
            return .agentConfirmation(sessionId: sid, confirmationId: cid, action: act, reason: rsn, riskLevel: rl, details: details)
        case "stream.richContent":
            guard let sid = sessionId, let fmt = format, let cnt = content else { return nil }
            return .streamRichContent(sessionId: sid, format: fmt, title: title, content: cnt, height: height)
        case "stream.progress":
            guard let sid = sessionId, let pid = progressId, let t = title, let s = steps else { return nil }
            return .streamProgress(sessionId: sid, progressId: pid, title: t, steps: s)
        case "stream.suggestions":
            guard let sid = sessionId, let s = suggestions else { return nil }
            return .streamSuggestions(sessionId: sid, suggestions: s)
        default:
            return nil
        }
    }
}
