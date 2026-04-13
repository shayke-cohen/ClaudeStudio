# Phase 2 — Cross-Network Discovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable iOS devices to discover and connect to the Mac sidecar over LAN and WAN via STUN + signed invite codes.

**Architecture:** NATTraversalManager uses raw UDP NWConnection to query public STUN servers and attempt hole-punch. InviteCodeGenerator bundles all connection credentials (TLS cert, bearer token, hints) into a signed, expiring base64url payload that travels as a QR code or deep link.

**Tech Stack:** Network.framework (NWConnection UDP), CryptoKit (Ed25519 verify), CoreImage (QR generation), JSONSerialization (canonical JSON), Phase 1 IdentityManager

---

## Prerequisites

Phase 1 (TLS + Bearer Token Auth) must be complete. This plan assumes the following APIs are available:

- `IdentityManager.shared.wsToken(for instanceName: String) -> Data` — returns the current bearer token bytes for the instance
- `IdentityManager.shared.sign(_ data: Data, instanceName: String) throws -> Data` — Ed25519 signature over arbitrary bytes
- `IdentityManager.shared.tlsCertificate(for instanceName: String) -> SecCertificate?` — the self-signed TLS cert
- `IdentityManager.shared.userIdentity(for instanceName: String) -> (publicKey: Data, displayName: String)?` — Ed25519 public key + user display name
- `IdentityManager.shared.rotateWSToken(for instanceName: String) async throws` — invalidates and rotates the bearer token

---

## File Structure

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `Odyssey/Services/NATTraversalManager.swift` | STUN Binding Request, XOR-MAPPED-ADDRESS parsing, UDP hole-punch |
| Create | `Odyssey/Services/InviteCodeGenerator.swift` | `InvitePayload` / `InviteHints` / `TURNConfig` types, generate / encode / decode / verify / qrCode |
| Create | `Odyssey/Views/Settings/iOSPairingSettingsView.swift` | QR code display, copy link, device list, revoke |
| Modify | `Odyssey/Services/P2PNetworkManager.swift` | Inject `wan=<ip>:<port>` into Bonjour TXT record |
| Modify | `Odyssey/Models/SharedRoomInvite.swift` | Add `signedPayloadJSON` and `pairingType` fields |
| Modify | `Odyssey/App/LaunchIntent.swift` | Add `.connectInvite` case to `LaunchMode` + `fromURL` handler for `odyssey://connect?invite=` |
| Modify | `Odyssey/Views/Settings/SettingsView.swift` | Add `.iosPairing` section to `SettingsSection` enum |
| Create | `OdysseyTests/NATTraversalTests.swift` | STUN encoding + response parsing unit tests |
| Create | `OdysseyTests/InviteCodeTests.swift` | Invite roundtrip, expiry, tampering, QR code, deep link tests |

---

## Task 1: NATTraversalManager — STUN Discovery and UDP Hole-Punch

**Files:**
- Create: `Odyssey/Services/NATTraversalManager.swift`

### Background: RFC 5389 STUN Binding Request

A STUN Binding Request is a 20-byte UDP datagram:

```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|0 0|  Message Type (0x0001)  |       Message Length (0x0000) |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                  Magic Cookie (0x2112A442)                     |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                Transaction ID (96 bits / 12 bytes, random)    |
|                                                               |
|                                                               |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

The response XOR-MAPPED-ADDRESS attribute (type 0x0020) encodes:
- Port: `networkPort ^ 0x2112`  (XOR with high 16 bits of magic cookie)
- IPv4 address: each byte XORed with the corresponding byte of `0x2112A442`

- [ ] **Step 1: Create `Odyssey/Services/NATTraversalManager.swift`**

```swift
// Odyssey/Services/NATTraversalManager.swift
import Foundation
import Network
import OSLog

private let logger = Logger(subsystem: "com.odyssey.app", category: "NATTraversal")

/// Discovers the machine's public WAN endpoint via STUN (RFC 5389) and
/// optionally attempts UDP hole-punching to a remote peer.
@MainActor
final class NATTraversalManager: ObservableObject {

    // MARK: - Published State

    /// The discovered public endpoint, e.g. "203.0.113.5:9849", or nil.
    @Published var publicEndpoint: String? = nil

    @Published var stunStatus: STUNStatus = .idle

    enum STUNStatus: Equatable {
        case idle
        case discovering
        case success
        case failed(String)
    }

    // MARK: - Constants

    private static let stunHost = "stun.l.google.com"
    private static let stunPort: UInt16 = 19302
    static let magicCookie: UInt32 = 0x2112_A442

    // MARK: - STUN Discovery

    /// Sends a STUN Binding Request over UDP to stun.l.google.com:19302 and
    /// parses the XOR-MAPPED-ADDRESS (or MAPPED-ADDRESS) from the response.
    ///
    /// - Parameter localPort: The UDP local port to bind (should match the sidecar WS port).
    func discoverPublicEndpoint(localPort: Int) async {
        stunStatus = .discovering
        publicEndpoint = nil

        do {
            let endpoint = try await Self.performSTUNRequest(localPort: localPort)
            publicEndpoint = endpoint
            stunStatus = .success
            logger.info("STUN discovery succeeded: \(endpoint)")
        } catch {
            stunStatus = .failed(error.localizedDescription)
            logger.error("STUN discovery failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Hole-Punch

    /// Attempts UDP hole-punch to the peer's public endpoint by sending
    /// small keepalive packets and waiting for a reply.
    ///
    /// - Parameters:
    ///   - peerEndpoint: "ip:port" string of the remote peer.
    ///   - localPort: UDP local port to bind.
    /// - Returns: A ready `NWConnection` on success, or `nil` on failure.
    func holePunch(to peerEndpoint: String, localPort: Int) async -> NWConnection? {
        guard let (host, port) = Self.parseEndpoint(peerEndpoint) else {
            logger.error("holePunch: cannot parse endpoint '\(peerEndpoint)'")
            return nil
        }

        let params = NWParameters.udp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host("0.0.0.0"),
            port: NWEndpoint.Port(rawValue: UInt16(localPort)) ?? 0
        )
        let conn = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port) ?? NWEndpoint.Port(integerLiteral: 9849),
            using: params
        )

        return await withCheckedContinuation { continuation in
            var resumed = false
            let queue = DispatchQueue(label: "com.odyssey.p2p.holepunch")

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    // Send a small ping payload
                    let ping = Data("ODYSSEY-PUNCH".utf8)
                    conn.send(content: ping, completion: .contentProcessed { _ in })
                    // Wait briefly for a reply
                    conn.receive(minimumIncompleteLength: 1, maximumLength: 64) { _, _, _, _ in
                        guard !resumed else { return }
                        resumed = true
                        continuation.resume(returning: conn)
                    }
                    // Timeout after 3 seconds
                    queue.asyncAfter(deadline: .now() + 3) {
                        guard !resumed else { return }
                        resumed = true
                        conn.cancel()
                        continuation.resume(returning: nil)
                    }
                case .failed:
                    guard !resumed else { return }
                    resumed = true
                    continuation.resume(returning: nil)
                default:
                    break
                }
            }
            conn.start(queue: queue)
        }
    }

    // MARK: - Internal STUN Implementation

    static func performSTUNRequest(localPort: Int) async throws -> String {
        let txID = Self.randomTransactionID()
        let request = Self.buildBindingRequest(transactionID: txID)

        return try await withCheckedThrowingContinuation { continuation in
            let state = STUNState(transactionID: txID, continuation: continuation)
            let fetch = STUNFetch(localPort: localPort, request: request, state: state)
            fetch.start()
        }
    }

    /// Builds the 20-byte STUN Binding Request header (RFC 5389 §6).
    static func buildBindingRequest(transactionID: Data) -> Data {
        precondition(transactionID.count == 12)
        var buf = Data(count: 20)
        // Message Type: Binding Request = 0x0001
        buf[0] = 0x00
        buf[1] = 0x01
        // Message Length: 0 (no attributes)
        buf[2] = 0x00
        buf[3] = 0x00
        // Magic Cookie: 0x2112A442
        buf[4] = 0x21
        buf[5] = 0x12
        buf[6] = 0xA4
        buf[7] = 0x42
        // Transaction ID (12 bytes)
        buf.replaceSubrange(8..<20, with: transactionID)
        return buf
    }

    /// Generates 12 cryptographically random bytes for a STUN transaction ID.
    static func randomTransactionID() -> Data {
        var bytes = [UInt8](repeating: 0, count: 12)
        for i in 0..<12 { bytes[i] = UInt8.random(in: 0...255) }
        return Data(bytes)
    }

    /// Parses a STUN Binding Response, returning "ip:port" from XOR-MAPPED-ADDRESS (0x0020)
    /// or MAPPED-ADDRESS (0x0001) if the former is absent.
    ///
    /// - Parameter data: Raw UDP datagram bytes from the STUN server.
    /// - Returns: "ip:port" string.
    /// - Throws: `STUNError` if the response is malformed or no address attribute is found.
    static func parseBindingResponse(_ data: Data) throws -> String {
        guard data.count >= 20 else { throw STUNError.truncatedResponse }

        // Verify message type: Binding Success Response = 0x0101
        let msgType = (UInt16(data[0]) << 8) | UInt16(data[1])
        guard msgType == 0x0101 else { throw STUNError.unexpectedMessageType(msgType) }

        // Verify magic cookie
        let cookie = (UInt32(data[4]) << 24) | (UInt32(data[5]) << 16)
                   | (UInt32(data[6]) << 8)  |  UInt32(data[7])
        guard cookie == magicCookie else { throw STUNError.badMagicCookie }

        let messageLength = Int((UInt16(data[2]) << 8) | UInt16(data[3]))
        guard data.count >= 20 + messageLength else { throw STUNError.truncatedResponse }

        // Walk attributes
        var offset = 20
        var xorMapped: String? = nil
        var mapped: String? = nil

        while offset + 4 <= 20 + messageLength {
            let attrType = (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
            let attrLen  = Int((UInt16(data[offset + 2]) << 8) | UInt16(data[offset + 3]))
            let valueStart = offset + 4
            guard valueStart + attrLen <= data.count else { throw STUNError.truncatedResponse }

            switch attrType {
            case 0x0020: // XOR-MAPPED-ADDRESS
                xorMapped = try parseXORMappedAddress(data, at: valueStart)
            case 0x0001: // MAPPED-ADDRESS
                mapped = try parseMappedAddress(data, at: valueStart)
            default:
                break
            }
            // Attributes are padded to 4-byte boundary
            offset = valueStart + ((attrLen + 3) & ~3)
        }

        if let addr = xorMapped { return addr }
        if let addr = mapped { return addr }
        throw STUNError.noAddressAttribute
    }

    // MARK: - Attribute Parsers

    /// Parses XOR-MAPPED-ADDRESS (RFC 5389 §15.2).
    static func parseXORMappedAddress(_ data: Data, at offset: Int) throws -> String {
        // Layout: 1 byte reserved, 1 byte family, 2 bytes XOR'd port, 4 bytes XOR'd addr (IPv4)
        guard offset + 8 <= data.count else { throw STUNError.truncatedResponse }
        let family = data[offset + 1]
        guard family == 0x01 else { throw STUNError.unsupportedAddressFamily(family) } // IPv4 only

        let xorPort = (UInt16(data[offset + 2]) << 8) | UInt16(data[offset + 3])
        let port = xorPort ^ UInt16(magicCookie >> 16)  // XOR with high 16 bits of magic

        let xorAddr = (UInt32(data[offset + 4]) << 24)
                    | (UInt32(data[offset + 5]) << 16)
                    | (UInt32(data[offset + 6]) << 8)
                    |  UInt32(data[offset + 7])
        let addr = xorAddr ^ magicCookie

        let ip = "\((addr >> 24) & 0xFF).\((addr >> 16) & 0xFF).\((addr >> 8) & 0xFF).\(addr & 0xFF)"
        return "\(ip):\(port)"
    }

    /// Parses MAPPED-ADDRESS (RFC 5389 §15.1) — no XOR, plain big-endian values.
    static func parseMappedAddress(_ data: Data, at offset: Int) throws -> String {
        guard offset + 8 <= data.count else { throw STUNError.truncatedResponse }
        let family = data[offset + 1]
        guard family == 0x01 else { throw STUNError.unsupportedAddressFamily(family) }

        let port = (UInt16(data[offset + 2]) << 8) | UInt16(data[offset + 3])
        let a0 = data[offset + 4], a1 = data[offset + 5]
        let a2 = data[offset + 6], a3 = data[offset + 7]
        return "\(a0).\(a1).\(a2).\(a3):\(port)"
    }

    // MARK: - Helpers

    static func parseEndpoint(_ endpoint: String) -> (host: String, port: UInt16)? {
        // Handle both "ip:port" and bare "ip"
        let parts = endpoint.split(separator: ":").map(String.init)
        guard parts.count == 2, let port = UInt16(parts[1]) else { return nil }
        return (parts[0], port)
    }
}

// MARK: - STUN Errors

enum STUNError: LocalizedError {
    case truncatedResponse
    case unexpectedMessageType(UInt16)
    case badMagicCookie
    case unsupportedAddressFamily(UInt8)
    case noAddressAttribute
    case timeout

    var errorDescription: String? {
        switch self {
        case .truncatedResponse:          return "STUN response was truncated."
        case .unexpectedMessageType(let t): return "Unexpected STUN message type: 0x\(String(t, radix: 16))."
        case .badMagicCookie:             return "STUN magic cookie mismatch."
        case .unsupportedAddressFamily(let f): return "Unsupported address family: \(f). Only IPv4 is supported."
        case .noAddressAttribute:         return "STUN response contained no address attribute."
        case .timeout:                    return "STUN server did not respond in time."
        }
    }
}

// MARK: - STUN UDP Fetch (NWConnection wrapper)

private final class STUNState: @unchecked Sendable {
    let transactionID: Data
    private let lock = NSLock()
    private var resumed = false
    private let continuation: CheckedContinuation<String, Error>

    init(transactionID: Data, continuation: CheckedContinuation<String, Error>) {
        self.transactionID = transactionID
        self.continuation = continuation
    }

    func complete(with result: Result<String, Error>, conn: NWConnection) {
        lock.lock()
        let shouldResume = !resumed
        resumed = true
        lock.unlock()
        guard shouldResume else { return }
        conn.cancel()
        switch result {
        case .success(let addr): continuation.resume(returning: addr)
        case .failure(let err):  continuation.resume(throwing: err)
        }
    }
}

private final class STUNFetch: Sendable {
    private let conn: NWConnection
    private let state: STUNState
    private let queue = DispatchQueue(label: "com.odyssey.p2p.stun")

    init(localPort: Int, request: Data, state: STUNState) {
        let params = NWParameters.udp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host("0.0.0.0"),
            port: NWEndpoint.Port(rawValue: UInt16(localPort)) ?? 0
        )
        self.conn = NWConnection(
            host: NWEndpoint.Host(NATTraversalManager.stunHost),
            port: NWEndpoint.Port(rawValue: NATTraversalManager.stunPort)!,
            using: params
        )
        self.state = state
        // Keep request data accessible via closure capture
        let req = request
        let s = state
        let c = conn
        let q = queue
        conn.stateUpdateHandler = { connState in
            switch connState {
            case .ready:
                c.send(content: req, completion: .contentProcessed { err in
                    if let err { s.complete(with: .failure(err), conn: c); return }
                    c.receive(minimumIncompleteLength: 20, maximumLength: 512) { data, _, _, error in
                        if let error { s.complete(with: .failure(error), conn: c); return }
                        guard let data else { s.complete(with: .failure(STUNError.truncatedResponse), conn: c); return }
                        do {
                            let addr = try NATTraversalManager.parseBindingResponse(data)
                            s.complete(with: .success(addr), conn: c)
                        } catch {
                            s.complete(with: .failure(error), conn: c)
                        }
                    }
                })
            case .failed(let err):
                s.complete(with: .failure(err), conn: c)
            default:
                break
            }
        }
        // Timeout
        q.asyncAfter(deadline: .now() + 5) {
            s.complete(with: .failure(STUNError.timeout), conn: c)
        }
    }

    func start() {
        conn.start(queue: queue)
    }
}
```

- [ ] **Step 2: Run `xcodegen generate` to register the new file**

```bash
cd /Users/shayco/Odyssey && xcodegen generate
```

---

## Task 2: NATTraversalManager Tests

**Files:**
- Create: `OdysseyTests/NATTraversalTests.swift`

- [ ] **Step 1: Create `OdysseyTests/NATTraversalTests.swift`**

```swift
// OdysseyTests/NATTraversalTests.swift
import XCTest
@testable import Odyssey

final class NATTraversalTests: XCTestCase {

    // MARK: - STUN Request Encoding

    func testSTUNRequestEncoding() {
        // A known 12-byte transaction ID
        let txID = Data([
            0x01, 0x02, 0x03, 0x04,
            0x05, 0x06, 0x07, 0x08,
            0x09, 0x0A, 0x0B, 0x0C
        ])
        let request = NATTraversalManager.buildBindingRequest(transactionID: txID)

        XCTAssertEqual(request.count, 20, "STUN Binding Request must be exactly 20 bytes")

        // Bytes 0–1: Message Type = Binding Request (0x0001)
        XCTAssertEqual(request[0], 0x00)
        XCTAssertEqual(request[1], 0x01)

        // Bytes 2–3: Message Length = 0x0000 (no attributes)
        XCTAssertEqual(request[2], 0x00)
        XCTAssertEqual(request[3], 0x00)

        // Bytes 4–7: Magic Cookie = 0x2112A442
        XCTAssertEqual(request[4], 0x21)
        XCTAssertEqual(request[5], 0x12)
        XCTAssertEqual(request[6], 0xA4)
        XCTAssertEqual(request[7], 0x42)

        // Bytes 8–19: Transaction ID verbatim
        XCTAssertEqual(Array(request[8..<20]), [
            0x01, 0x02, 0x03, 0x04,
            0x05, 0x06, 0x07, 0x08,
            0x09, 0x0A, 0x0B, 0x0C
        ])
    }

    // MARK: - STUN Response Parsing

    /// Builds a minimal synthetic STUN Binding Success Response with a
    /// single XOR-MAPPED-ADDRESS attribute for 203.0.113.5:9849.
    private func syntheticXORMappedResponse(ip: UInt32, port: UInt16) -> Data {
        let magic: UInt32 = NATTraversalManager.magicCookie

        // XOR the port with high 16 bits of magic cookie
        let xorPort = port ^ UInt16(magic >> 16)
        // XOR the address with the magic cookie
        let xorAddr = ip ^ magic

        // XOR-MAPPED-ADDRESS attribute value: 8 bytes
        // [reserved=0x00, family=0x01, xorPort(2), xorAddr(4)]
        var attrValue = Data(count: 8)
        attrValue[0] = 0x00
        attrValue[1] = 0x01
        attrValue[2] = UInt8(xorPort >> 8)
        attrValue[3] = UInt8(xorPort & 0xFF)
        attrValue[4] = UInt8((xorAddr >> 24) & 0xFF)
        attrValue[5] = UInt8((xorAddr >> 16) & 0xFF)
        attrValue[6] = UInt8((xorAddr >>  8) & 0xFF)
        attrValue[7] = UInt8( xorAddr        & 0xFF)

        // Attribute header: type=0x0020, length=8
        var attrHeader = Data(count: 4)
        attrHeader[0] = 0x00; attrHeader[1] = 0x20
        attrHeader[2] = 0x00; attrHeader[3] = 0x08

        let attrTotal = attrHeader + attrValue  // 12 bytes

        // STUN message header: type=0x0101 (Binding Success), length=12
        var header = Data(count: 20)
        header[0] = 0x01; header[1] = 0x01
        header[2] = 0x00; header[3] = 0x0C   // length = 12
        header[4] = 0x21; header[5] = 0x12; header[6] = 0xA4; header[7] = 0x42  // magic
        // Transaction ID (arbitrary for this test)
        for i in 8..<20 { header[i] = 0x00 }

        return header + attrTotal
    }

    func testSTUNResponseParsing() throws {
        // 203.0.113.5 = 0xCB007105, port 9849 = 0x2679
        let ip: UInt32 = 0xCB00_7105
        let port: UInt16 = 9849
        let response = syntheticXORMappedResponse(ip: ip, port: port)

        let result = try NATTraversalManager.parseBindingResponse(response)
        XCTAssertEqual(result, "203.0.113.5:9849")
    }

    func testXORMappedAddressIPv4() throws {
        // Verify the XOR arithmetic for port 0x2679 (9849) independently.
        // 0x2679 ^ 0x2112 = 0x076B = 1899? No — magic high 16 = 0x2112.
        // 0x2679 ^ 0x2112 = 0x076B = 1899. Let's verify the inverse is consistent.
        let magic: UInt32 = NATTraversalManager.magicCookie
        let rawPort: UInt16 = 0x2679  // 9849
        let xorPort = rawPort ^ UInt16(magic >> 16)  // ^ 0x2112

        // Build a minimal XOR-MAPPED-ADDRESS value blob directly and parse it.
        let xorAddr: UInt32 = 0x00000000 ^ magic  // ip=0.0.0.0 for simplicity

        var attrValue = Data(count: 8)
        attrValue[0] = 0x00; attrValue[1] = 0x01  // reserved, family IPv4
        attrValue[2] = UInt8(xorPort >> 8); attrValue[3] = UInt8(xorPort & 0xFF)
        attrValue[4] = UInt8((xorAddr >> 24) & 0xFF)
        attrValue[5] = UInt8((xorAddr >> 16) & 0xFF)
        attrValue[6] = UInt8((xorAddr >>  8) & 0xFF)
        attrValue[7] = UInt8( xorAddr        & 0xFF)

        var buf = Data(count: 8)
        buf.replaceSubrange(0..<8, with: attrValue)
        let result = try NATTraversalManager.parseXORMappedAddress(buf, at: 0)

        // Port round-trips correctly
        let parts = result.split(separator: ":")
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(UInt16(parts[1]), rawPort, "Port must survive XOR round-trip")
    }

    func testParseEndpointValid() {
        let result = NATTraversalManager.parseEndpoint("203.0.113.5:9849")
        XCTAssertEqual(result?.host, "203.0.113.5")
        XCTAssertEqual(result?.port, 9849)
    }

    func testParseEndpointInvalid() {
        XCTAssertNil(NATTraversalManager.parseEndpoint("notanendpoint"))
        XCTAssertNil(NATTraversalManager.parseEndpoint("192.168.1.1:notaport"))
    }

    func testTruncatedResponseThrows() {
        let shortData = Data([0x01, 0x01])  // way too short
        XCTAssertThrowsError(try NATTraversalManager.parseBindingResponse(shortData))
    }

    func testBadMagicCookieThrows() {
        var data = Data(count: 20)
        data[0] = 0x01; data[1] = 0x01  // Binding Success
        data[2] = 0x00; data[3] = 0x00  // length=0
        // Wrong magic: 0xDEADBEEF
        data[4] = 0xDE; data[5] = 0xAD; data[6] = 0xBE; data[7] = 0xEF
        XCTAssertThrowsError(try NATTraversalManager.parseBindingResponse(data)) { error in
            XCTAssertEqual(error as? STUNError, STUNError.badMagicCookie)
        }
    }
}

extension STUNError: Equatable {
    public static func == (lhs: STUNError, rhs: STUNError) -> Bool {
        switch (lhs, rhs) {
        case (.truncatedResponse, .truncatedResponse): return true
        case (.badMagicCookie, .badMagicCookie): return true
        case (.noAddressAttribute, .noAddressAttribute): return true
        case (.timeout, .timeout): return true
        case (.unexpectedMessageType(let a), .unexpectedMessageType(let b)): return a == b
        case (.unsupportedAddressFamily(let a), .unsupportedAddressFamily(let b)): return a == b
        default: return false
        }
    }
}
```

- [ ] **Step 2: Run tests**

```bash
cd /Users/shayco/Odyssey && xcodebuild test -scheme Odyssey -destination 'platform=macOS' -only-testing OdysseyTests/NATTraversalTests 2>&1 | tail -40
```

---

## Task 3: P2PNetworkManager — Inject WAN into Bonjour TXT Record

**Files:**
- Modify: `Odyssey/Services/P2PNetworkManager.swift`
- Modify: `Odyssey/Services/PeerCatalogServer.swift` (add TXT record `wan` field)

The Bonjour TXT record is set in `PeerCatalogServer`. Examine it first.

- [ ] **Step 1: Read `PeerCatalogServer.swift` to find TXT record construction**

```bash
grep -n "TXTRecord\|txtRecord\|txt\|wan\|bonjourTXT" /Users/shayco/Odyssey/Odyssey/Services/PeerCatalogServer.swift | head -30
```

- [ ] **Step 2: Add `publicWANEndpoint` property to `PeerCatalogServer`**

In `PeerCatalogServer.swift`, add a settable property that is included in the TXT record when non-nil:

```swift
/// When set, the Bonjour TXT record will include `wan=<ip>:<port>`.
var publicWANEndpoint: String? = nil {
    didSet { rebuildTXTRecord() }
}
```

Modify the TXT record builder method (or `start()`) to include `wan` when non-nil:

```swift
private func makeTXTRecord() -> [String: String] {
    var txt: [String: String] = [
        "port": "\(sidecarWsPort)"
        // add other existing fields here verbatim
    ]
    if let wan = publicWANEndpoint {
        txt["wan"] = wan
    }
    return txt
}
```

- [ ] **Step 3: Propagate `publicEndpoint` from `NATTraversalManager` to `PeerCatalogServer` via `P2PNetworkManager`**

In `P2PNetworkManager.swift`, add an `@ObservedObject`-style observer or a direct setter. Since both are `@MainActor`, a simple `didSet` sink works. Add a `NATTraversalManager` dependency:

```swift
// In P2PNetworkManager, add:
private let natManager = NATTraversalManager()
private var natCancellable: AnyCancellable?

// In init(), after server setup:
natCancellable = natManager.$publicEndpoint.sink { [weak self] endpoint in
    self?.server.publicWANEndpoint = endpoint
}
```

Add `import Combine` to `P2PNetworkManager.swift`.

- [ ] **Step 4: Trigger STUN discovery when P2P starts**

In `P2PNetworkManager.start()`, after `startBrowser()`:

```swift
Task {
    await natManager.discoverPublicEndpoint(localPort: server.sidecarWsPort)
}
```

- [ ] **Step 5: Expose `natManager` for the pairing UI**

Add a read-only accessor to `P2PNetworkManager`:

```swift
var natTraversalManager: NATTraversalManager { natManager }
```

- [ ] **Step 6: Run `xcodegen generate`**

```bash
cd /Users/shayco/Odyssey && xcodegen generate
```

---

## Task 4: InviteCodeGenerator — Types, Signing, QR Code

**Files:**
- Create: `Odyssey/Services/InviteCodeGenerator.swift`

### Canonical JSON and signing

The signature is computed over canonical JSON of all fields **except** `sig`, serialized with `JSONSerialization` using `.sortedKeys` to guarantee key ordering. The bytes are then signed with `IdentityManager.shared.sign(_:instanceName:)` (Ed25519).

### base64url encoding

Standard base64, but: `+` → `-`, `/` → `_`, strip `=` padding. Reverse on decode.

### QR Code via CoreImage

`CIFilter(name: "CIQRCodeGenerator")` produces a `CIImage`. Scale it up with `CIFilter(name: "CILanczosScaleTransform")` then convert to `CGImage` via `CIContext`.

- [ ] **Step 1: Create `Odyssey/Services/InviteCodeGenerator.swift`**

```swift
// Odyssey/Services/InviteCodeGenerator.swift
import Foundation
import CryptoKit
import CoreImage
import CoreGraphics
import OSLog

private let logger = Logger(subsystem: "com.odyssey.app", category: "InviteCode")

// MARK: - TURN Config

struct TURNConfig: Codable, Sendable, Equatable {
    let uri: String          // e.g. "turn:turn.metered.ca:443?transport=tcp"
    let username: String
    let credential: String
    var ttl: Date? = nil     // nil = non-rotating
}

// MARK: - Invite Payload Types

struct InviteHints: Codable, Sendable, Equatable {
    let lan: String?         // e.g. "192.168.1.5"
    let wan: String?         // e.g. "203.0.113.5:9849"
    let turn: TURNConfig?
}

struct InvitePayload: Codable, Sendable, Equatable {
    let v: Int               // schema version, currently 1
    let type: String         // "device" | "room" | "user"
    let userPublicKey: String   // base64 Ed25519 public key bytes
    let displayName: String
    let tlsCertDER: String      // base64 DER-encoded TLS certificate
    let wsToken: String         // base64 bearer token bytes
    let wsPort: Int
    let hints: InviteHints
    let exp: TimeInterval       // Unix timestamp (seconds since 1970)
    let singleUse: Bool
    var sig: String             // base64 Ed25519 signature; empty string before signing
}

// MARK: - Errors

enum InviteCodeError: LocalizedError, Equatable {
    case identityUnavailable
    case encodingFailed
    case decodingFailed(String)
    case signatureVerificationFailed
    case expired
    case certificateExportFailed

    var errorDescription: String? {
        switch self {
        case .identityUnavailable:        return "Device identity is not available. Ensure Phase 1 setup is complete."
        case .encodingFailed:             return "Failed to encode invite payload."
        case .decodingFailed(let reason): return "Failed to decode invite: \(reason)."
        case .signatureVerificationFailed: return "Invite signature verification failed."
        case .expired:                    return "This invite has expired."
        case .certificateExportFailed:    return "Could not export TLS certificate DER bytes."
        }
    }
}

// MARK: - InviteCodeGenerator

struct InviteCodeGenerator {

    // MARK: - Generate

    /// Generates a signed device invite payload.
    ///
    /// - Parameters:
    ///   - instanceName: The Odyssey instance name (used to resolve `IdentityManager` keys).
    ///   - expiresIn: Seconds from now until expiry. Default 300 (5 minutes).
    ///   - singleUse: If true, the invite should be invalidated after first use.
    ///   - lanHint: Local IP address, e.g. "192.168.1.5".
    ///   - wanHint: Public IP:port from STUN, e.g. "203.0.113.5:9849".
    ///   - turnConfig: Optional TURN relay credentials.
    /// - Returns: A signed `InvitePayload`.
    static func generateDevice(
        instanceName: String,
        expiresIn: TimeInterval = 300,
        singleUse: Bool = true,
        lanHint: String?,
        wanHint: String?,
        turnConfig: TURNConfig? = nil
    ) async throws -> InvitePayload {
        guard let identity = IdentityManager.shared.userIdentity(for: instanceName) else {
            throw InviteCodeError.identityUnavailable
        }

        let wsToken = IdentityManager.shared.wsToken(for: instanceName)
        guard !wsToken.isEmpty else { throw InviteCodeError.identityUnavailable }

        guard let cert = IdentityManager.shared.tlsCertificate(for: instanceName),
              let certDER = SecCertificateCopyData(cert) as Data?
        else {
            throw InviteCodeError.certificateExportFailed
        }

        let wsPort = InstanceConfig.wsPort

        let hints = InviteHints(lan: lanHint, wan: wanHint, turn: turnConfig)

        var payload = InvitePayload(
            v: 1,
            type: "device",
            userPublicKey: identity.publicKey.base64EncodedString(),
            displayName: identity.displayName,
            tlsCertDER: certDER.base64EncodedString(),
            wsToken: wsToken.base64EncodedString(),
            wsPort: wsPort,
            hints: hints,
            exp: Date().addingTimeInterval(expiresIn).timeIntervalSince1970,
            singleUse: singleUse,
            sig: ""
        )

        // Sign the canonical JSON of all fields except `sig`
        let sigBytes = try signPayload(payload, instanceName: instanceName)
        payload.sig = sigBytes.base64EncodedString()
        return payload
    }

    // MARK: - Encode / Decode

    /// Encodes a payload to a base64url string (URL-safe, no padding).
    static func encode(_ payload: InvitePayload) throws -> String {
        let data = try JSONEncoder().encode(payload)
        return base64urlEncode(data)
    }

    /// Decodes a base64url string to an `InvitePayload`.
    static func decode(_ base64url: String) throws -> InvitePayload {
        guard let data = base64urlDecode(base64url) else {
            throw InviteCodeError.decodingFailed("invalid base64url")
        }
        do {
            return try JSONDecoder().decode(InvitePayload.self, from: data)
        } catch {
            throw InviteCodeError.decodingFailed(error.localizedDescription)
        }
    }

    // MARK: - Verify

    /// Verifies the signature and checks expiry.
    ///
    /// - Throws: `InviteCodeError.expired` if `exp` is in the past.
    /// - Throws: `InviteCodeError.signatureVerificationFailed` if the signature is invalid.
    static func verify(_ payload: InvitePayload) throws {
        // 1. Check expiry
        if payload.exp < Date().timeIntervalSince1970 {
            throw InviteCodeError.expired
        }

        // 2. Reconstruct the signed bytes (canonical JSON without `sig`)
        let signedBytes = try canonicalJSONWithoutSig(payload)

        // 3. Decode the public key
        guard let pubKeyData = Data(base64Encoded: payload.userPublicKey),
              let curve25519PubKey = try? Curve25519.Signing.PublicKey(rawRepresentation: pubKeyData)
        else {
            throw InviteCodeError.signatureVerificationFailed
        }

        // 4. Decode the signature
        guard let sigData = Data(base64Encoded: payload.sig) else {
            throw InviteCodeError.signatureVerificationFailed
        }

        // 5. Verify
        guard curve25519PubKey.isValidSignature(sigData, for: signedBytes) else {
            throw InviteCodeError.signatureVerificationFailed
        }
    }

    // MARK: - QR Code

    /// Generates a QR code `CGImage` for the given payload.
    ///
    /// - Parameters:
    ///   - payload: The `InvitePayload` to encode.
    ///   - size: The desired output side length in points. Default 300.
    /// - Returns: A `CGImage`, or `nil` if generation fails.
    static func qrCode(for payload: InvitePayload, size: CGFloat = 300) -> CGImage? {
        guard let encoded = try? encode(payload),
              let inputData = "odyssey://connect?invite=\(encoded)".data(using: .utf8)
        else { return nil }

        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(inputData, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let ciImage = filter.outputImage else { return nil }

        // Scale to requested size
        let scaleX = size / ciImage.extent.width
        let scaleY = size / ciImage.extent.height
        let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        let context = CIContext()
        return context.createCGImage(scaledImage, from: scaledImage.extent)
    }

    // MARK: - Internal: Signing

    private static func signPayload(_ payload: InvitePayload, instanceName: String) throws -> Data {
        let bytes = try canonicalJSONWithoutSig(payload)
        return try IdentityManager.shared.sign(bytes, instanceName: instanceName)
    }

    /// Produces canonical JSON of the payload with all fields sorted alphabetically
    /// and the `sig` field excluded. Uses `JSONSerialization.sortedKeys`.
    static func canonicalJSONWithoutSig(_ payload: InvitePayload) throws -> Data {
        // Encode to JSON dict, remove `sig`, then re-serialize with sorted keys
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let fullData = try encoder.encode(payload)

        guard var dict = try JSONSerialization.jsonObject(with: fullData) as? [String: Any] else {
            throw InviteCodeError.encodingFailed
        }
        dict.removeValue(forKey: "sig")

        return try JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
    }

    // MARK: - Internal: base64url

    static func base64urlEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func base64urlDecode(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // Re-pad to multiple of 4
        let remainder = base64.count % 4
        if remainder > 0 { base64 += String(repeating: "=", count: 4 - remainder) }
        return Data(base64Encoded: base64)
    }
}
```

- [ ] **Step 2: Run `xcodegen generate`**

```bash
cd /Users/shayco/Odyssey && xcodegen generate
```

---

## Task 5: InviteCode Tests

**Files:**
- Create: `OdysseyTests/InviteCodeTests.swift`

These tests exercise the pure-Swift logic in `InviteCodeGenerator` without touching `IdentityManager` (mocked where needed). The `generate` path uses `IdentityManager`; for unit tests, we test encode/decode/verify with inline-generated keys.

- [ ] **Step 1: Create `OdysseyTests/InviteCodeTests.swift`**

```swift
// OdysseyTests/InviteCodeTests.swift
import XCTest
import CryptoKit
@testable import Odyssey

final class InviteCodeTests: XCTestCase {

    // MARK: - Helpers

    /// Builds a signed InvitePayload using a locally generated ephemeral Ed25519 key.
    private func makeSignedPayload(
        exp: TimeInterval? = nil,
        singleUse: Bool = true,
        displayName: String = "Test Mac"
    ) throws -> (payload: InvitePayload, privateKey: Curve25519.Signing.PrivateKey) {
        let key = Curve25519.Signing.PrivateKey()
        let pubKeyB64 = key.publicKey.rawRepresentation.base64EncodedString()

        var payload = InvitePayload(
            v: 1,
            type: "device",
            userPublicKey: pubKeyB64,
            displayName: displayName,
            tlsCertDER: Data([0x01, 0x02, 0x03]).base64EncodedString(),
            wsToken: Data([0xAA, 0xBB]).base64EncodedString(),
            wsPort: 9849,
            hints: InviteHints(lan: "192.168.1.5", wan: "203.0.113.5:9849", turn: nil),
            exp: exp ?? Date().addingTimeInterval(300).timeIntervalSince1970,
            singleUse: singleUse,
            sig: ""
        )

        let canonicalBytes = try InviteCodeGenerator.canonicalJSONWithoutSig(payload)
        let sig = try key.signature(for: canonicalBytes)
        payload.sig = sig.base64EncodedString()
        return (payload, key)
    }

    // MARK: - Round-trip

    func testDeviceInviteRoundTrip() throws {
        let (payload, _) = try makeSignedPayload()
        let encoded = try InviteCodeGenerator.encode(payload)
        let decoded = try InviteCodeGenerator.decode(encoded)
        XCTAssertNoThrow(try InviteCodeGenerator.verify(decoded))
        XCTAssertEqual(decoded.v, 1)
        XCTAssertEqual(decoded.type, "device")
        XCTAssertEqual(decoded.wsPort, 9849)
        XCTAssertEqual(decoded.hints.lan, "192.168.1.5")
        XCTAssertEqual(decoded.hints.wan, "203.0.113.5:9849")
        XCTAssertEqual(decoded.singleUse, true)
    }

    // MARK: - Expiry

    func testExpiredInviteRejected() throws {
        // exp = 60 seconds ago
        let (payload, _) = try makeSignedPayload(exp: Date().addingTimeInterval(-60).timeIntervalSince1970)
        XCTAssertThrowsError(try InviteCodeGenerator.verify(payload)) { error in
            XCTAssertEqual(error as? InviteCodeError, .expired)
        }
    }

    // MARK: - Tamper Detection

    func testTamperedInviteRejected() throws {
        var (payload, _) = try makeSignedPayload()
        payload = InvitePayload(
            v: payload.v,
            type: payload.type,
            userPublicKey: payload.userPublicKey,
            displayName: "EVIL HACKER",   // mutated after signing
            tlsCertDER: payload.tlsCertDER,
            wsToken: payload.wsToken,
            wsPort: payload.wsPort,
            hints: payload.hints,
            exp: payload.exp,
            singleUse: payload.singleUse,
            sig: payload.sig
        )
        XCTAssertThrowsError(try InviteCodeGenerator.verify(payload)) { error in
            XCTAssertEqual(error as? InviteCodeError, .signatureVerificationFailed)
        }
    }

    // MARK: - base64url Encoding

    func testBase64UrlEncoding() {
        // Generate data that would produce +, /, = in standard base64
        let data = Data([0xFB, 0xFF, 0xFE, 0xFD, 0xFC])
        let encoded = InviteCodeGenerator.base64urlEncode(data)
        XCTAssertFalse(encoded.contains("+"), "base64url must not contain '+'")
        XCTAssertFalse(encoded.contains("/"), "base64url must not contain '/'")
        XCTAssertFalse(encoded.contains("="), "base64url must not contain padding '='")

        let decoded = InviteCodeGenerator.base64urlDecode(encoded)
        XCTAssertEqual(decoded, data, "base64url roundtrip must be lossless")
    }

    func testBase64UrlRoundtripVariousLengths() {
        for length in [1, 2, 3, 4, 16, 31, 32, 33, 64, 100] {
            var bytes = [UInt8](repeating: 0, count: length)
            for i in 0..<length { bytes[i] = UInt8(i % 256) }
            let data = Data(bytes)
            let encoded = InviteCodeGenerator.base64urlEncode(data)
            XCTAssertEqual(InviteCodeGenerator.base64urlDecode(encoded), data,
                           "Roundtrip failed for length \(length)")
        }
    }

    // MARK: - QR Code

    func testQRCodeProducesValidImage() throws {
        let (payload, _) = try makeSignedPayload()
        let cgImage = InviteCodeGenerator.qrCode(for: payload, size: 300)
        XCTAssertNotNil(cgImage, "qrCode(for:) must return a non-nil CGImage")
        if let img = cgImage {
            XCTAssertGreaterThan(img.width, 0)
            XCTAssertGreaterThan(img.height, 0)
        }
    }

    // MARK: - Canonical JSON

    func testCanonicalJSONExcludesSig() throws {
        let (payload, _) = try makeSignedPayload()
        let canonical = try InviteCodeGenerator.canonicalJSONWithoutSig(payload)
        let dict = try JSONSerialization.jsonObject(with: canonical) as? [String: Any]
        XCTAssertNotNil(dict)
        XCTAssertNil(dict?["sig"], "Canonical JSON must not include 'sig' field")
        XCTAssertNotNil(dict?["v"])
        XCTAssertNotNil(dict?["userPublicKey"])
    }

    func testCanonicalJSONIsDeterministic() throws {
        let (payload, _) = try makeSignedPayload()
        let a = try InviteCodeGenerator.canonicalJSONWithoutSig(payload)
        let b = try InviteCodeGenerator.canonicalJSONWithoutSig(payload)
        XCTAssertEqual(a, b, "Canonical JSON must be deterministic across calls")
    }

    // MARK: - Deep Link Parsing

    func testDeepLinkParsingConnectInvite() throws {
        let url = URL(string: "odyssey://connect?invite=abc123def456")!
        let intent = LaunchIntent.fromURL(url)
        XCTAssertNotNil(intent, "odyssey://connect?invite=... should produce a LaunchIntent")
        guard let intent else { return }
        switch intent.mode {
        case .connectInvite(let payload):
            XCTAssertEqual(payload, "abc123def456")
        default:
            XCTFail("Expected .connectInvite mode, got \(intent.mode)")
        }
    }

    func testDeepLinkMissingInviteParamReturnsNil() {
        let url = URL(string: "odyssey://connect")!
        let intent = LaunchIntent.fromURL(url)
        XCTAssertNil(intent, "odyssey://connect without invite= should return nil")
    }
}
```

- [ ] **Step 2: Run tests (expect failures on `connectInvite` until Task 6 is done)**

```bash
cd /Users/shayco/Odyssey && xcodebuild test -scheme Odyssey -destination 'platform=macOS' -only-testing OdysseyTests/InviteCodeTests/testDeviceInviteRoundTrip -only-testing OdysseyTests/InviteCodeTests/testExpiredInviteRejected -only-testing OdysseyTests/InviteCodeTests/testBase64UrlEncoding -only-testing OdysseyTests/InviteCodeTests/testQRCodeProducesValidImage 2>&1 | tail -40
```

---

## Task 6: LaunchIntent — `connectInvite` Mode

**Files:**
- Modify: `Odyssey/App/LaunchIntent.swift`

- [ ] **Step 1: Add `.connectInvite` to `LaunchMode`**

In `LaunchIntent.swift`, after the `case roomJoin(payload: SharedRoomService.JoinPayload)` line in the `LaunchMode` enum, add:

```swift
case connectInvite(payload: String)
```

- [ ] **Step 2: Handle `odyssey://connect?invite=<base64url>` in `fromURL`**

In the `switch host` block of `fromURL(_:)`, add a new case before `default`:

```swift
case "connect":
    guard let invite = queryValue("invite"), !invite.isEmpty else { return nil }
    mode = .connectInvite(payload: invite)
```

- [ ] **Step 3: Verify the `LaunchIntent` struct's init is unchanged**

The `LaunchIntent` struct's memberwise init passes `mode` through; no changes needed there. The `connectInvite` mode carries its payload entirely in the enum associated value.

- [ ] **Step 4: Add CLI handling for `--connect-invite` (optional convenience for testing)**

In `fromArguments(_:)`, inside the `switch args[i]` block, add:

```swift
case "--connect-invite":
    i += 1
    guard i < args.count else { break }
    mode = .connectInvite(payload: args[i])
```

- [ ] **Step 5: Add handler stub in `AppState.executeLaunchIntent`**

In `AppState.swift`, in the `executeLaunchIntent(_:modelContext:)` method, add a case to the switch on `intent.mode`:

```swift
case .connectInvite(let encoded):
    await handleConnectInvite(encoded: encoded)
```

Then add the stub method to `AppState`:

```swift
/// Handles an `odyssey://connect?invite=<base64url>` deep link.
/// Decodes and verifies the invite, then presents the pairing confirmation UI.
private func handleConnectInvite(encoded: String) async {
    do {
        let payload = try InviteCodeGenerator.decode(encoded)
        try InviteCodeGenerator.verify(payload)
        // TODO (Phase 2b follow-up): present pairing confirmation sheet
        // For now, log the event for debugging.
        logger.info("Received valid connect invite from '\(payload.displayName)'")
    } catch {
        logger.error("connectInvite handling failed: \(error.localizedDescription)")
        // Surface error to user via launchError on the relevant WindowState
    }
}
```

- [ ] **Step 6: Run the `LaunchIntent` deep-link test**

```bash
cd /Users/shayco/Odyssey && xcodebuild test -scheme Odyssey -destination 'platform=macOS' -only-testing OdysseyTests/InviteCodeTests/testDeepLinkParsingConnectInvite -only-testing OdysseyTests/InviteCodeTests/testDeepLinkMissingInviteParamReturnsNil 2>&1 | tail -20
```

---

## Task 7: SharedRoomInvite Model — New Fields

**Files:**
- Modify: `Odyssey/Models/SharedRoomInvite.swift`

- [ ] **Step 1: Add `signedPayloadJSON` and `pairingType` fields to `SharedRoomInvite`**

In `SharedRoomInvite.swift`, add the two new stored properties after `isRevoked`:

```swift
/// Base64url-encoded `InvitePayload` JSON for device/user pairing invites.
/// Nil for legacy room invites.
var signedPayloadJSON: String? = nil

/// Discriminates between invite kinds: "room" (default), "device", or "user".
var pairingType: String = "room"
```

Update the `init` to keep all existing parameters unchanged; the new fields default naturally. No migration is required because SwiftData handles optional and defaulted new fields automatically.

- [ ] **Step 2: Run the shared room model tests to confirm no regressions**

```bash
cd /Users/shayco/Odyssey && xcodebuild test -scheme Odyssey -destination 'platform=macOS' -only-testing OdysseyTests/SharedRoomModelTests 2>&1 | tail -20
```

---

## Task 8: iOSPairingSettingsView

**Files:**
- Create: `Odyssey/Views/Settings/iOSPairingSettingsView.swift`
- Modify: `Odyssey/Views/Settings/SettingsView.swift`

This view lets users generate, display, and revoke device pairing invites.

- [ ] **Step 1: Create `Odyssey/Views/Settings/iOSPairingSettingsView.swift`**

```swift
// Odyssey/Views/Settings/iOSPairingSettingsView.swift
import SwiftUI
import SwiftData
import OSLog

private let logger = Logger(subsystem: "com.odyssey.app", category: "iOSPairing")

/// Settings pane for iOS device pairing: QR code display, copy link, and device management.
struct iOSPairingSettingsView: View {

    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<SharedRoomInvite> { $0.pairingType == "device" },
        sort: \SharedRoomInvite.createdAt, order: .reverse
    ) private var deviceInvites: [SharedRoomInvite]

    @State private var currentPayload: InvitePayload? = nil
    @State private var qrImage: CGImage? = nil
    @State private var isGenerating = false
    @State private var generateError: String? = nil
    @State private var allowIOSConnections = false
    @State private var copyConfirmation = false
    @State private var refreshTimer: Timer? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                allowToggleSection
                Divider()
                qrSection
                Divider()
                pairedDevicesSection
            }
            .padding(24)
        }
        .onAppear { startRefreshCycle() }
        .onDisappear { refreshTimer?.invalidate() }
        .accessibilityIdentifier("settings.iosPairing.root")
    }

    // MARK: - Allow Toggle

    private var allowToggleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("iOS Connections")
                .font(.headline)
            Toggle("Allow iOS connections", isOn: $allowIOSConnections)
                .onChange(of: allowIOSConnections) { _, newValue in
                    handleAllowToggle(newValue)
                }
                .accessibilityIdentifier("settings.iosPairing.allowToggle")
            if allowIOSConnections {
                Text("The sidecar will accept connections from 0.0.0.0 (all interfaces). Ensure your macOS firewall permits incoming TCP connections on port \(InstanceConfig.wsPort).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings.iosPairing.firewallNote")
            }
        }
    }

    // MARK: - QR Code Section

    private var qrSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pair a New Device")
                .font(.headline)
            Text("Scan this QR code from the Odyssey iOS app. The code expires in 5 minutes.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if isGenerating {
                ProgressView()
                    .frame(width: 300, height: 300)
                    .accessibilityIdentifier("settings.iosPairing.qrLoadingIndicator")
            } else if let cgImage = qrImage {
                Image(decorative: cgImage, scale: 1.0)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 300, height: 300)
                    .accessibilityIdentifier("settings.iosPairing.qrCodeImage")
                    .accessibilityLabel("Pairing QR Code")
            } else if let err = generateError {
                Text("Failed to generate invite: \(err)")
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("settings.iosPairing.qrError")
            }

            HStack(spacing: 12) {
                Button("Refresh QR") {
                    Task { await generateNewInvite() }
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("settings.iosPairing.refreshQRButton")
                .accessibilityLabel("Refresh QR Code")

                Button(copyConfirmation ? "Copied!" : "Copy Invite Link") {
                    copyInviteLink()
                }
                .buttonStyle(.bordered)
                .disabled(currentPayload == nil)
                .accessibilityIdentifier("settings.iosPairing.copyLinkButton")
            }
        }
    }

    // MARK: - Paired Devices Section

    private var pairedDevicesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Paired Devices")
                .font(.headline)
            if deviceInvites.isEmpty {
                Text("No paired devices yet.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings.iosPairing.emptyDeviceList")
            } else {
                ForEach(deviceInvites) { invite in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(invite.recipientLabel ?? "Unknown Device")
                                .font(.body)
                            Text(invite.status.rawValue.capitalized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Revoke") {
                            revokeInvite(invite)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("settings.iosPairing.revokeButton.\(invite.id.uuidString)")
                        .accessibilityLabel("Revoke pairing for \(invite.recipientLabel ?? "device")")
                    }
                    .padding(.vertical, 4)
                    .accessibilityIdentifier("settings.iosPairing.deviceRow.\(invite.id.uuidString)")
                    Divider()
                }
            }
        }
    }

    // MARK: - Actions

    private func startRefreshCycle() {
        Task { await generateNewInvite() }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 270, repeats: true) { _ in
            Task { @MainActor in
                await generateNewInvite()
            }
        }
    }

    private func generateNewInvite() async {
        isGenerating = true
        generateError = nil
        do {
            let lanHint = appState.p2pNetworkManager?.natTraversalManager.publicEndpoint.map { _ in
                // Local IP: best-effort from network interface enumeration
                Self.localIPAddress()
            } ?? nil
            let wanHint = appState.p2pNetworkManager?.natTraversalManager.publicEndpoint

            let payload = try await InviteCodeGenerator.generateDevice(
                instanceName: InstanceConfig.name,
                expiresIn: 300,
                singleUse: true,
                lanHint: lanHint,
                wanHint: wanHint
            )
            currentPayload = payload
            qrImage = InviteCodeGenerator.qrCode(for: payload, size: 300)

            // Persist the invite record
            let encoded = try InviteCodeGenerator.encode(payload)
            let invite = SharedRoomInvite(
                inviteId: UUID().uuidString,
                inviteToken: payload.wsToken,
                roomId: "",
                inviterUserId: payload.userPublicKey,
                inviterDisplayName: payload.displayName,
                recipientLabel: nil,
                roomTopic: "Device Pairing",
                deepLink: "odyssey://connect?invite=\(encoded)",
                expiresAt: Date(timeIntervalSince1970: payload.exp),
                singleUse: payload.singleUse
            )
            invite.signedPayloadJSON = encoded
            invite.pairingType = "device"
            modelContext.insert(invite)
            try? modelContext.save()

        } catch {
            generateError = error.localizedDescription
            logger.error("iOSPairing invite generation failed: \(error.localizedDescription)")
        }
        isGenerating = false
    }

    private func copyInviteLink() {
        guard let payload = currentPayload,
              let encoded = try? InviteCodeGenerator.encode(payload)
        else { return }
        let link = "odyssey://connect?invite=\(encoded)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link, forType: .string)
        copyConfirmation = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copyConfirmation = false
        }
    }

    private func handleAllowToggle(_ allow: Bool) {
        // Signal AppState/SidecarManager to restart sidecar with ODYSSEY_WS_BIND
        if allow {
            appState.sidecarManager?.setBindAddress("0.0.0.0")
        } else {
            appState.sidecarManager?.setBindAddress("127.0.0.1")
        }
    }

    private func revokeInvite(_ invite: SharedRoomInvite) {
        invite.status = .revoked
        invite.isRevoked = true
        invite.updatedAt = Date()
        try? modelContext.save()
        Task {
            try? await IdentityManager.shared.rotateWSToken(for: InstanceConfig.name)
        }
    }

    // MARK: - Network Helpers

    private static func localIPAddress() -> String? {
        // Returns the first non-loopback IPv4 address on en0.
        var ifaddr: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }
        var current = ifaddr
        while let ptr = current {
            let ifa = ptr.pointee
            if ifa.ifa_addr.pointee.sa_family == UInt8(AF_INET),
               let name = String(validatingCString: ifa.ifa_name),
               name == "en0" {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(ifa.ifa_addr, socklen_t(ifa.ifa_addr.pointee.sa_len),
                            &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                return String(cString: hostname)
            }
            current = ifa.ifa_next
        }
        return nil
    }
}
```

- [ ] **Step 2: Add `.iosPairing` to `SettingsSection` enum in `SettingsView.swift`**

In `SettingsView.swift`, extend the `SettingsSection` enum by adding a new case. Find the `case developer` case and add after it:

```swift
case iosPairing
```

Add to `title`:
```swift
case .iosPairing: "iOS Pairing"
```

Add to `subtitle`:
```swift
case .iosPairing: "QR code and device pairing for iOS access"
```

Add to `systemImage`:
```swift
case .iosPairing: "iphone.and.arrow.forward"
```

Add to `xrayId`:
```swift
case .iosPairing: "settings.tab.iosPairing"
```

- [ ] **Step 3: Wire the new section in the `detailPane` switch**

In `SettingsView.swift`, find the `detailPane` computed property or the switch that dispatches to each settings subview, and add:

```swift
case .iosPairing:
    iOSPairingSettingsView()
        .environmentObject(appState)
```

- [ ] **Step 4: Add `p2pNetworkManager` accessor to AppState (if not already present)**

In `AppState.swift`, ensure the P2P manager is accessible from the pairing view. If it isn't already a property:

```swift
/// Set by OdysseyApp after P2P is initialized.
weak var p2pNetworkManager: P2PNetworkManager?
```

- [ ] **Step 5: Add `setBindAddress` stub to `SidecarManager` (if not already present)**

```swift
/// Reconfigures the sidecar bind address and schedules a restart.
func setBindAddress(_ address: String) {
    // Store preference and restart sidecar with ODYSSEY_WS_BIND env var
    UserDefaults.standard.set(address, forKey: "sidecarBindAddress")
    Task { await restart() }
}
```

- [ ] **Step 6: Run `xcodegen generate`**

```bash
cd /Users/shayco/Odyssey && xcodegen generate
```

---

## Task 9: Full Test Suite Pass

- [ ] **Step 1: Run NATTraversal tests**

```bash
cd /Users/shayco/Odyssey && xcodebuild test -scheme Odyssey -destination 'platform=macOS' -only-testing OdysseyTests/NATTraversalTests 2>&1 | tail -40
```

All 6 tests must pass: `testSTUNRequestEncoding`, `testSTUNResponseParsing`, `testXORMappedAddressIPv4`, `testParseEndpointValid`, `testParseEndpointInvalid`, `testTruncatedResponseThrows`, `testBadMagicCookieThrows`.

- [ ] **Step 2: Run InviteCode tests**

```bash
cd /Users/shayco/Odyssey && xcodebuild test -scheme Odyssey -destination 'platform=macOS' -only-testing OdysseyTests/InviteCodeTests 2>&1 | tail -40
```

All 9 tests must pass: `testDeviceInviteRoundTrip`, `testExpiredInviteRejected`, `testTamperedInviteRejected`, `testBase64UrlEncoding`, `testBase64UrlRoundtripVariousLengths`, `testQRCodeProducesValidImage`, `testCanonicalJSONExcludesSig`, `testCanonicalJSONIsDeterministic`, `testDeepLinkParsingConnectInvite`, `testDeepLinkMissingInviteParamReturnsNil`.

- [ ] **Step 3: Run LaunchIntent regression tests**

```bash
cd /Users/shayco/Odyssey && xcodebuild test -scheme Odyssey -destination 'platform=macOS' -only-testing OdysseyTests/LaunchIntentTests 2>&1 | tail -20
```

All existing tests must still pass.

- [ ] **Step 4: Run SharedRoom model regression tests**

```bash
cd /Users/shayco/Odyssey && xcodebuild test -scheme Odyssey -destination 'platform=macOS' -only-testing OdysseyTests/SharedRoomModelTests 2>&1 | tail -20
```

- [ ] **Step 5: Run full suite**

```bash
cd /Users/shayco/Odyssey && xcodebuild test -scheme Odyssey -destination 'platform=macOS' 2>&1 | grep -E "Test (Suite|Case|session)" | tail -60
```

---

## Task 10: Commit

- [ ] **Step 1: Stage all changes**

```bash
cd /Users/shayco/Odyssey && git add \
  Odyssey/Services/NATTraversalManager.swift \
  Odyssey/Services/InviteCodeGenerator.swift \
  Odyssey/Services/P2PNetworkManager.swift \
  Odyssey/Services/PeerCatalogServer.swift \
  Odyssey/Models/SharedRoomInvite.swift \
  Odyssey/App/LaunchIntent.swift \
  Odyssey/App/AppState.swift \
  Odyssey/Views/Settings/iOSPairingSettingsView.swift \
  Odyssey/Views/Settings/SettingsView.swift \
  OdysseyTests/NATTraversalTests.swift \
  OdysseyTests/InviteCodeTests.swift \
  project.yml
```

- [ ] **Step 2: Commit**

```bash
cd /Users/shayco/Odyssey && git commit -m "$(cat <<'EOF'
Add Phase 2 cross-network discovery: STUN + signed invite codes

- NATTraversalManager: UDP STUN Binding Request/Response (RFC 5389),
  XOR-MAPPED-ADDRESS parsing, UDP hole-punch helper
- InviteCodeGenerator: Ed25519-signed InvitePayload, base64url encode/
  decode, CoreImage QR code, TURNConfig, InviteHints
- P2PNetworkManager: inject WAN endpoint into Bonjour TXT record via
  NATTraversalManager sink
- SharedRoomInvite: add signedPayloadJSON and pairingType fields
- LaunchIntent: add .connectInvite(payload:) mode for odyssey://connect
- iOSPairingSettingsView: QR display, copy link, allow-iOS toggle,
  paired-device list with revoke
- Tests: NATTraversalTests (STUN encoding/parsing), InviteCodeTests
  (roundtrip, expiry, tamper, base64url, QR, deep link)

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Implementation Notes

### STUN server alternatives

The plan uses `stun.l.google.com:19302` (free, high-availability). Alternatives:
- `stun1.l.google.com:19302`, `stun2.l.google.com:19302` (same pool)
- `stun.cloudflare.com:3478`
- Self-hosted `coturn`

For production, query multiple servers and take the majority answer (symmetrical NAT may produce per-destination mappings; if two servers return different addresses, the NAT is symmetric and full cone traversal will not work).

### Symmetric NAT fallback

When STUN results differ across two queries (indicating symmetric NAT), the `NATTraversalManager.holePunch` will silently return `nil`. In that case, the `TURNConfig` relay should be used as the fallback. This is out of scope for Phase 2 but the `InviteHints.turn` field is included so the iOS client can initiate a relay-based connection without a new invite.

### `IdentityManager` dependency

The `InviteCodeGenerator.generateDevice` method calls `IdentityManager.shared` directly. For the unit tests in `InviteCodeTests.swift`, we bypass `generateDevice` and construct `InvitePayload` values directly using a locally generated ephemeral `Curve25519.Signing.PrivateKey` — this keeps tests hermetic and fast.

### `iOSPairingSettingsView` — `setBindAddress` and `p2pNetworkManager`

Task 8 adds stubs for `SidecarManager.setBindAddress` and `AppState.p2pNetworkManager`. If either already exists from Phase 1 or other work, skip the corresponding sub-step. The important contract is:
- `setBindAddress("0.0.0.0")` causes the sidecar to restart with `ODYSSEY_WS_BIND=0.0.0.0`
- `setBindAddress("127.0.0.1")` reverts to loopback-only mode

### `getifaddrs` import

`iOSPairingSettingsView.localIPAddress()` calls POSIX `getifaddrs`. Add `import Darwin` at the top of that file if needed (it is usually available transitively via Foundation on macOS, but an explicit import is safer).

### `InstanceConfig.wsPort`

`InstanceConfig.wsPort` is assumed to return `Int` (the configured WebSocket port, default 9849). Verify this exists in `Odyssey/App/InstanceConfig.swift`; if not, use the raw default `9849`.

### XcodeGen after every new Swift file

Always run `xcodegen generate` from the repo root after creating any new `.swift` file. This updates `Odyssey.xcodeproj` so Xcode picks up the new source.
