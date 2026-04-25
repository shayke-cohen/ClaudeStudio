import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

struct AdapterContext: Sendable {
    var toolExecutor: ToolExecutor
    var workingDirectory: String
    var remoteToolNames: Set<String>
    var mcpServers: [LocalAgentMCPServer]
    var localPermissionRules: [String]
    var allowedBuiltInTools: Set<String>
    var tokenReporter: (@Sendable (String, String) -> Void)?

    var isStreaming: Bool { tokenReporter != nil }
}

struct AdapterTurnResult: Sendable {
    var resultText: String
    var events: [LocalAgentEvent]
}

protocol LocalModelAdapter: Sendable {
    var provider: LocalAgentProvider { get }
    func probe() async -> ProviderProbeResult
    func sendTurn(
        sessionId: String,
        config: LocalAgentConfig,
        text: String,
        transcript: [TranscriptItem],
        context: AdapterContext
    ) async throws -> AdapterTurnResult
}

struct FoundationModelAdapter: LocalModelAdapter {
    let provider: LocalAgentProvider = .foundation

    func probe() async -> ProviderProbeResult {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let model = SystemLanguageModel.default
            if model.isAvailable {
                return ProviderProbeResult(
                    provider: provider,
                    available: true,
                    supportsTools: true,
                    supportsTranscriptResume: true
                )
            }

            return ProviderProbeResult(
                provider: provider,
                available: false,
                reason: availabilityReason(model.availability),
                supportsTools: true,
                supportsTranscriptResume: true
            )
        }
        #endif

        return ProviderProbeResult(
            provider: provider,
            available: false,
            reason: "Foundation Models requires macOS 26+ with the FoundationModels framework available",
            supportsTools: true,
            supportsTranscriptResume: true
        )
    }

    func sendTurn(
        sessionId: String,
        config: LocalAgentConfig,
        text: String,
        transcript: [TranscriptItem],
        context: AdapterContext
    ) async throws -> AdapterTurnResult {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return try await FoundationSessionRunner.run(
                sessionId: sessionId,
                config: config,
                text: text,
                transcript: transcript,
                context: context
            )
        }
        #endif

        return try await executePromptLoop(
            modePrefix: "[foundation-fallback]",
            sessionId: sessionId,
            config: config,
            text: text,
            transcript: transcript,
            context: context,
            generator: FallbackGenerator(prefix: "[foundation-fallback]")
        )
    }
}

struct MLXModelAdapter: LocalModelAdapter {
    let provider: LocalAgentProvider = .mlx

    func probe() async -> ProviderProbeResult {
        let command = ManagedMLXModels.resolveRunner()
        guard let command else {
            return ProviderProbeResult(
                provider: provider,
                available: false,
                reason: "MLX tool runner not found. Set ODYSSEY_MLX_RUNNER or install llm-tool from mlx-swift-examples.",
                supportsTools: true,
                supportsTranscriptResume: true
            )
        }

        return ProviderProbeResult(
            provider: provider,
            available: true,
            reason: "Using MLX runner at \(command)",
            supportsTools: true,
            supportsTranscriptResume: true
        )
    }

    func sendTurn(
        sessionId: String,
        config: LocalAgentConfig,
        text: String,
        transcript: [TranscriptItem],
        context: AdapterContext
    ) async throws -> AdapterTurnResult {
        let reporter = context.tokenReporter
        let sid = sessionId
        let generator: any LocalAgentTextGenerating = {
            if let command = ManagedMLXModels.resolveRunner() {
                return MLXCommandGenerator(
                    command: command,
                    sessionId: sid,
                    onToken: reporter.map { r in { chunk in r(sid, chunk) } }
                )
            }
            return FallbackGenerator(prefix: "[mlx-fallback]")
        }()
        return try await executePromptLoop(
            modePrefix: "[mlx]",
            sessionId: sessionId,
            config: config,
            text: text,
            transcript: transcript,
            context: context,
            generator: generator
        )
    }
}

private protocol LocalAgentTextGenerating {
    func generate(prompt: String, config: LocalAgentConfig) async throws -> String
}

private struct FallbackGenerator: LocalAgentTextGenerating {
    let prefix: String

    func generate(prompt: String, config: LocalAgentConfig) async throws -> String {
        "\(prefix) \(config.name): \(prompt.prefix(500))"
    }
}

private struct MLXCommandGenerator: LocalAgentTextGenerating {
    let command: String?
    let sessionId: String
    let onToken: (@Sendable (String) -> Void)?

    func generate(prompt: String, config: LocalAgentConfig) async throws -> String {
        guard let command else {
            throw NSError(domain: "OdysseyLocalAgent.MLX", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No MLX runner command is configured"
            ])
        }

        return try await runMLXCommand(
            command: command,
            model: config.model,
            prompt: prompt,
            config: config,
            sessionId: sessionId,
            onToken: onToken
        )
    }
}

private func executePromptLoop(
    modePrefix: String,
    sessionId: String,
    config: LocalAgentConfig,
    text: String,
    transcript: [TranscriptItem],
    context: AdapterContext,
    generator: any LocalAgentTextGenerating
) async throws -> AdapterTurnResult {
    var loopTranscript = transcript
    var events = [LocalAgentEvent]()
    let maxSteps = max(1, config.maxTurns ?? 6)
    let actionableText = extractActionableUserText(from: text)

    let toolExecutionContext = ToolExecutionContext(
        sessionId: sessionId,
        workingDirectory: context.workingDirectory,
        configuredMCPServers: context.mcpServers,
        configuredRemoteTools: context.remoteToolNames,
        localPermissionRules: context.localPermissionRules,
        allowedBuiltInTools: context.allowedBuiltInTools
    )

    if let directToolCall = parseLegacyToolInvocation(in: actionableText)
        ?? planConversationalToolCall(
            in: actionableText,
            availableTools: Set(config.toolDefinitions.map(\.name)),
            workingDirectory: context.workingDirectory
        ) {
        let toolResult = try await context.toolExecutor.execute(
            toolName: directToolCall.name,
            arguments: directToolCall.arguments,
            context: toolExecutionContext
        )
        let resultText = renderToolCompletion(
            toolCall: directToolCall,
            toolResult: toolResult,
            modePrefix: modePrefix
        )
        events.append(contentsOf: toolEvents(
            sessionId: sessionId,
            toolCall: directToolCall,
            toolResult: toolResult
        ))
        if !context.isStreaming {
            events.append(contentsOf: tokenEvents(for: resultText, sessionId: sessionId))
        }
        return AdapterTurnResult(resultText: resultText, events: events)
    }

    if shouldPreferDirectChatResponse(
        for: actionableText,
        availableTools: Set(config.toolDefinitions.map(\.name))
    ) {
        let prompt = buildDirectChatPrompt(config: config, transcript: loopTranscript)
        let generated = try await generator.generate(prompt: prompt, config: config)
        let finalAnswer: String
        if isDegenerateAssistantResponse(generated, userText: actionableText) {
            let retryPrompt = buildDirectRetryPrompt(config: config, latestUserText: actionableText)
            let retried = try await generator.generate(prompt: retryPrompt, config: config)
            finalAnswer = retried
        } else {
            finalAnswer = generated
        }
        let normalized = normalizeAssistantResponse(finalAnswer, modePrefix: modePrefix)
        if !context.isStreaming {
            events.append(contentsOf: tokenEvents(for: normalized, sessionId: sessionId))
        }
        return AdapterTurnResult(resultText: normalized, events: events)
    }

    for _ in 0..<maxSteps {
        let prompt = buildAgentLoopPrompt(config: config, transcript: loopTranscript)
        let generated = try await generator.generate(prompt: prompt, config: config)

        if let toolCall = extractToolCall(from: generated) {
            events.append(
                LocalAgentEvent(
                    type: .toolCall,
                    sessionId: sessionId,
                    tool: toolCall.name,
                    input: toolCall.arguments.prettyJSONString,
                    arguments: toolCall.arguments
                )
            )

            let toolResult = try await context.toolExecutor.execute(
                toolName: toolCall.name,
                arguments: toolCall.arguments,
                context: toolExecutionContext
            )

            events.append(
                LocalAgentEvent(
                    type: .toolResult,
                    sessionId: sessionId,
                    tool: toolCall.name,
                    output: toolResult.output
                )
            )
            loopTranscript.append(.init(role: .assistant, text: generated))
            loopTranscript.append(.init(role: .tool, text: toolResult.output))
            continue
        }

        let resultText = generated.hasPrefix(modePrefix) ? generated : "\(modePrefix) \(generated)"
        if !context.isStreaming {
            events.append(contentsOf: tokenEvents(for: resultText, sessionId: sessionId))
        }
        return AdapterTurnResult(resultText: resultText, events: events)
    }

    let exhausted = "\(modePrefix) Reached the tool loop limit without a final response."
    if !context.isStreaming {
        events.append(contentsOf: tokenEvents(for: exhausted, sessionId: sessionId))
    }
    return AdapterTurnResult(resultText: exhausted, events: events)
}

private func parseLegacyToolInvocation(in text: String) -> ParsedToolCall? {
    let prefix = "[[tool:"
    let suffix = "]]"
    guard let startRange = text.range(of: prefix),
          let endRange = text.range(of: suffix, range: startRange.upperBound..<text.endIndex) else {
        return nil
    }

    let body = String(text[startRange.upperBound..<endRange.lowerBound])
    let parts = body.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
    guard let rawName = parts.first else { return nil }

    let toolName = String(rawName)
    guard parts.count == 2,
          let data = String(parts[1]).data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return ParsedToolCall(name: toolName, arguments: [:])
    }

    return ParsedToolCall(name: toolName, arguments: json.mapValues(DynamicValue.from(any:)))
}

func extractActionableUserText(from text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return trimmed }

    let blockPatterns = [
        #"Latest user message:\s*"""\s*([\s\S]*?)\s*"""#,
        #"User message to respond to:\s*([\s\S]*?)$"#,
        #"--- Group chat: peer message ---\s*([\s\S]*?)\s*--- End ---"#,
    ]

    for pattern in blockPatterns {
        if let match = firstCapture(
            pattern: pattern,
            in: trimmed,
            options: [.dotMatchesLineSeparators]
        ), !match.isEmpty {
            return match.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    return trimmed
}

private func buildAgentLoopPrompt(config: LocalAgentConfig, transcript: [TranscriptItem]) -> String {
    let skills = config.skills
        .map { "### \($0.name)\n\($0.content)" }
        .joined(separator: "\n\n")
    let tools = config.toolDefinitions
        .map { tool in
            let parameters = tool.inputSchema
                .map { "\($0): \($1)" }
                .sorted()
                .joined(separator: ", ")
            return "- \(tool.name): \(tool.description) [\(parameters)]"
        }
        .joined(separator: "\n")

    let history = transcript
        .map { "\($0.role.rawValue.uppercased()): \($0.text)" }
        .joined(separator: "\n")

    return """
    \(config.systemPrompt)

    \(skills.isEmpty ? "" : "Skills:\n\(skills)\n")

    Available tools:
    \(tools)

    Conversation:
    \(history)

    TOOL USE:
    If you need a tool, output ONLY a tool call — nothing else. Use one of:

    Format A (preferred — XML):
    <tool_call>
    {"tool":"tool_name","arguments":{"key":"value"}}
    </tool_call>

    Format B (fallback — bare JSON):
    {"tool":"tool_name","arguments":{"key":"value"}}

    Otherwise reply with your final answer in plain text. Do not combine a tool call with prose.
    """
}

func buildDirectChatPrompt(config: LocalAgentConfig, transcript: [TranscriptItem]) -> String {
    let skills = config.skills
        .map { "### \($0.name)\n\($0.content)" }
        .joined(separator: "\n\n")

    let history = transcript
        .map { "\($0.role.rawValue.capitalized): \($0.text)" }
        .joined(separator: "\n")

    return """
    \(config.systemPrompt)

    \(skills.isEmpty ? "" : "Skills:\n\(skills)\n")

    Conversation:
    \(history)

    Reply to the most recent user message naturally and concisely.
    Do not output JSON unless the user explicitly asked for JSON.
    """
}

func buildDirectRetryPrompt(config: LocalAgentConfig, latestUserText: String) -> String {
    """
    \(config.systemPrompt)

    Answer this user request directly in one short sentence.
    Do not output JSON.
    Do not repeat the question.

    User: \(latestUserText)
    Assistant:
    """
}

func shouldPreferDirectChatResponse(
    for text: String,
    availableTools: Set<String>
) -> Bool {
    guard !availableTools.isEmpty else { return true }

    let lowercased = text.lowercased()
    let toolSignals = [
        "tool",
        "file",
        "files",
        "directory",
        "folder",
        "read ",
        "open ",
        "show ",
        "search ",
        "grep",
        "find ",
        "bash",
        "shell",
        "command",
        "run ",
        "git ",
        "workspace",
        "blackboard",
        "task",
        "mcp",
        "url",
        "website",
        "web ",
        "http",
        "fetch ",
        "download ",
        "write ",
        "replace ",
        "edit ",
    ]

    return !toolSignals.contains(where: { lowercased.contains($0) })
}

func normalizeAssistantResponse(_ generated: String, modePrefix: String) -> String {
    let trimmed = generated.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.hasPrefix(modePrefix) ? trimmed : "\(modePrefix) \(trimmed)"
}

func isDegenerateAssistantResponse(_ response: String, userText: String) -> Bool {
    let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return true }

    let normalizedResponse = trimmed.lowercased()
    let normalizedUserText = userText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

    if ["none", "null", "n/a", "\"none\"", "'none'"].contains(normalizedResponse) {
        return true
    }

    if normalizedResponse == normalizedUserText || normalizedResponse == "\"\(normalizedUserText)\"" {
        return true
    }

    return false
}

struct ParsedToolCall {
    var name: String
    var arguments: [String: DynamicValue]
}

private func toolEvents(
    sessionId: String,
    toolCall: ParsedToolCall,
    toolResult: ToolExecutionResult
) -> [LocalAgentEvent] {
    [
        LocalAgentEvent(
            type: .toolCall,
            sessionId: sessionId,
            tool: toolCall.name,
            input: toolCall.arguments.prettyJSONString,
            arguments: toolCall.arguments
        ),
        LocalAgentEvent(
            type: .toolResult,
            sessionId: sessionId,
            tool: toolCall.name,
            output: toolResult.output
        ),
    ]
}

private func renderToolCompletion(
    toolCall: ParsedToolCall,
    toolResult: ToolExecutionResult,
    modePrefix: String
) -> String {
    let statusPrefix = toolResult.success ? modePrefix : "\(modePrefix) tool failed"
    let path = toolCall.arguments["path"]?.stringValue

    switch toolCall.name {
    case "list_directory":
        let target = path ?? "."
        return toolResult.success
            ? "\(modePrefix) directory listing for \(target):\n\(toolResult.output)"
            : "\(statusPrefix): \(toolResult.output)"
    case "read_file":
        let target = path ?? "file"
        return toolResult.success
            ? "\(modePrefix) contents of \(target):\n\(toolResult.output)"
            : "\(statusPrefix): \(toolResult.output)"
    case "search_files":
        return toolResult.success
            ? "\(modePrefix) search results:\n\(toolResult.output.isEmpty ? "No matches found." : toolResult.output)"
            : "\(statusPrefix): \(toolResult.output)"
    case "run_command":
        return toolResult.success
            ? "\(modePrefix) command output:\n\(toolResult.output)"
            : "\(statusPrefix): \(toolResult.output)"
    case "web_search":
        return toolResult.success
            ? "\(modePrefix) web search:\n\(toolResult.output)"
            : "\(statusPrefix): \(toolResult.output)"
    case "fetch_url":
        return toolResult.success
            ? "\(modePrefix) fetched URL:\n\(toolResult.output)"
            : "\(statusPrefix): \(toolResult.output)"
    case "write_file", "replace_in_file":
        return toolResult.success
            ? "\(modePrefix) \(toolResult.output)"
            : "\(statusPrefix): \(toolResult.output)"
    default:
        return toolResult.success
            ? "\(modePrefix) completed tool \(toolCall.name): \(toolResult.output)"
            : "\(statusPrefix): \(toolResult.output)"
    }
}

func planConversationalToolCall(
    in text: String,
    availableTools: Set<String>,
    workingDirectory: String
) -> ParsedToolCall? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let lowercased = trimmed.lowercased()

    if availableTools.contains("fetch_url"),
       let url = firstURL(in: trimmed),
       lowercased.contains("fetch") || lowercased.contains("open url") || lowercased.contains("load ") {
        return ParsedToolCall(name: "fetch_url", arguments: ["url": .string(url)])
    }

    if availableTools.contains("web_search"),
       lowercased.contains("search the web for") || lowercased.contains("search web for") || lowercased.hasPrefix("look up ") {
        let query = extractSearchQuery(from: trimmed)
        if !query.isEmpty {
            return ParsedToolCall(name: "web_search", arguments: ["query": .string(query)])
        }
    }

    if availableTools.contains("run_command"),
       let command = extractCommand(from: trimmed) {
        return ParsedToolCall(name: "run_command", arguments: ["command": .string(command)])
    }

    if availableTools.contains("read_file"),
       let path = extractFilePath(from: trimmed, workingDirectory: workingDirectory),
       looksLikeReadRequest(lowercased) {
        return ParsedToolCall(name: "read_file", arguments: ["path": .string(path)])
    }

    if availableTools.contains("search_files"),
       let searchRequest = extractFileSearch(from: trimmed) {
        return ParsedToolCall(
            name: "search_files",
            arguments: [
                "path": .string(searchRequest.path),
                "query": .string(searchRequest.query),
                "maxResults": .number(20),
            ]
        )
    }

    if availableTools.contains("list_directory"),
       looksLikeDirectoryRequest(lowercased) {
        let path = extractDirectoryPath(from: trimmed) ?? "."
        return ParsedToolCall(name: "list_directory", arguments: ["path": .string(path)])
    }

    return nil
}

private func looksLikeDirectoryRequest(_ lowercased: String) -> Bool {
    lowercased.contains("list files")
        || lowercased.contains("list the files")
        || lowercased.contains("show files")
        || lowercased.contains("show me files")
        || lowercased.contains("show directory")
        || lowercased.contains("list directory")
        || lowercased.contains("what files")
        || lowercased.contains("what's in")
        || lowercased.contains("what is in")
        || lowercased == "ls"
}

private func looksLikeReadRequest(_ lowercased: String) -> Bool {
    lowercased.contains("read ")
        || lowercased.contains("open ")
        || lowercased.contains("show ")
        || lowercased.contains("display ")
        || lowercased.contains("print ")
}

private func extractDirectoryPath(from text: String) -> String? {
    if let quoted = firstQuotedValue(in: text) {
        return quoted
    }

    let patterns = [
        #"(?i)\b(?:in|under|inside|at)\s+([A-Za-z0-9_./~\-]+)"#,
        #"(?i)\bfor\s+([A-Za-z0-9_./~\-]+)$"#,
    ]

    for pattern in patterns {
        if let match = firstCapture(pattern: pattern, in: text) {
            return sanitizedPathCandidate(match)
        }
    }

    if text.lowercased().contains("current directory") || text.lowercased().contains("here") {
        return "."
    }

    return nil
}

private func extractFilePath(from text: String, workingDirectory: String) -> String? {
    if let quoted = firstQuotedValue(in: text) {
        return quoted
    }

    let tokens = text
        .split(whereSeparator: \.isWhitespace)
        .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: ".,:;!?()[]{}")) }

    if let match = tokens.first(where: { candidate in
        let lowercased = candidate.lowercased()
        return candidate.contains("/")
            || candidate.hasPrefix(".")
            || lowercased.hasSuffix(".md")
            || lowercased.hasSuffix(".txt")
            || lowercased.hasSuffix(".swift")
            || lowercased.hasSuffix(".ts")
            || lowercased.hasSuffix(".js")
            || lowercased.hasSuffix(".json")
            || lowercased.hasSuffix(".yaml")
            || lowercased.hasSuffix(".yml")
        }) {
        return match
    }

    if FileManager.default.fileExists(atPath: URL(fileURLWithPath: workingDirectory).appendingPathComponent("AGENTS.md").path),
       text.lowercased().contains("agents.md") {
        return "AGENTS.md"
    }

    return nil
}

private func extractFileSearch(from text: String) -> (query: String, path: String)? {
    let patterns = [
        #"(?i)\bsearch for ['"]([^'"]+)['"] in ([A-Za-z0-9_./~\-]+)"#,
        #"(?i)\bfind ['"]([^'"]+)['"] in ([A-Za-z0-9_./~\-]+)"#,
        #"(?i)\bsearch for ['"]([^'"]+)['"]"#,
        #"(?i)\bfind ['"]([^'"]+)['"]"#,
    ]

    for pattern in patterns {
        guard let captures = captureGroups(pattern: pattern, in: text), !captures.isEmpty else { continue }
        let query = captures[0]
        let path = captures.count > 1 ? captures[1] : "."
        return (query, path)
    }

    return nil
}

private func extractCommand(from text: String) -> String? {
    let lowercased = text.lowercased()
    if lowercased.hasPrefix("run ") {
        return String(text.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if lowercased.hasPrefix("execute ") {
        return String(text.dropFirst(8)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if let inline = firstBacktickedValue(in: text) {
        return inline
    }
    if lowercased.hasPrefix("git ") || lowercased.hasPrefix("pwd") || lowercased.hasPrefix("ls ") {
        return text
    }
    return nil
}

private func extractSearchQuery(from text: String) -> String {
    let patterns = [
        #"(?i)\bsearch (?:the )?web for ['"]?(.+?)['"]?$"#,
        #"(?i)\blook up ['"]?(.+?)['"]?$"#,
    ]

    for pattern in patterns {
        if let match = firstCapture(pattern: pattern, in: text) {
            return match
        }
    }

    return text
}

private func firstURL(in text: String) -> String? {
    let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    let range = NSRange(location: 0, length: text.utf16.count)
    return detector?.firstMatch(in: text, options: [], range: range)?.url?.absoluteString
}

private func firstQuotedValue(in text: String) -> String? {
    firstCapture(pattern: #""([^"]+)""#, in: text)
        ?? firstCapture(pattern: #"'([^']+)'"#, in: text)
}

private func firstBacktickedValue(in text: String) -> String? {
    firstCapture(pattern: #"`([^`]+)`"#, in: text)
}

private func firstCapture(pattern: String, in text: String) -> String? {
    captureGroups(pattern: pattern, in: text)?.first
}

private func captureGroups(pattern: String, in text: String) -> [String]? {
    captureGroups(pattern: pattern, in: text, options: [])
}

private func firstCapture(
    pattern: String,
    in text: String,
    options: NSRegularExpression.Options
) -> String? {
    captureGroups(pattern: pattern, in: text, options: options)?.first
}

private func captureGroups(
    pattern: String,
    in text: String,
    options: NSRegularExpression.Options
) -> [String]? {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
        return nil
    }
    let range = NSRange(location: 0, length: text.utf16.count)
    guard let match = regex.firstMatch(in: text, options: [], range: range), match.numberOfRanges > 1 else {
        return nil
    }

    return (1..<match.numberOfRanges).compactMap { index in
        let nsRange = match.range(at: index)
        guard nsRange.location != NSNotFound,
              let range = Range(nsRange, in: text) else {
            return nil
        }
        return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private func sanitizedPathCandidate(_ path: String) -> String {
    path.trimmingCharacters(in: CharacterSet(charactersIn: ".,:;!?()[]{}"))
}

func extractToolCall(from text: String) -> ParsedToolCall? {
    // Strategy 1: <tool_call>...</tool_call> XML block (Qwen3 native format)
    if let body = firstCapture(
        pattern: #"<tool_call>\s*([\s\S]*?)\s*</tool_call>"#,
        in: text,
        options: [.dotMatchesLineSeparators]
    ), let call = parseToolCallJSON(body) {
        return call
    }

    // Strategy 2: fenced code block ```json {...} ``` or ``` {...} ```
    if let body = firstCapture(
        pattern: #"```(?:json)?\s*(\{[\s\S]*?\})\s*```"#,
        in: text,
        options: [.dotMatchesLineSeparators]
    ), let call = parseToolCallJSON(body) {
        return call
    }

    // Strategy 3: scan for first '{' — handles preamble text before bare JSON
    if let braceRange = text.range(of: "{") {
        let candidate = longestLeadingObject(from: String(text[braceRange.lowerBound...]))
        if let call = parseToolCallJSON(candidate) {
            return call
        }
    }

    return nil
}

private func parseToolCallJSON(_ raw: String) -> ParsedToolCall? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
          let data = trimmed.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let toolName = json["tool"] as? String,
          !toolName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return nil
    }
    let rawArguments = json["arguments"] as? [String: Any] ?? [:]
    return ParsedToolCall(
        name: toolName,
        arguments: rawArguments.mapValues(DynamicValue.from(any:))
    )
}

// Walk forward to find the first complete top-level JSON object starting at text[0]
private func longestLeadingObject(from text: String) -> String {
    var depth = 0
    var inString = false
    var escaped = false
    for (i, c) in text.enumerated() {
        if escaped { escaped = false; continue }
        if c == "\\" && inString { escaped = true; continue }
        if c == "\"" { inString.toggle(); continue }
        if inString { continue }
        if c == "{" { depth += 1 }
        if c == "}" {
            depth -= 1
            if depth == 0 { return String(text.prefix(i + 1)) }
        }
    }
    return text
}

private func tokenEvents(for text: String, sessionId: String) -> [LocalAgentEvent] {
    text.split(separator: " ").map {
        LocalAgentEvent(type: .token, sessionId: sessionId, text: "\($0) ")
    }
}

private func runMLXCommand(
    command: String,
    model: String,
    prompt: String,
    config: LocalAgentConfig,
    sessionId: String,
    onToken: (@Sendable (String) -> Void)? = nil
) async throws -> String {
    let resolvedModel = ManagedMLXModels.resolveModelPath(model)
    let maxTokens = config.maxTokensPerStep ?? 2048
    var arguments = [
        "eval",
        "--model", resolvedModel,
        "--prompt", prompt,
        "--max-tokens", "\(maxTokens)",
        "--quiet",
    ]
    if !ManagedMLXModels.looksLikeLocalModelPath(resolvedModel) {
        arguments.append(contentsOf: ["--download", ManagedMLXModels.resolveDownloadDirectory()])
    }
    let extraEnv = [ManagedMLXModels.downloadDirectoryEnvironmentKey: ManagedMLXModels.resolveDownloadDirectory()]
    if let onToken {
        let raw = try await ManagedMLXModels.runProcessForSessionStreaming(
            executable: command,
            arguments: arguments,
            sessionId: sessionId,
            extraEnvironment: extraEnv,
            onChunk: onToken
        )
        return sanitizeMLXOutput(raw)
    } else {
        let output = try await ManagedMLXModels.runProcessForSession(
            executable: command,
            arguments: arguments,
            sessionId: sessionId,
            extraEnvironment: extraEnv
        )
        return sanitizeMLXOutput(output)
    }
}

func sanitizeMLXOutput(_ rawOutput: String) -> String {
    let trimmed = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return trimmed }

    let filteredLines = trimmed
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { line in
            !line.isEmpty && !line.lowercased().hasPrefix("loading ")
        }

    let collapsed = collapseDuplicateAdjacentContent(
        filteredLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    )
    guard !collapsed.isEmpty else { return trimmed }

    if let extracted = extractStructuredAnswer(from: collapsed) {
        return extracted
    }

    return collapsed
}

private func extractStructuredAnswer(from text: String) -> String? {
    guard text.hasPrefix("{"), text.hasSuffix("}"), let data = text.data(using: .utf8) else {
        return nil
    }

    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return nil
    }

    for key in ["result", "answer", "response", "output"] {
        if let value = object[key] as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
    }

    return nil
}

private func collapseDuplicateAdjacentContent(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return trimmed }

    for separator in ["\n", " "] {
        var searchRange = trimmed.startIndex..<trimmed.endIndex
        while let range = trimmed.range(of: separator, options: [], range: searchRange) {
            let first = String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let second = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !first.isEmpty, first == second {
                return first
            }
            searchRange = range.upperBound..<trimmed.endIndex
        }
    }

    let count = trimmed.count
    if count.isMultiple(of: 2) {
        let midpoint = trimmed.index(trimmed.startIndex, offsetBy: count / 2)
        let first = String(trimmed[..<midpoint]).trimmingCharacters(in: .whitespacesAndNewlines)
        let second = String(trimmed[midpoint...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !first.isEmpty, first == second {
            return first
        }
    }

    return trimmed
}

private extension Dictionary where Key == String, Value == DynamicValue {
    var prettyJSONString: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try? encoder.encode(self)
        return data.map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
private enum FoundationSessionRunner {
    static func run(
        sessionId: String,
        config: LocalAgentConfig,
        text: String,
        transcript: [TranscriptItem],
        context: AdapterContext
    ) async throws -> AdapterTurnResult {
        let model = SystemLanguageModel.default
        let tools = config.toolDefinitions.map {
            DynamicFoundationTool(
                name: $0.name,
                description: $0.description,
                inputSchema: $0.inputSchema,
                sessionId: sessionId,
                executor: context.toolExecutor,
                toolContext: ToolExecutionContext(
                    sessionId: sessionId,
                    workingDirectory: context.workingDirectory,
                    configuredMCPServers: context.mcpServers,
                    configuredRemoteTools: context.remoteToolNames,
                    localPermissionRules: context.localPermissionRules,
                    allowedBuiltInTools: context.allowedBuiltInTools
                )
            )
        }

        let session = LanguageModelSession(
            model: model,
            tools: tools,
            instructions: buildFoundationInstructions(config: config)
        )

        let prompt = buildFoundationPrompt(transcript: transcript, latestText: text)
        let response = try await session.respond(to: prompt)
        let events = foundationEvents(from: response.transcriptEntries, sessionId: sessionId, finalText: response.content)
        return AdapterTurnResult(resultText: response.content, events: events)
    }

    private static func buildFoundationInstructions(config: LocalAgentConfig) -> String {
        let skills = config.skills
            .map { "\($0.name): \($0.content)" }
            .joined(separator: "\n")
        if skills.isEmpty {
            return config.systemPrompt
        }
        return "\(config.systemPrompt)\n\nSkills:\n\(skills)"
    }

    private static func buildFoundationPrompt(transcript: [TranscriptItem], latestText: String) -> String {
        let history = transcript
            .dropLast()
            .map { "\($0.role.rawValue.capitalized): \($0.text)" }
            .joined(separator: "\n")
        if history.isEmpty {
            return latestText
        }
        return "Conversation so far:\n\(history)\n\nUser: \(latestText)"
    }

    private static func foundationEvents(
        from entries: ArraySlice<Transcript.Entry>,
        sessionId: String,
        finalText: String
    ) -> [LocalAgentEvent] {
        var events = [LocalAgentEvent]()
        for entry in entries {
            switch entry {
            case .toolCalls(let toolCalls):
                for toolCall in toolCalls {
                    let arguments = (try? JSONSerialization.jsonObject(with: Data(toolCall.arguments.jsonString.utf8)) as? [String: Any]) ?? [:]
                    events.append(
                        LocalAgentEvent(
                            type: .toolCall,
                            sessionId: sessionId,
                            tool: toolCall.toolName,
                            input: toolCall.arguments.jsonString,
                            arguments: arguments.mapValues(DynamicValue.from(any:))
                        )
                    )
                }
            case .toolOutput(let toolOutput):
                let output = toolOutput.segments.map(\.description).joined(separator: "\n")
                events.append(
                    LocalAgentEvent(type: .toolResult, sessionId: sessionId, tool: toolOutput.toolName, output: output)
                )
            default:
                break
            }
        }
        events.append(contentsOf: tokenEvents(for: finalText, sessionId: sessionId))
        return events
    }
}

@available(macOS 26.0, *)
private struct DynamicFoundationTool: Tool {
    typealias Arguments = GeneratedContent
    typealias Output = String

    let name: String
    let description: String
    let parameters: GenerationSchema
    let includesSchemaInInstructions: Bool = true
    let sessionId: String
    let executor: ToolExecutor
    let toolContext: ToolExecutionContext

    init(
        name: String,
        description: String,
        inputSchema: [String: String],
        sessionId: String,
        executor: ToolExecutor,
        toolContext: ToolExecutionContext
    ) {
        self.name = name
        self.description = description
        self.parameters = Self.makeSchema(name: name, inputSchema: inputSchema)
        self.sessionId = sessionId
        self.executor = executor
        self.toolContext = toolContext
    }

    func call(arguments: GeneratedContent) async throws -> String {
        let raw = (try? JSONSerialization.jsonObject(with: Data(arguments.jsonString.utf8)) as? [String: Any]) ?? [:]
        let result = try await executor.execute(
            toolName: name,
            arguments: raw.mapValues(DynamicValue.from(any:)),
            context: toolContext
        )
        return result.output
    }

    private static func makeSchema(name: String, inputSchema: [String: String]) -> GenerationSchema {
        let properties = inputSchema.map { entry in
            DynamicGenerationSchema.Property(
                name: entry.key,
                description: nil,
                schema: dynamicSchema(for: entry.value),
                isOptional: false
            )
        }

        let root = DynamicGenerationSchema(
            name: "\(name)_arguments",
            description: "Arguments for tool \(name)",
            properties: properties
        )
        return (try? GenerationSchema(root: root, dependencies: []))
            ?? GenerationSchema(type: GeneratedContent.self, description: "Dynamic tool arguments", properties: [])
    }

    private static func dynamicSchema(for type: String) -> DynamicGenerationSchema {
        switch type.lowercased() {
        case "number", "int", "integer", "double":
            DynamicGenerationSchema(type: Double.self)
        case "bool", "boolean":
            DynamicGenerationSchema(type: Bool.self)
        default:
            DynamicGenerationSchema(type: String.self)
        }
    }
}

@available(macOS 26.0, *)
private func availabilityReason(_ availability: SystemLanguageModel.Availability) -> String {
    switch availability {
    case .available:
        "Available"
    case .unavailable(let reason):
        switch reason {
        case .deviceNotEligible:
            "This Mac is not eligible for Apple Intelligence"
        case .appleIntelligenceNotEnabled:
            "Apple Intelligence is not enabled"
        case .modelNotReady:
            "The on-device Foundation model is not ready yet"
        @unknown default:
            "Foundation Models is unavailable"
        }
    }
}
#endif
