// Sources/OdysseyCore/Networking/InviteTypes.swift
import Foundation

/// Version-2 invite payload — contains only what is needed to establish a Nostr relay
/// connection. No TLS certs, no bearer tokens, no expiry. Security is provided by
/// NIP-44 encryption using the exchanged Nostr public keys.
public struct InvitePayload: Codable, Sendable {
    public let v: Int           // 2
    public let type: String     // "device"
    /// Mac's secp256k1 Nostr public key (hex, 64 chars).
    public let macNpub: String
    public let displayName: String
    /// Preferred Nostr relay URLs.
    public let relays: [String]
    /// Optional LAN IP hint (no port). Used for HTTP data loading when on the same network.
    public let lanHint: String?

    public init(
        v: Int = 2,
        type: String = "device",
        macNpub: String,
        displayName: String,
        relays: [String],
        lanHint: String?
    ) {
        self.v = v
        self.type = type
        self.macNpub = macNpub
        self.displayName = displayName
        self.relays = relays
        self.lanHint = lanHint
    }
}

// MARK: - Decode helpers

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
}

/// Errors thrown by `InvitePayload.decode(_:)`.
public enum InviteDecodeError: LocalizedError {
    case invalidBase64
    case decodingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidBase64:               return "Invalid invite link encoding"
        case .decodingFailed(let reason):  return "Failed to decode invite: \(reason)"
        }
    }
}
