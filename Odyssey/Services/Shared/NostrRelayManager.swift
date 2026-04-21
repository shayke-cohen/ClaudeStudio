import Foundation
import OSLog

// MARK: - Nostr wire types

struct NostrEvent: Codable {
    let id: String
    let pubkey: String
    let created_at: Int
    let kind: Int
    let tags: [[String]]
    let content: String
    let sig: String
}

// MARK: - NostrRelayManager

/// Connects to Nostr relay URLs via URLSession WebSocket, subscribes to events addressed
/// to this device's npub, and publishes NIP-44 encrypted events to peers.
/// Uses exponential backoff reconnection (1s → 2s → 4s → max 30s).
@MainActor
final class NostrRelayManager: NSObject {

    // MARK: - Types

    enum ConnectionState { case disconnected, connecting, connected }

    // MARK: - Configuration

    private let relayURLs: [String]
    private let privkeyHex: String
    private let pubkeyHex: String
    private let onEvent: (NostrEvent) -> Void

    // MARK: - State

    private var connections: [String: URLSessionWebSocketTask] = [:]
    private var sessions: [String: URLSession] = [:]
    private(set) var state: ConnectionState = .disconnected
    private var reconnectTasks: [String: Task<Void, Never>] = [:]
    private var reconnectAttempts: [String: Int] = [:]

    // MARK: - Init

    init(relayURLs: [String], privkeyHex: String, pubkeyHex: String, onEvent: @escaping (NostrEvent) -> Void) {
        self.relayURLs = relayURLs
        self.privkeyHex = privkeyHex
        self.pubkeyHex = pubkeyHex
        self.onEvent = onEvent
    }

    // MARK: - Public API

    func connect() {
        for url in relayURLs {
            openConnection(to: url)
        }
    }

    func disconnect() {
        for (url, task) in connections {
            task.cancel(with: .goingAway, reason: nil)
            sessions[url]?.invalidateAndCancel()
            reconnectTasks[url]?.cancel()
        }
        connections.removeAll()
        sessions.removeAll()
        reconnectTasks.removeAll()
        reconnectAttempts.removeAll()
        state = .disconnected
    }

    func publish(to peerPubkeyHex: String, eventJSON: String) {
        let msg = Self.buildEVENTMessage(eventJSON: eventJSON)
        for task in connections.values {
            task.send(.string(msg)) { _ in }
        }
    }

    // MARK: - Message builders (exposed for testing)

    static func buildREQMessage(subscriptionId: String, npub: String) -> String {
        let filter: [String: Any] = ["kinds": [4], "#p": [npub]]
        let arr: [Any] = ["REQ", subscriptionId, filter]
        let data = try! JSONSerialization.data(withJSONObject: arr)
        return String(data: data, encoding: .utf8)!
    }

    static func buildEVENTMessage(eventJSON: String) -> String {
        guard let eventData = eventJSON.data(using: .utf8),
              let eventObj = try? JSONSerialization.jsonObject(with: eventData) else {
            return """
            ["EVENT",\(eventJSON)]
            """
        }
        let arr: [Any] = ["EVENT", eventObj]
        let data = try! JSONSerialization.data(withJSONObject: arr)
        return String(data: data, encoding: .utf8)!
    }

    static func parseIncomingEvent(message: String) -> NostrEvent? {
        guard let data = message.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [Any],
              arr.count >= 3,
              arr[0] as? String == "EVENT" else { return nil }
        guard let eventData = try? JSONSerialization.data(withJSONObject: arr[2]),
              let event = try? JSONDecoder().decode(NostrEvent.self, from: eventData) else {
            return nil
        }
        return event
    }

    static func backoffDuration(attempt: Int) -> TimeInterval {
        min(pow(2.0, Double(attempt)), 30.0)
    }

    // MARK: - Private connection management

    private func openConnection(to relayURL: String) {
        guard let url = URL(string: relayURL) else { return }
        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config)
        sessions[relayURL] = session
        let task = session.webSocketTask(with: url)
        connections[relayURL] = task
        task.resume()
        state = .connecting
        sendSubscription(to: relayURL, task: task)
        receiveMessages(from: relayURL, task: task)
    }

    private func sendSubscription(to relayURL: String, task: URLSessionWebSocketTask) {
        let subId = "odyssey-\(pubkeyHex.prefix(8))"
        let req = Self.buildREQMessage(subscriptionId: subId, npub: pubkeyHex)
        task.send(.string(req)) { [weak self] error in
            if error == nil {
                Task { @MainActor [weak self] in
                    self?.state = .connected
                    self?.reconnectAttempts[relayURL] = 0
                }
            }
        }
    }

    private func receiveMessages(from relayURL: String, task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch result {
                case .success(let msg):
                    self.handleMessage(msg)
                    self.receiveMessages(from: relayURL, task: task)
                case .failure:
                    self.connections.removeValue(forKey: relayURL)
                    self.sessions[relayURL]?.invalidateAndCancel()
                    self.sessions.removeValue(forKey: relayURL)
                    self.scheduleReconnect(to: relayURL)
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        let text: String
        switch message {
        case .string(let t): text = t
        case .data(let d): text = String(data: d, encoding: .utf8) ?? ""
        @unknown default: return
        }
        if let event = Self.parseIncomingEvent(message: text) {
            onEvent(event)
        }
    }

    private static let maxReconnectAttempts = 30

    private func scheduleReconnect(to relayURL: String) {
        let attempt = reconnectAttempts[relayURL, default: 0]
        guard attempt < Self.maxReconnectAttempts else {
            Log.sidecar.warning("NostrRelayManager: giving up on \(relayURL, privacy: .public) after \(attempt) attempts")
            return
        }
        let delay = Self.backoffDuration(attempt: attempt)
        reconnectAttempts[relayURL] = attempt + 1

        Log.sidecar.info("NostrRelayManager: reconnecting to \(relayURL, privacy: .public) in \(delay)s (attempt \(attempt))")

        reconnectTasks[relayURL]?.cancel()
        reconnectTasks[relayURL] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.openConnection(to: relayURL)
        }
    }
}
