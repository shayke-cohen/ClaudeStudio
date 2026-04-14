// OdysseyiOS/Services/RemoteSidecarManager.swift
import Foundation
import Network
import OdysseyCore

/// Manages a WebSocket connection from the iOS client to a paired Mac's sidecar.
@MainActor
final class RemoteSidecarManager: ObservableObject {

    // MARK: - Types

    enum ConnectionStatus: Equatable {
        case disconnected
        case connecting
        case connected(method: String)
    }

    enum ConnectionMethod: String, Equatable {
        case lan
        case wanDirect
        case turn
    }

    // MARK: - Published state

    @Published var status: ConnectionStatus = .disconnected
    @Published var connectedPeer: PeerCredentials?

    // MARK: - Private state

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var activeSessions: Set<String> = []
    private var eventContinuation: AsyncStream<SidecarEvent>.Continuation?
    private var _events: AsyncStream<SidecarEvent>!
    private var pingTask: Task<Void, Never>?

    // MARK: - Event stream

    init() {
        let (stream, continuation) = AsyncStream<SidecarEvent>.makeStream()
        _events = stream
        eventContinuation = continuation
    }

    var events: AsyncStream<SidecarEvent> { _events }

    // MARK: - Public API

    func connect(using credentials: PeerCredentials) async {
        status = .connecting
        connectedPeer = credentials

        for endpoint in Self.candidateEndpoints(for: credentials) {
            do {
                try await connectWebSocket(to: endpoint, credentials: credentials)
                return
            } catch {
                continue
            }
        }
        status = .disconnected
    }

    func send(_ command: SidecarCommand) async throws {
        guard let task = webSocketTask else { throw RemoteError.notConnected }
        let data = try command.encodeToJSON()
        guard let text = String(data: data, encoding: .utf8) else {
            throw RemoteError.encodingFailed
        }
        try await task.send(.string(text))
    }

    func disconnect() {
        pingTask?.cancel()
        pingTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        urlSession?.invalidateAndCancel()
        webSocketTask = nil
        urlSession = nil
        status = .disconnected
    }

    func reconnectIfNeeded() async {
        guard case .disconnected = status, let peer = connectedPeer else { return }
        await connect(using: peer)
    }

    func suspendForBackground() async {
        for sessionId in activeSessions {
            try? await send(.sessionPause(sessionId: sessionId))
        }
        disconnect()
    }

    func trackSession(_ sessionId: String) { activeSessions.insert(sessionId) }
    func untrackSession(_ sessionId: String) { activeSessions.remove(sessionId) }

    // MARK: - Endpoint helpers

    static func candidateEndpoints(for credentials: PeerCredentials) -> [String] {
        var endpoints: [String] = []
        if let lan = credentials.lanHint { endpoints.append(lan) }
        if let wan = credentials.wanHint { endpoints.append(wan) }
        return endpoints
    }

    // MARK: - Private connection

    private func connectWebSocket(to host: String, credentials: PeerCredentials) async throws {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        urlSession?.invalidateAndCancel()

        // Normalise host:port
        let hostPort: String
        if host.contains(":") {
            hostPort = host
        } else {
            hostPort = "\(host):\(credentials.wsPort)"
        }
        let url = URL(string: "wss://\(hostPort)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(credentials.wsToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 5

        let config = URLSessionConfiguration.default
        let delegate = CertPinningDelegate(pinnedDER: credentials.tlsCertDER)
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        urlSession = session
        let task = session.webSocketTask(with: request)
        webSocketTask = task
        task.resume()

        // Receive the sidecar.ready handshake message (any first message is treated as handshake).
        let message = try await task.receive()
        _ = message  // discard — just confirms the connection is live

        // Determine method
        let method: ConnectionMethod = (credentials.lanHint.map { host.hasPrefix($0) } ?? false)
            ? .lan
            : .wanDirect

        status = .connected(method: method.rawValue)
        eventContinuation?.yield(.connected)
        receiveMessages()
        startPing()
    }

    private func receiveMessages() {
        webSocketTask?.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch result {
                case .success(let msg):
                    self.handleMessage(msg)
                    self.receiveMessages()
                case .failure:
                    self.status = .disconnected
                    self.eventContinuation?.yield(.disconnected)
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .string(let t): data = Data(t.utf8)
        case .data(let d): data = d
        @unknown default: return
        }
        guard let wire = try? JSONDecoder().decode(IncomingWireMessage.self, from: data),
              let event = wire.toEvent() else { return }
        eventContinuation?.yield(event)
    }

    private func startPing() {
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { break }
                await self?.webSocketTask?.sendPing { _ in }
            }
        }
    }

    // MARK: - Errors

    enum RemoteError: Error {
        case notConnected
        case encodingFailed
        case handshakeFailed
    }
}

// MARK: - TLS Certificate Pinning

final class CertPinningDelegate: NSObject, URLSessionDelegate {
    let pinnedDER: Data
    init(pinnedDER: Data) { self.pinnedDER = pinnedDER }

    /// Returns true if `certDERData` equals the pinned certificate bytes.
    /// Used in tests to verify comparison logic without requiring a live TLS connection.
    func matches(certDERData: Data) -> Bool {
        return certDERData == pinnedDER
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        // Compare leaf certificate DER bytes against the pinned cert
        if #available(iOS 15.0, *) {
            if let chain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
               let leaf = chain.first {
                let leafData = SecCertificateCopyData(leaf) as Data
                if leafData == pinnedDER {
                    completionHandler(.useCredential, URLCredential(trust: serverTrust))
                    return
                }
            }
        } else {
            // Fallback for older OS (pre-15)
            if let leaf = SecTrustGetCertificateAtIndex(serverTrust, 0) {
                let leafData = SecCertificateCopyData(leaf) as Data
                if leafData == pinnedDER {
                    completionHandler(.useCredential, URLCredential(trust: serverTrust))
                    return
                }
            }
        }
        completionHandler(.cancelAuthenticationChallenge, nil)
    }
}
