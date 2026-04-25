import OdysseyLocalAgentCore
import Foundation

private enum HostCommand: String {
    case stdio
    case run
    case models
    case installModel = "install-model"
    case removeModel = "remove-model"
    case serve
    case chat
    case help
}

actor HostService {
    private let core: LocalAgentCore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(remoteToolCaller: (any RemoteToolCalling)? = nil) {
        self.core = LocalAgentCore(remoteToolCaller: remoteToolCaller)
        encoder.outputFormatting = [.sortedKeys]
    }

    func handle(
        method: String,
        params: Any?,
        tokenReporter: (@Sendable (String, String) -> Void)? = nil
    ) async throws -> Any {
        let paramsData = try data(for: params)
        switch method {
        case LocalAgentHostMethod.initialize.rawValue:
            return ["name": "OdysseyLocalAgentHost", "version": "0.3.0"]
        case LocalAgentHostMethod.providerProbe.rawValue,
             LocalAgentHostMethod.agentProbeProvider.rawValue:
            let decoded = try decoder.decode(ProbeProviderParams.self, from: paramsData)
            return try jsonObject(from: await core.probe(decoded))
        case LocalAgentHostMethod.mlxModelsList.rawValue:
            let decoded = try decoder.decode(MLXModelsListParams.self, from: paramsData)
            return try jsonObject(from: ManagedMLXModels.listModels(
                downloadDirectory: decoded.downloadDirectory,
                runnerPath: decoded.runnerPath
            ))
        case LocalAgentHostMethod.mlxModelInstall.rawValue:
            let decoded = try decoder.decode(InstallMLXModelParams.self, from: paramsData)
            return try jsonObject(from: ManagedMLXModels.installModel(
                modelIdentifier: decoded.modelIdentifier,
                downloadDirectory: decoded.downloadDirectory,
                runnerPath: decoded.runnerPath
            ))
        case LocalAgentHostMethod.mlxModelDelete.rawValue:
            let decoded = try decoder.decode(RemoveMLXModelParams.self, from: paramsData)
            return try jsonObject(from: ManagedMLXModels.removeModel(
                modelIdentifier: decoded.modelIdentifier,
                downloadDirectory: decoded.downloadDirectory
            ))
        case LocalAgentHostMethod.sessionCreate.rawValue,
             LocalAgentHostMethod.agentCreateSession.rawValue:
            let decoded = try decoder.decode(CreateSessionParams.self, from: paramsData)
            return try jsonObject(from: await core.createSession(decoded))
        case LocalAgentHostMethod.sessionMessage.rawValue,
             LocalAgentHostMethod.agentSendMessage.rawValue:
            let decoded = try decoder.decode(MessageSessionParams.self, from: paramsData)
            return try jsonObject(from: try await core.sendMessage(decoded, tokenReporter: tokenReporter))
        case LocalAgentHostMethod.sessionResume.rawValue,
             LocalAgentHostMethod.agentResumeSession.rawValue:
            let decoded = try decoder.decode(ResumeSessionParams.self, from: paramsData)
            return try jsonObject(from: await core.resumeSession(decoded))
        case LocalAgentHostMethod.sessionPause.rawValue,
             LocalAgentHostMethod.agentPauseSession.rawValue:
            let decoded = try decoder.decode(PauseSessionParams.self, from: paramsData)
            return try jsonObject(from: await core.pauseSession(sessionId: decoded.sessionId))
        case LocalAgentHostMethod.sessionFork.rawValue,
             LocalAgentHostMethod.agentForkSession.rawValue:
            let decoded = try decoder.decode(ForkSessionParams.self, from: paramsData)
            return try jsonObject(from: try await core.forkSession(decoded))
        case LocalAgentHostMethod.sessionRun.rawValue,
             LocalAgentHostMethod.agentRun.rawValue:
            let decoded = try decoder.decode(RunOnceParams.self, from: paramsData)
            return try jsonObject(from: try await core.runOnce(decoded))
        case LocalAgentHostMethod.sessionTranscript.rawValue,
             LocalAgentHostMethod.agentGetTranscript.rawValue:
            let decoded = try decoder.decode(SessionTranscriptParams.self, from: paramsData)
            return try jsonObject(from: SessionTranscriptResult(sessionId: decoded.sessionId, transcript: await core.transcript(for: decoded.sessionId)))
        case LocalAgentHostMethod.sessionTools.rawValue,
             LocalAgentHostMethod.agentGetTools.rawValue:
            let decoded = try decoder.decode(SessionToolsParams.self, from: paramsData)
            return try jsonObject(from: SessionToolsResult(sessionId: decoded.sessionId, tools: await core.tools(for: decoded.sessionId)))
        default:
            throw NSError(domain: "OdysseyLocalAgentHost", code: -32601, userInfo: [
                NSLocalizedDescriptionKey: "Unknown method \(method)"
            ])
        }
    }

    func runOnce(config: LocalAgentConfig, prompt: String) async throws -> TurnResponse {
        try await core.runOnce(.init(config: config, prompt: prompt))
    }

    private func data(for params: Any?) throws -> Data {
        guard let params else { return Data("{}".utf8) }
        return try JSONSerialization.data(withJSONObject: params)
    }

    private func jsonObject(from value: some Encodable) throws -> Any {
        try JSONSerialization.jsonObject(with: encoder.encode(value))
    }
}

private actor StdioRequestBroker {
    private var pending: [Int: CheckedContinuation<Any, Error>] = [:]
    private weak var writer: StdioWriter?

    func attach(writer: StdioWriter) {
        self.writer = writer
    }

    func sendRequest(method: String, params: [String: Any]) async throws -> Any {
        let requestID = Int.random(in: 1_000_000...9_999_999)
        return try await withCheckedThrowingContinuation { continuation in
            pending[requestID] = continuation
            Task {
                try await writer?.write([
                    "id": requestID,
                    "method": method,
                    "params": params,
                ])
            }
        }
    }

    func resolve(id: Int, result: Any) {
        pending.removeValue(forKey: id)?.resume(returning: result)
    }

    func fail(id: Int, error: Error) {
        pending.removeValue(forKey: id)?.resume(throwing: error)
    }
}

private actor StdioWriter {
    func write(_ payload: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: payload)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}

private struct StdioRemoteToolCaller: RemoteToolCalling {
    let broker: StdioRequestBroker

    func callTool(name: String, arguments: [String: DynamicValue], context: ToolExecutionContext) async throws -> ToolExecutionResult {
        let result = try await broker.sendRequest(
            method: LocalAgentHostMethod.toolCall.rawValue,
            params: [
                "sessionId": context.sessionId,
                "toolName": name,
                "arguments": try jsonObject(from: arguments),
            ]
        )
        let data = try JSONSerialization.data(withJSONObject: result)
        return try JSONDecoder().decode(ToolExecutionResult.self, from: data)
    }

    private func jsonObject(from value: some Encodable) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
    }
}

private enum HTTPServerModeError: Error {
    case notImplemented
}

private final class StdioServer {
    private let broker = StdioRequestBroker()
    private let writer = StdioWriter()
    private lazy var service = HostService(remoteToolCaller: StdioRemoteToolCaller(broker: broker))

    init() {
        Task { await broker.attach(writer: writer) }
    }

    func run() async {
        while let line = readLine(strippingNewline: true) {
            guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            Task {
                await self.handle(line: line)
            }
        }
    }

    private func handle(line: String) async {
        var requestID: Any?
        do {
            guard let root = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let id = root["id"] else {
                return
            }
            requestID = id

            if let method = root["method"] as? String {
                let isMessageMethod = method == LocalAgentHostMethod.sessionMessage.rawValue
                    || method == LocalAgentHostMethod.agentSendMessage.rawValue
                var tokenReporter: (@Sendable (String, String) -> Void)?
                if isMessageMethod {
                    tokenReporter = { [writer] sessionId, text in
                        Task<Void, Never> {
                            try? await writer.write([
                                "method": "stream.token",
                                "params": ["sessionId": sessionId, "text": text],
                            ])
                        }
                    }
                }
                let result = try await service.handle(method: method, params: root["params"], tokenReporter: tokenReporter)
                try await writer.write(["id": id, "result": result])
                return
            }

            if let numericID = id as? Int {
                if let error = root["error"] as? [String: Any] {
                    await broker.fail(
                        id: numericID,
                        error: NSError(domain: "OdysseyLocalAgentHost", code: error["code"] as? Int ?? -32000, userInfo: [
                            NSLocalizedDescriptionKey: error["message"] as? String ?? "Unknown host callback error"
                        ])
                    )
                    return
                }
                await broker.resolve(id: numericID, result: root["result"] as Any)
            }
        } catch {
            try? await writer.write([
                "id": requestID ?? NSNull(),
                "error": [
                    "code": -32000,
                    "message": error.localizedDescription,
                ],
            ])
        }
    }
}

private func parseMode(arguments: [String]) -> HostCommand {
    guard arguments.count > 1, let mode = HostCommand(rawValue: arguments[1]) else {
        return .stdio
    }
    return mode
}

private func argumentValue(_ name: String, from arguments: [String], default defaultValue: String? = nil) -> String? {
    guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else {
        return defaultValue
    }
    return arguments[index + 1]
}

private func boolFlag(_ name: String, from arguments: [String]) -> Bool {
    arguments.contains(name)
}

private func repeatedArgumentValues(_ name: String, from arguments: [String]) -> [String] {
    var values = [String]()
    var index = 0
    while index < arguments.count {
        if arguments[index] == name, arguments.indices.contains(index + 1) {
            values.append(arguments[index + 1])
            index += 2
            continue
        }
        index += 1
    }
    return values
}

private func buildConfig(from arguments: [String]) -> LocalAgentConfig {
    if let configPath = argumentValue("--config", from: arguments),
       let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
       let config = try? JSONDecoder().decode(LocalAgentConfig.self, from: data) {
        return config
    }

    let provider = LocalAgentProvider(rawValue: argumentValue("--provider", from: arguments, default: "foundation") ?? "foundation") ?? .foundation
    let model = argumentValue(
        "--model",
        from: arguments,
        default: provider == .foundation ? "foundation.system" : "mlx-community/Qwen3-14B-4bit"
    ) ?? "foundation.system"
    let cwd = argumentValue("--cwd", from: arguments, default: FileManager.default.currentDirectoryPath) ?? FileManager.default.currentDirectoryPath
    let prompt = argumentValue("--system-prompt", from: arguments, default: "You are a local coding agent.") ?? "You are a local coding agent."
    let allowedTools = repeatedArgumentValues("--allow", from: arguments)
    let skillFiles = repeatedArgumentValues("--skill-file", from: arguments)
    let skills = skillFiles.compactMap { path -> LocalAgentSkill? in
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        return LocalAgentSkill(name: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent, content: content)
    }

    return LocalAgentConfig(
        name: argumentValue("--name", from: arguments, default: "Local Agent") ?? "Local Agent",
        provider: provider,
        model: model,
        systemPrompt: prompt,
        workingDirectory: cwd,
        allowedTools: allowedTools,
        skills: skills
    )
}

private func runCommand(arguments: [String]) async throws {
    let service = HostService()
    let prompt = argumentValue("--prompt", from: arguments, default: "") ?? ""
    let response = try await service.runOnce(config: buildConfig(from: arguments), prompt: prompt)
    if boolFlag("--json", from: arguments) {
        let data = try JSONEncoder().encode(response)
        print(String(decoding: data, as: UTF8.self))
    } else {
        print(response.resultText)
    }
}

private func modelsCommand(arguments: [String]) async throws {
    let service = HostService()
    let result = try await service.handle(
        method: LocalAgentHostMethod.mlxModelsList.rawValue,
        params: try jsonObject(from: MLXModelsListParams(
            downloadDirectory: argumentValue("--download-dir", from: arguments),
            runnerPath: argumentValue("--runner", from: arguments)
        ))
    )

    if boolFlag("--json", from: arguments),
       let payload = result as? [String: Any],
       let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
        print(String(decoding: data, as: UTF8.self))
        return
    }

    guard let payload = result as? [String: Any],
          let data = try? JSONSerialization.data(withJSONObject: payload),
          let decoded = try? JSONDecoder().decode(MLXModelsListResult.self, from: data) else {
        print("Unable to decode model list.")
        return
    }

    print("Managed MLX download directory: \(decoded.downloadDirectory)")
    print("Manifest: \(decoded.manifestPath)")
    print("Runner: \(decoded.runnerPath ?? "not installed")")
    print("")
    print("Recommended models:")
    for preset in decoded.presets {
        let suffix = preset.recommended ? " (recommended)" : ""
        print("- \(preset.modelIdentifier): \(preset.label)\(suffix)")
        print("  \(preset.summary)")
    }
    if decoded.installed.isEmpty {
        print("")
        print("Installed models: none yet")
    } else {
        print("")
        print("Installed models:")
        let formatter = ISO8601DateFormatter()
        for model in decoded.installed {
            print("- \(model.modelIdentifier) [\(formatter.string(from: model.installedAt))]")
        }
    }
}

private func installModelCommand(arguments: [String]) async throws {
    let service = HostService()
    let modelIdentifier = argumentValue("--model", from: arguments, default: nil)
        ?? argumentValue("--source", from: arguments, default: nil)
        ?? ""
    let result = try await service.handle(
        method: LocalAgentHostMethod.mlxModelInstall.rawValue,
        params: try jsonObject(from: InstallMLXModelParams(
            modelIdentifier: modelIdentifier,
            downloadDirectory: argumentValue("--download-dir", from: arguments),
            runnerPath: argumentValue("--runner", from: arguments)
        ))
    )

    guard let payload = result as? [String: Any],
          let data = try? JSONSerialization.data(withJSONObject: payload) else {
        print("Unable to decode install result.")
        return
    }

    if boolFlag("--json", from: arguments) {
        let pretty = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: pretty, as: UTF8.self))
        return
    }

    let decoded = try JSONDecoder().decode(InstallMLXModelResult.self, from: data)
    let verb = decoded.alreadyInstalled ? "Already installed" : "Installed"
    print("\(verb) \(decoded.modelIdentifier)")
    print("Runner: \(decoded.runnerPath)")
    print("Download directory: \(decoded.downloadDirectory)")
    print("Manifest: \(decoded.manifestPath)")
    if !decoded.output.isEmpty {
        print("")
        print(decoded.output)
    }
}

private func removeModelCommand(arguments: [String]) async throws {
    let service = HostService()
    let modelIdentifier = argumentValue("--model", from: arguments, default: nil)
        ?? argumentValue("--source", from: arguments, default: nil)
        ?? ""
    let result = try await service.handle(
        method: LocalAgentHostMethod.mlxModelDelete.rawValue,
        params: try jsonObject(from: RemoveMLXModelParams(
            modelIdentifier: modelIdentifier,
            downloadDirectory: argumentValue("--download-dir", from: arguments)
        ))
    )

    guard let payload = result as? [String: Any],
          let data = try? JSONSerialization.data(withJSONObject: payload) else {
        print("Unable to decode delete result.")
        return
    }

    if boolFlag("--json", from: arguments) {
        let pretty = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: pretty, as: UTF8.self))
        return
    }

    let decoded = try JSONDecoder().decode(RemoveMLXModelResult.self, from: data)
    let verb = decoded.alreadyRemoved ? "Already removed" : "Removed"
    print("\(verb) \(decoded.modelIdentifier)")
    print("Download directory: \(decoded.downloadDirectory)")
    print("Manifest: \(decoded.manifestPath)")
    if decoded.deletedPaths.isEmpty {
        print("Deleted paths: none")
    } else {
        print("Deleted paths:")
        for path in decoded.deletedPaths {
            print("- \(path)")
        }
    }
}

private func serveCommand(arguments: [String]) async throws {
    let port = Int(argumentValue("--port", from: arguments, default: "8787") ?? "8787") ?? 8787
    let server = try LocalAgentHTTPServer(port: port, service: HostService())
    try await server.run()
}

private func chatCommand(arguments: [String]) async throws {
    let service = HostService()
    let config = buildConfig(from: arguments)
    let sessionId = argumentValue("--session-id", from: arguments, default: "chat-\(UUID().uuidString)") ?? "chat-\(UUID().uuidString)"
    _ = try await service.handle(
        method: LocalAgentHostMethod.sessionCreate.rawValue,
        params: try jsonObject(from: CreateSessionParams(sessionId: sessionId, config: config))
    )

    print("OdysseyLocalAgentHost interactive chat")
    print("Type /help for commands, /exit to quit.\n")

    while true {
        print("you> ", terminator: "")
        fflush(stdout)
        guard let line = readLine(strippingNewline: true) else { break }
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "/exit" || trimmed == "/quit" {
            break
        }
        if trimmed.isEmpty {
            continue
        }
        if try await handleChatCommand(trimmed, config: config, sessionId: sessionId, service: service) {
            continue
        }

        let response = try await service.handle(
            method: LocalAgentHostMethod.sessionMessage.rawValue,
            params: try jsonObject(from: MessageSessionParams(sessionId: sessionId, text: trimmed))
        )
        if let payload = response as? [String: Any],
           let data = try? JSONSerialization.data(withJSONObject: payload),
           let decoded = try? JSONDecoder().decode(TurnResponse.self, from: data) {
            print("assistant> \(decoded.resultText)")
            print("")
        }
    }
}

private func handleChatCommand(
    _ input: String,
    config: LocalAgentConfig,
    sessionId: String,
    service: HostService
) async throws -> Bool {
    switch input {
    case "/help":
        print(
            """
            Commands:
              /help        Show chat commands and examples
              /tools       List tools available in this session
              /pwd         Show the current working directory
              /exit        Quit the chat

            Examples:
              list files here
              read AGENTS.md
              search for "LocalProviderSupport" in Odyssey
              run `git status --short`
            """
        )
        print("")
        return true
    case "/tools":
        let response = try await service.handle(
            method: LocalAgentHostMethod.sessionTools.rawValue,
            params: try jsonObject(from: SessionToolsParams(sessionId: sessionId))
        )
        if let payload = response as? [String: Any],
           let data = try? JSONSerialization.data(withJSONObject: payload),
           let decoded = try? JSONDecoder().decode(SessionToolsResult.self, from: data) {
            print("assistant> Available tools:")
            for tool in decoded.tools {
                print("- \(tool.name): \(tool.description)")
            }
            print("")
        }
        return true
    case "/pwd":
        print("assistant> Working directory: \(config.workingDirectory)")
        print("")
        return true
    default:
        return false
    }
}

private func printHelp() {
    print(
        """
        OdysseyLocalAgentHost

        Commands:
          stdio                     Run the JSON-RPC stdio host (default)
          run                       Run one prompt and exit
          models                    Show managed MLX model presets and installed models
          install-model             Download and register an MLX model in the managed cache
          remove-model              Delete a managed MLX model from the local cache
          chat                      Start an interactive local-agent chat
          serve                     Start the local REST server

        Common flags:
          --config <path>           Read a full LocalAgentConfig JSON file
          --provider <foundation|mlx>
          --model <model>
          --cwd <path>
          --system-prompt <text>
          --name <display-name>
          --allow <rule>            Repeat to pass permission rules like Read, Write(*.md), Bash(git *)
          --skill-file <path>       Repeat to attach skill content files

        Extra flags:
          run  --prompt <text> [--json]
          models [--download-dir <path>] [--runner <path>] [--json]
          install-model --model <hugging-face-id|hugging-face-url|archive-url> [--download-dir <path>] [--runner <path>] [--json]
          remove-model --model <installed-id-or-hugging-face-url> [--download-dir <path>] [--json]
          chat --session-id <id>
          serve --port <port>
        """
    )
}

private func jsonObject(from value: some Encodable) throws -> Any {
    try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
}

let semaphore = DispatchSemaphore(value: 0)

Task {
    defer { semaphore.signal() }
    do {
        switch parseMode(arguments: CommandLine.arguments) {
        case .stdio:
            await StdioServer().run()
        case .run:
            try await runCommand(arguments: CommandLine.arguments)
        case .models:
            try await modelsCommand(arguments: CommandLine.arguments)
        case .installModel:
            try await installModelCommand(arguments: CommandLine.arguments)
        case .removeModel:
            try await removeModelCommand(arguments: CommandLine.arguments)
        case .serve:
            try await serveCommand(arguments: CommandLine.arguments)
        case .chat:
            try await chatCommand(arguments: CommandLine.arguments)
        case .help:
            printHelp()
        }
    } catch {
        fputs("OdysseyLocalAgentHost error: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

semaphore.wait()
