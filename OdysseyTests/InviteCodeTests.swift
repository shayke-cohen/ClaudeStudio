// OdysseyTests/InviteCodeTests.swift
import CryptoKit
import XCTest
@testable import Odyssey

final class InviteCodeTests: XCTestCase {

    // MARK: - Helpers

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

    // MARK: - Tests

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

    func testExpiredInviteRejected() throws {
        let (payload, _) = try makeSignedPayload(exp: Date().addingTimeInterval(-60).timeIntervalSince1970)
        XCTAssertThrowsError(try InviteCodeGenerator.verify(payload)) { error in
            XCTAssertEqual(error as? InviteCodeError, .expired)
        }
    }

    func testTamperedInviteRejected() throws {
        var (payload, _) = try makeSignedPayload()
        // Replace displayName but keep the original sig — signature should fail.
        payload = InvitePayload(
            v: payload.v,
            type: payload.type,
            userPublicKey: payload.userPublicKey,
            displayName: "EVIL HACKER",
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

    func testBase64UrlEncoding() {
        let data = Data([0xFB, 0xFF, 0xFE, 0xFD, 0xFC])
        let encoded = InviteCodeGenerator.base64urlEncode(data)
        XCTAssertFalse(encoded.contains("+"))
        XCTAssertFalse(encoded.contains("/"))
        XCTAssertFalse(encoded.contains("="))
        let decoded = InviteCodeGenerator.base64urlDecode(encoded)
        XCTAssertEqual(decoded, data)
    }

    func testBase64UrlRoundtripVariousLengths() {
        for length in [1, 2, 3, 4, 16, 31, 32, 33, 64, 100] {
            var bytes = [UInt8](repeating: 0, count: length)
            for i in 0..<length { bytes[i] = UInt8(i % 256) }
            let data = Data(bytes)
            let encoded = InviteCodeGenerator.base64urlEncode(data)
            XCTAssertEqual(
                InviteCodeGenerator.base64urlDecode(encoded), data,
                "Roundtrip failed for length \(length)"
            )
        }
    }

    func testQRCodeProducesValidImage() throws {
        let (payload, _) = try makeSignedPayload()
        let cgImage = InviteCodeGenerator.qrCode(for: payload, size: 300)
        XCTAssertNotNil(cgImage, "qrCode(for:) must return a non-nil CGImage")
        if let img = cgImage {
            XCTAssertGreaterThan(img.width, 0)
            XCTAssertGreaterThan(img.height, 0)
        }
    }

    func testCanonicalJSONExcludesSig() throws {
        let (payload, _) = try makeSignedPayload()
        let canonical = try InviteCodeGenerator.canonicalJSONWithoutSig(payload)
        let dict = try JSONSerialization.jsonObject(with: canonical) as? [String: Any]
        XCTAssertNotNil(dict)
        XCTAssertNil(dict?["sig"])
        XCTAssertNotNil(dict?["v"])
        XCTAssertNotNil(dict?["userPublicKey"])
    }

    func testCanonicalJSONIsDeterministic() throws {
        let (payload, _) = try makeSignedPayload()
        let a = try InviteCodeGenerator.canonicalJSONWithoutSig(payload)
        let b = try InviteCodeGenerator.canonicalJSONWithoutSig(payload)
        XCTAssertEqual(a, b)
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

// MARK: - InviteCodeError: Equatable

extension InviteCodeError: Equatable {
    public static func == (lhs: InviteCodeError, rhs: InviteCodeError) -> Bool {
        switch (lhs, rhs) {
        case (.identityUnavailable, .identityUnavailable): return true
        case (.encodingFailed, .encodingFailed): return true
        case (.signatureVerificationFailed, .signatureVerificationFailed): return true
        case (.expired, .expired): return true
        case (.certificateExportFailed, .certificateExportFailed): return true
        case (.decodingFailed(let a), .decodingFailed(let b)): return a == b
        default: return false
        }
    }
}
