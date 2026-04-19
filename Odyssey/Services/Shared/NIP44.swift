import CryptoKit
import Foundation
import P256K

// MARK: - NIP-44 v2 Encryption

/// Implements NIP-44 v2 encryption compatible with nostr-tools `nip44.v2`.
/// Uses secp256k1 ECDH + HKDF-SHA256 + ChaCha20 + HMAC-SHA256.
enum NIP44 {

    // MARK: - Public API

    static func conversationKey(privkeyHex: String, peerPubkeyHex: String) throws -> Data {
        let privBytes = Data(hexString: privkeyHex)!
        let compressedPubkeyHex = "02" + peerPubkeyHex
        let pubkeyData = Data(hexString: compressedPubkeyHex)!

        let privkey = try P256K.KeyAgreement.PrivateKey(dataRepresentation: privBytes)
        let pubkey = try P256K.KeyAgreement.PublicKey(dataRepresentation: pubkeyData)
        let shared = privkey.sharedSecretFromKeyAgreement(with: pubkey, format: .compressed)
        // Skip the 02/03 compression prefix byte; keep the 32-byte X coordinate
        let sharedX = shared.withUnsafeBytes { Data($0).dropFirst() }

        let salt = Data("nip44-v2".utf8)
        return hkdfExtract(ikm: sharedX, salt: salt)
    }

    static func encrypt(plaintext: String, conversationKey: Data, nonce: Data? = nil) throws -> String {
        let n = nonce ?? randomBytes(32)
        let keys = try messageKeys(conversationKey: conversationKey, nonce: n)
        let padded = pad(plaintext: plaintext)
        let ciphertext = chacha20(key: keys.cipherKey, nonce: keys.cipherNonce, data: padded)
        let mac = hmacSHA256(key: keys.hmacKey, data: n + ciphertext)
        var payload = Data([0x02])
        payload.append(n)
        payload.append(ciphertext)
        payload.append(mac)
        return payload.base64EncodedString()
    }

    static func decrypt(payload: String, conversationKey: Data) throws -> String {
        guard let raw = Data(base64Encoded: payload), raw.count >= 99 else {
            throw NIP44Error.invalidPayload
        }
        guard raw[0] == 0x02 else { throw NIP44Error.unknownVersion }

        let nonce = raw[1..<33]
        let ciphertext = raw[33..<(raw.count - 32)]
        let mac = raw[(raw.count - 32)...]

        let keys = try messageKeys(conversationKey: conversationKey, nonce: Data(nonce))
        let expectedMac = hmacSHA256(key: keys.hmacKey, data: Data(nonce) + Data(ciphertext))
        guard mac.elementsEqual(expectedMac) else { throw NIP44Error.invalidMAC }

        let padded = chacha20(key: keys.cipherKey, nonce: keys.cipherNonce, data: Data(ciphertext))
        return try unpad(padded: padded)
    }

    // MARK: - Padding (exposed for tests)

    static func calcPaddedLen(_ len: Int) -> Int {
        if len <= 32 { return 32 }
        let nextPower = 1 << (Int(log2(Double(len - 1))) + 1)
        let chunk = nextPower <= 256 ? 32 : nextPower / 8
        return chunk * ((len - 1) / chunk + 1)
    }

    // MARK: - Private helpers

    private struct MessageKeys {
        let cipherKey: Data    // 32 bytes
        let cipherNonce: Data  // 12 bytes
        let hmacKey: Data      // 32 bytes
    }

    private static func messageKeys(conversationKey: Data, nonce: Data) throws -> MessageKeys {
        let expanded = hkdfExpand(prk: conversationKey, info: nonce, len: 76)
        return MessageKeys(
            cipherKey: expanded[0..<32],
            cipherNonce: expanded[32..<44],
            hmacKey: expanded[44..<76]
        )
    }

    private static func pad(plaintext: String) -> Data {
        let bytes = Data(plaintext.utf8)
        let len = bytes.count
        var out = Data(capacity: 2 + calcPaddedLen(len))
        out.append(UInt8(len >> 8))
        out.append(UInt8(len & 0xFF))
        out.append(bytes)
        out.append(contentsOf: Data(repeating: 0, count: calcPaddedLen(len) - len))
        return out
    }

    private static func unpad(padded: Data) throws -> String {
        guard padded.count >= 2 else { throw NIP44Error.invalidPadding }
        let len = Int(padded[0]) << 8 | Int(padded[1])
        guard len >= 1, len <= 65535 else { throw NIP44Error.invalidPadding }
        guard padded.count == 2 + calcPaddedLen(len) else { throw NIP44Error.invalidPadding }
        let content = padded[2..<(2 + len)]
        return String(data: Data(content), encoding: .utf8) ?? ""
    }

    // MARK: - HKDF (manual, to separate extract and expand)

    static func hkdfExtract(ikm: Data, salt: Data) -> Data {
        let authCode = HMAC<CryptoKit.SHA256>.authenticationCode(for: ikm, using: SymmetricKey(data: salt))
        return Data(authCode)
    }

    static func hkdfExpand(prk: Data, info: Data, len: Int) -> Data {
        var okm = Data()
        var t = Data()
        var counter: UInt8 = 1
        while okm.count < len {
            var input = t + info
            input.append(counter)
            t = Data(HMAC<CryptoKit.SHA256>.authenticationCode(for: input, using: SymmetricKey(data: prk)))
            okm.append(t)
            counter += 1
        }
        return okm.prefix(len)
    }

    // MARK: - HMAC-SHA256

    private static func hmacSHA256(key: Data, data: Data) -> Data {
        Data(HMAC<CryptoKit.SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key)))
    }

    // MARK: - ChaCha20 (IETF, 12-byte nonce)

    static func chacha20(key: Data, nonce: Data, data: Data) -> Data {
        precondition(key.count == 32 && nonce.count == 12)
        let k = key.toUInt32LE()
        let n = nonce.toUInt32LE()
        var out = Data(capacity: data.count)
        var offset = 0
        var blockIdx: UInt32 = 0
        while offset < data.count {
            let block = chacha20Block(key: k, counter: blockIdx, nonce: n)
            let blockBytes = block.toDataLE()
            let count = min(64, data.count - offset)
            for i in 0..<count {
                out.append(data[offset + i] ^ blockBytes[i])
            }
            offset += count
            blockIdx &+= 1
        }
        return out
    }

    private static func chacha20Block(key: [UInt32], counter: UInt32, nonce: [UInt32]) -> [UInt32] {
        var s: [UInt32] = [
            0x61707865, 0x3320646e, 0x79622d32, 0x6b206574,
            key[0], key[1], key[2], key[3],
            key[4], key[5], key[6], key[7],
            counter, nonce[0], nonce[1], nonce[2],
        ]
        let initial = s
        for _ in 0..<10 {
            qr(&s, 0, 4,  8, 12); qr(&s, 1, 5,  9, 13)
            qr(&s, 2, 6, 10, 14); qr(&s, 3, 7, 11, 15)
            qr(&s, 0, 5, 10, 15); qr(&s, 1, 6, 11, 12)
            qr(&s, 2, 7,  8, 13); qr(&s, 3, 4,  9, 14)
        }
        return (0..<16).map { s[$0] &+ initial[$0] }
    }

    private static func qr(_ s: inout [UInt32], _ a: Int, _ b: Int, _ c: Int, _ d: Int) {
        s[a] = s[a] &+ s[b]; s[d] = rotl(s[d] ^ s[a], 16)
        s[c] = s[c] &+ s[d]; s[b] = rotl(s[b] ^ s[c], 12)
        s[a] = s[a] &+ s[b]; s[d] = rotl(s[d] ^ s[a], 8)
        s[c] = s[c] &+ s[d]; s[b] = rotl(s[b] ^ s[c], 7)
    }

    private static func rotl(_ x: UInt32, _ n: Int) -> UInt32 {
        (x << UInt32(n)) | (x >> UInt32(32 - n))
    }

    private static func randomBytes(_ count: Int) -> Data {
        Data((0..<count).map { _ in UInt8.random(in: 0...255) })
    }
}

// MARK: - Errors

enum NIP44Error: Error {
    case invalidPayload
    case unknownVersion
    case invalidMAC
    case invalidPadding
}

// MARK: - Data helpers

private extension Data {
    func toUInt32LE() -> [UInt32] {
        stride(from: 0, to: count, by: 4).map { i in
            UInt32(self[i]) |
            (UInt32(self[safe: i + 1] ?? 0) << 8) |
            (UInt32(self[safe: i + 2] ?? 0) << 16) |
            (UInt32(self[safe: i + 3] ?? 0) << 24)
        }
    }

    init?(hexString: String) {
        guard hexString.count % 2 == 0 else { return nil }
        var data = Data(capacity: hexString.count / 2)
        var idx = hexString.startIndex
        while idx < hexString.endIndex {
            let next = hexString.index(idx, offsetBy: 2)
            guard let byte = UInt8(hexString[idx..<next], radix: 16) else { return nil }
            data.append(byte)
            idx = next
        }
        self = data
    }

    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension Array where Element == UInt32 {
    func toDataLE() -> Data {
        var out = Data(capacity: count * 4)
        for w in self {
            out.append(UInt8(w & 0xFF))
            out.append(UInt8((w >> 8) & 0xFF))
            out.append(UInt8((w >> 16) & 0xFF))
            out.append(UInt8((w >> 24) & 0xFF))
        }
        return out
    }
}
