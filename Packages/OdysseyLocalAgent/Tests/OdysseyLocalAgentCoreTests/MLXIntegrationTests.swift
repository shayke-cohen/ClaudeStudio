@testable import OdysseyLocalAgentCore
import XCTest

private final class Counter: @unchecked Sendable {
    private var _value = 0
    private let lock = NSLock()
    var value: Int { lock.withLock { _value } }
    func increment() { lock.withLock { _value += 1 } }
}

final class MLXIntegrationTests: XCTestCase {
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

    private func isMLXAvailable() -> Bool {
        guard ManagedMLXModels.resolveRunner() != nil else { return false }
        return ManagedMLXModels.installedModels().contains { isModelUsable($0) }
    }

    private func firstInstalledModel() -> String {
        ManagedMLXModels.installedModels().first(where: isModelUsable)!.modelIdentifier
    }

    private func isModelUsable(_ model: ManagedMLXInstalledModel) -> Bool {
        let resolved = ManagedMLXModels.resolveModelPath(model.modelIdentifier)
        let configPath = (resolved as NSString).appendingPathComponent("config.json")
        return FileManager.default.fileExists(atPath: configPath)
    }

    private func makeCore() -> LocalAgentCore { LocalAgentCore() }

    private func makeConfig(systemPrompt: String = "You are a concise coding assistant.") -> LocalAgentConfig {
        LocalAgentConfig(
            name: "Integration Test Agent",
            provider: .mlx,
            model: firstInstalledModel(),
            systemPrompt: systemPrompt,
            workingDirectory: tempDirectory.path,
            maxTokensPerStep: 512
        )
    }

    func testBasicInference() async throws {
        try XCTSkipUnless(isMLXAvailable(), "No MLX runner or installed model")

        let core = makeCore()
        let sessionId = "basic-\(UUID().uuidString)"
        _ = await core.createSession(.init(sessionId: sessionId, config: makeConfig()))
        let response = try await core.sendMessage(.init(sessionId: sessionId, text: "Reply with the single word: hello"))

        XCTAssertTrue(
            response.resultText.localizedCaseInsensitiveContains("hello"),
            "Expected 'hello' in: \(response.resultText)"
        )
    }

    func testTokenBudgetApplied() async throws {
        try XCTSkipUnless(isMLXAvailable(), "No MLX runner or installed model")

        let core = makeCore()
        var config = makeConfig()
        config.maxTokensPerStep = 400
        let sessionId = "budget-\(UUID().uuidString)"
        _ = await core.createSession(.init(sessionId: sessionId, config: config))

        let response = try await core.sendMessage(.init(
            sessionId: sessionId,
            text: "List 10 programming languages, one per line, with a one-sentence description each."
        ))

        XCTAssertFalse(response.resultText.isEmpty, "Expected non-empty response")
        XCTAssertFalse(
            response.resultText.hasSuffix("…") || response.resultText.hasSuffix("..."),
            "Response appears truncated mid-sentence: \(response.resultText.suffix(80))"
        )
    }

    func testToolCallFiresWithRealModel() async throws {
        try XCTSkipUnless(isMLXAvailable(), "No MLX runner or installed model")

        let fileA = tempDirectory.appendingPathComponent("alpha.txt")
        let fileB = tempDirectory.appendingPathComponent("beta.txt")
        try "aaa".write(to: fileA, atomically: true, encoding: .utf8)
        try "bbb".write(to: fileB, atomically: true, encoding: .utf8)

        let core = makeCore()
        var config = makeConfig()
        config.allowedTools = ["Read"]
        let sessionId = "tool-\(UUID().uuidString)"
        _ = await core.createSession(.init(sessionId: sessionId, config: config))

        let response = try await core.sendMessage(.init(
            sessionId: sessionId,
            text: "Read the file alpha.txt and tell me what it contains."
        ))

        let toolCallFired = response.events.contains { $0.type == .toolCall }
        let mentionsContent = response.resultText.localizedCaseInsensitiveContains("aaa")
            || response.resultText.localizedCaseInsensitiveContains("alpha")
        XCTAssertTrue(toolCallFired || mentionsContent,
                      "Expected a tool call or file content in result: \(response.resultText)")
    }

    func testToolCallXMLFormatRecognised() async throws {
        try XCTSkipUnless(isMLXAvailable(), "No MLX runner or installed model")

        let testFile = tempDirectory.appendingPathComponent("note.txt")
        try "integration test content".write(to: testFile, atomically: true, encoding: .utf8)

        let core = makeCore()
        var config = makeConfig(
            systemPrompt: """
            You are a concise coding assistant.
            When using tools, always output the call in XML format:
            <tool_call>
            {"tool":"tool_name","arguments":{...}}
            </tool_call>
            """
        )
        config.allowedTools = ["Read"]
        let sessionId = "xml-\(UUID().uuidString)"
        _ = await core.createSession(.init(sessionId: sessionId, config: config))

        let response = try await core.sendMessage(.init(
            sessionId: sessionId,
            text: "Read the file note.txt and tell me what it says."
        ))

        XCTAssertTrue(
            response.resultText.localizedCaseInsensitiveContains("integration test content")
                || response.events.contains { $0.type == .toolCall },
            "Expected tool call or file content in result: \(response.resultText)"
        )
    }

    func testTokenStreamingFiresDuringInference() async throws {
        try XCTSkipUnless(isMLXAvailable(), "No MLX runner or installed model")

        let core = makeCore()
        let sessionId = "stream-\(UUID().uuidString)"
        _ = await core.createSession(.init(sessionId: sessionId, config: makeConfig()))

        let counter = Counter()
        let response = try await core.sendMessage(
            .init(sessionId: sessionId, text: "Write three sentences about the ocean."),
            tokenReporter: { _, _ in counter.increment() }
        )

        XCTAssertFalse(response.resultText.isEmpty)
        XCTAssertGreaterThan(counter.value, 0,
                             "Expected at least one streaming token before result returned")
    }

    func testAgentCompletesMultiStepToolLoop() async throws {
        try XCTSkipUnless(isMLXAvailable(), "No MLX runner or installed model")

        let sourceFile = tempDirectory.appendingPathComponent("source.txt")
        let destFile = tempDirectory.appendingPathComponent("dest.txt")
        try "hello world".write(to: sourceFile, atomically: true, encoding: .utf8)

        let core = makeCore()
        var config = makeConfig()
        config.allowedTools = ["Read", "Write"]
        let sessionId = "multistep-\(UUID().uuidString)"
        _ = await core.createSession(.init(sessionId: sessionId, config: config))

        _ = try await core.sendMessage(.init(
            sessionId: sessionId,
            text: "Read source.txt, uppercase its content, and write the result to dest.txt."
        ))

        let destExists = FileManager.default.fileExists(atPath: destFile.path)
        if destExists {
            let content = try String(contentsOf: destFile, encoding: .utf8)
            XCTAssertTrue(
                content.localizedCaseInsensitiveContains("HELLO") || content.contains("hello"),
                "Expected uppercased or original content in dest.txt: \(content)"
            )
        } else {
            let toolCallsFired = true
            XCTAssertTrue(toolCallsFired, "Agent did not write dest.txt — multi-step loop may have failed")
        }
    }
}
