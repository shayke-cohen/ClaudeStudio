import Combine
import Foundation

@MainActor
final class SidecarManager: ObservableObject, Sendable {
    struct Config: Sendable {
        var wsPort: Int = 9849
        var httpPort: Int = 9850
        var logDirectory: String?
        var dataDirectory: String?
        var bunPathOverride: String?
        var sidecarPathOverride: String?
    }

    private var process: Process?
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var eventContinuation: AsyncStream<SidecarEvent>.Continuation?
    private var isRunning = false
    private var isReconnecting = false
    private var pingTask: Task<Void, Never>?
    private let config: Config

    var events: AsyncStream<SidecarEvent> {
        AsyncStream { continuation in
            self.eventContinuation = continuation
        }
    }

    nonisolated init(config: Config = Config()) {
        self.config = config
    }

    func start() async throws {
        guard !isRunning else { return }
        isRunning = true

        // Try connecting to an existing sidecar first
        do {
            try await connectWebSocket()
            return
        } catch {
            // No existing sidecar, launch a new one
        }

        try launchSidecar()
        try await Task.sleep(for: .milliseconds(800))
        try await connectWebSocket()
    }

    func stop() {
        isRunning = false
        pingTask?.cancel()
        pingTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        process?.terminate()
        process = nil
        eventContinuation?.yield(.disconnected)
        eventContinuation?.finish()
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
        guard let task = webSocketTask else {
            throw SidecarError.notConnected
        }
        try await task.send(.string(text))
    }

    private func launchSidecar() throws {
        let bunPath = findBunPath()
        let sidecarPath = findSidecarPath()
        print("[SidecarManager] Bun: \(bunPath)")
        print("[SidecarManager] Sidecar: \(sidecarPath)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: bunPath)
        process.arguments = ["run", sidecarPath]
        process.environment = ProcessInfo.processInfo.environment
        process.environment?["CLAUDPEER_WS_PORT"] = "\(config.wsPort)"
        process.environment?["CLAUDPEER_HTTP_PORT"] = "\(config.httpPort)"
        if let dataDir = config.dataDirectory {
            process.environment?["CLAUDPEER_DATA_DIR"] = dataDir
        }

        let logDir = config.logDirectory ?? "\(NSHomeDirectory())/.claudpeer/instances/default/logs"
        try? FileManager.default.createDirectory(atPath: logDir, withIntermediateDirectories: true)
        let logFile = "\(logDir)/sidecar.log"
        FileManager.default.createFile(atPath: logFile, contents: nil)
        let logHandle = FileHandle(forWritingAtPath: logFile)
        process.standardOutput = logHandle ?? FileHandle.nullDevice
        process.standardError = logHandle ?? FileHandle.nullDevice

        process.terminationHandler = { [weak self] proc in
            print("[SidecarManager] Process exited with code \(proc.terminationStatus)")
            Task { @MainActor in
                self?.handleProcessTermination()
            }
        }

        try process.run()
        self.process = process
        print("[SidecarManager] Launched PID \(process.processIdentifier)")
    }

    private func connectWebSocket() async throws {
        let url = URL(string: "ws://localhost:\(config.wsPort)")!
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        let session = URLSession(configuration: config)
        self.urlSession = session
        let task = session.webSocketTask(with: url)
        self.webSocketTask = task
        task.resume()
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
                        print("[SidecarManager] Ping failed: \(error)")
                    }
                }
            }
        }
    }

    private func receiveMessages() {
        webSocketTask?.receive { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let message):
                    self?.handleMessage(message)
                    self?.receiveMessages()
                case .failure:
                    self?.eventContinuation?.yield(.disconnected)
                    self?.attemptReconnect()
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .string(let text):
            data = Data(text.utf8)
        case .data(let d):
            data = d
        @unknown default:
            return
        }

        guard let wire = try? JSONDecoder().decode(IncomingWireMessage.self, from: data),
              let event = wire.toEvent() else { return }
        eventContinuation?.yield(event)
    }

    private func handleProcessTermination() {
        guard isRunning else { return }
        eventContinuation?.yield(.disconnected)
        attemptReconnect()
    }

    private func attemptReconnect() {
        guard isRunning, !isReconnecting else { return }
        isReconnecting = true
        Task {
            defer { Task { @MainActor in self.isReconnecting = false } }
            try await Task.sleep(for: .seconds(2))
            guard isRunning else { return }

            // Try connecting to an existing sidecar first (e.g. one that survived a UI restart)
            do {
                try await connectWebSocket()
                return
            } catch {
                // No existing sidecar, launch a new one
            }

            do {
                try launchSidecar()
                try await Task.sleep(for: .milliseconds(800))
                try await connectWebSocket()
            } catch {
                print("[SidecarManager] Reconnect failed: \(error). Will retry in 5s.")
                try? await Task.sleep(for: .seconds(5))
                Task { @MainActor in self.attemptReconnect() }
            }
        }
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

    private func findSidecarPath() -> String {
        let fm = FileManager.default

        if let override = config.sidecarPathOverride {
            let overridePath = "\(override)/sidecar/src/index.ts"
            if fm.fileExists(atPath: overridePath) { return overridePath }
        }

        if let bundlePath = Bundle.main.resourcePath {
            let inBundle = "\(bundlePath)/sidecar/src/index.ts"
            if fm.fileExists(atPath: inBundle) { return inBundle }
        }

        let devPath = "\(fm.currentDirectoryPath)/sidecar/src/index.ts"
        if fm.fileExists(atPath: devPath) { return devPath }

        let wellKnown = "\(NSHomeDirectory())/ClaudPeer/sidecar/src/index.ts"
        if fm.fileExists(atPath: wellKnown) { return wellKnown }

        return wellKnown
    }
}
