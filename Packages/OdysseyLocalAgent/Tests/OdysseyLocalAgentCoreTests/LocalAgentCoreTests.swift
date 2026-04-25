@testable import OdysseyLocalAgentCore
import XCTest

final class LocalAgentCoreTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        super.tearDown()
    }

    func testProbeReflectsRunnerAvailabilityWithoutStubEnv() async {
        unsetenv("ODYSSEY_MLX_RUNNER")
        unsetenv("CLAUDESTUDIO_MLX_RUNNER")
        let core = LocalAgentCore()

        let result = await core.probe(.init(provider: .mlx))

        XCTAssertEqual(result.provider, .mlx)
        XCTAssertEqual(result.available, ManagedMLXModels.resolveRunner() != nil)
        XCTAssertTrue(result.supportsTools)
    }

    func testResolveRunnerIgnoresDirectoryNamedLikeLLMTool() throws {
        let previousPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let fakeBin = tempDirectory.appendingPathComponent("fake-bin", isDirectory: true)
        let fakeRunnerDirectory = fakeBin.appendingPathComponent("llm-tool", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeRunnerDirectory, withIntermediateDirectories: true)

        unsetenv("ODYSSEY_MLX_RUNNER")
        unsetenv("CLAUDESTUDIO_MLX_RUNNER")
        _ = fakeBin.path.withCString { pointer in
            setenv("PATH", pointer, 1)
        }
        defer {
            _ = previousPath.withCString { pointer in
                setenv("PATH", pointer, 1)
            }
        }

        XCTAssertNotEqual(ManagedMLXModels.resolveRunner(fakeRunnerDirectory.path), fakeRunnerDirectory.path)
    }

    func testManagedMLXPresetsIncludeSizingAndAgentGuidance() {
        let presets = ManagedMLXModels.presets()

        XCTAssertFalse(presets.isEmpty)
        XCTAssertTrue(presets.allSatisfy { !$0.parameterSize.isEmpty })
        XCTAssertTrue(presets.allSatisfy { !$0.downloadSize.isEmpty })
        XCTAssertTrue(presets.allSatisfy { !$0.bestFor.isEmpty })
        XCTAssertTrue(presets.allSatisfy { !$0.agentSuitability.isEmpty })
    }

    func testManagedMLXPresetsMatchCuratedList() {
        XCTAssertEqual(
            ManagedMLXModels.presets().map(\.modelIdentifier),
            [
                "mlx-community/Qwen3-4B-Instruct-2507-4bit",
                "mlx-community/Qwen3-8B-4bit",
                "mlx-community/Qwen2.5-7B-Instruct-4bit",
                "mlx-community/Qwen2.5-Coder-7B-Instruct-4bit",
                "mlx-community/gemma-4-e2b-it-4bit",
                "mlx-community/gemma-4-e4b-it-4bit",
                "mlx-community/gemma-4-26b-a4b-it-4bit",
                "mlx-community/gemma-4-31b-it-4bit",
            ]
        )
    }

    func testManualToolLoopExecutesRegisteredTool() async throws {
        setenv("ODYSSEY_MLX_RUNNER", "/bin/echo", 1)
        setenv("CLAUDESTUDIO_MLX_RUNNER", "/bin/echo", 1)
        let core = LocalAgentCore()
        await core.registerTool(
            ToolDefinition(name: "echo", description: "Echo") { arguments, _ in
                ToolExecutionResult(success: true, output: "ECHO:\(arguments["message"]?.stringValue ?? "")")
            }
        )

        _ = await core.createSession(
            .init(
                sessionId: "mlx-session",
                config: .init(
                    name: "Local Coder",
                    provider: .mlx,
                    model: "mlx-default",
                    systemPrompt: "prompt",
                    workingDirectory: "/tmp",
                    allowedTools: ["echo"]
                )
            )
        )

        let response = try await core.sendMessage(
            .init(sessionId: "mlx-session", text: #"please [[tool:echo {"message":"hi"}]] now"#)
        )

        XCTAssertTrue(response.resultText.contains("[mlx]"))
        XCTAssertEqual(response.events.first?.type, .toolCall)
        XCTAssertEqual(response.events.dropFirst().first?.type, .toolResult)
    }

    func testConversationalDirectoryRequestExecutesToolWithoutInternalSyntax() async throws {
        unsetenv("ODYSSEY_MLX_RUNNER")
        unsetenv("CLAUDESTUDIO_MLX_RUNNER")
        let core = LocalAgentCore()
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        FileManager.default.createFile(atPath: tempDirectory.appendingPathComponent("notes.md").path, contents: Data())

        _ = await core.createSession(
            .init(
                sessionId: "mlx-natural-language-session",
                config: .init(
                    name: "Local Coder",
                    provider: .mlx,
                    model: "mlx-default",
                    systemPrompt: "prompt",
                    workingDirectory: tempDirectory.path,
                    allowedTools: ["Read"]
                )
            )
        )

        let response = try await core.sendMessage(
            .init(sessionId: "mlx-natural-language-session", text: "list files here")
        )

        XCTAssertTrue(response.resultText.contains("directory listing"))
        XCTAssertEqual(response.events.first?.type, .toolCall)
        XCTAssertEqual(response.events.dropFirst().first?.type, .toolResult)
        XCTAssertTrue(response.resultText.contains("notes.md"))
    }

    func testConversationalReadRequestExecutesToolWithoutInternalSyntax() async throws {
        unsetenv("ODYSSEY_MLX_RUNNER")
        unsetenv("CLAUDESTUDIO_MLX_RUNNER")
        let core = LocalAgentCore()
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let fileURL = tempDirectory.appendingPathComponent("notes.md")
        try "hello world".write(to: fileURL, atomically: true, encoding: .utf8)

        _ = await core.createSession(
            .init(
                sessionId: "mlx-natural-language-read-session",
                config: .init(
                    name: "Local Coder",
                    provider: .mlx,
                    model: "mlx-default",
                    systemPrompt: "prompt",
                    workingDirectory: tempDirectory.path,
                    allowedTools: ["Read"]
                )
            )
        )

        let response = try await core.sendMessage(
            .init(sessionId: "mlx-natural-language-read-session", text: "read notes.md")
        )

        XCTAssertTrue(response.resultText.contains("contents of notes.md"))
        XCTAssertEqual(response.events.first?.type, .toolCall)
        XCTAssertEqual(response.events.dropFirst().first?.type, .toolResult)
        XCTAssertTrue(response.resultText.contains("hello world"))
    }

    func testSanitizeMLXOutputRemovesLoadingLine() {
        let output = """
        Loading mlx-community/Qwen2.5-7B-Instruct-4bit...
        1 + 1 = 2
        """

        XCTAssertEqual(sanitizeMLXOutput(output), "1 + 1 = 2")
    }

    func testSanitizeMLXOutputExtractsStructuredResult() {
        let output = """
        Loading mlx-community/Qwen2.5-7B-Instruct-4bit...
        {"result": "2"}
        """

        XCTAssertEqual(sanitizeMLXOutput(output), "2")
    }

    func testSanitizeMLXOutputCollapsesDuplicatedAnswer() {
        let output = """
        "1+1 equals 2." "1+1 equals 2."
        """

        XCTAssertEqual(sanitizeMLXOutput(output), "\"1+1 equals 2.\"")
    }

    func testShouldPreferDirectChatResponseForGeneralQuestion() {
        XCTAssertTrue(
            shouldPreferDirectChatResponse(
                for: "where is tel aviv?",
                availableTools: ["read_file", "run_command"]
            )
        )
    }

    func testShouldPreferDirectChatResponseForToolingRequest() {
        XCTAssertFalse(
            shouldPreferDirectChatResponse(
                for: "read AGENTS.md",
                availableTools: ["read_file", "run_command"]
            )
        )
    }

    func testExtractActionableUserTextFromGroupPrompt() {
        let prompt = """
        [Group Communication Protocol]
        Mention teammates and use the blackboard if needed.
        --- Group thread (new since your last reply) ---
        User: hi
        --- End ---

        You are @Coder. Respond to the latest user message in this group.

        Latest user message:
        \"\"\"
        hi
        \"\"\"
        """

        XCTAssertEqual(extractActionableUserText(from: prompt), "hi")
    }

    func testShouldPreferDirectChatResponseForGroupPromptWithToolWordsInWrapper() {
        let prompt = """
        [Group Communication Protocol]
        Use workspace tools, task board tools, and the blackboard when needed.
        You are @Coder. Respond to the latest user message in this group.

        Latest user message:
        \"\"\"
        hi
        \"\"\"
        """

        XCTAssertTrue(
            shouldPreferDirectChatResponse(
                for: extractActionableUserText(from: prompt),
                availableTools: ["read_file", "run_command", "blackboard_write"]
            )
        )
    }

    func testPlansToolCallFromGroupPromptUsingLatestUserMessage() {
        let prompt = """
        [Group Communication Protocol]
        Use workspace tools, task board tools, and the blackboard when needed.
        You are @Coder. Respond to the latest user message in this group.

        Latest user message:
        \"\"\"
        list files here
        \"\"\"
        """

        let toolCall = planConversationalToolCall(
            in: extractActionableUserText(from: prompt),
            availableTools: ["list_directory", "read_file"],
            workingDirectory: "/tmp"
        )

        XCTAssertEqual(toolCall?.name, "list_directory")
        XCTAssertEqual(toolCall?.arguments["path"]?.stringValue, ".")
    }

    func testDetectsDegenerateAssistantResponses() {
        XCTAssertTrue(isDegenerateAssistantResponse("None", userText: "where is tel aviv?"))
        XCTAssertTrue(isDegenerateAssistantResponse("\"where is tel aviv?\"", userText: "where is tel aviv?"))
        XCTAssertFalse(isDegenerateAssistantResponse("Tel Aviv is on Israel's Mediterranean coast.", userText: "where is tel aviv?"))
    }

    func testNativeToolFlowExecutesRegisteredTool() async throws {
        let core = LocalAgentCore()
        await core.registerTool(
            ToolDefinition(name: "echo", description: "Echo") { arguments, _ in
                ToolExecutionResult(success: true, output: "FOUNDATION:\(arguments["message"]?.stringValue ?? "")")
            }
        )

        _ = await core.createSession(
            .init(
                sessionId: "foundation-session",
                config: .init(
                    name: "On Device Assistant",
                    provider: .foundation,
                    model: "foundation.system",
                    systemPrompt: "prompt",
                    workingDirectory: "/tmp",
                    allowedTools: ["echo"]
                )
            )
        )

        let response = try await core.sendMessage(
            .init(sessionId: "foundation-session", text: #"please [[tool:echo {"message":"hi"}]] now"#)
        )

        XCTAssertEqual(response.events.first?.type, .toolCall)
        XCTAssertEqual(response.events.dropFirst().first?.type, .toolResult)
    }

    func testPermissionRulesRestrictBuiltInTools() async throws {
        let core = LocalAgentCore()
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        _ = await core.createSession(
            .init(
                sessionId: "restricted-session",
                config: .init(
                    name: "Restricted",
                    provider: .foundation,
                    model: "foundation.system",
                    systemPrompt: "prompt",
                    workingDirectory: tempDirectory.path,
                    allowedTools: ["Read"]
                )
            )
        )

        let response = try await core.sendMessage(
            .init(
                sessionId: "restricted-session",
                text: #"please [[tool:write_file {"path":"notes.md","content":"hello"}]] now"#
            )
        )

        XCTAssertTrue(response.resultText.contains("not enabled") || response.resultText.contains("not allowed"))
    }

    func testWritePatternRuleAllowsMatchingFilesOnly() {
        let policy = LocalToolAccessPolicy(rules: ["Write(*.md)"])

        XCTAssertTrue(
            policy.allowsInvocation(
                toolName: "write_file",
                arguments: ["path": .string("notes.md")],
                workingDirectory: "/tmp"
            )
        )
        XCTAssertFalse(
            policy.allowsInvocation(
                toolName: "write_file",
                arguments: ["path": .string("main.swift")],
                workingDirectory: "/tmp"
            )
        )
    }

    func testToolsAndTranscriptAreAvailableForInspection() async throws {
        let core = LocalAgentCore()
        _ = await core.createSession(
            .init(
                sessionId: "inspectable-session",
                config: .init(
                    name: "Inspectable",
                    provider: .foundation,
                    model: "foundation.system",
                    systemPrompt: "prompt",
                    workingDirectory: "/tmp",
                    allowedTools: ["Read", "Grep"]
                )
            )
        )

        let tools = await core.tools(for: "inspectable-session")
        let transcript = await core.transcript(for: "inspectable-session")

        XCTAssertTrue(tools.contains(where: { $0.name == "read_file" }))
        XCTAssertTrue(tools.contains(where: { $0.name == "search_files" }))
        XCTAssertEqual(transcript.first?.role, .system)
    }

    func testTranscriptCodecRoundTripsItems() throws {
        let transcript = [
            TranscriptItem(role: .system, text: "sys"),
            TranscriptItem(role: .user, text: "hello"),
            TranscriptItem(role: .assistant, text: "hi"),
        ]

        let encoded = try TranscriptCodec.encode(transcript)
        let decoded = try TranscriptCodec.decode(encoded)

        XCTAssertEqual(decoded.map(\.role), transcript.map(\.role))
        XCTAssertEqual(decoded.map(\.text), transcript.map(\.text))
    }

    func testMCPBridgeCreatesSummary() async {
        let bridge = MCPBridge()
        let summary = await bridge.summarize(
            servers: [
                LocalAgentMCPServer(name: "filesystem", command: "/does/not/exist"),
                LocalAgentMCPServer(name: "docs", url: "http://localhost:9999"),
            ]
        )

        XCTAssertEqual(summary.configuredServers, ["filesystem", "docs"])
        XCTAssertEqual(summary.discoveredTools.count, 2)
        await bridge.shutdown()
    }

    func testMCPBridgeDiscoversAndCallsWorkingServer() async throws {
        let server = try makeStubMCPServer(
            in: tempDirectory,
            name: "working-mcp",
            toolName: "mcp_echo",
            responsePrefix: "MCP"
        )
        let bridge = MCPBridge()

        let summary = await bridge.summarize(servers: [server])
        XCTAssertEqual(summary.configuredServers, ["working-mcp"])
        XCTAssertEqual(summary.discoveredTools.map(\.name), ["mcp_echo"])

        let result = try await bridge.callTool(
            named: "mcp_echo",
            arguments: ["text": .string("hello")],
            servers: [server]
        )

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.output, "MCP: hello")
        await bridge.shutdown()
    }

    func testCreateSessionMergesLocalRemoteAndMCPTools() async throws {
        let server = try makeStubMCPServer(
            in: tempDirectory,
            name: "merge-mcp",
            toolName: "mcp_lookup",
            responsePrefix: "LOOKUP"
        )
        let core = LocalAgentCore()

        _ = await core.createSession(
            .init(
                sessionId: "merged-tools-session",
                config: .init(
                    name: "Merged Tools",
                    provider: .foundation,
                    model: "foundation.system",
                    systemPrompt: "prompt",
                    workingDirectory: tempDirectory.path,
                    allowedTools: ["Read"],
                    mcpServers: [server],
                    toolDefinitions: [
                        LocalAgentToolDefinition(
                            name: "remote_lookup",
                            description: "Remote lookup"
                        )
                    ]
                )
            )
        )

        let tools = await core.tools(for: "merged-tools-session")
        let toolNames = tools.map(\.name)

        XCTAssertTrue(toolNames.contains("read_file"))
        XCTAssertTrue(toolNames.contains("remote_lookup"))
        XCTAssertTrue(toolNames.contains("mcp_lookup"))
        XCTAssertEqual(toolNames.filter { $0 == "read_file" }.count, 1)
        await core.shutdown()
    }

    func testManagedMLXInstallWritesManifest() throws {
        let runnerPath = try makeStubRunner()
        let downloadDirectory = tempDirectory.appendingPathComponent("huggingface").path

        let result = try ManagedMLXModels.installModel(
            modelIdentifier: "mlx-community/Qwen3-0.6B-4bit",
            downloadDirectory: downloadDirectory,
            runnerPath: runnerPath
        )

        XCTAssertEqual(result.modelIdentifier, "mlx-community/Qwen3-0.6B-4bit")
        XCTAssertFalse(result.alreadyInstalled)
        XCTAssertEqual(result.downloadDirectory, downloadDirectory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.manifestPath))

        let listed = ManagedMLXModels.installedModels(downloadDirectory: downloadDirectory)
        XCTAssertEqual(listed.map(\.modelIdentifier), ["mlx-community/Qwen3-0.6B-4bit"])
    }

    func testManagedMLXInstallNormalizesHuggingFaceURL() throws {
        let runnerPath = try makeStubRunner()
        let downloadDirectory = tempDirectory.appendingPathComponent("huggingface").path

        let result = try ManagedMLXModels.installModel(
            modelIdentifier: "https://huggingface.co/mlx-community/Qwen3-0.6B-4bit",
            downloadDirectory: downloadDirectory,
            runnerPath: runnerPath
        )

        XCTAssertEqual(result.modelIdentifier, "mlx-community/Qwen3-0.6B-4bit")
    }

    func testManagedMLXInstallSupportsArchiveURL() throws {
        let runnerPath = try makeStubRunner()
        let downloadDirectory = tempDirectory.appendingPathComponent("huggingface").path
        let archiveURL = try makeModelArchive(named: "Qwen3 Archive Demo")

        let result = try ManagedMLXModels.installModel(
            modelIdentifier: archiveURL.absoluteString,
            downloadDirectory: downloadDirectory,
            runnerPath: runnerPath
        )

        XCTAssertEqual(result.modelIdentifier, "archive/qwen3-archive-demo")
        XCTAssertFalse(result.alreadyInstalled)

        let listed = ManagedMLXModels.installedModels(downloadDirectory: downloadDirectory)
        XCTAssertEqual(listed.map(\.modelIdentifier), ["archive/qwen3-archive-demo"])
        XCTAssertEqual(listed.first?.sourceURL, archiveURL.absoluteString)
        XCTAssertTrue(FileManager.default.fileExists(atPath: listed.first?.managedPath ?? ""))
    }

    func testInstalledModelsHealHuggingFaceManagedPathLayout() throws {
        let downloadDirectory = tempDirectory.appendingPathComponent("huggingface").path
        let actualManagedPath = tempDirectory
            .appendingPathComponent("huggingface/models/mlx-community/Qwen3-4B-Instruct-2507-4bit", isDirectory: true)
        try FileManager.default.createDirectory(at: actualManagedPath, withIntermediateDirectories: true)

        let manifestPath = ManagedMLXModels.manifestPath(for: downloadDirectory)
        struct TestManifest: Encodable {
            let installed: [ManagedMLXInstalledModel]
        }

        let manifest = TestManifest(installed: [
            ManagedMLXInstalledModel(
                modelIdentifier: "mlx-community/Qwen3-4B-Instruct-2507-4bit",
                downloadDirectory: downloadDirectory,
                installedAt: Date(),
                sourceURL: "https://huggingface.co/mlx-community/Qwen3-4B-Instruct-2507-4bit",
                managedPath: tempDirectory.appendingPathComponent("huggingface/mlx-community/Qwen3-4B-Instruct-2507-4bit").path
            )
        ])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: manifestPath).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(manifest).write(to: URL(fileURLWithPath: manifestPath), options: .atomic)

        let listed = ManagedMLXModels.installedModels(downloadDirectory: downloadDirectory)
        XCTAssertEqual(listed.first?.managedPath, actualManagedPath.path)
    }

    func testManagedMLXRemoveModelDeletesManagedPathAndManifestEntry() throws {
        let runnerPath = try makeStubRunner()
        let downloadDirectory = tempDirectory.appendingPathComponent("huggingface").path
        let managedPath = tempDirectory
            .appendingPathComponent("huggingface")
            .appendingPathComponent("mlx-community")
            .appendingPathComponent("Qwen3-0.6B-4bit")
        try FileManager.default.createDirectory(at: managedPath, withIntermediateDirectories: true)
        try "weights".write(
            to: managedPath.appendingPathComponent("weights.bin"),
            atomically: true,
            encoding: .utf8
        )

        _ = try ManagedMLXModels.installModel(
            modelIdentifier: "mlx-community/Qwen3-0.6B-4bit",
            downloadDirectory: downloadDirectory,
            runnerPath: runnerPath
        )

        let result = try ManagedMLXModels.removeModel(
            modelIdentifier: "https://huggingface.co/mlx-community/Qwen3-0.6B-4bit",
            downloadDirectory: downloadDirectory
        )

        XCTAssertEqual(result.modelIdentifier, "mlx-community/Qwen3-0.6B-4bit")
        XCTAssertFalse(result.alreadyRemoved)
        XCTAssertFalse(FileManager.default.fileExists(atPath: managedPath.path))
        XCTAssertEqual(
            ManagedMLXModels.installedModels(downloadDirectory: downloadDirectory).map(\.modelIdentifier),
            []
        )
    }

    func testNormalizeModelIdentifierRejectsInvalidURL() {
        XCTAssertNil(ManagedMLXModels.normalizeModelIdentifier("https://example.com/mlx-community/Qwen3-0.6B-4bit"))
        XCTAssertNil(ManagedMLXModels.normalizeModelIdentifier("/tmp/local-model"))
    }

    func testManagedMLXListReturnsPresetsAndInstalledModels() throws {
        let runnerPath = try makeStubRunner()
        let downloadDirectory = tempDirectory.appendingPathComponent("huggingface").path
        _ = try ManagedMLXModels.installModel(
            modelIdentifier: "mlx-community/Qwen2.5-7B-Instruct-4bit",
            downloadDirectory: downloadDirectory,
            runnerPath: runnerPath
        )

        let result = ManagedMLXModels.listModels(
            downloadDirectory: downloadDirectory,
            runnerPath: runnerPath
        )

        XCTAssertTrue(result.presets.contains(where: { $0.modelIdentifier == "mlx-community/Qwen2.5-7B-Instruct-4bit" }))
        XCTAssertEqual(result.installed.map(\.modelIdentifier), ["mlx-community/Qwen2.5-7B-Instruct-4bit"])
        XCTAssertEqual(result.runnerPath, runnerPath)
    }

    func testRunProcessReturnsOutputFromStubRunner() throws {
        let runnerPath = try makeStubRunner()

        let output = try ManagedMLXModels.runProcess(
            executable: runnerPath,
            arguments: ["eval", "--model", "mlx-community/Qwen3-0.6B-4bit"]
        )

        XCTAssertEqual(output, "eval --model mlx-community/Qwen3-0.6B-4bit")
    }

    func testRunProcessTimesOutHungRunner() throws {
        let runnerPath = try makeHangingRunner()

        XCTAssertThrowsError(
            try ManagedMLXModels.runProcess(
                executable: runnerPath,
                arguments: ["eval", "--model", "mlx-community/Qwen3-0.6B-4bit"],
                timeout: 0.2
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("Process timed out"))
        }
    }

    func testPauseSessionCancelsActiveMLXTurn() async throws {
        let runnerPath = try makeHangingRunner()
        setenv("ODYSSEY_MLX_RUNNER", runnerPath, 1)
        setenv("CLAUDESTUDIO_MLX_RUNNER", runnerPath, 1)

        let core = LocalAgentCore()
        _ = await core.createSession(
            .init(
                sessionId: "pause-mlx-session",
                config: .init(
                    name: "Pause MLX",
                    provider: .mlx,
                    model: "mlx-community/Qwen3-4B-Instruct-2507-4bit",
                    systemPrompt: "You are a local coding agent.",
                    workingDirectory: tempDirectory.path,
                    allowedTools: []
                )
            )
        )

        let startedAt = Date()
        let sendTask = Task {
            try await core.sendMessage(
                .init(sessionId: "pause-mlx-session", text: "hi")
            )
        }

        try await Task.sleep(for: .milliseconds(200))
        _ = await core.pauseSession(sessionId: "pause-mlx-session")

        await XCTAssertThrowsErrorAsync(try await sendTask.value) { error in
            let message = error.localizedDescription.lowercased()
            XCTAssertTrue(message.contains("cancel") || message.contains("terminate") || message.contains("failed"))
        }
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 2.5)
    }

    private func makeStubRunner() throws -> String {
        let scriptURL = tempDirectory.appendingPathComponent("llm-tool")
        try """
        #!/bin/zsh
        echo "$@"
        """.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        return scriptURL.path
    }

    private func makeHangingRunner() throws -> String {
        let scriptURL = tempDirectory.appendingPathComponent("llm-tool-hang")
        try """
        #!/bin/zsh
        trap "exit 130" TERM INT
        sleep 5
        """.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        return scriptURL.path
    }

    // MARK: - Token budget tests

    func testMLXUsesConfiguredTokenBudget() async throws {
        let echoBin = tempDirectory.appendingPathComponent("echo-runner.sh")
        try """
        #!/bin/sh
        echo "$@"
        """.write(to: echoBin, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: echoBin.path)
        setenv("ODYSSEY_MLX_RUNNER", echoBin.path, 1)
        defer { unsetenv("ODYSSEY_MLX_RUNNER") }

        let core = LocalAgentCore()
        _ = await core.createSession(.init(
            sessionId: "budget-session",
            config: .init(
                name: "Budget", provider: .mlx, model: "test-model",
                systemPrompt: "sys", workingDirectory: "/tmp",
                maxTokensPerStep: 4096
            )
        ))

        let response = try await core.sendMessage(.init(sessionId: "budget-session", text: "hi"))
        let eventTexts = response.events.compactMap(\.text).joined()
        XCTAssertTrue(
            response.resultText.contains("4096") || eventTexts.contains("4096"),
            "Expected --max-tokens 4096 in args: \(response.resultText)"
        )
    }

    func testMLXDefaultTokenBudgetIs2048() async throws {
        let echoBin = tempDirectory.appendingPathComponent("echo-runner-default.sh")
        try """
        #!/bin/sh
        echo "$@"
        """.write(to: echoBin, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: echoBin.path)
        setenv("ODYSSEY_MLX_RUNNER", echoBin.path, 1)
        defer { unsetenv("ODYSSEY_MLX_RUNNER") }

        let core = LocalAgentCore()
        _ = await core.createSession(.init(
            sessionId: "default-budget-session",
            config: .init(
                name: "DefaultBudget", provider: .mlx, model: "test-model",
                systemPrompt: "sys", workingDirectory: "/tmp"
            )
        ))

        let response = try await core.sendMessage(.init(sessionId: "default-budget-session", text: "hi"))
        XCTAssertTrue(response.resultText.contains("2048"),
                      "Expected --max-tokens 2048 in args: \(response.resultText)")
    }

    // MARK: - Tool-call extraction tests

    func testExtractToolCallFromXMLBlock() {
        let text = """
        Sure, let me look that up.
        <tool_call>
        {"tool":"read_file","arguments":{"path":"README.md"}}
        </tool_call>
        """
        let result = extractToolCall(from: text)
        XCTAssertEqual(result?.name, "read_file")
        XCTAssertEqual(result?.arguments["path"]?.stringValue, "README.md")
    }

    func testExtractToolCallFromEmbeddedJSON() {
        let text = #"Let me call the tool: {"tool":"write_file","arguments":{"path":"out.txt","content":"hello"}}"#
        let result = extractToolCall(from: text)
        XCTAssertEqual(result?.name, "write_file")
        XCTAssertEqual(result?.arguments["path"]?.stringValue, "out.txt")
    }

    func testExtractToolCallFromFencedCodeBlock() {
        let text = """
        I'll use this:
        ```json
        {"tool":"run_command","arguments":{"command":"ls"}}
        ```
        """
        let result = extractToolCall(from: text)
        XCTAssertEqual(result?.name, "run_command")
        XCTAssertEqual(result?.arguments["command"]?.stringValue, "ls")
    }

    func testExtractToolCallIgnoresPureProse() {
        let text = "Tel Aviv is on Israel's Mediterranean coast, about 60 km from Jerusalem."
        XCTAssertNil(extractToolCall(from: text))
    }

    private func makeModelArchive(named directoryName: String) throws -> URL {
        let modelDirectory = tempDirectory.appendingPathComponent(directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        try "{}".write(to: modelDirectory.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
        try "{}".write(to: modelDirectory.appendingPathComponent("tokenizer.json"), atomically: true, encoding: .utf8)
        try "weights".write(to: modelDirectory.appendingPathComponent("weights.safetensors"), atomically: true, encoding: .utf8)

        let archiveURL = tempDirectory.appendingPathComponent("mlx-model.tar.gz")
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-czf", archiveURL.path, "-C", tempDirectory.path, directoryName]
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(process.terminationStatus, 0, output)
        return archiveURL
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void = { _ in },
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw an error", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
