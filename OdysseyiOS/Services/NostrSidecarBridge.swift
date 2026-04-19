// OdysseyiOS/Services/NostrSidecarBridge.swift
import Foundation
import OdysseyCore
import P256K
import OSLog

private let log = Logger(subsystem: "com.odyssey.app.ios", category: "nostr")

// MARK: - NostrSidecarBridge

/// iOS-side Nostr relay client.
/// Connects to Nostr relay URLs, publishes encrypted SidecarCommands to the paired
/// Mac's npub, and receives encrypted SidecarEvents from the Mac.
@MainActor
final class NostrSidecarBridge: ObservableObject {

    @Published var isConnected = false

    private let macPubkeyHex: String
    private let privkeyHex: String
    private let pubkeyHex: String
    private let relayURLs: [String]
    private var relay: NostrRelayManageriOS?
    private var onEvent: ((SidecarEvent) -> Void)?

    init(
        macPubkeyHex: String,
        privkeyHex: String,
        pubkeyHex: String,
        relayURLs: [String] = ["wss://relay.damus.io", "wss://relay.nostr.band"],
        onEvent: @escaping (SidecarEvent) -> Void
    ) {
        self.macPubkeyHex = macPubkeyHex
        self.privkeyHex = privkeyHex
        self.pubkeyHex = pubkeyHex
        self.relayURLs = relayURLs
        self.onEvent = onEvent
    }

    func connect() {
        let r = NostrRelayManageriOS(
            relayURLs: relayURLs,
            privkeyHex: privkeyHex,
            pubkeyHex: pubkeyHex,
            onEvent: { [weak self] event in
                Task { @MainActor [weak self] in
                    self?.handleIncomingEvent(event)
                }
            }
        )
        relay = r
        r.connect()
    }

    func disconnect() {
        relay?.disconnect()
        relay = nil
        isConnected = false
    }

    func send(_ command: SidecarCommand) {
        guard let relay, let priv = privkeyHex.nilIfEmpty else { return }
        Task {
            do {
                guard let cmdData = try? command.encodeToJSON(),
                      let cmdStr = String(data: cmdData, encoding: .utf8) else { return }
                let convKey = try NIP44iOS.conversationKey(privkeyHex: priv, peerPubkeyHex: macPubkeyHex)
                let encrypted = try NIP44iOS.encrypt(plaintext: cmdStr, conversationKey: convKey)
                let eventJSON = makeEventJSON(content: encrypted, recipientPubkey: macPubkeyHex, senderPubkey: pubkeyHex)
                relay.publish(to: macPubkeyHex, eventJSON: eventJSON)
            } catch {
                log.error("NostrSidecarBridge: send failed — \(error)")
            }
        }
    }

    // MARK: - Private

    private func handleIncomingEvent(_ event: NostrEventiOS) {
        guard event.kind == 4, let priv = privkeyHex.nilIfEmpty else { return }
        let pTags = event.tags.filter { $0.first == "p" }
        guard pTags.contains(where: { $0.count > 1 && $0[1] == pubkeyHex }) else { return }
        guard event.pubkey == macPubkeyHex else { return }

        do {
            let convKey = try NIP44iOS.conversationKey(privkeyHex: priv, peerPubkeyHex: event.pubkey)
            let plaintext = try NIP44iOS.decrypt(payload: event.content, conversationKey: convKey)
            guard let data = plaintext.data(using: .utf8),
                  let wire = try? JSONDecoder().decode(IncomingWireMessage.self, from: data),
                  let sidecarEvent = wire.toEvent() else { return }
            isConnected = true
            onEvent?(sidecarEvent)
        } catch {
            log.debug("NostrSidecarBridge: decrypt failed — \(error)")
        }
    }

    private func makeEventJSON(content: String, recipientPubkey: String, senderPubkey: String) -> String {
        let timestamp = Int(Date().timeIntervalSince1970)
        let contentEsc = content
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return """
        {"kind":4,"created_at":\(timestamp),"tags":[["p","\(recipientPubkey)"]],"content":"\(contentEsc)","pubkey":"\(senderPubkey)","id":"","sig":""}
        """
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - NIP44iOS

/// NIP-44 v2 for iOS — mirrors the macOS NIP44 implementation.
private enum NIP44iOS {

    static func conversationKey(privkeyHex: String, peerPubkeyHex: String) throws -> Data {
        let privBytes = Data(hexString: privkeyHex)!
        let pubkeyData = Data(hexString: "02" + peerPubkeyHex)!
        let privkey = try P256K.KeyAgreement.PrivateKey(dataRepresentation: privBytes)
        let pubkey = try P256K.KeyAgreement.PublicKey(dataRepresentation: pubkeyData)
        let shared = privkey.sharedSecretFromKeyAgreement(with: pubkey, format: .compressed)
        let sharedX = shared.withUnsafeBytes { Data($0).dropFirst() }
        return hkdfExtract(ikm: sharedX, salt: Data("nip44-v2".utf8))
    }

    static func encrypt(plaintext: String, conversationKey: Data, nonce: Data? = nil) throws -> String {
        let n = nonce ?? randomBytes(32)
        let keys = messageKeys(conversationKey: conversationKey, nonce: n)
        let padded = pad(plaintext)
        let ciphertext = chacha20(key: keys.ck, nonce: keys.cn, data: padded)
        let mac = hmacSHA256(key: keys.hk, data: n + ciphertext)
        var payload = Data([0x02]); payload.append(n); payload.append(ciphertext); payload.append(mac)
        return payload.base64EncodedString()
    }

    static func decrypt(payload: String, conversationKey: Data) throws -> String {
        guard let raw = Data(base64Encoded: payload), raw.count >= 99, raw[0] == 0x02 else {
            throw NIP44iOSError.invalid
        }
        let nonce = raw[1..<33]; let ct = raw[33..<(raw.count-32)]; let mac = raw[(raw.count-32)...]
        let keys = messageKeys(conversationKey: conversationKey, nonce: Data(nonce))
        let expected = hmacSHA256(key: keys.hk, data: Data(nonce) + Data(ct))
        guard mac.elementsEqual(expected) else { throw NIP44iOSError.badMAC }
        let padded = chacha20(key: keys.ck, nonce: keys.cn, data: Data(ct))
        return try unpad(padded)
    }

    private struct Keys { let ck: Data; let cn: Data; let hk: Data }

    private static func messageKeys(conversationKey: Data, nonce: Data) -> Keys {
        let exp = hkdfExpand(prk: conversationKey, info: nonce, len: 76)
        return Keys(ck: exp[0..<32], cn: exp[32..<44], hk: exp[44..<76])
    }

    private static func calcPaddedLen(_ n: Int) -> Int {
        if n <= 32 { return 32 }
        let np = 1 << (Int(log2(Double(n - 1))) + 1); let c = np <= 256 ? 32 : np / 8
        return c * ((n - 1) / c + 1)
    }

    private static func pad(_ s: String) -> Data {
        let b = Data(s.utf8); let n = b.count
        var out = Data(); out.append(UInt8(n >> 8)); out.append(UInt8(n & 0xFF))
        out.append(b); out.append(Data(repeating: 0, count: calcPaddedLen(n) - n))
        return out
    }

    private static func unpad(_ d: Data) throws -> String {
        guard d.count >= 2 else { throw NIP44iOSError.invalid }
        let n = Int(d[0]) << 8 | Int(d[1])
        guard n >= 1, n <= 65535, d.count == 2 + calcPaddedLen(n) else { throw NIP44iOSError.invalid }
        return String(data: Data(d[2..<(2+n)]), encoding: .utf8) ?? ""
    }

    // MARK: HKDF + HMAC + ChaCha20

    private static func hkdfExtract(ikm: Data, salt: Data) -> Data {
        var key = SymmetricKey(data: salt)
        return Data(HMAC<SHA256>.authenticationCode(for: ikm, using: key))
    }

    private static func hkdfExpand(prk: Data, info: Data, len: Int) -> Data {
        var okm = Data(); var t = Data(); var ctr: UInt8 = 1
        while okm.count < len {
            var input = t + info; input.append(ctr)
            t = Data(HMAC<SHA256>.authenticationCode(for: input, using: SymmetricKey(data: prk)))
            okm.append(t); ctr += 1
        }
        return okm.prefix(len)
    }

    private static func hmacSHA256(key: Data, data: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key)))
    }

    private static func chacha20(key: Data, nonce: Data, data: Data) -> Data {
        precondition(key.count == 32 && nonce.count == 12)
        let k = key.u32le(); let n = nonce.u32le()
        var out = Data(capacity: data.count); var off = 0; var blk: UInt32 = 0
        while off < data.count {
            let ks = chacha20Block(k: k, ctr: blk, n: n).u8le()
            let cnt = min(64, data.count - off)
            for i in 0..<cnt { out.append(data[off + i] ^ ks[i]) }
            off += cnt; blk &+= 1
        }
        return out
    }

    private static func chacha20Block(k: [UInt32], ctr: UInt32, n: [UInt32]) -> [UInt32] {
        var s: [UInt32] = [0x61707865,0x3320646e,0x79622d32,0x6b206574,k[0],k[1],k[2],k[3],k[4],k[5],k[6],k[7],ctr,n[0],n[1],n[2]]
        let i = s
        for _ in 0..<10 {
            qr(&s,0,4,8,12);qr(&s,1,5,9,13);qr(&s,2,6,10,14);qr(&s,3,7,11,15)
            qr(&s,0,5,10,15);qr(&s,1,6,11,12);qr(&s,2,7,8,13);qr(&s,3,4,9,14)
        }
        return (0..<16).map { s[$0] &+ i[$0] }
    }

    private static func qr(_ s: inout [UInt32], _ a: Int, _ b: Int, _ c: Int, _ d: Int) {
        s[a]=s[a]&+s[b];s[d]=rl(s[d]^s[a],16);s[c]=s[c]&+s[d];s[b]=rl(s[b]^s[c],12)
        s[a]=s[a]&+s[b];s[d]=rl(s[d]^s[a],8);s[c]=s[c]&+s[d];s[b]=rl(s[b]^s[c],7)
    }

    private static func rl(_ x: UInt32, _ n: Int) -> UInt32 { (x << n) | (x >> (32 - n)) }
    private static func randomBytes(_ n: Int) -> Data { Data((0..<n).map { _ in UInt8.random(in: 0...255) }) }

    enum NIP44iOSError: Error { case invalid, badMAC }
}

import CryptoKit

// MARK: - Data helpers

private extension Data {
    init?(hexString: String) {
        guard hexString.count % 2 == 0 else { return nil }
        var d = Data(capacity: hexString.count / 2)
        var idx = hexString.startIndex
        while idx < hexString.endIndex {
            let next = hexString.index(idx, offsetBy: 2)
            guard let b = UInt8(hexString[idx..<next], radix: 16) else { return nil }
            d.append(b); idx = next
        }
        self = d
    }

    func u32le() -> [UInt32] {
        stride(from: 0, to: count, by: 4).map { i in
            UInt32(self[i]) | (UInt32(self[safe: i+1] ?? 0) << 8) |
            (UInt32(self[safe: i+2] ?? 0) << 16) | (UInt32(self[safe: i+3] ?? 0) << 24)
        }
    }

    subscript(safe i: Index) -> Element? { indices.contains(i) ? self[i] : nil }
}

private extension Array where Element == UInt32 {
    func u8le() -> [UInt8] {
        flatMap { w in [UInt8(w&0xFF), UInt8((w>>8)&0xFF), UInt8((w>>16)&0xFF), UInt8((w>>24)&0xFF)] }
    }
}

// MARK: - Minimal Nostr types for iOS (standalone, no P256K-based signing needed)

struct NostrEventiOS: Codable {
    let id: String
    let pubkey: String
    let created_at: Int
    let kind: Int
    let tags: [[String]]
    let content: String
    let sig: String
}

@MainActor
final class NostrRelayManageriOS: NSObject {

    private let relayURLs: [String]
    private let privkeyHex: String
    private let pubkeyHex: String
    private let onEvent: (NostrEventiOS) -> Void

    private var connections: [String: URLSessionWebSocketTask] = [:]
    private var sessions: [String: URLSession] = [:]
    private var reconnectTasks: [String: Task<Void, Never>] = [:]
    private var reconnectAttempts: [String: Int] = [:]

    init(relayURLs: [String], privkeyHex: String, pubkeyHex: String, onEvent: @escaping (NostrEventiOS) -> Void) {
        self.relayURLs = relayURLs
        self.privkeyHex = privkeyHex
        self.pubkeyHex = pubkeyHex
        self.onEvent = onEvent
    }

    func connect() {
        for url in relayURLs { openConnection(to: url) }
    }

    func disconnect() {
        for (url, task) in connections {
            task.cancel(with: .goingAway, reason: nil)
            sessions[url]?.invalidateAndCancel()
            reconnectTasks[url]?.cancel()
        }
        connections.removeAll(); sessions.removeAll()
        reconnectTasks.removeAll(); reconnectAttempts.removeAll()
    }

    func publish(to peerPubkeyHex: String, eventJSON: String) {
        let msg: String
        guard let eventData = eventJSON.data(using: .utf8),
              let eventObj = try? JSONSerialization.jsonObject(with: eventData) else { return }
        let arr: [Any] = ["EVENT", eventObj]
        guard let data = try? JSONSerialization.data(withJSONObject: arr),
              let text = String(data: data, encoding: .utf8) else { return }
        msg = text
        for task in connections.values { task.send(.string(msg)) { _ in } }
    }

    private func openConnection(to relayURL: String) {
        guard let url = URL(string: relayURL) else { return }
        let session = URLSession(configuration: .default)
        sessions[relayURL] = session
        let task = session.webSocketTask(with: url)
        connections[relayURL] = task
        task.resume()
        let subId = "ios-\(pubkeyHex.prefix(8))"
        let filter: [String: Any] = ["kinds": [4], "#p": [pubkeyHex]]
        let arr: [Any] = ["REQ", subId, filter]
        if let data = try? JSONSerialization.data(withJSONObject: arr),
           let req = String(data: data, encoding: .utf8) {
            task.send(.string(req)) { _ in }
        }
        receiveMessages(from: relayURL, task: task)
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
                    let attempt = self.reconnectAttempts[relayURL, default: 0]
                    let delay = min(pow(2.0, Double(attempt)), 30.0)
                    self.reconnectAttempts[relayURL] = attempt + 1
                    self.reconnectTasks[relayURL]?.cancel()
                    self.reconnectTasks[relayURL] = Task { [weak self] in
                        try? await Task.sleep(for: .seconds(delay))
                        guard !Task.isCancelled else { return }
                        await self?.openConnection(to: relayURL)
                    }
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
        guard let data = text.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [Any],
              arr.count >= 3,
              arr[0] as? String == "EVENT",
              let eventData = try? JSONSerialization.data(withJSONObject: arr[2]),
              let event = try? JSONDecoder().decode(NostrEventiOS.self, from: eventData) else { return }
        onEvent(event)
    }
}
