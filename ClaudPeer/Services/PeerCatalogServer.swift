import Foundation
import Network

/// Minimal TCP HTTP responder for `GET /claudpeer/v1/agents` on the LAN (Bonjour-advertised).
final class PeerCatalogServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.claudpeer.peer.catalog.server")
    private var listener: NWListener?
    private let lock = NSLock()
    private var cachedBody: Data
    /// Sidecar WebSocket port to advertise in Bonjour TXT for relay connections.
    var sidecarWsPort: Int?

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
        let txt = NWTXTRecord(txtEntries)
        l.service = NWListener.Service(
            name: PeerCatalogServer.bonjourName(),
            type: PeerCatalogServer.serviceType,
            domain: nil,
            txtRecord: txt
        )
        l.stateUpdateHandler = { [weak self] state in
            if case .failed(let err) = state {
                print("[PeerCatalogServer] listener failed: \(err)")
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

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private static let serviceType = "_claudpeer._tcp"

    private static func bonjourName() -> String {
        let host = ProcessInfo.processInfo.hostName.split(separator: ".").first.map(String.init) ?? "Mac"
        return "\(host)-\(InstanceConfig.name)"
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        var requestBuffer = Data()
        func readUntilHeaders() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
                guard let self else {
                    connection.cancel()
                    return
                }
                if let error {
                    print("[PeerCatalogServer] receive error: \(error)")
                    connection.cancel()
                    return
                }
                if let data, !data.isEmpty {
                    requestBuffer.append(data)
                }
                // Check if we have the full header block yet
                if let req = String(data: requestBuffer, encoding: .utf8),
                   req.contains("\r\n\r\n") {
                    self.dispatchRequest(req, connection: connection)
                } else if isComplete {
                    // Connection closed before full headers — try what we have
                    if let req = String(data: requestBuffer, encoding: .utf8), !req.isEmpty {
                        self.dispatchRequest(req, connection: connection)
                    } else {
                        connection.cancel()
                    }
                } else {
                    readUntilHeaders()
                }
            }
        }
        readUntilHeaders()
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
        if path == "/claudpeer/v1/agents" || path.hasPrefix("/claudpeer/v1/agents?") {
            let body = snapshotBody()
            sendJSON(connection, body: body)
        } else {
            sendText(connection, status: 404, body: "Not Found")
        }
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
        let reason = status == 404 ? "Not Found" : "Bad Request"
        let header = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(b.count)\r\nConnection: close\r\n\r\n"
        var out = Data(header.utf8)
        out.append(b)
        connection.send(content: out, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
