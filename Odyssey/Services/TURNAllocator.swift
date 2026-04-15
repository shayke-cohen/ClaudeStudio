// Odyssey/Services/TURNAllocator.swift
// TURN TCP relay client (RFC 5766 + RFC 6062)
import Foundation
import Network
import CommonCrypto
import OSLog
import OdysseyCore

private let logger = Logger(subsystem: "com.odyssey.app", category: "TURN")

// MARK: - Errors

enum TURNError: LocalizedError {
    case invalidURL(String)
    case connectionFailed(String)
    case timeout
    case authenticationFailed
    case allocationFailed(UInt16, String)
    case noRelayAddress
    case truncatedMessage
    case unexpectedResponse(UInt16)
    case connectFailed(String)
    case connectionBindFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):              return "Invalid TURN server URL: \(url)"
        case .connectionFailed(let reason):     return "TURN connection failed: \(reason)"
        case .timeout:                          return "TURN server did not respond in time."
        case .authenticationFailed:             return "TURN authentication failed."
        case .allocationFailed(let code, let m): return "TURN allocation failed (\(code)): \(m)"
        case .noRelayAddress:                   return "TURN response contained no relay address."
        case .truncatedMessage:                 return "TURN message was truncated."
        case .unexpectedResponse(let t):        return "Unexpected TURN message type: 0x\(String(t, radix: 16))"
        case .connectFailed(let reason):        return "TURN Connect failed: \(reason)"
        case .connectionBindFailed(let reason): return "TURN ConnectionBind failed: \(reason)"
        }
    }
}

// MARK: - TURNAllocator

/// TURN TCP relay client (RFC 5766 + RFC 6062).
///
/// Allocates a TCP relay endpoint on a TURN server.
/// The Mac holds the TURN control connection and keeps the allocation alive.
/// When a peer connects to the relay address, TURN notifies the Mac via
/// ConnectionAttempt indication; the Mac opens a data connection and the
/// bridge is established — the peer's WebSocket then flows through it.
actor TURNAllocator {

    // MARK: - Types

    enum AllocatorStatus: Equatable, Sendable {
        case idle
        case allocating
        case allocated(relayEndpoint: String)
        case failed(String)
    }

    // MARK: - Public state

    private(set) var status: AllocatorStatus = .idle

    // MARK: - Configuration

    private var config: TURNConfig?

    // MARK: - Control connection

    private var controlConn: NWConnection?
    private var controlBuffer = Data()

    // MARK: - Auth state (populated from the server's 401 challenge)

    private var realm: String?
    private var nonce: String?
    private var authKey: Data?

    // MARK: - Allocation result

    private var relayEndpoint: String?

    // MARK: - Refresh

    private var refreshTask: Task<Void, Never>?

    // MARK: - Data connections awaiting bind

    private var pendingDataConnections: [UInt32: NWConnection] = [:]

    /// Called when a TURN data connection is fully established (bridged to
    /// the peer). The caller can layer WebSocket framing on top.
    var onDataConnection: (@Sendable (NWConnection) -> Void)?

    // MARK: - STUN constants

    static let magicCookie: UInt32 = 0x2112_A442
    private static let stunHeaderSize = 20

    // STUN message types
    private static let allocateRequest:   UInt16 = 0x0003
    private static let allocateSuccess:   UInt16 = 0x0103
    private static let allocateError:     UInt16 = 0x0113
    private static let refreshRequest:    UInt16 = 0x0004
    private static let refreshSuccess:    UInt16 = 0x0104
    private static let connectRequest:    UInt16 = 0x000A
    private static let connectSuccess:    UInt16 = 0x010A
    private static let connectionBind:    UInt16 = 0x000B
    private static let connectionBindOK:  UInt16 = 0x010B
    private static let connectionAttempt: UInt16 = 0x0019  // RFC 6062 indication

    // STUN attribute types
    private static let attrMappedAddress:      UInt16 = 0x0001
    private static let attrUsername:           UInt16 = 0x0006
    private static let attrMessageIntegrity:   UInt16 = 0x0008
    private static let attrErrorCode:          UInt16 = 0x0009
    private static let attrLifetime:           UInt16 = 0x000D
    private static let attrRealm:              UInt16 = 0x0014
    private static let attrNonce:              UInt16 = 0x0015
    private static let attrXorRelayedAddress:  UInt16 = 0x0016
    private static let attrRequestedTransport: UInt16 = 0x0019
    private static let attrXorMappedAddress:   UInt16 = 0x0020
    private static let attrConnectionID:       UInt16 = 0x002A

    // MARK: - Public API

    /// Allocate a TCP relay address on the TURN server.
    /// Returns the relay endpoint as "host:port" suitable for embedding in invites.
    func allocate(config: TURNConfig) async throws -> String {
        self.config = config
        status = .allocating

        let (host, port) = try Self.parseURL(config.url)
        logger.info("Connecting to TURN server \(host):\(port)")

        // Open TCP control connection
        let conn = try await openTCPConnection(host: host, port: port)
        self.controlConn = conn

        // Phase 1: unauthenticated Allocate — expect 401
        let txID1 = Self.randomTransactionID()
        let unauthReq = Self.buildAllocateRequest(transactionID: txID1, auth: nil)
        try await sendMessage(conn: conn, data: unauthReq)

        let response1 = try await readSTUNMessage(conn: conn)
        let (type1, _, attrs1) = try Self.parseSTUNMessage(response1)

        guard type1 == Self.allocateError else {
            // Some servers might succeed without auth — handle that
            if type1 == Self.allocateSuccess {
                let relay = try Self.extractRelayAddress(attrs1)
                self.relayEndpoint = relay
                status = .allocated(relayEndpoint: relay)
                startReadLoop(conn: conn)
                scheduleRefresh()
                logger.info("TURN allocation succeeded (no auth): relay=\(relay)")
                return relay
            }
            throw TURNError.unexpectedResponse(type1)
        }

        // Extract realm + nonce from the 401 error
        guard let realmVal = Self.extractStringAttribute(attrs1, type: Self.attrRealm),
              let nonceVal = Self.extractStringAttribute(attrs1, type: Self.attrNonce) else {
            throw TURNError.authenticationFailed
        }
        self.realm = realmVal
        self.nonce = nonceVal
        self.authKey = Self.computeAuthKey(
            username: config.username,
            realm: realmVal,
            password: config.credential
        )

        logger.debug("TURN 401 received, realm=\(realmVal), authenticating…")

        // Phase 2: authenticated Allocate
        let txID2 = Self.randomTransactionID()
        let auth = AuthContext(
            username: config.username,
            realm: realmVal,
            nonce: nonceVal,
            key: self.authKey!
        )
        let authReq = Self.buildAllocateRequest(transactionID: txID2, auth: auth)
        try await sendMessage(conn: conn, data: authReq)

        let response2 = try await readSTUNMessage(conn: conn)
        let (type2, _, attrs2) = try Self.parseSTUNMessage(response2)

        if type2 == Self.allocateError {
            let errMsg = Self.extractErrorCode(attrs2)
            throw TURNError.allocationFailed(errMsg.code, errMsg.reason)
        }
        guard type2 == Self.allocateSuccess else {
            throw TURNError.unexpectedResponse(type2)
        }

        let relay = try Self.extractRelayAddress(attrs2)
        self.relayEndpoint = relay
        status = .allocated(relayEndpoint: relay)

        // Start reading indications on the control connection
        startReadLoop(conn: conn)

        // Keep allocation alive
        scheduleRefresh()

        logger.info("TURN allocation succeeded: relay=\(relay)")
        return relay
    }

    /// Tear down the allocation and close all connections.
    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        controlConn?.cancel()
        controlConn = nil
        for conn in pendingDataConnections.values { conn.cancel() }
        pendingDataConnections.removeAll()
        status = .idle
        relayEndpoint = nil
        realm = nil
        nonce = nil
        authKey = nil
        controlBuffer = Data()
        logger.info("TURN allocator stopped")
    }

    // MARK: - TCP Connection Helpers

    /// Opens a TCP connection and waits until it is ready.
    private func openTCPConnection(host: String, port: UInt16) async throws -> NWConnection {
        let conn = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port) ?? NWEndpoint.Port(integerLiteral: 3478),
            using: .tcp
        )

        return try await withCheckedThrowingContinuation { continuation in
            let state = ConnectionState(continuation: continuation)
            let queue = DispatchQueue(label: "com.odyssey.turn.tcp")

            conn.stateUpdateHandler = { connState in
                switch connState {
                case .ready:
                    state.complete(with: .success(conn))
                case .failed(let err):
                    state.complete(with: .failure(
                        TURNError.connectionFailed(err.localizedDescription)
                    ))
                case .cancelled:
                    state.complete(with: .failure(
                        TURNError.connectionFailed("Connection cancelled")
                    ))
                default:
                    break
                }
            }
            conn.start(queue: queue)

            // Timeout
            queue.asyncAfter(deadline: .now() + 10) {
                conn.cancel()
                state.complete(with: .failure(TURNError.timeout))
            }
        }
    }

    /// Send raw data on a connection.
    private func sendMessage(conn: NWConnection, data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            conn.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    /// Read a complete STUN message from a TCP connection.
    /// STUN over TCP: messages are self-framing — read the 20-byte header
    /// to get message length, then read that many more bytes.
    private func readSTUNMessage(conn: NWConnection) async throws -> Data {
        // Read the 20-byte STUN header
        let header = try await readExact(conn: conn, count: Self.stunHeaderSize)

        // Extract message length from bytes 2-3
        let msgLen = Int(UInt16(header[2]) << 8 | UInt16(header[3]))

        if msgLen == 0 {
            return header
        }

        // Read the body
        let body = try await readExact(conn: conn, count: msgLen)
        return header + body
    }

    /// Read exactly `count` bytes from a connection.
    private func readExact(conn: NWConnection, count: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            conn.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, data.count == count {
                    continuation.resume(returning: data)
                } else if let data, data.count > 0 {
                    // We got a partial read — this shouldn't happen with
                    // minimumIncompleteLength == count, but handle it gracefully
                    // by returning what we have (caller may need to loop)
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: TURNError.truncatedMessage)
                }
            }
        }
    }

    // MARK: - Control Channel Read Loop

    /// Continuously read STUN messages from the control connection and
    /// dispatch ConnectionAttempt indications.
    private nonisolated func startReadLoop(conn: NWConnection) {
        readNextMessage(conn: conn)
    }

    private nonisolated func readNextMessage(conn: NWConnection) {
        conn.receive(minimumIncompleteLength: Self.stunHeaderSize, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self, let data, !data.isEmpty else {
                if isComplete {
                    logger.warning("TURN control connection closed by server")
                }
                if let error {
                    logger.error("TURN control read error: \(error.localizedDescription)")
                }
                return
            }

            Task { await self.handleControlData(data, conn: conn) }
        }
    }

    private func handleControlData(_ data: Data, conn: NWConnection) {
        controlBuffer.append(data)

        // Try to parse complete STUN messages from the buffer
        while controlBuffer.count >= Self.stunHeaderSize {
            let msgLen = Int(UInt16(controlBuffer[2]) << 8 | UInt16(controlBuffer[3]))
            let totalLen = Self.stunHeaderSize + msgLen

            guard controlBuffer.count >= totalLen else {
                break // Need more data
            }

            let message = controlBuffer.prefix(totalLen)
            controlBuffer.removeFirst(totalLen)

            do {
                let (type, _, attrs) = try Self.parseSTUNMessage(Data(message))
                handleSTUNMessage(type: type, attributes: attrs)
            } catch {
                logger.error("Failed to parse STUN message from control channel: \(error.localizedDescription)")
            }
        }

        // Continue reading
        readNextMessage(conn: conn)
    }

    private func handleSTUNMessage(type: UInt16, attributes: [STUNAttribute]) {
        switch type {
        case Self.connectionAttempt:
            handleConnectionAttempt(attributes: attributes)
        case Self.refreshSuccess:
            logger.debug("TURN refresh succeeded")
        default:
            logger.debug("TURN control: received message type 0x\(String(type, radix: 16))")
        }
    }

    // MARK: - ConnectionAttempt Handling (RFC 6062 Section 5.3)

    private func handleConnectionAttempt(attributes: [STUNAttribute]) {
        guard let connIDAttr = attributes.first(where: { $0.type == Self.attrConnectionID }),
              connIDAttr.value.count >= 4 else {
            logger.error("ConnectionAttempt missing CONNECTION-ID attribute")
            return
        }

        let connectionID = connIDAttr.value.withUnsafeBytes { buf in
            buf.load(as: UInt32.self).bigEndian
        }

        logger.info("ConnectionAttempt received, connectionID=\(connectionID)")

        guard let config = self.config else {
            logger.error("No TURN config available for data connection")
            return
        }

        // Open a new TCP connection to the TURN server and perform ConnectionBind
        Task {
            await establishDataConnection(connectionID: connectionID, config: config)
        }
    }

    /// Opens a new TCP connection to the TURN server, sends ConnectionBind,
    /// and hands the resulting bridged connection to the caller.
    private func establishDataConnection(connectionID: UInt32, config: TURNConfig) async {
        do {
            let (host, port) = try Self.parseURL(config.url)
            let dataConn = try await openTCPConnection(host: host, port: port)

            guard let realm = self.realm,
                  let nonce = self.nonce,
                  let authKey = self.authKey else {
                logger.error("Missing auth state for ConnectionBind")
                dataConn.cancel()
                return
            }

            let auth = AuthContext(
                username: config.username,
                realm: realm,
                nonce: nonce,
                key: authKey
            )

            // RFC 6062 §5.3: Send Connect request on the new data connection first
            let connectTxID = Self.randomTransactionID()
            let connectReq = Self.buildConnectRequest(
                transactionID: connectTxID,
                connectionID: connectionID,
                auth: auth
            )
            try await sendMessage(conn: dataConn, data: connectReq)

            let connectResp = try await readSTUNMessage(conn: dataConn)
            let (connectType, _, _) = try Self.parseSTUNMessage(connectResp)
            guard connectType == Self.connectSuccess else {
                logger.error("Connect failed, response type: 0x\(String(connectType, radix: 16))")
                dataConn.cancel()
                return
            }
            logger.debug("TURN Connect succeeded for connectionID=\(connectionID)")

            // Now send ConnectionBind to activate the data channel
            let bindTxID = Self.randomTransactionID()
            let bindReq = Self.buildConnectionBindRequest(
                transactionID: bindTxID,
                connectionID: connectionID,
                auth: auth
            )
            try await sendMessage(conn: dataConn, data: bindReq)

            // Read the response
            let response = try await readSTUNMessage(conn: dataConn)
            let (respType, _, _) = try Self.parseSTUNMessage(response)

            guard respType == Self.connectionBindOK else {
                logger.error("ConnectionBind failed, response type: 0x\(String(respType, radix: 16))")
                dataConn.cancel()
                return
            }

            logger.info("ConnectionBind succeeded for connectionID=\(connectionID)")

            // Hand the bridged connection to the caller
            onDataConnection?(dataConn)

        } catch {
            logger.error("Failed to establish data connection: \(error.localizedDescription)")
        }
    }

    // MARK: - Refresh

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(540))
                guard !Task.isCancelled else { break }
                guard let self else { break }
                await self.sendRefresh()
            }
        }
    }

    private func sendRefresh() {
        guard let conn = controlConn,
              let config = self.config,
              let realm = self.realm,
              let nonce = self.nonce,
              let authKey = self.authKey else {
            logger.warning("Cannot refresh: missing connection or auth state")
            return
        }

        let auth = AuthContext(
            username: config.username,
            realm: realm,
            nonce: nonce,
            key: authKey
        )
        let txID = Self.randomTransactionID()
        let msg = Self.buildRefreshRequest(transactionID: txID, auth: auth)

        conn.send(content: msg, completion: .contentProcessed { error in
            if let error {
                logger.error("TURN refresh send failed: \(error.localizedDescription)")
            } else {
                logger.debug("TURN refresh sent")
            }
        })
    }

    // MARK: - STUN Message Building

    /// Auth context for authenticated STUN messages.
    private struct AuthContext {
        let username: String
        let realm: String
        let nonce: String
        let key: Data   // MD5(username:realm:password)
    }

    /// Parsed STUN attribute.
    private struct STUNAttribute {
        let type: UInt16
        let value: Data
    }

    /// Build a STUN message with the given type, transaction ID, and attributes.
    /// If `auth` is provided, USERNAME, REALM, NONCE, and MESSAGE-INTEGRITY are appended.
    private static func buildSTUNMessage(
        type: UInt16,
        transactionID: Data,
        attributes: [(UInt16, Data)],
        auth: AuthContext? = nil
    ) -> Data {
        precondition(transactionID.count == 12)

        var allAttrs = attributes
        if let auth {
            allAttrs.append((attrUsername, Data(auth.username.utf8)))
            allAttrs.append((attrRealm, Data(auth.realm.utf8)))
            allAttrs.append((attrNonce, Data(auth.nonce.utf8)))
        }

        // Build attribute bytes (without MESSAGE-INTEGRITY)
        var attrData = Data()
        for (attrType, value) in allAttrs {
            var paddedValue = value
            while paddedValue.count % 4 != 0 { paddedValue.append(0) }
            attrData += bigEndian16(attrType)
            attrData += bigEndian16(UInt16(value.count))
            attrData += paddedValue
        }

        if let auth {
            // Build the message up to this point (for HMAC computation)
            // MESSAGE-INTEGRITY attribute will be 24 bytes (4-byte header + 20-byte HMAC)
            let lengthWithMI = UInt16(attrData.count + 24)
            var msgForHMAC = Data()
            msgForHMAC += bigEndian16(type)
            msgForHMAC += bigEndian16(lengthWithMI)
            msgForHMAC += bigEndian32(magicCookie)
            msgForHMAC += transactionID
            msgForHMAC += attrData

            let hmac = computeHMACSHA1(key: auth.key, data: msgForHMAC)

            // Append MESSAGE-INTEGRITY attribute
            attrData += bigEndian16(attrMessageIntegrity)
            attrData += bigEndian16(20) // HMAC-SHA1 is 20 bytes
            attrData += hmac
        }

        // Final message
        var msg = Data()
        msg += bigEndian16(type)
        msg += bigEndian16(UInt16(attrData.count))
        msg += bigEndian32(magicCookie)
        msg += transactionID
        msg += attrData
        return msg
    }

    /// Build an Allocate Request (0x0003) with REQUESTED-TRANSPORT = TCP (6).
    private static func buildAllocateRequest(transactionID: Data, auth: AuthContext?) -> Data {
        // REQUESTED-TRANSPORT: protocol number 6 (TCP) + 3 reserved bytes
        let transport = Data([0x06, 0x00, 0x00, 0x00])

        // LIFETIME: 600 seconds
        var lifetime = Data()
        lifetime += bigEndian32(600)

        return buildSTUNMessage(
            type: allocateRequest,
            transactionID: transactionID,
            attributes: [
                (attrRequestedTransport, transport),
                (attrLifetime, lifetime),
            ],
            auth: auth
        )
    }

    /// Build a Refresh Request (0x0004) with LIFETIME = 600s.
    private static func buildRefreshRequest(transactionID: Data, auth: AuthContext) -> Data {
        var lifetime = Data()
        lifetime += bigEndian32(600)

        return buildSTUNMessage(
            type: refreshRequest,
            transactionID: transactionID,
            attributes: [(attrLifetime, lifetime)],
            auth: auth
        )
    }

    /// Build a Connect Request (RFC 6062, 0x000A) with CONNECTION-ID.
    /// This must be sent on the new data TCP connection before ConnectionBind.
    private static func buildConnectRequest(
        transactionID: Data,
        connectionID: UInt32,
        auth: AuthContext
    ) -> Data {
        var connID = Data()
        connID += bigEndian32(connectionID)

        return buildSTUNMessage(
            type: connectRequest,
            transactionID: transactionID,
            attributes: [(attrConnectionID, connID)],
            auth: auth
        )
    }

    /// Build a ConnectionBind Request (0x000B) with CONNECTION-ID.
    private static func buildConnectionBindRequest(
        transactionID: Data,
        connectionID: UInt32,
        auth: AuthContext
    ) -> Data {
        var connID = Data()
        connID += bigEndian32(connectionID)

        return buildSTUNMessage(
            type: connectionBind,
            transactionID: transactionID,
            attributes: [(attrConnectionID, connID)],
            auth: auth
        )
    }

    // MARK: - STUN Message Parsing

    /// Parse a raw STUN message into (type, transactionID, attributes).
    private static func parseSTUNMessage(_ data: Data) throws -> (UInt16, Data, [STUNAttribute]) {
        guard data.count >= stunHeaderSize else {
            throw TURNError.truncatedMessage
        }

        let msgType = UInt16(data[0]) << 8 | UInt16(data[1])
        let msgLen = Int(UInt16(data[2]) << 8 | UInt16(data[3]))

        let cookie = UInt32(data[4]) << 24 | UInt32(data[5]) << 16
                   | UInt32(data[6]) << 8  | UInt32(data[7])
        guard cookie == magicCookie else {
            throw TURNError.truncatedMessage // Bad magic cookie
        }

        let txID = data[8..<20]
        guard data.count >= stunHeaderSize + msgLen else {
            throw TURNError.truncatedMessage
        }

        // Parse attributes
        var attrs: [STUNAttribute] = []
        var offset = stunHeaderSize
        let end = stunHeaderSize + msgLen

        while offset + 4 <= end {
            let attrType = UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
            let attrLen = Int(UInt16(data[offset + 2]) << 8 | UInt16(data[offset + 3]))
            let valueStart = offset + 4

            guard valueStart + attrLen <= data.count else {
                throw TURNError.truncatedMessage
            }

            let value = data[valueStart..<(valueStart + attrLen)]
            attrs.append(STUNAttribute(type: attrType, value: Data(value)))

            // Advance past value + padding to 4-byte boundary
            offset = valueStart + ((attrLen + 3) & ~3)
        }

        return (msgType, Data(txID), attrs)
    }

    /// Extract a string value from attributes of the given type.
    private static func extractStringAttribute(_ attrs: [STUNAttribute], type: UInt16) -> String? {
        guard let attr = attrs.first(where: { $0.type == type }) else { return nil }
        return String(data: attr.value, encoding: .utf8)
    }

    /// Extract error code and reason from an ERROR-CODE attribute.
    private static func extractErrorCode(_ attrs: [STUNAttribute]) -> (code: UInt16, reason: String) {
        guard let attr = attrs.first(where: { $0.type == attrErrorCode }),
              attr.value.count >= 4 else {
            return (0, "Unknown error")
        }
        // Bytes 2-3: class (hundreds digit) in bits 0-2 of byte 2, number in byte 3
        let classVal = UInt16(attr.value[2] & 0x07)
        let number = UInt16(attr.value[3])
        let code = classVal * 100 + number
        let reason: String
        if attr.value.count > 4 {
            reason = String(data: attr.value[4...], encoding: .utf8) ?? "Unknown"
        } else {
            reason = "Error \(code)"
        }
        return (code, reason)
    }

    /// Extract the relay address from XOR-RELAYED-ADDRESS (0x0016).
    private static func extractRelayAddress(_ attrs: [STUNAttribute]) throws -> String {
        guard let attr = attrs.first(where: { $0.type == attrXorRelayedAddress }),
              attr.value.count >= 8 else {
            throw TURNError.noRelayAddress
        }
        return parseXORAddress(attr.value)
    }

    /// Parse an XOR-encoded address (XOR-MAPPED-ADDRESS / XOR-RELAYED-ADDRESS).
    /// Format: reserved(1) | family(1) | xor-port(2) | xor-ip(4 for IPv4)
    private static func parseXORAddress(_ data: Data) -> String {
        let family = data[1]
        guard family == 0x01, data.count >= 8 else {
            return "0.0.0.0:0" // Only IPv4 supported
        }

        let xorPort = UInt16(data[2]) << 8 | UInt16(data[3])
        let port = xorPort ^ UInt16(magicCookie >> 16)

        let xorAddr = UInt32(data[4]) << 24 | UInt32(data[5]) << 16
                    | UInt32(data[6]) << 8  | UInt32(data[7])
        let addr = xorAddr ^ magicCookie

        let ip = "\((addr >> 24) & 0xFF).\((addr >> 16) & 0xFF).\((addr >> 8) & 0xFF).\(addr & 0xFF)"
        return "\(ip):\(port)"
    }

    // MARK: - Cryptographic Helpers

    /// Compute the long-term credential auth key: MD5(username:realm:password).
    private static func computeAuthKey(username: String, realm: String, password: String) -> Data {
        let input = "\(username):\(realm):\(password)"
        let inputData = Data(input.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        inputData.withUnsafeBytes { buf in
            _ = CC_MD5(buf.baseAddress, CC_LONG(inputData.count), &digest)
        }
        return Data(digest)
    }

    /// Compute HMAC-SHA1 over `data` using `key`.
    private static func computeHMACSHA1(key: Data, data: Data) -> Data {
        var hmac = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        key.withUnsafeBytes { keyBuf in
            data.withUnsafeBytes { dataBuf in
                CCHmac(
                    CCHmacAlgorithm(kCCHmacAlgSHA1),
                    keyBuf.baseAddress, key.count,
                    dataBuf.baseAddress, data.count,
                    &hmac
                )
            }
        }
        return Data(hmac)
    }

    // MARK: - Transaction ID

    /// Generate a random 12-byte STUN transaction ID.
    static func randomTransactionID() -> Data {
        var bytes = [UInt8](repeating: 0, count: 12)
        for i in 0..<12 { bytes[i] = UInt8.random(in: 0...255) }
        return Data(bytes)
    }

    // MARK: - URL Parsing

    /// Parse a TURN server URL of the form "turn:host:port" or "host:port" or "host".
    static func parseURL(_ url: String) throws -> (host: String, port: UInt16) {
        var cleaned = url
        // Strip turn: or turns: prefix
        if cleaned.hasPrefix("turn:") {
            cleaned = String(cleaned.dropFirst(5))
        } else if cleaned.hasPrefix("turns:") {
            cleaned = String(cleaned.dropFirst(6))
        }
        // Strip any leading //
        if cleaned.hasPrefix("//") {
            cleaned = String(cleaned.dropFirst(2))
        }
        // Strip query parameters
        if let qIdx = cleaned.firstIndex(of: "?") {
            cleaned = String(cleaned[..<qIdx])
        }

        let parts = cleaned.split(separator: ":").map(String.init)
        if parts.count == 2, let port = UInt16(parts[1]) {
            return (parts[0], port)
        } else if parts.count == 1 {
            return (parts[0], 3478) // Default TURN port
        }
        throw TURNError.invalidURL(url)
    }

    // MARK: - Binary Helpers

    private static func bigEndian16(_ value: UInt16) -> Data {
        var data = Data(count: 2)
        data[0] = UInt8(value >> 8)
        data[1] = UInt8(value & 0xFF)
        return data
    }

    private static func bigEndian32(_ value: UInt32) -> Data {
        var data = Data(count: 4)
        data[0] = UInt8((value >> 24) & 0xFF)
        data[1] = UInt8((value >> 16) & 0xFF)
        data[2] = UInt8((value >> 8) & 0xFF)
        data[3] = UInt8(value & 0xFF)
        return data
    }
}

// MARK: - Connection State (thread-safe continuation guard)

private final class ConnectionState<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false
    private let continuation: CheckedContinuation<T, Error>

    init(continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func complete(with result: Result<T, Error>) {
        lock.lock()
        let shouldResume = !resumed
        resumed = true
        lock.unlock()
        guard shouldResume else { return }
        continuation.resume(with: result)
    }
}
