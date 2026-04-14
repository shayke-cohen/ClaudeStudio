// Sources/OdysseyCore/Networking/InviteTypes.swift
import Foundation
import CryptoKit

/// Network location hints embedded in an invite payload.
public struct InviteHints: Codable, Sendable {
    public let lan: String?
    public let wan: String?
    public let bonjour: String?

    public init(lan: String?, wan: String?, bonjour: String?) {
        self.lan = lan
        self.wan = wan
        self.bonjour = bonjour
    }
}

/// TURN relay configuration for NAT traversal fallback.
public struct TURNConfig: Codable, Sendable {
    public let url: String
    public let username: String
    public let credential: String

    public init(url: String, username: String, credential: String) {
        self.url = url
        self.username = username
        self.credential = credential
    }
}

/// The signed payload embedded in an invite QR code or deep link.
public struct InvitePayload: Codable, Sendable {
    public let hostPublicKeyBase64url: String
    public let hostDisplayName: String
    public let bearerToken: String
    public let tlsCertDERBase64: String
    public let hints: InviteHints
    public let turn: TURNConfig?
    public let expiresAt: String
    public let signature: String

    public init(
        hostPublicKeyBase64url: String,
        hostDisplayName: String,
        bearerToken: String,
        tlsCertDERBase64: String,
        hints: InviteHints,
        turn: TURNConfig?,
        expiresAt: String,
        signature: String
    ) {
        self.hostPublicKeyBase64url = hostPublicKeyBase64url
        self.hostDisplayName = hostDisplayName
        self.bearerToken = bearerToken
        self.tlsCertDERBase64 = tlsCertDERBase64
        self.hints = hints
        self.turn = turn
        self.expiresAt = expiresAt
        self.signature = signature
    }
}

// MARK: - Decode / Verify helpers

public extension InvitePayload {
    /// Decode a base64url-encoded JSON invite payload.
    static func decode(_ base64url: String) throws -> InvitePayload {
        var base64 = base64url
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 { base64 += String(repeating: "=", count: 4 - remainder) }
        guard let data = Data(base64Encoded: base64) else {
            throw InviteDecodeError.invalidBase64
        }
        return try JSONDecoder().decode(InvitePayload.self, from: data)
    }

    /// Verify that the payload has not expired and the Ed25519 signature is valid.
    func verify() throws {
        // Check expiry
        let formatter = ISO8601DateFormatter()
        if let expiry = formatter.date(from: expiresAt), expiry < Date() {
            throw InviteDecodeError.expired
        }
        // Decode public key
        var pubBase64 = hostPublicKeyBase64url
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let pubRemainder = pubBase64.count % 4
        if pubRemainder != 0 { pubBase64 += String(repeating: "=", count: 4 - pubRemainder) }
        guard let pubKeyData = Data(base64Encoded: pubBase64) else {
            throw InviteDecodeError.invalidPublicKey
        }
        let pubKey: Curve25519.Signing.PublicKey
        do {
            pubKey = try Curve25519.Signing.PublicKey(rawRepresentation: pubKeyData)
        } catch {
            throw InviteDecodeError.invalidPublicKey
        }
        // Build canonical payload (all fields except signature) for verification.
        // Canonical form omits nil/null fields at every level (matches TypeScript generator
        // which filters null/undefined with encodeIfPresent semantics).
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard var dict = try? JSONSerialization.jsonObject(
            with: encoder.encode(self), options: []
        ) as? [String: Any] else {
            throw InviteDecodeError.invalidSignature
        }
        dict.removeValue(forKey: "signature")
        // Strip NSNull values recursively so nil optionals are excluded from the canonical bytes.
        func stripNulls(_ value: Any) -> Any? {
            if value is NSNull { return nil }
            if var d = value as? [String: Any] {
                for (k, v) in d {
                    if let stripped = stripNulls(v) { d[k] = stripped } else { d.removeValue(forKey: k) }
                }
                return d
            }
            if let arr = value as? [Any] { return arr.compactMap { stripNulls($0) } }
            return value
        }
        guard let stripped = stripNulls(dict) as? [String: Any] else {
            throw InviteDecodeError.invalidSignature
        }
        let rawCanonical = try JSONSerialization.data(withJSONObject: stripped, options: .sortedKeys)
        // NSJSONSerialization escapes '/' as '\/' but TypeScript's JSON.stringify does not.
        // Unescape '\/' → '/' so canonical bytes match the TypeScript-signed payload.
        guard let canonicalStr = String(data: rawCanonical, encoding: .utf8) else {
            throw InviteDecodeError.invalidSignature
        }
        let canonical = canonicalStr
            .replacingOccurrences(of: "\\/", with: "/")
            .data(using: .utf8)!
        // Decode signature
        var sigBase64 = signature
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let sigRemainder = sigBase64.count % 4
        if sigRemainder != 0 { sigBase64 += String(repeating: "=", count: 4 - sigRemainder) }
        guard let sigData = Data(base64Encoded: sigBase64) else {
            throw InviteDecodeError.invalidSignature
        }
        guard pubKey.isValidSignature(sigData, for: canonical) else {
            throw InviteDecodeError.signatureVerificationFailed
        }
    }
}

/// Errors thrown by `InvitePayload.decode(_:)` and `InvitePayload.verify()`.
public enum InviteDecodeError: LocalizedError {
    case invalidBase64
    case expired
    case invalidPublicKey
    case invalidSignature
    case signatureVerificationFailed

    public var errorDescription: String? {
        switch self {
        case .invalidBase64:             return "Invalid invite link encoding"
        case .expired:                   return "Invite link has expired"
        case .invalidPublicKey:          return "Invalid public key in invite"
        case .invalidSignature:          return "Invalid signature in invite"
        case .signatureVerificationFailed: return "Signature verification failed"
        }
    }
}
