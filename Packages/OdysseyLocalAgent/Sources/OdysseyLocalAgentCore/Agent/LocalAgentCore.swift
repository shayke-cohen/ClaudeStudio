import Foundation

private struct LocalAgentSession: Sendable {
    var sessionId: String
    var backendSessionId: String
    var config: LocalAgentConfig
    var transcript: [TranscriptItem]
    var remoteToolNames: Set<String>
    var allowedBuiltInTools: Set<String>
}

public actor LocalAgentCore {
    private var sessions: [String: LocalAgentSession] = [:]
    private let toolRegistry: ToolRegistry
    private let toolExecutor: ToolExecutor
    private let mcpBridge: MCPBridge
    private let adapters: [LocalAgentProvider: any LocalModelAdapter]

    public init(
        toolRegistry: ToolRegistry? = nil,
        remoteToolCaller: (any RemoteToolCalling)? = nil,
        mcpBridge: MCPBridge = MCPBridge()
    ) {
        let registry = toolRegistry ?? ToolRegistry(tools: BuiltInTools.makeDefaultTools())
        self.toolRegistry = registry
        self.mcpBridge = mcpBridge
        self.toolExecutor = ToolExecutor(registry: registry, remoteToolCaller: remoteToolCaller, mcpBridge: mcpBridge)
        self.adapters = [
            .foundation: FoundationModelAdapter(),
            .mlx: MLXModelAdapter(),
        ]
    }

    public func registerTool(_ tool: ToolDefinition) async {
        await toolRegistry.register(tool)
    }

    public func probe(_ params: ProbeProviderParams) async -> ProviderProbeResult {
        guard let adapter = adapters[params.provider] else {
            return ProviderProbeResult(
                provider: params.provider,
                available: false,
                reason: "No adapter registered",
                supportsTools: false,
                supportsTranscriptResume: false
            )
        }
        return await adapter.probe()
    }

    public func createSession(_ params: CreateSessionParams) async -> SessionOperationResult {
        let backendSessionId = UUID().uuidString
        var config = params.config
        let accessPolicy = await accessPolicy(for: config)
        let allLocalTools = await allLocalToolDefinitions()
        let allowedBuiltInTools = accessPolicy.allowedBuiltInToolNames(from: allLocalTools)
        let localTools = allLocalTools.filter { allowedBuiltInTools.contains($0.name) }
        let mcpTools = await mcpBridge.discoverTools(for: config.mcpServers)
        config.toolDefinitions = mergeToolDefinitions(local: localTools, remote: config.toolDefinitions, mcp: mcpTools)

        sessions[params.sessionId] = LocalAgentSession(
            sessionId: params.sessionId,
            backendSessionId: backendSessionId,
            config: config,
            transcript: [.init(role: .system, text: config.systemPrompt)],
            remoteToolNames: Set(params.config.toolDefinitions.map(\.name)),
            allowedBuiltInTools: allowedBuiltInTools
        )
        return SessionOperationResult(backendSessionId: backendSessionId)
    }

    public func sendMessage(
        _ params: MessageSessionParams,
        tokenReporter: (@Sendable (String, String) -> Void)? = nil
    ) async throws -> TurnResponse {
        guard var session = sessions[params.sessionId] else {
            throw NSError(domain: "OdysseyLocalAgentCore", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "Session not found: \(params.sessionId)",
            ])
        }

        guard let adapter = adapters[session.config.provider] else {
            throw NSError(domain: "OdysseyLocalAgentCore", code: 500, userInfo: [
                NSLocalizedDescriptionKey: "No adapter for provider \(session.config.provider.rawValue)",
            ])
        }

        session.transcript.append(.init(role: .user, text: params.text))
        let result = try await adapter.sendTurn(
            sessionId: params.sessionId,
            config: session.config,
            text: params.text,
            transcript: session.transcript,
            context: AdapterContext(
                toolExecutor: toolExecutor,
                workingDirectory: session.config.workingDirectory,
                remoteToolNames: session.remoteToolNames,
                mcpServers: session.config.mcpServers,
                localPermissionRules: session.config.allowedTools,
                allowedBuiltInTools: session.allowedBuiltInTools,
                tokenReporter: tokenReporter
            )
        )
        session.transcript.append(contentsOf: transcriptEntries(from: result.events))
        session.transcript.append(.init(role: .assistant, text: result.resultText))
        sessions[params.sessionId] = session

        return TurnResponse(
            backendSessionId: session.backendSessionId,
            resultText: result.resultText,
            inputTokens: max(1, params.text.split(separator: " ").count),
            outputTokens: max(1, result.resultText.split(separator: " ").count),
            numTurns: max(1, session.transcript.filter { $0.role == .assistant }.count),
            events: result.events
        )
    }

    public func runOnce(_ params: RunOnceParams) async throws -> TurnResponse {
        let sessionId = "run-\(UUID().uuidString)"
        _ = await createSession(.init(sessionId: sessionId, config: params.config))
        return try await sendMessage(.init(sessionId: sessionId, text: params.prompt))
    }

    public func resumeSession(_ params: ResumeSessionParams) async -> SessionOperationResult {
        guard var session = sessions[params.sessionId] else {
            let config = params.config ?? LocalAgentConfig(
                name: params.sessionId,
                provider: .foundation,
                model: "foundation.system",
                systemPrompt: "Restored local agent session",
                workingDirectory: FileManager.default.currentDirectoryPath
            )
            let accessPolicy = await accessPolicy(for: config)
            let allowedBuiltInTools = accessPolicy.allowedBuiltInToolNames(from: await allLocalToolDefinitions())
            sessions[params.sessionId] = LocalAgentSession(
                sessionId: params.sessionId,
                backendSessionId: params.backendSessionId,
                config: config,
                transcript: params.transcript ?? [.init(role: .system, text: config.systemPrompt)],
                remoteToolNames: [],
                allowedBuiltInTools: allowedBuiltInTools
            )
            return SessionOperationResult(backendSessionId: params.backendSessionId)
        }

        session.backendSessionId = params.backendSessionId
        if let config = params.config {
            session.config = config
            let accessPolicy = await accessPolicy(for: config)
            session.allowedBuiltInTools = accessPolicy.allowedBuiltInToolNames(from: await allLocalToolDefinitions())
            session.remoteToolNames = Set(config.toolDefinitions.map(\.name))
        }
        if let transcript = params.transcript {
            session.transcript = transcript
        }
        sessions[params.sessionId] = session
        return SessionOperationResult(backendSessionId: params.backendSessionId)
    }

    public func pauseSession(sessionId: String) async -> SessionOperationResult {
        await ManagedMLXModels.cancelSessionProcess(sessionId: sessionId)
        let backendSessionId = sessions[sessionId]?.backendSessionId ?? sessionId
        return SessionOperationResult(backendSessionId: backendSessionId)
    }

    public func forkSession(_ params: ForkSessionParams) async throws -> SessionOperationResult {
        guard let parent = sessions[params.parentSessionId] else {
            throw NSError(domain: "OdysseyLocalAgentCore", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "Parent session not found: \(params.parentSessionId)",
            ])
        }

        let childBackendSessionId = UUID().uuidString
        sessions[params.childSessionId] = LocalAgentSession(
            sessionId: params.childSessionId,
            backendSessionId: childBackendSessionId,
            config: parent.config,
            transcript: parent.transcript,
            remoteToolNames: parent.remoteToolNames,
            allowedBuiltInTools: parent.allowedBuiltInTools
        )
        return SessionOperationResult(backendSessionId: childBackendSessionId)
    }

    public func transcript(for sessionId: String) async -> [TranscriptItem] {
        sessions[sessionId]?.transcript ?? []
    }

    public func tools(for sessionId: String) async -> [LocalAgentToolDefinition] {
        sessions[sessionId]?.config.toolDefinitions ?? []
    }

    public func shutdown() async {
        sessions.removeAll()
        await mcpBridge.shutdown()
    }

    private func accessPolicy(for config: LocalAgentConfig) async -> LocalToolAccessPolicy {
        LocalToolAccessPolicy(rules: config.allowedTools)
    }

    private func allLocalToolDefinitions() async -> [LocalAgentToolDefinition] {
        await toolRegistry.allToolDefinitions()
    }

    private func transcriptEntries(from events: [LocalAgentEvent]) -> [TranscriptItem] {
        events.compactMap { event in
            switch event.type {
            case .toolCall:
                let payload = event.input ?? encodedArguments(event.arguments)
                return TranscriptItem(role: .assistant, text: #"{"tool":"\#(event.tool ?? "unknown")","arguments":\#(payload)}"#)
            case .toolResult:
                return TranscriptItem(role: .tool, text: event.output ?? "")
            case .token, .thinking, .error:
                return nil
            }
        }
    }

    private func mergeToolDefinitions(
        local: [LocalAgentToolDefinition],
        remote: [LocalAgentToolDefinition],
        mcp: [LocalAgentToolDefinition]
    ) -> [LocalAgentToolDefinition] {
        var seen = Set<String>()
        var merged = [LocalAgentToolDefinition]()
        for definition in local + remote + mcp {
            if seen.insert(definition.name).inserted {
                merged.append(definition)
            }
        }
        return merged.sorted { $0.name < $1.name }
    }

    private func encodedArguments(_ arguments: [String: DynamicValue]?) -> String {
        guard let arguments,
              let data = try? JSONEncoder().encode(arguments) else {
            return "{}"
        }
        return String(decoding: data, as: UTF8.self)
    }
}
