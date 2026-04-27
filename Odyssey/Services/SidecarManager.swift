import Combine
import Darwin
import Foundation
import OSLog
import Security
import SwiftData
import OdysseyCore

@MainActor
final class SidecarManager: NSObject, ObservableObject, Sendable {
    struct Config: Sendable {
        var wsPort: Int = 9849
        var httpPort: Int = 9850
        var logDirectory: String?
        var dataDirectory: String?
        var bunPathOverride: String?
        var sidecarPathOverride: String?
        var localAgentHostPathOverride: String?
        var mlxRunnerPathOverride: String?
        /// The instance name used for Keychain key namespacing and TLS cert paths.
        /// Defaults to "default" to match the existing log directory convention.
        var instanceName: String = "default"
        /// Agent names to publish in the Nostr instance directory profile.
        var agentNames: [String] = []
    }

    struct Hooks: Sendable {
        var connectWebSocket: (@MainActor @Sendable () async throws -> Void)?
        var launchSidecar: (@MainActor @Sendable () throws -> Void)?
        var terminateConflictingSidecars: (@MainActor @Sendable () async throws -> Void)?
        var sleep: (@MainActor @Sendable (Duration) async -> Void)?
    }

    private var process: Process?
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var eventContinuation: AsyncStream<SidecarEvent>.Continuation?
    private var isRunning = false
    private var isReconnecting = false
    private var pingTask: Task<Void, Never>?
    private let config: Config
    private let hooks: Hooks

    /// Called with every raw JSON string received from the sidecar before it is parsed.
    /// Used by NostrEventRelay to forward messages to iOS devices.
    var rawMessageInterceptor: ((String) -> Void)?

    /// The instance name used for Keychain key namespacing and TLS cert paths.
    var instanceName: String { config.instanceName }
    /// DER bytes of the self-signed TLS cert generated for this instance.
    /// Written in `launchSidecar()` (always before the first connection attempt).
    /// Read in the `URLSessionDelegate` cert-pinning callback. Ordering is safe.
    nonisolated(unsafe) private var pinnedCertDERData: Data?

    var events: AsyncStream<SidecarEvent> {
        AsyncStream { continuation in
            self.eventContinuation = continuation
        }
    }

    nonisolated init(config: Config = Config(), hooks: Hooks = Hooks()) {
        self.config = config
        self.hooks = hooks
        super.init()
    }

    func start() async throws {
        guard !isRunning else { return }
        isRunning = true

        do {
            try await terminateConflictingManagedSidecarsIfNeeded()
            try launchSidecar()
            try await connectWithRetry()
            return
        } catch {
            Log.sidecar.warning("Fresh sidecar launch failed, falling back to existing listener: \(error.localizedDescription, privacy: .public)")
        }

        do {
            try await connectWebSocket()
        } catch {
            isRunning = false
            throw error
        }
    }

    func stop() {
        isRunning = false
        pingTask?.cancel()
        pingTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        process?.terminate()
        process = nil
        eventContinuation?.yield(.disconnected)
        eventContinuation?.finish()
    }

    /// Reconfigures the sidecar bind address and schedules a restart.
    func setBindAddress(_ address: String) {
        UserDefaults.standard.set(address, forKey: "sidecarBindAddress")
        Task { await restart() }
    }

    /// Stop the current sidecar, then restart it.
    /// Useful for refreshing TLS certificates or rotating WS tokens at runtime.
    func restart() async {
        stop()
        // Brief pause to let the port be released
        try? await Task.sleep(for: .milliseconds(300))
        try? await start()
    }

    enum SidecarError: Error, LocalizedError {
        case notConnected
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case .notConnected: return "Sidecar not connected"
            case .encodingFailed: return "Failed to encode command"
            }
        }
    }

    func send(_ command: SidecarCommand) async throws {
        let data = try command.encodeToJSON()
        guard let text = String(data: data, encoding: .utf8) else {
            throw SidecarError.encodingFailed
        }
        try await sendRaw(text)
    }

    func sendRaw(_ text: String) async throws {
        guard let task = webSocketTask else {
            throw SidecarError.notConnected
        }
        try await task.send(.string(text))
    }

    private func launchSidecar() throws {
        if let override = hooks.launchSidecar {
            try override()
            return
        }

        let process = Process()
        if let bundled = findBundledSidecar() {
            Log.sidecar.info("Sidecar (bundled): bun=\(bundled.bunPath, privacy: .public) js=\(bundled.jsPath, privacy: .public)")
            process.executableURL = URL(fileURLWithPath: bundled.bunPath)
            process.arguments = [bundled.jsPath]
        } else {
            let bunPath = findBunPath()
            let sidecarPath = findSidecarPath()
            Log.sidecar.info("Bun: \(bunPath, privacy: .public)")
            Log.sidecar.info("Sidecar: \(sidecarPath, privacy: .public)")
            Log.sidecar.info("Sidecar exists: \(FileManager.default.fileExists(atPath: sidecarPath))")
            Log.sidecar.info("Bun exists: \(FileManager.default.fileExists(atPath: bunPath))")
            process.executableURL = URL(fileURLWithPath: bunPath)
            process.arguments = ["run", sidecarPath]
        }
        process.environment = normalizedEnvironment()
        process.environment?["ODYSSEY_WS_PORT"] = "\(config.wsPort)"
        process.environment?["ODYSSEY_HTTP_PORT"] = "\(config.httpPort)"
        process.environment?["ODYSSEY_INSTANCE"] = config.instanceName
        process.environment?["CLAUDESTUDIO_WS_PORT"] = "\(config.wsPort)"
        process.environment?["CLAUDESTUDIO_HTTP_PORT"] = "\(config.httpPort)"
        if let dataDir = config.dataDirectory {
            process.environment?["ODYSSEY_DATA_DIR"] = dataDir
            process.environment?["CLAUDESTUDIO_DATA_DIR"] = dataDir
        }
        // Shared config dir is always ~/.odyssey/config — independent of the per-instance data dir.
        let configDir = NSHomeDirectory() + "/.odyssey/config"
        process.environment?["ODYSSEY_CONFIG_DIR"] = configDir
        for (key, value) in localProviderEnvironment() {
            process.environment?[key] = value
        }
        let logLevel = InstanceConfig.userDefaults.string(forKey: AppSettings.logLevelKey) ?? AppSettings.defaultLogLevel
        process.environment?["ODYSSEY_LOG_LEVEL"] = logLevel
        process.environment?["CLAUDESTUDIO_LOG_LEVEL"] = logLevel

        // Watchdog: lets the sidecar exit cleanly if this app is force-quit / crashes.
        process.environment?["ODYSSEY_PARENT_PID"] = "\(ProcessInfo.processInfo.processIdentifier)"

        // Inject WS bearer token
        if let token = try? IdentityManager.shared.wsToken(for: config.instanceName) {
            process.environment?["ODYSSEY_WS_TOKEN"] = token
            process.environment?["CLAUDESTUDIO_WS_TOKEN"] = token
        }

        // Inject Nostr keypair for internet relay
        if let nostrKP = try? IdentityManager.shared.nostrKeypair(for: config.instanceName) {
            process.environment?["ODYSSEY_NOSTR_PRIVKEY_HEX"] = nostrKP.privkeyHex
            process.environment?["ODYSSEY_NOSTR_PUBKEY_HEX"] = nostrKP.pubkeyHex
        }
        // Inject relay list from UserDefaults (fallback: sidecar uses hardcoded defaults)
        let relays = AppSettings.nostrRelays()
        if !relays.isEmpty {
            process.environment?["ODYSSEY_NOSTR_RELAYS"] = relays.joined(separator: ",")
        }
        // Inject directory opt-out flag (default enabled when key absent)
        let rawDirectoryValue = InstanceConfig.userDefaults.object(forKey: AppSettings.nostrDirectoryEnabledKey)
        let directoryEnabled = rawDirectoryValue == nil ? true : InstanceConfig.userDefaults.bool(forKey: AppSettings.nostrDirectoryEnabledKey)
        process.environment?["ODYSSEY_NOSTR_DIRECTORY"] = directoryEnabled ? "1" : "0"
        // Inject agent names for directory profile
        if !config.agentNames.isEmpty {
            process.environment?["ODYSSEY_AGENT_NAMES"] = config.agentNames.joined(separator: ",")
        }

        // TLS is intentionally disabled for localhost IPC — bearer token auth is sufficient,
        // and self-signed cert pinning caused connection failures on first-run DMG installs.

        let logDir = config.logDirectory ?? "\(NSHomeDirectory())/.odyssey/instances/default/logs"
        try? FileManager.default.createDirectory(atPath: logDir, withIntermediateDirectories: true)
        let logFile = "\(logDir)/sidecar.log"
        FileManager.default.createFile(atPath: logFile, contents: nil)
        let logHandle = FileHandle(forWritingAtPath: logFile)
        process.standardOutput = logHandle ?? FileHandle.nullDevice
        process.standardError = logHandle ?? FileHandle.nullDevice

        process.terminationHandler = { [weak self] proc in
            Log.sidecar.warning("Process exited with code \(proc.terminationStatus)")
            Task { @MainActor in
                self?.handleProcessTermination(proc)
            }
        }

        try process.run()
        self.process = process
        Log.sidecar.info("Launched PID \(process.processIdentifier)")
    }

    private func normalizedEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment

        let home = environment["HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? environment["HOME"]!
            : NSHomeDirectory()
        let user = environment["USER"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? environment["USER"]!
            : NSUserName()
        let logname = environment["LOGNAME"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? environment["LOGNAME"]!
            : user
        let shell = environment["SHELL"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? environment["SHELL"]!
            : "/bin/zsh"

        let defaultPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        let currentPath = environment["PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        environment["HOME"] = home
        environment["USER"] = user
        environment["LOGNAME"] = logname
        environment["SHELL"] = shell
        environment["PATH"] = currentPath.isEmpty ? defaultPath : [defaultPath, currentPath]
            .joined(separator: ":")

        return environment
    }

    private func localProviderEnvironment() -> [String: String] {
        LocalProviderSupport.environmentValues(
            bundleResourcePath: Bundle.main.resourcePath,
            currentDirectoryPath: FileManager.default.currentDirectoryPath,
            projectRootOverride: config.sidecarPathOverride,
            hostOverride: config.localAgentHostPathOverride,
            mlxRunnerOverride: config.mlxRunnerPathOverride
        )
    }

    private func connectWebSocket() async throws {
        if let override = hooks.connectWebSocket {
            try await override()
            eventContinuation?.yield(.connected)
            return
        }

        // Cancel any previous connection attempt
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        urlSession?.invalidateAndCancel()

        let scheme = (pinnedCertDERData != nil) ? "wss" : "ws"
        let url = URL(string: "\(scheme)://localhost:\(config.wsPort)")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        // Add bearer token if available
        if let token = try? IdentityManager.shared.wsToken(for: config.instanceName) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 5
        // Use self as delegate so we can pin the self-signed cert
        let session = URLSession(configuration: sessionConfig, delegate: self, delegateQueue: nil)
        self.urlSession = session
        let task = session.webSocketTask(with: request)
        self.webSocketTask = task
        task.resume()

        // Verify connection by receiving the sidecar.ready message
        let message = try await task.receive()
        if case .string(let text) = message {
            Log.sidecar.debug("Handshake received: \(text.prefix(80), privacy: .public)")
        }

        eventContinuation?.yield(.connected)
        receiveMessages()
        startPingPong()
    }

    private func startPingPong() {
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { break }
                self?.webSocketTask?.sendPing { error in
                    if let error {
                        Log.sidecar.warning("Ping failed: \(error)")
                    }
                }
            }
        }
    }

    private func receiveMessages() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                Task.detached(priority: .userInitiated) { [weak self] in
                    guard let self else { return }
                    await self.decodeAndYield(message)
                }
            case .failure:
                Task { @MainActor in
                    self?.eventContinuation?.yield(.disconnected)
                    self?.attemptReconnect()
                }
            }
        }
    }

    private nonisolated func decodeAndYield(_ message: URLSessionWebSocketTask.Message) async {
        let data: Data
        let rawText: String?
        switch message {
        case .string(let text):
            data = Data(text.utf8)
            rawText = text
        case .data(let d):
            data = d
            rawText = String(data: d, encoding: .utf8)
        @unknown default:
            await MainActor.run { self.receiveMessages() }
            return
        }

        if let text = rawText {
            await MainActor.run { self.rawMessageInterceptor?(text) }
        }

        guard let wire = try? JSONDecoder().decode(IncomingWireMessage.self, from: data),
              let event = wire.toEvent() else {
            await MainActor.run { self.receiveMessages() }
            return
        }
        await MainActor.run {
            self.eventContinuation?.yield(event)
            self.receiveMessages()
        }
    }

    private func handleProcessTermination(_ terminatedProcess: Process? = nil) {
        guard isRunning else { return }
        if let terminatedProcess, process === terminatedProcess {
            process = nil
        }
        eventContinuation?.yield(.disconnected)
        attemptReconnect()
    }

    private func attemptReconnect() {
        guard isRunning, !isReconnecting else { return }
        isReconnecting = true
        Task {
            defer { Task { @MainActor in self.isReconnecting = false } }
            await sleep(for: .seconds(2))
            guard isRunning else { return }

            if let process, process.isRunning {
                do {
                    try await connectWebSocket()
                    return
                } catch {
                    Log.sidecar.warning("Reconnect to managed sidecar failed: \(error.localizedDescription, privacy: .public)")
                }
            }

            do {
                try await terminateConflictingManagedSidecarsIfNeeded()
                try launchSidecar()
                try await connectWithRetry()
            } catch {
                Log.sidecar.error("Reconnect failed: \(error). Will retry in 5s.")
                await sleep(for: .seconds(5))
                Task { @MainActor in self.attemptReconnect() }
            }
        }
    }

    private func connectWithRetry() async throws {
        var lastError: Error?
        for attempt in 1...5 {
            await sleep(for: .milliseconds(attempt == 1 ? 800 : 1500))
            do {
                try await connectWebSocket()
                return
            } catch {
                lastError = error
                Log.sidecar.warning("Connect attempt \(attempt)/5 failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        throw lastError ?? SidecarError.notConnected
    }

    private func sleep(for duration: Duration) async {
        if let override = hooks.sleep {
            await override(duration)
            return
        }
        try? await Task.sleep(for: duration)
    }

    private func terminateConflictingManagedSidecarsIfNeeded() async throws {
        if let override = hooks.terminateConflictingSidecars {
            try await override()
            return
        }

        let pids = try await conflictingManagedSidecarPIDs()
        guard !pids.isEmpty else { return }

        Log.sidecar.warning("Stopping \(pids.count) conflicting sidecar listener(s) before launch")
        for pid in pids {
            _ = Darwin.kill(pid, SIGTERM)
        }

        if try await waitForManagedSidecarsToExit(timeout: .seconds(2)) {
            return
        }

        let stubbornPIDs = try await conflictingManagedSidecarPIDs()
        for pid in stubbornPIDs {
            _ = Darwin.kill(pid, SIGKILL)
        }

        guard try await waitForManagedSidecarsToExit(timeout: .seconds(1)) else {
            throw SidecarError.notConnected
        }
    }

    private func waitForManagedSidecarsToExit(timeout: Duration) async throws -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if try await conflictingManagedSidecarPIDs().isEmpty {
                return true
            }
            await sleep(for: .milliseconds(150))
        }
        return try await conflictingManagedSidecarPIDs().isEmpty
    }

    private func conflictingManagedSidecarPIDs() async throws -> [pid_t] {
        try await Task.detached(priority: .userInitiated) { [config] in
            let ports = Set([config.wsPort, config.httpPort])
            let pids = try ports.flatMap { try Self.listeningPIDs(on: $0) }
            let managed = try pids.filter { pid in
                guard let command = try Self.commandLine(for: pid) else {
                    return false
                }
                return Self.looksLikeManagedSidecar(command)
            }
            return Array(Set(managed)).sorted()
        }.value
    }

    nonisolated private static func listeningPIDs(on port: Int) throws -> [pid_t] {
        let output = try runCommand("/usr/sbin/lsof", arguments: [
            "-n", "-P", "-t",
            "-iTCP:\(port)",
            "-sTCP:LISTEN",
        ])

        return output
            .split(whereSeparator: \.isNewline)
            .compactMap { pid_t($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    nonisolated private static func commandLine(for pid: pid_t) throws -> String? {
        let output = try runCommand("/bin/ps", arguments: ["-p", "\(pid)", "-o", "command="])
        let command = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return command.isEmpty ? nil : command
    }

    nonisolated private static func runCommand(_ launchPath: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

        if process.terminationStatus == 0 {
            return output
        }

        if launchPath == "/usr/sbin/lsof", process.terminationStatus == 1 {
            return ""
        }

        throw NSError(
            domain: "SidecarManager",
            code: Int(process.terminationStatus),
            userInfo: [NSLocalizedDescriptionKey: errorOutput.isEmpty ? output : errorOutput]
        )
    }

    nonisolated private static func looksLikeManagedSidecar(_ command: String) -> Bool {
        (command.contains("sidecar/src/index.ts") || command.contains("odyssey-sidecar.js"))
            && command.contains("bun")
    }

    private func findBunPath() -> String {
        if let override = config.bunPathOverride,
           FileManager.default.fileExists(atPath: override) {
            return override
        }
        let candidates = [
            "/opt/homebrew/bin/bun",
            "/usr/local/bin/bun",
            "\(NSHomeDirectory())/.bun/bin/bun",
        ]
        for path in candidates {
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        return "bun"
    }

    private func findBundledSidecar() -> (bunPath: String, jsPath: String)? {
        LocalProviderSupport.resolveBundledSidecar()
    }

    private func findSidecarPath() -> String {
        LocalProviderSupport.resolveSidecarPath(
            bundleResourcePath: Bundle.main.resourcePath,
            currentDirectoryPath: FileManager.default.currentDirectoryPath,
            projectRootOverride: config.sidecarPathOverride
        ) ?? "\(NSHomeDirectory())/Odyssey/sidecar/src/index.ts"
    }
}

// MARK: - iOS Data Bridge

extension SidecarManager {
    private static let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func isoString(from date: Date) -> String {
        iso8601Formatter.string(from: date)
    }

    /// Push a snapshot of all conversations and projects from SwiftData to the sidecar.
    /// Called after the sidecar becomes connected so the iOS client can read them via REST.
    /// Sync conversation metadata (and optionally recent message history) to the sidecar.
    /// - Parameter pushMessages: If true, also backfill the last 30 chat messages per
    ///   conversation. Pass true on initial connect; false for periodic metadata-only refreshes.
    func pushConversationSync(modelContext: ModelContext, pushMessages: Bool = false) async {
        let _pushStart = ContinuousClock.now
        defer {
            let elapsed = ContinuousClock.now - _pushStart
            if elapsed > .milliseconds(100) {
                Log.perf.warning("pushConversationSync total: \(elapsed, privacy: .public) (pushMessages=\(pushMessages))")
            }
        }
        do {
            // Fetch all non-archived conversations (most-recent 100 to avoid huge payloads)
            var convDescriptor = FetchDescriptor<Conversation>(
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )
            convDescriptor.fetchLimit = 100
            let conversations = (try? modelContext.fetch(convDescriptor)) ?? []

            // Fetch all projects
            let projectDescriptor = FetchDescriptor<Project>(
                sortBy: [SortDescriptor(\.name)]
            )
            let projects = (try? modelContext.fetch(projectDescriptor)) ?? []

            // Map conversations to wire type. Yield every 5 conversations
            // (vs the previous 20) so the run loop pumps scroll/input
            // frequently during the cold sync — total CPU is unchanged but
            // perceived stutter drops markedly. We tried per-conversation
            // `FetchDescriptor<ConversationMessage>(fetchLimit: 1)` to skip
            // the lazy `.messages` load, but 100 separate fetches were
            // *slower* than one bulk relationship hit (2.1 s vs 1.3 s) —
            // SwiftData is much better at materialising a relationship in
            // bulk than at per-row fetches with predicates.
            var convWires: [ConversationSummaryWire] = []
            convWires.reserveCapacity(conversations.count)
            for (index, conv) in conversations.enumerated() {
                let lastMsg = (conv.messages ?? [])
                    .filter { !$0.isStreaming }
                    .max(by: { $0.timestamp < $1.timestamp })

                let participantWires: [ParticipantWire] = (conv.participants ?? []).map { p in
                    let isAgent: Bool
                    switch p.type {
                    case .agentSession: isAgent = true
                    default: isAgent = false
                    }
                    return ParticipantWire(
                        id: p.id.uuidString,
                        displayName: p.displayName,
                        isAgent: isAgent,
                        isLocal: p.isLocalParticipant
                    )
                }
                convWires.append(ConversationSummaryWire(
                    id: conv.id.uuidString,
                    topic: conv.topic ?? "Conversation",
                    lastMessageAt: Self.isoString(from: lastMsg?.timestamp ?? conv.startedAt),
                    lastMessagePreview: String((lastMsg?.text ?? "").prefix(100)),
                    unread: conv.isUnread,
                    participants: participantWires,
                    projectId: conv.projectId?.uuidString,
                    projectName: nil,
                    workingDirectory: conv.primarySession?.workingDirectory
                ))
                if index % 25 == 24 { await Task.yield() }
            }

            // Map projects to wire type
            let projectWires: [ProjectSummaryWire] = projects.map { project in
                ProjectSummaryWire(
                    id: project.id.uuidString,
                    name: project.name,
                    rootPath: project.rootPath,
                    icon: project.icon,
                    color: project.color,
                    isPinned: project.isPinned,
                    pinnedAgentIds: project.pinnedAgentIds.map { $0.uuidString }
                )
            }

            // Collect message wires per conversation (capped fetch to avoid main-thread stalls).
            var messageWiresByConv: [(convId: String, wires: [MessageWire])] = []
            if pushMessages {
                for conv in conversations {
                    let convId = conv.id
                    var msgDesc = FetchDescriptor<ConversationMessage>(
                        predicate: #Predicate<ConversationMessage> { msg in
                            msg.conversation?.id == convId
                        },
                        sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
                    )
                    msgDesc.fetchLimit = 30
                    let recent = ((try? modelContext.fetch(msgDesc)) ?? []).reversed()
                    let wires: [MessageWire] = recent.compactMap { msg in
                        guard !msg.isStreaming, !msg.text.isEmpty else { return nil }
                        return MessageWire(
                            id: msg.id.uuidString,
                            text: msg.text,
                            type: msg.type.rawValue,
                            senderParticipantId: msg.senderParticipantId?.uuidString,
                            timestamp: Self.isoString(from: msg.timestamp),
                            isStreaming: false,
                            toolName: msg.toolName,
                            toolOutput: msg.toolOutput,
                            thinkingText: msg.thinkingText
                        )
                    }
                    if !wires.isEmpty {
                        messageWiresByConv.append((convId: convId.uuidString, wires: wires))
                    }
                }
            }

            // Now do all the async sends
            try await send(.conversationSync(conversations: convWires))
            try await send(.projectSync(projects: projectWires))
            Log.sidecar.info("pushConversationSync: pushed \(convWires.count) conversations, \(projectWires.count) projects")

            if pushMessages {
                var totalMsgs = 0
                for (convId, wires) in messageWiresByConv {
                    for wire in wires {
                        try await send(.conversationMessageAppend(conversationId: convId, message: wire))
                        totalMsgs += 1
                    }
                }
                Log.sidecar.info("pushConversationSync: backfilled \(totalMsgs) messages across \(messageWiresByConv.count) conversations")
            }
        } catch {
            Log.sidecar.warning("pushConversationSync failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Push a single message append to the sidecar so it can be served to iOS via REST.
    func pushMessageAppend(conversationId: UUID, message: ConversationMessage) async {
        let wire = MessageWire(
            id: message.id.uuidString,
            text: message.text,
            type: message.type.rawValue,
            senderParticipantId: message.senderParticipantId?.uuidString,
            timestamp: Self.isoString(from: message.timestamp),
            isStreaming: message.isStreaming,
            toolName: message.toolName,
            toolOutput: message.toolOutput,
            thinkingText: message.thinkingText
        )
        do {
            try await send(.conversationMessageAppend(conversationId: conversationId.uuidString, message: wire))
        } catch {
            Log.sidecar.warning("pushMessageAppend failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - URLSessionDelegate (cert pinning for self-signed TLS)

extension SidecarManager: URLSessionDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // If no pinned cert is loaded, fall back to default TLS validation
        guard let pinnedData = pinnedCertDERData else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Compare the server's leaf cert DER bytes against our pinned bytes
        var leafCert: SecCertificate?
        if #available(macOS 12.0, *) {
            leafCert = (SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate])?.first
        } else {
            leafCert = SecTrustGetCertificateAtIndex(serverTrust, 0)
        }
        if let leaf = leafCert {
            let leafData = SecCertificateCopyData(leaf) as Data
            if leafData == pinnedData {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
                return
            }
        }

        Log.sidecar.warning("TLS cert pinning failed — cert mismatch")
        completionHandler(.cancelAuthenticationChallenge, nil)
    }
}
