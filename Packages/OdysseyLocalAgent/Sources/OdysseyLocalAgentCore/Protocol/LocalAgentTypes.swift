import Foundation

public enum LocalAgentProvider: String, Codable, CaseIterable, Sendable {
    case foundation
    case mlx
}

public enum DynamicValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: DynamicValue])
    case array([DynamicValue])
    case null

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: DynamicValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([DynamicValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.typeMismatch(
                DynamicValue.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported dynamic value")
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    public var stringValue: String {
        switch self {
        case .string(let value):
            value
        case .number(let value):
            if value.rounded() == value {
                String(Int(value))
            } else {
                String(value)
            }
        case .bool(let value):
            value ? "true" : "false"
        case .object(let value):
            (try? jsonString(from: value)) ?? "{}"
        case .array(let value):
            (try? jsonString(from: value)) ?? "[]"
        case .null:
            "null"
        }
    }

    public var objectValue: [String: DynamicValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    public static func from(any value: Any) -> DynamicValue {
        switch value {
        case let string as String:
            .string(string)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                .bool(number.boolValue)
            } else {
                .number(number.doubleValue)
            }
        case let dictionary as [String: Any]:
            .object(dictionary.mapValues(DynamicValue.from(any:)))
        case let array as [Any]:
            .array(array.map(DynamicValue.from(any:)))
        default:
            .string(String(describing: value))
        }
    }
}

private func jsonString(from value: some Encodable) throws -> String {
    let data = try JSONEncoder().encode(value)
    return String(decoding: data, as: UTF8.self)
}

public struct LocalAgentSkill: Codable, Sendable, Equatable {
    public var name: String
    public var content: String

    public init(name: String, content: String) {
        self.name = name
        self.content = content
    }
}

public struct LocalAgentMCPServer: Codable, Sendable, Equatable {
    public var name: String
    public var command: String?
    public var args: [String]?
    public var env: [String: String]?
    public var url: String?

    public init(
        name: String,
        command: String? = nil,
        args: [String]? = nil,
        env: [String: String]? = nil,
        url: String? = nil
    ) {
        self.name = name
        self.command = command
        self.args = args
        self.env = env
        self.url = url
    }
}

public struct LocalAgentToolDefinition: Codable, Sendable, Equatable {
    public var name: String
    public var description: String
    public var inputSchema: [String: String]

    public init(name: String, description: String, inputSchema: [String: String] = [:]) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

public struct LocalAgentConfig: Codable, Sendable, Equatable {
    public var name: String
    public var provider: LocalAgentProvider
    public var model: String
    public var systemPrompt: String
    public var workingDirectory: String
    public var maxTurns: Int?
    public var maxThinkingTokens: Int?
    public var maxTokensPerStep: Int?
    public var allowedTools: [String]
    public var mcpServers: [LocalAgentMCPServer]
    public var skills: [LocalAgentSkill]
    public var toolDefinitions: [LocalAgentToolDefinition]

    public init(
        name: String,
        provider: LocalAgentProvider,
        model: String,
        systemPrompt: String,
        workingDirectory: String,
        maxTurns: Int? = nil,
        maxThinkingTokens: Int? = nil,
        maxTokensPerStep: Int? = nil,
        allowedTools: [String] = [],
        mcpServers: [LocalAgentMCPServer] = [],
        skills: [LocalAgentSkill] = [],
        toolDefinitions: [LocalAgentToolDefinition] = []
    ) {
        self.name = name
        self.provider = provider
        self.model = model
        self.systemPrompt = systemPrompt
        self.workingDirectory = workingDirectory
        self.maxTurns = maxTurns
        self.maxThinkingTokens = maxThinkingTokens
        self.maxTokensPerStep = maxTokensPerStep
        self.allowedTools = allowedTools
        self.mcpServers = mcpServers
        self.skills = skills
        self.toolDefinitions = toolDefinitions
    }
}

public struct TranscriptItem: Codable, Sendable, Equatable {
    public enum Role: String, Codable, Sendable {
        case system
        case user
        case assistant
        case tool
    }

    public var role: Role
    public var text: String
    public var createdAt: Date

    public init(role: Role, text: String, createdAt: Date = Date()) {
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }
}

public struct LocalAgentEvent: Codable, Sendable, Equatable {
    public enum EventType: String, Codable, Sendable {
        case token
        case thinking
        case toolCall
        case toolResult
        case error
    }

    public var type: EventType
    public var sessionId: String
    public var text: String?
    public var tool: String?
    public var input: String?
    public var output: String?
    public var arguments: [String: DynamicValue]?

    public init(
        type: EventType,
        sessionId: String,
        text: String? = nil,
        tool: String? = nil,
        input: String? = nil,
        output: String? = nil,
        arguments: [String: DynamicValue]? = nil
    ) {
        self.type = type
        self.sessionId = sessionId
        self.text = text
        self.tool = tool
        self.input = input
        self.output = output
        self.arguments = arguments
    }
}

public struct ProviderProbeResult: Codable, Sendable, Equatable {
    public var provider: LocalAgentProvider
    public var available: Bool
    public var reason: String?
    public var supportsTools: Bool
    public var supportsTranscriptResume: Bool

    public init(
        provider: LocalAgentProvider,
        available: Bool,
        reason: String? = nil,
        supportsTools: Bool,
        supportsTranscriptResume: Bool
    ) {
        self.provider = provider
        self.available = available
        self.reason = reason
        self.supportsTools = supportsTools
        self.supportsTranscriptResume = supportsTranscriptResume
    }
}

public struct CreateSessionParams: Codable, Sendable, Equatable {
    public var sessionId: String
    public var config: LocalAgentConfig

    public init(sessionId: String, config: LocalAgentConfig) {
        self.sessionId = sessionId
        self.config = config
    }
}

public struct MessageSessionParams: Codable, Sendable, Equatable {
    public var sessionId: String
    public var text: String

    public init(sessionId: String, text: String) {
        self.sessionId = sessionId
        self.text = text
    }
}

public struct ToolCallParams: Codable, Sendable, Equatable {
    public var sessionId: String
    public var toolName: String
    public var arguments: [String: DynamicValue]

    public init(sessionId: String, toolName: String, arguments: [String: DynamicValue]) {
        self.sessionId = sessionId
        self.toolName = toolName
        self.arguments = arguments
    }
}

public struct RunOnceParams: Codable, Sendable, Equatable {
    public var config: LocalAgentConfig
    public var prompt: String

    public init(config: LocalAgentConfig, prompt: String) {
        self.config = config
        self.prompt = prompt
    }
}

public struct SessionTranscriptParams: Codable, Sendable, Equatable {
    public var sessionId: String

    public init(sessionId: String) {
        self.sessionId = sessionId
    }
}

public struct SessionTranscriptResult: Codable, Sendable, Equatable {
    public var sessionId: String
    public var transcript: [TranscriptItem]

    public init(sessionId: String, transcript: [TranscriptItem]) {
        self.sessionId = sessionId
        self.transcript = transcript
    }
}

public struct SessionToolsParams: Codable, Sendable, Equatable {
    public var sessionId: String

    public init(sessionId: String) {
        self.sessionId = sessionId
    }
}

public struct SessionToolsResult: Codable, Sendable, Equatable {
    public var sessionId: String
    public var tools: [LocalAgentToolDefinition]

    public init(sessionId: String, tools: [LocalAgentToolDefinition]) {
        self.sessionId = sessionId
        self.tools = tools
    }
}

public struct ResumeSessionParams: Codable, Sendable, Equatable {
    public var sessionId: String
    public var backendSessionId: String
    public var config: LocalAgentConfig?
    public var transcript: [TranscriptItem]?

    public init(
        sessionId: String,
        backendSessionId: String,
        config: LocalAgentConfig? = nil,
        transcript: [TranscriptItem]? = nil
    ) {
        self.sessionId = sessionId
        self.backendSessionId = backendSessionId
        self.config = config
        self.transcript = transcript
    }
}

public struct PauseSessionParams: Codable, Sendable, Equatable {
    public var sessionId: String

    public init(sessionId: String) {
        self.sessionId = sessionId
    }
}

public struct ForkSessionParams: Codable, Sendable, Equatable {
    public var parentSessionId: String
    public var childSessionId: String

    public init(parentSessionId: String, childSessionId: String) {
        self.parentSessionId = parentSessionId
        self.childSessionId = childSessionId
    }
}

public struct ProbeProviderParams: Codable, Sendable, Equatable {
    public var provider: LocalAgentProvider

    public init(provider: LocalAgentProvider) {
        self.provider = provider
    }
}

public struct SessionOperationResult: Codable, Sendable, Equatable {
    public var backendSessionId: String

    public init(backendSessionId: String) {
        self.backendSessionId = backendSessionId
    }
}

public struct TurnResponse: Codable, Sendable, Equatable {
    public var backendSessionId: String
    public var resultText: String
    public var inputTokens: Int
    public var outputTokens: Int
    public var numTurns: Int
    public var events: [LocalAgentEvent]

    public init(
        backendSessionId: String,
        resultText: String,
        inputTokens: Int,
        outputTokens: Int,
        numTurns: Int,
        events: [LocalAgentEvent]
    ) {
        self.backendSessionId = backendSessionId
        self.resultText = resultText
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.numTurns = numTurns
        self.events = events
    }
}

public enum LocalAgentHostMethod: String, Sendable {
    case initialize = "initialize"
    case providerProbe = "provider.probe"
    case mlxModelsList = "mlx.models.list"
    case mlxModelInstall = "mlx.models.install"
    case mlxModelDelete = "mlx.models.delete"
    case sessionCreate = "session.create"
    case sessionMessage = "session.message"
    case sessionResume = "session.resume"
    case sessionPause = "session.pause"
    case sessionFork = "session.fork"
    case sessionRun = "session.run"
    case sessionTranscript = "session.transcript"
    case sessionTools = "session.tools"
    case agentCreateSession = "agent.createSession"
    case agentSendMessage = "agent.sendMessage"
    case agentResumeSession = "agent.resumeSession"
    case agentPauseSession = "agent.pauseSession"
    case agentForkSession = "agent.forkSession"
    case agentRun = "agent.run"
    case agentGetTranscript = "agent.getTranscript"
    case agentGetTools = "agent.getTools"
    case agentProbeProvider = "agent.probeProvider"
    case toolCall = "tool.call"
}
