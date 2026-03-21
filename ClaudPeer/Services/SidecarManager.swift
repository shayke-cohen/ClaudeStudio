import Combine
import Foundation

@MainActor
final class SidecarManager: ObservableObject, Sendable {
    private var process: Process?
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var eventContinuation: AsyncStream<SidecarEvent>.Continuation?
    private var isRunning = false
    private let port: Int

    var events: AsyncStream<SidecarEvent> {
        AsyncStream { continuation in
            self.eventContinuation = continuation
        }
    }

    nonisolated init(port: Int = 9849) {
        self.port = port
    }

    func start() async throws {
        guard !isRunning else { return }
        isRunning = true
        try launchSidecar()
        try await Task.sleep(for: .milliseconds(500))
        try await connectWebSocket()
    }

    func stop() {
        isRunning = false
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        process?.terminate()
        process = nil
        eventContinuation?.yield(.disconnected)
        eventContinuation?.finish()
    }

    func send(_ command: SidecarCommand) async throws {
        let message = command.wireMessage
        let data = try JSONEncoder().encode(message)
        guard let text = String(data: data, encoding: .utf8) else { return }
        try await webSocketTask?.send(.string(text))
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
        process.environment?["CLAUDPEER_WS_PORT"] = "\(port)"

        let logDir = "\(NSHomeDirectory())/.claudpeer/logs"
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
        let url = URL(string: "ws://localhost:\(port)")!
        let session = URLSession(configuration: .default)
        self.urlSession = session
        let task = session.webSocketTask(with: url)
        self.webSocketTask = task
        task.resume()
        eventContinuation?.yield(.connected)
        receiveMessages()
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
        guard isRunning else { return }
        Task {
            try await Task.sleep(for: .seconds(2))
            guard isRunning else { return }
            do {
                try launchSidecar()
                try await Task.sleep(for: .milliseconds(500))
                try await connectWebSocket()
            } catch {
                try await Task.sleep(for: .seconds(5))
                attemptReconnect()
            }
        }
    }

    private func findBunPath() -> String {
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

        if let bundlePath = Bundle.main.resourcePath {
            let inBundle = "\(bundlePath)/sidecar/src/index.ts"
            if fm.fileExists(atPath: inBundle) { return inBundle }
        }

        let devPath = "\(fm.currentDirectoryPath)/sidecar/src/index.ts"
        if fm.fileExists(atPath: devPath) { return devPath }

        let wellKnown = "\(NSHomeDirectory())/ClaudPeer/sidecar/src/index.ts"
        if fm.fileExists(atPath: wellKnown) { return wellKnown }

        if let saved = UserDefaults.standard.string(forKey: "claudpeer.projectPath") {
            let savedPath = "\(saved)/sidecar/src/index.ts"
            if fm.fileExists(atPath: savedPath) { return savedPath }
        }

        return wellKnown
    }
}
