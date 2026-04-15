// Sources/OdysseyCore/Networking/InviteTypes.swift
import Foundation
import CryptoKit

/// Network location hints embedded in an invite payload.
/// Field names match the Mac generator (InviteCodeGenerator.swift).
public struct InviteHints: Codable, Sendable {
    public let lan: String?
    public let wan: String?
    /// TURN relay config — nested inside hints on the Mac side.
    public let turn: TURNConfig?

    public init(lan: String?, wan: String?, turn: TURNConfig? = nil) {
        self.lan = lan
        self.wan = wan
        self.turn = turn
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
/// Field names match the Mac generator (InviteCodeGenerator.swift):
///   v, type, userPublicKey, displayName, tlsCertDER, wsToken, wsPort,
///   hints, exp (unix timestamp), singleUse, sig.
public struct InvitePayload: Codable, Sendable {
    public let v: Int
    public let type: String
    /// Base64-encoded Ed25519 public key bytes (32 bytes).
    public let userPublicKey: String
    public let displayName: String
    /// Base64-encoded DER-encoded TLS certificate.
    public let tlsCertDER: String
    /// Base64-encoded bearer token bytes.
    public let wsToken: String
    public let wsPort: Int
    public let hints: InviteHints
    /// Unix timestamp (seconds since epoch) after which the invite is invalid.
    public let exp: TimeInterval
    public let singleUse: Bool
    /// Base64-encoded Ed25519 signature over canonical JSON (without this field).
    public let sig: String
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
        do {
            return try JSONDecoder().decode(InvitePayload.self, from: data)
        } catch {
            throw InviteDecodeError.decodingFailed(error.localizedDescription)
        }
    }

    /// Verify that the payload has not expired and the Ed25519 signature is valid.
    func verify() throws {
        // Check expiry (exp is a unix timestamp)
        guard exp >= Date().timeIntervalSince1970 else {
            throw InviteDecodeError.expired
        }

        // Decode public key (standard base64, not base64url)
        guard let pubKeyData = Data(base64Encoded: userPublicKey) else {
            throw InviteDecodeError.invalidPublicKey
        }
        let pubKey: Curve25519.Signing.PublicKey
        do {
            pubKey = try Curve25519.Signing.PublicKey(rawRepresentation: pubKeyData)
        } catch {
            throw InviteDecodeError.invalidPublicKey
        }

        // Build canonical JSON without the sig field (matches Mac's canonicalJSONWithoutSig)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard var dict = try? JSONSerialization.jsonObject(
            with: encoder.encode(self), options: []
        ) as? [String: Any] else {
            throw InviteDecodeError.invalidSignature
        }
        dict.removeValue(forKey: "sig")
        let canonical = try JSONSerialization.data(withJSONObject: dict, options: .sortedKeys)

        // Decode signature (standard base64)
        guard let sigData = Data(base64Encoded: sig) else {
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
    case decodingFailed(String)
    case expired
    case invalidPublicKey
    case invalidSignature
    case signatureVerificationFailed

    public var errorDescription: String? {
        switch self {
        case .invalidBase64:               return "Invalid invite link encoding"
        case .decodingFailed(let reason):  return "Failed to decode invite: \(reason)"
        case .expired:                     return "Invite link has expired"
        case .invalidPublicKey:            return "Invalid public key in invite"
        case .invalidSignature:            return "Invalid signature in invite"
        case .signatureVerificationFailed: return "Signature verification failed"
        }
    }
}
