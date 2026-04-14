import CryptoKit
import XCTest
@testable import Odyssey

@MainActor
final class IdentityManagerTests: XCTestCase {

    // Use a unique instance name per test run to avoid Keychain collisions
    private let testInstance = "test-\(UUID().uuidString)"

    override func tearDown() async throws {
        // Clean up Keychain entries created during tests so they don't leak
        try? IdentityManager.shared.deleteKeychainItem(
            forKey: "odyssey.identity.\(testInstance)"
        )
        try? IdentityManager.shared.deleteKeychainItem(
            forKey: "odyssey.wstoken.\(testInstance)"
        )
    }

    // MARK: - IM1: Keypair generation and persistence

    func testIM1_keypairGenerationAndPersistence() throws {
        let first = try IdentityManager.shared.userIdentity(for: testInstance)
        let second = try IdentityManager.shared.userIdentity(for: testInstance)
        XCTAssertEqual(first.publicKeyData, second.publicKeyData,
            "Same instance must return same public key bytes on repeated calls")
        XCTAssertEqual(first.publicKeyData.count, 32,
            "Curve25519 public key must be exactly 32 bytes")
    }

    // MARK: - IM2: Sign and verify round-trip

    func testIM2_signAndVerify() throws {
        let identity = try IdentityManager.shared.userIdentity(for: testInstance)
        let payload = Data("hello odyssey".utf8)
        let signature = try IdentityManager.shared.sign(payload, instanceName: testInstance)

        let pubKey = try Curve25519.Signing.PublicKey(rawRepresentation: identity.publicKeyData)
        XCTAssertTrue(pubKey.isValidSignature(signature, for: payload),
            "Signature produced by sign() must verify with the corresponding public key")
    }

    // MARK: - IM3: Agent bundle signature verification

    func testIM3_agentBundleSignature() throws {
        let agentId = UUID()
        // Note: agentBundle() generates a fresh ephemeral keypair for the agent.
        // The agent private key is NOT stored in Keychain (only used to sign the bundle),
        // so no tearDown cleanup is needed for this test.
        let bundle = try IdentityManager.shared.agentBundle(
            for: agentId,
            agentName: "TestAgent",
            instanceName: testInstance
        )

        // Reconstruct the signed message: agentPublicKey ++ agentId.uuidBytes ++ agentName.utf8
        var message = bundle.agentPublicKeyData
        message.append(contentsOf: agentId.uuidBytes)
        message.append(contentsOf: Data("TestAgent".utf8))

        let ownerPubKey = try Curve25519.Signing.PublicKey(rawRepresentation: bundle.ownerPublicKeyData)
        XCTAssertTrue(ownerPubKey.isValidSignature(bundle.ownerSignature, for: message),
            "ownerSignature must be a valid Ed25519 signature over agentPublicKey++agentId++agentName")
    }

    // MARK: - IM4: WS token format — base64, 32 bytes, stable

    func testIM4_wsTokenFormat() throws {
        let token = try IdentityManager.shared.wsToken(for: testInstance)
        let decoded = try XCTUnwrap(Data(base64Encoded: token), "wsToken must be valid base64")
        XCTAssertEqual(decoded.count, 32, "WS token must decode to exactly 32 bytes")

        let second = try IdentityManager.shared.wsToken(for: testInstance)
        XCTAssertEqual(token, second,
            "Repeated calls to wsToken(for:) must return the same token")
    }

    // MARK: - IM5: WS token rotation produces a new value

    func testIM5_wsTokenRotation() throws {
        let original = try IdentityManager.shared.wsToken(for: testInstance)
        let rotated = try IdentityManager.shared.rotateWSToken(for: testInstance)
        XCTAssertNotEqual(original, rotated,
            "rotateWSToken must produce a different token than the previous one")
    }

    // MARK: - IM6: Distinct instances have different keys

    func testIM6_distinctInstancesHaveDifferentKeys() throws {
        let instanceA = "\(testInstance)-a"
        let instanceB = "\(testInstance)-b"
        defer {
            try? IdentityManager.shared.deleteKeychainItem(forKey: "odyssey.identity.\(instanceA)")
            try? IdentityManager.shared.deleteKeychainItem(forKey: "odyssey.identity.\(instanceB)")
        }

        let identityA = try IdentityManager.shared.userIdentity(for: instanceA)
        let identityB = try IdentityManager.shared.userIdentity(for: instanceB)
        XCTAssertNotEqual(identityA.publicKeyData, identityB.publicKeyData,
            "Different instance names must produce different keypairs")
    }

    // MARK: - IM8: verifyAgentBundle round-trip

    func testIM8_verifyAgentBundleSucceeds() throws {
        let agentId = UUID()
        let bundle = try IdentityManager.shared.agentBundle(
            for: agentId,
            agentName: "VerifyAgent",
            instanceName: testInstance
        )
        XCTAssertTrue(
            IdentityManager.shared.verifyAgentBundle(bundle),
            "verifyAgentBundle must return true for a bundle produced by agentBundle()"
        )
    }

    func testIM9_verifyAgentBundleFailsWithTamperedAgentName() throws {
        let agentId = UUID()
        let bundle = try IdentityManager.shared.agentBundle(
            for: agentId,
            agentName: "Original",
            instanceName: testInstance
        )
        let tampered = AgentIdentityBundle(
            agentPublicKeyData: bundle.agentPublicKeyData,
            agentId: bundle.agentId,
            agentName: "Tampered",
            ownerPublicKeyData: bundle.ownerPublicKeyData,
            ownerSignature: bundle.ownerSignature,
            createdAt: bundle.createdAt
        )
        XCTAssertFalse(
            IdentityManager.shared.verifyAgentBundle(tampered),
            "verifyAgentBundle must return false when agentName is tampered"
        )
    }

    func testIM10_ownerDisplayNameReturnsNilForUnknownBundle() throws {
        // Phase 1 TODO: ownerDisplayName currently stubs to nil because the UserIdentity
        // fingerprint registry is not yet wired up. Once Phase 1 is complete, this test
        // should be updated to assert a non-nil display name for a known owner bundle.
        throw XCTSkip("ownerDisplayName lookup not yet implemented (Phase 1 stub)")
    }

    // MARK: - IM7: TLS bundle generation

    func testIM7_tlsBundleGeneration() throws {
        let bundle = try IdentityManager.shared.tlsCertificate(for: testInstance)

        defer {
            // Remove the entire instance directory (cert, key, and directory itself)
            let instanceDir = "\(NSHomeDirectory())/.odyssey/instances/\(testInstance)"
            try? FileManager.default.removeItem(atPath: instanceDir)
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: bundle.certPEMPath),
            "TLS cert PEM file must exist at the returned path")
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundle.keyPEMPath),
            "TLS key PEM file must exist at the returned path")
        XCTAssertFalse(bundle.certDERData.isEmpty,
            "certDERData must be non-empty")

        let bundle2 = try IdentityManager.shared.tlsCertificate(for: testInstance)
        XCTAssertEqual(bundle.certDERData, bundle2.certDERData,
            "Repeated calls must return the cached cert, not regenerate it")
    }
}
