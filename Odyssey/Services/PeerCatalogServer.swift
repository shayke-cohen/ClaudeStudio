import Foundation
import Network
import OSLog

struct RoomSyncHint: Sendable, Equatable {
    let roomId: String
    let hostSequence: Int
}

/// Minimal TCP HTTP responder for `GET /odyssey/v1/agents` on the LAN (Bonjour-advertised).
final class PeerCatalogServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.odyssey.peer.catalog.server")
    private var listener: NWListener?
    private let lock = NSLock()
    private var cachedBody: Data
    /// Sidecar WebSocket port to advertise in Bonjour TXT for relay connections.
    var sidecarWsPort: Int?
    var onRoomSyncHint: (@Sendable (RoomSyncHint) -> Void)?

    /// When set, the Bonjour TXT record will include `wan=<ip>:<port>`.
    /// Must only be set from the main actor (P2PNetworkManager is @MainActor).
    nonisolated(unsafe) var publicWANEndpoint: String? = nil {
        didSet { restartForTXTUpdate() }
    }

    private var isRunning: Bool { listener != nil }

    init(initialJSON: Data) {
        self.cachedBody = initialJSON
    }

    func updateJSON(_ data: Data) {
        lock.lock()
        cachedBody = data
        lock.unlock()
    }

    private func snapshotBody() -> Data {
        lock.lock()
        let d = cachedBody
        lock.unlock()
        return d
    }

    func start() throws {
        guard listener == nil else { return }
        try startListener()
    }

    func stop() {
        stopListener()
    }

    /// Creates a new NWListener with the current TXT record (including wan= if set) and starts it.
    private func startListener() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let l = try NWListener(using: params, on: NWEndpoint.Port.any)
        var txtEntries: [String: String] = [
            "ver": "1",
            "instance": InstanceConfig.name,
        ]
        if let wsPort = sidecarWsPort {
            txtEntries["ws"] = "\(wsPort)"
        }
        if let wan = publicWANEndpoint {
            txtEntries["wan"] = wan
        }
        let txt = NWTXTRecord(txtEntries)
        l.service = NWListener.Service(
            name: PeerCatalogServer.bonjourName(),
            type: PeerCatalogServer.serviceType,
            domain: nil,
            txtRecord: txt
        )
        l.stateUpdateHandler = { [weak self] state in
            if case .failed(let err) = state {
                Log.peerCatalog.error("listener failed: \(err)")
                self?.listener?.cancel()
                self?.listener = nil
            }
        }
        l.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }
        l.start(queue: queue)
        listener = l
    }

    /// Cancels and nils out the current NWListener.
    private func stopListener() {
        listener?.cancel()
        listener = nil
    }

    /// Called when publicWANEndpoint changes. Stops and restarts the listener
    /// so the new TXT record (with wan= entry) takes effect.
    /// NWListener.service is write-once, so reassignment on a running listener is silently ignored.
    private func restartForTXTUpdate() {
        guard isRunning else { return }
        stopListener()
        try? startListener()
    }

    private static let serviceType = "_odyssey._tcp"

    private static func bonjourName() -> String {
        let host = ProcessInfo.processInfo.hostName.split(separator: ".").first.map(String.init) ?? "Mac"
        return "\(host)-\(InstanceConfig.name)"
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        let state = PeerCatalogRequestState()
        receiveHeaders(on: connection, state: state)
    }

    private func receiveHeaders(on connection: NWConnection, state: PeerCatalogRequestState) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            if let error {
                Log.peerCatalog.error("receive error: \(error)")
                connection.cancel()
                return
            }
            if let data, !data.isEmpty {
                state.append(data)
            }
            // Check if we have the full header block yet
            if let req = String(data: state.snapshot(), encoding: .utf8),
               req.contains("\r\n\r\n") {
                self.dispatchRequest(req, connection: connection)
            } else if isComplete {
                // Connection closed before full headers — try what we have
                if let req = String(data: state.snapshot(), encoding: .utf8), !req.isEmpty {
                    self.dispatchRequest(req, connection: connection)
                } else {
                    connection.cancel()
                }
            } else {
                self.receiveHeaders(on: connection, state: state)
            }
        }
    }

    private func dispatchRequest(_ req: String, connection: NWConnection) {
        let lines = req.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let first = lines.first else {
            connection.cancel()
            return
        }
        let parts = first.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" else {
            sendText(connection, status: 400, body: "Bad Request")
            return
        }
        let path = String(parts[1])
        if path == "/odyssey/v1/agents" || path.hasPrefix("/odyssey/v1/agents?") {
            let body = snapshotBody()
            sendJSON(connection, body: body)
        } else if path.hasPrefix("/odyssey/v1/rooms/sync") {
            handleRoomSyncHint(path: path, connection: connection)
        } else {
            sendText(connection, status: 404, body: "Not Found")
        }
    }

    private func handleRoomSyncHint(path: String, connection: NWConnection) {
        guard let components = URLComponents(string: "http://localhost\(path)"),
              let roomId = components.queryItems?.first(where: { $0.name == "roomId" })?.value,
              !roomId.isEmpty
        else {
            sendText(connection, status: 400, body: "Missing roomId")
            return
        }

        let hostSequence = components.queryItems?
            .first(where: { $0.name == "hostSequence" })?
            .value
            .flatMap(Int.init) ?? 0

        onRoomSyncHint?(RoomSyncHint(roomId: roomId, hostSequence: hostSequence))
        sendText(connection, status: 202, body: "Accepted")
    }

    private func sendJSON(_ connection: NWConnection, body: Data) {
        let header = "HTTP/1.1 200 OK\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var out = Data(header.utf8)
        out.append(body)
        connection.send(content: out, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func sendText(_ connection: NWConnection, status: Int, body: String) {
        let b = Data(body.utf8)
        let reason: String
        switch status {
        case 202:
            reason = "Accepted"
        case 404:
            reason = "Not Found"
        default:
            reason = "Bad Request"
        }
        let header = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(b.count)\r\nConnection: close\r\n\r\n"
        var out = Data(header.utf8)
        out.append(b)
        connection.send(content: out, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

private final class PeerCatalogRequestState: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    func append(_ data: Data) {
        lock.lock()
        buffer.append(data)
        lock.unlock()
    }

    func snapshot() -> Data {
        lock.lock()
        let current = buffer
        lock.unlock()
        return current
    }
}
