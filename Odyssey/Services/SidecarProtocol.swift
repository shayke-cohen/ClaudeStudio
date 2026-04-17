import Foundation
import OdysseyCore

enum SidecarCommand: Sendable {
    case sessionCreate(conversationId: String, agentConfig: AgentConfig)
    case sessionMessage(sessionId: String, text: String, attachments: [WireAttachment] = [], planMode: Bool = false)
    case sessionResume(sessionId: String, claudeSessionId: String)
    case sessionBulkResume(sessions: [SessionBulkResumeEntry])
    case sessionFork(parentSessionId: String, childSessionId: String)
    case sessionPause(sessionId: String)
    case sessionUpdateMode(sessionId: String, interactive: Bool, instancePolicy: String?, instancePolicyPoolMax: Int?)
    case agentRegister(agents: [AgentDefinitionWire])
    case delegateTask(sessionId: String, toAgent: String, task: String, context: String?, waitForResult: Bool)
    case peerRegister(name: String, endpoint: String, agents: [AgentDefinitionWire])
    case peerRemove(name: String)
    case nostrAddPeer(name: String, pubkeyHex: String, relays: [String])
    case nostrRemovePeer(name: String)
    case generateAgent(requestId: String, prompt: String, availableSkills: [SkillCatalogEntry], availableMCPs: [MCPCatalogEntry])
    case questionAnswer(sessionId: String, questionId: String, answer: String, selectedOptions: [String]?)
    case confirmationAnswer(sessionId: String, confirmationId: String, approved: Bool, modifiedAction: String?)
    case sessionUpdateCwd(sessionId: String, workingDirectory: String)
    case taskCreate(task: TaskWireSwift)
    case taskUpdate(taskId: String, updates: TaskWireSwift)
    case taskList(filter: TaskListFilter?)
    case taskClaim(taskId: String, agentName: String)
    case connectorList
    case connectorBeginAuth(connection: ConnectorWire)
    case connectorCompleteAuth(connection: ConnectorWire, credentials: ConnectorCredentialsWire?)
    case connectorRevoke(connectionId: String)
    case connectorTest(connectionId: String)
    case configSetOllama(enabled: Bool, baseURL: String)
    case configSetLogLevel(level: String)
    case conversationSync(conversations: [ConversationSummaryWire])
    case conversationMessageAppend(conversationId: String, message: MessageWire)
    case projectSync(projects: [ProjectSummaryWire])
    case iosRegisterPush(apnsToken: String, appId: String)
    case setDelegationMode(sessionId: String, mode: DelegationMode, targetAgentName: String?)

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
        case .sessionUpdateMode(let sessionId, let interactive, let instancePolicy, let instancePolicyPoolMax):
            return try encoder.encode(
                SessionUpdateModeWire(
                    type: "session.updateMode",
                    sessionId: sessionId,
                    interactive: interactive,
                    instancePolicy: instancePolicy,
                    instancePolicyPoolMax: instancePolicyPoolMax
                )
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
        case .nostrAddPeer(let name, let pubkeyHex, let relays):
            return try encoder.encode(
                NostrAddPeerWire(type: "nostr.addPeer", name: name, pubkeyHex: pubkeyHex, relays: relays)
            )
        case .nostrRemovePeer(let name):
            return try encoder.encode(
                NostrRemovePeerWire(type: "nostr.removePeer", name: name)
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
        case .taskCreate(let task):
            return try encoder.encode(
                TaskCreateWire(type: "task.create", task: task)
            )
        case .taskUpdate(let taskId, let updates):
            return try encoder.encode(
                TaskUpdateWire(type: "task.update", taskId: taskId, updates: updates)
            )
        case .taskList(let filter):
            return try encoder.encode(
                TaskListWire(type: "task.list", filter: filter)
            )
        case .taskClaim(let taskId, let agentName):
            return try encoder.encode(
                TaskClaimWire(type: "task.claim", taskId: taskId, agentName: agentName)
            )
        case .connectorList:
            return try encoder.encode(
                ConnectorListWire(type: "connector.list")
            )
        case .connectorBeginAuth(let connection):
            return try encoder.encode(
                ConnectorBeginAuthWire(type: "connector.beginAuth", connection: connection)
            )
        case .connectorCompleteAuth(let connection, let credentials):
            return try encoder.encode(
                ConnectorCompleteAuthWire(type: "connector.completeAuth", connection: connection, credentials: credentials)
            )
        case .connectorRevoke(let connectionId):
            return try encoder.encode(
                ConnectorIdWire(type: "connector.revoke", connectionId: connectionId)
            )
        case .connectorTest(let connectionId):
            return try encoder.encode(
                ConnectorIdWire(type: "connector.test", connectionId: connectionId)
            )
        case .configSetOllama(let enabled, let baseURL):
            return try encoder.encode(
                ConfigSetOllamaWire(type: "config.setOllama", enabled: enabled, baseURL: baseURL)
            )
        case .configSetLogLevel(let level):
            return try encoder.encode(
                ConfigSetLogLevelWire(type: "config.setLogLevel", level: level)
            )
        case .conversationSync(let conversations):
            return try encoder.encode(
                ConversationSyncWire(type: "conversation.sync", conversations: conversations)
            )
        case .conversationMessageAppend(let conversationId, let message):
            return try encoder.encode(
                ConversationMessageAppendWire(type: "conversation.messageAppend", conversationId: conversationId, message: message)
            )
        case .projectSync(let projects):
            return try encoder.encode(
                ProjectSyncWire(type: "project.sync", projects: projects)
            )
        case .iosRegisterPush(let apnsToken, let appId):
            return try encoder.encode(
                IosRegisterPushWire(type: "ios.registerPush", apnsToken: apnsToken, appId: appId)
            )
        case .setDelegationMode(let sessionId, let mode, let targetAgentName):
            return try encoder.encode(
                SetDelegationModeWire(type: "conversation.setDelegationMode", sessionId: sessionId, mode: mode.rawValue, targetAgentName: targetAgentName)
            )
        }
    }
}

private struct IosRegisterPushWire: Encodable {
    let type: String
    let apnsToken: String
    let appId: String
}

private struct SetDelegationModeWire: Encodable {
    let type: String
    let sessionId: String
    let mode: String
    let targetAgentName: String?
}

enum DelegationMode: String, Codable, CaseIterable, Sendable {
    case off
    case byAgents = "by_agents"
    case specificAgent = "specific_agent"
    case coordinator

    var shortLabel: String {
        switch self {
        case .off: return "Off"
        case .byAgents: return "agents"
        case .specificAgent: return "specific"
        case .coordinator: return "coordinator"
        }
    }
}

private struct ConversationSyncWire: Encodable {
    let type: String
    let conversations: [ConversationSummaryWire]
}

private struct ConversationMessageAppendWire: Encodable {
    let type: String
    let conversationId: String
    let message: MessageWire
}

private struct ProjectSyncWire: Encodable {
    let type: String
    let projects: [ProjectSummaryWire]
}

struct AgentDefinitionWire: Codable, Sendable {
    let name: String
    let config: AgentConfig

    let instancePolicy: String?

    init(name: String, config: AgentConfig, instancePolicy: String? = nil) {
        self.name = name
        self.config = config
        self.instancePolicy = instancePolicy
    }
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

private struct SessionUpdateModeWire: Encodable {
    let type: String
    let sessionId: String
    let interactive: Bool
    let instancePolicy: String?
    let instancePolicyPoolMax: Int?
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

private struct NostrAddPeerWire: Encodable {
    let type: String
    let name: String
    let pubkeyHex: String
    let relays: [String]
}

private struct NostrRemovePeerWire: Encodable {
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

struct TaskWireSwift: Codable, Sendable {
    let id: String
    let projectId: String?
    let title: String
    let description: String
    let status: String
    let priority: String
    let labels: [String]
    let result: String?
    let parentTaskId: String?
    let assignedAgentId: String?
    let assignedAgentName: String?
    let assignedGroupId: String?
    let conversationId: String?
    let createdAt: String
    let startedAt: String?
    let completedAt: String?
}

private struct TaskCreateWire: Encodable {
    let type: String
    let task: TaskWireSwift
}

private struct TaskUpdateWire: Encodable {
    let type: String
    let taskId: String
    let updates: TaskWireSwift
}

private struct TaskListWire: Encodable {
    let type: String
    let filter: TaskListFilter?
}

struct TaskListFilter: Codable, Sendable {
    let status: String?
}

private struct TaskClaimWire: Encodable {
    let type: String
    let taskId: String
    let agentName: String
}

private struct ConnectorListWire: Encodable {
    let type: String
}

private struct ConnectorBeginAuthWire: Encodable {
    let type: String
    let connection: ConnectorWire
}

private struct ConnectorCompleteAuthWire: Encodable {
    let type: String
    let connection: ConnectorWire
    let credentials: ConnectorCredentialsWire?
}

private struct ConnectorIdWire: Encodable {
    let type: String
    let connectionId: String
}

private struct ConfigSetLogLevelWire: Encodable {
    let type: String
    let level: String
}

private struct ConfigSetOllamaWire: Encodable {
    let type: String
    let enabled: Bool
    let baseURL: String
}

struct ConnectorWire: Codable, Sendable, Identifiable {
    let id: String
    let provider: String
    let installScope: String
    let displayName: String
    let accountId: String?
    let accountHandle: String?
    let accountMetadataJSON: String?
    let grantedScopes: [String]
    let authMode: String
    let writePolicy: String
    let status: String
    let statusMessage: String?
    let brokerReference: String?
    let auditSummary: String?
    let lastAuthenticatedAt: String?
    let lastCheckedAt: String?
}

struct ConnectorCredentialsWire: Codable, Sendable {
    let accessToken: String?
    let refreshToken: String?
    let tokenType: String?
    let expiresAt: String?
    let brokerReference: String?
}

struct AgentConfig: Codable, Sendable {
    let name: String
    let systemPrompt: String
    let allowedTools: [String]
    let mcpServers: [MCPServerConfig]
    var provider: String = "claude"
    let model: String
    let maxTurns: Int?
    let maxBudget: Double?
    let maxThinkingTokens: Int?
    let workingDirectory: String
    let skills: [SkillContent]
    var interactive: Bool?
    var instancePolicy: String? = nil
    var instancePolicyPoolMax: Int? = nil

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
    case peerChat(sessionId: String, channelId: String, from: String, message: String)
    case peerDelegate(sessionId: String, from: String, to: String, task: String)
    case blackboardUpdate(sessionId: String, key: String, value: String, writtenBy: String)
    case sessionForked(parentSessionId: String, childSessionId: String)
    case streamImage(sessionId: String, imageData: String, mediaType: String, fileName: String?)
    case streamFileCard(sessionId: String, filePath: String, fileType: String, fileName: String)
    case sessionReused(originalSessionId: String, reusedSessionId: String)
    case generatedAgent(requestId: String, spec: GeneratedAgentSpec)
    case generateAgentError(requestId: String, error: String)
    case agentQuestion(sessionId: String, questionId: String, question: String, options: [QuestionOption]?, multiSelect: Bool, isPrivate: Bool, inputType: String?, inputConfig: QuestionInputConfig?, timeoutSeconds: Int?, autoRouting: Bool?)
    case agentConfirmation(sessionId: String, confirmationId: String, action: String, reason: String, riskLevel: String, details: String?)
    case streamRichContent(sessionId: String, format: String, title: String?, content: String, height: Int?)
    case streamProgress(sessionId: String, progressId: String, title: String, steps: [ProgressStep])
    case streamSuggestions(sessionId: String, suggestions: [SuggestionItem])
    case conversationInviteAgent(sessionId: String, agentName: String)
    case planComplete(sessionId: String, plan: String?, allowedPrompts: [PlanAllowedPrompt]?)
    case taskCreated(sessionId: String?, task: TaskWireSwift)
    case taskUpdated(sessionId: String?, task: TaskWireSwift)
    case taskListResult(tasks: [TaskWireSwift])
    case connectorListResult(connections: [ConnectorWire])
    case connectorStatusChanged(connection: ConnectorWire)
    case connectorAudit(sessionId: String?, connectionId: String, provider: String, action: String, outcome: String, summary: String)
    case workspaceCreated(sessionId: String, workspaceName: String, agentName: String)
    case workspaceJoined(sessionId: String, workspaceName: String, agentName: String)
    case agentInvited(sessionId: String, invitedAgent: String, invitedBy: String)
    case iosPushRegistered(apnsToken: String, success: Bool, error: String?)
    case nostrStatus(connectedRelays: Int, totalRelays: Int)
    case agentQuestionRouting(sessionId: String, questionId: String, targetAgentName: String)
    case agentQuestionResolved(sessionId: String, questionId: String, answeredBy: String, isFallback: Bool)
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

struct PlanAllowedPrompt: Codable, Sendable, Identifiable {
    let tool: String
    let prompt: String
    var id: String { "\(tool):\(prompt)" }
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
    let plan: String?
    let allowedPrompts: [PlanAllowedPrompt]?
    let taskWire: TaskWireSwift?
    let tasks: [TaskWireSwift]?
    let connection: ConnectorWire?
    let connections: [ConnectorWire]?
    let connectionId: String?
    let provider: String?
    let outcome: String?
    let summary: String?
    let agentName: String?
    let workspaceName: String?
    let workspaceId: String?
    let invitedAgent: String?
    let invitedBy: String?
    let apnsToken: String?
    let success: Bool?
    let connectedRelays: Int?
    let totalRelays: Int?
    let timeoutSeconds: Int?
    let autoRouting: Bool?
    let answeredBy: String?
    let isFallback: Bool?
    let targetAgentName: String?

    enum CodingKeys: String, CodingKey {
        case type, sessionId, text, tool, input, output, result, cost
        case inputTokens, outputTokens, numTurns, toolCallCount
        case error, channelId, from, to, message, key, value, writtenBy
        case parentSessionId, childSessionId, originalSessionId, reusedSessionId
        case imageData, mediaType, filePath, fileType, fileName
        case requestId, spec, questionId, question, options, multiSelect
        case `private`, inputType, inputConfig
        case confirmationId, action, reason, riskLevel, details
        case format, title, content, height, progressId, steps, suggestions
        case plan, allowedPrompts
        case taskWire = "task"
        case tasks
        case connection, connections, connectionId, provider, outcome, summary
        case agentName, workspaceName, workspaceId
        case invitedAgent, invitedBy
        case apnsToken, success
        case connectedRelays, totalRelays
        case timeoutSeconds, autoRouting, answeredBy, isFallback, targetAgentName
    }

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
            guard let sid = sessionId, let ch = channelId, let f = from, let m = message else { return nil }
            return .peerChat(sessionId: sid, channelId: ch, from: f, message: m)
        case "peer.delegate":
            guard let sid = sessionId, let f = from, let t = to, let tk = text ?? message else { return nil }
            return .peerDelegate(sessionId: sid, from: f, to: t, task: tk)
        case "blackboard.update":
            guard let sid = sessionId, let k = key, let v = value, let w = writtenBy else { return nil }
            return .blackboardUpdate(sessionId: sid, key: k, value: v, writtenBy: w)
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
            return .agentQuestion(sessionId: sid, questionId: qid, question: q, options: options, multiSelect: multiSelect ?? false, isPrivate: `private` ?? true, inputType: inputType, inputConfig: inputConfig, timeoutSeconds: timeoutSeconds, autoRouting: autoRouting)
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
        case "session.planComplete":
            guard let sid = sessionId else { return nil }
            return .planComplete(sessionId: sid, plan: plan, allowedPrompts: allowedPrompts)
        case "conversation.inviteAgent":
            guard let sid = sessionId, let name = agentName else { return nil }
            return .conversationInviteAgent(sessionId: sid, agentName: name)
        case "task.created":
            guard let t = taskWire else { return nil }
            return .taskCreated(sessionId: sessionId, task: t)
        case "task.updated":
            guard let t = taskWire else { return nil }
            return .taskUpdated(sessionId: sessionId, task: t)
        case "task.list.result":
            return .taskListResult(tasks: tasks ?? [])
        case "connector.list.result":
            return .connectorListResult(connections: connections ?? [])
        case "connector.statusChanged":
            guard let connection else { return nil }
            return .connectorStatusChanged(connection: connection)
        case "connector.audit":
            guard let connectionId, let provider, let action, let outcome, let summary else { return nil }
            return .connectorAudit(
                sessionId: sessionId,
                connectionId: connectionId,
                provider: provider,
                action: action,
                outcome: outcome,
                summary: summary
            )
        case "workspace.created":
            guard let sid = sessionId, let name = workspaceName, let agent = agentName else { return nil }
            return .workspaceCreated(sessionId: sid, workspaceName: name, agentName: agent)
        case "workspace.joined":
            guard let sid = sessionId, let name = workspaceName, let agent = agentName else { return nil }
            return .workspaceJoined(sessionId: sid, workspaceName: name, agentName: agent)
        case "agent.invited":
            guard let sid = sessionId, let invited = invitedAgent, let by = invitedBy else { return nil }
            return .agentInvited(sessionId: sid, invitedAgent: invited, invitedBy: by)
        case "ios.pushRegistered":
            let token = apnsToken ?? ""
            let successVal = success ?? false
            return .iosPushRegistered(apnsToken: token, success: successVal, error: error)
        case "nostr.status":
            let connected = connectedRelays ?? 0
            let total = totalRelays ?? 0
            return .nostrStatus(connectedRelays: connected, totalRelays: total)
        case "agent.question.routing":
            guard let sid = sessionId, let qid = questionId, let target = targetAgentName else { return nil }
            return .agentQuestionRouting(sessionId: sid, questionId: qid, targetAgentName: target)
        case "agent.question.resolved":
            guard let sid = sessionId, let qid = questionId, let answered = answeredBy else { return nil }
            return .agentQuestionResolved(sessionId: sid, questionId: qid, answeredBy: answered, isFallback: isFallback ?? false)
        default:
            return nil
        }
    }
}
