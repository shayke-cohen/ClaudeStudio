// Odyssey/Services/InviteCodeGenerator.swift
import CryptoKit
import CoreGraphics
import CoreImage
import Foundation
import OSLog
import OdysseyCore

private let logger = Logger(subsystem: "com.odyssey.app", category: "InviteCode")

// MARK: - Invite Payload Types

struct InviteHints: Codable, Sendable, Equatable {
    let lan: String?
    let wan: String?
    let turn: OdysseyCore.TURNConfig?
}

struct InvitePayload: Codable, Sendable, Equatable {
    let v: Int
    let type: String
    /// Base64-encoded Ed25519 public key bytes (32 bytes).
    let userPublicKey: String
    let displayName: String
    /// Base64-encoded DER-encoded TLS certificate.
    let tlsCertDER: String
    /// Base64-encoded bearer token bytes.
    let wsToken: String
    let wsPort: Int
    let hints: InviteHints
    /// Unix timestamp (seconds since epoch) after which the invite is invalid.
    let exp: TimeInterval
    let singleUse: Bool
    /// Base64-encoded Ed25519 signature over canonical JSON (without this field).
    /// Empty string before signing.
    var sig: String
}

// MARK: - Errors

enum InviteCodeError: LocalizedError {
    case identityUnavailable
    case encodingFailed
    case decodingFailed(String)
    case signatureVerificationFailed
    case expired
    case certificateExportFailed

    var errorDescription: String? {
        switch self {
        case .identityUnavailable:
            return "Local identity is unavailable."
        case .encodingFailed:
            return "Failed to encode invite payload."
        case .decodingFailed(let reason):
            return "Failed to decode invite payload: \(reason)"
        case .signatureVerificationFailed:
            return "Invite signature verification failed."
        case .expired:
            return "Invite has expired."
        case .certificateExportFailed:
            return "Failed to export TLS certificate."
        }
    }
}

// MARK: - InviteCodeGenerator

struct InviteCodeGenerator {

    /// Generate a signed device-invite payload using the local IdentityManager.
    ///
    /// Must be called from a `@MainActor` context because `IdentityManager.shared`
    /// is `@MainActor`-isolated.
    @MainActor
    static func generateDevice(
        instanceName: String,
        wsPort: Int = 9849,
        expiresIn: TimeInterval = 300,
        singleUse: Bool = true,
        lanHint: String?,
        wanHint: String?,
        turnConfig: OdysseyCore.TURNConfig? = nil
    ) async throws -> InvitePayload {
        let identityManager = IdentityManager.shared

        // Retrieve or generate the Ed25519 identity for this instance.
        let identity: UserIdentity
        do {
            identity = try identityManager.userIdentity(for: instanceName)
        } catch {
            logger.error("InviteCodeGenerator: failed to load identity for '\(instanceName, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            throw InviteCodeError.identityUnavailable
        }

        // wsToken is already base64-encoded by IdentityManager.
        let wsToken: String
        do {
            wsToken = try identityManager.wsToken(for: instanceName)
        } catch {
            logger.error("InviteCodeGenerator: failed to load WS token for '\(instanceName, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            throw InviteCodeError.identityUnavailable
        }

        // Retrieve the TLS certificate; certDERData contains the raw DER bytes.
        let tlsBundle: TLSBundle
        do {
            tlsBundle = try identityManager.tlsCertificate(for: instanceName)
        } catch {
            logger.error("InviteCodeGenerator: failed to load TLS cert for '\(instanceName, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            throw InviteCodeError.certificateExportFailed
        }

        let hints = InviteHints(lan: lanHint, wan: wanHint, turn: turnConfig)

        var payload = InvitePayload(
            v: 1,
            type: "device",
            userPublicKey: identity.publicKeyData.base64EncodedString(),
            displayName: identity.displayName,
            tlsCertDER: tlsBundle.certDERData.base64EncodedString(),
            wsToken: wsToken,
            wsPort: wsPort,
            hints: hints,
            exp: Date().addingTimeInterval(expiresIn).timeIntervalSince1970,
            singleUse: singleUse,
            sig: ""
        )

        // Sign the canonical JSON (without the sig field).
        do {
            let sigData = try signPayload(payload, instanceName: instanceName)
            payload.sig = sigData.base64EncodedString()
        } catch {
            logger.error("InviteCodeGenerator: signing failed: \(error.localizedDescription)")
            throw InviteCodeError.identityUnavailable
        }

        logger.info("InviteCodeGenerator: generated device invite for '\(instanceName, privacy: .public)'")
        return payload
    }

    // MARK: - Encode / Decode

    /// Encode a payload to a URL-safe base64url string.
    static func encode(_ payload: InvitePayload) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(payload)
        return base64urlEncode(data)
    }

    /// Decode a base64url string back to an `InvitePayload`.
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

    // MARK: - Verification

    /// Verify the expiry and Ed25519 signature on a decoded payload.
    static func verify(_ payload: InvitePayload) throws {
        guard payload.exp >= Date().timeIntervalSince1970 else {
            throw InviteCodeError.expired
        }

        guard let pubKeyData = Data(base64Encoded: payload.userPublicKey),
              let curve25519PubKey = try? Curve25519.Signing.PublicKey(rawRepresentation: pubKeyData)
        else {
            throw InviteCodeError.signatureVerificationFailed
        }

        guard let sigData = Data(base64Encoded: payload.sig) else {
            throw InviteCodeError.signatureVerificationFailed
        }

        let signedBytes = try canonicalJSONWithoutSig(payload)
        guard curve25519PubKey.isValidSignature(sigData, for: signedBytes) else {
            throw InviteCodeError.signatureVerificationFailed
        }
    }

    // MARK: - QR Code

    /// Render a QR code for the `odyssey://connect?invite=<encoded>` deep link.
    /// Returns `nil` if encoding fails or CIFilter is unavailable.
    static func qrCode(for payload: InvitePayload, size: CGFloat = 300) -> CGImage? {
        guard let encoded = try? encode(payload),
              let inputData = "odyssey://connect?invite=\(encoded)".data(using: .utf8)
        else { return nil }

        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(inputData, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let ciImage = filter.outputImage else { return nil }

        let scaleX = size / ciImage.extent.width
        let scaleY = size / ciImage.extent.height
        let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        let context = CIContext()
        return context.createCGImage(scaledImage, from: scaledImage.extent)
    }

    // MARK: - Canonical JSON

    /// Produce deterministic JSON bytes with the `sig` key removed, for signing/verification.
    static func canonicalJSONWithoutSig(_ payload: InvitePayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let fullData = try encoder.encode(payload)

        guard var dict = try JSONSerialization.jsonObject(with: fullData) as? [String: Any] else {
            throw InviteCodeError.encodingFailed
        }
        dict.removeValue(forKey: "sig")
        return try JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
    }

    // MARK: - Base64url Helpers

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
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }

    // MARK: - User Federation Invite (Phase 6)

    /// Generates a signed invite payload for user-level federation via Matrix.
    @MainActor
    static func generateUser(
        instanceName: String,
        matrixUserId: String,
        expiresIn: TimeInterval = 7 * 24 * 60 * 60  // 7 days
    ) throws -> String {
        let now = Date()
        let payload: [String: Any] = [
            "type": "user",
            "instanceName": instanceName,
            "matrixUserId": matrixUserId,
            "issuedAt": Int(now.timeIntervalSince1970),
            "expiresAt": Int(now.addingTimeInterval(expiresIn).timeIntervalSince1970),
            "nonce": UUID().uuidString
        ]
        let canonicalJSON = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let signature = try IdentityManager.shared.sign(canonicalJSON, instanceName: instanceName)
        let envelope: [String: Any] = [
            "payload": String(data: canonicalJSON, encoding: .utf8)!,
            "signature": signature.base64EncodedString()
        ]
        let envelopeData = try JSONSerialization.data(withJSONObject: envelope)
        return base64urlEncode(envelopeData)
    }

    // MARK: - Private

    @MainActor
    private static func signPayload(_ payload: InvitePayload, instanceName: String) throws -> Data {
        let bytes = try canonicalJSONWithoutSig(payload)
        return try IdentityManager.shared.sign(bytes, instanceName: instanceName)
    }
}
