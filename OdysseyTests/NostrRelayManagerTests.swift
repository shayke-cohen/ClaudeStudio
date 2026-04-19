import CryptoKit
import Foundation
import P256K
import XCTest
@testable import Odyssey

// MARK: - NIP-44 Crypto Tests

@MainActor
final class NIP44CryptoTests: XCTestCase {

    func testConversationKey_isSymmetric() throws {
        let kpA = try IdentityManager.shared.nostrKeypair(for: "nip44-test-a-\(UUID())")
        let kpB = try IdentityManager.shared.nostrKeypair(for: "nip44-test-b-\(UUID())")
        let aToB = try NIP44.conversationKey(privkeyHex: kpA.privkeyHex, peerPubkeyHex: kpB.pubkeyHex)
        let bToA = try NIP44.conversationKey(privkeyHex: kpB.privkeyHex, peerPubkeyHex: kpA.pubkeyHex)
        XCTAssertEqual(aToB, bToA, "ECDH must be symmetric: A→B == B→A")
    }

    func testEncryptDecrypt_roundtrip() throws {
        let kpA = try IdentityManager.shared.nostrKeypair(for: "nip44-enc-a-\(UUID())")
        let kpB = try IdentityManager.shared.nostrKeypair(for: "nip44-enc-b-\(UUID())")
        let convKey = try NIP44.conversationKey(privkeyHex: kpA.privkeyHex, peerPubkeyHex: kpB.pubkeyHex)
        let plaintext = "Hello from iOS! This is a session.message command."
        let encrypted = try NIP44.encrypt(plaintext: plaintext, conversationKey: convKey)
        let decrypted = try NIP44.decrypt(payload: encrypted, conversationKey: convKey)
        XCTAssertEqual(decrypted, plaintext)
    }

    func testEncryptDecrypt_emptyString() throws {
        let kpA = try IdentityManager.shared.nostrKeypair(for: "nip44-empty-a-\(UUID())")
        let kpB = try IdentityManager.shared.nostrKeypair(for: "nip44-empty-b-\(UUID())")
        let convKey = try NIP44.conversationKey(privkeyHex: kpA.privkeyHex, peerPubkeyHex: kpB.pubkeyHex)
        let plaintext = "x"  // Minimum 1 byte
        let encrypted = try NIP44.encrypt(plaintext: plaintext, conversationKey: convKey)
        let decrypted = try NIP44.decrypt(payload: encrypted, conversationKey: convKey)
        XCTAssertEqual(decrypted, plaintext)
    }

    func testEncryptDecrypt_longMessage() throws {
        let kpA = try IdentityManager.shared.nostrKeypair(for: "nip44-long-a-\(UUID())")
        let kpB = try IdentityManager.shared.nostrKeypair(for: "nip44-long-b-\(UUID())")
        let convKey = try NIP44.conversationKey(privkeyHex: kpA.privkeyHex, peerPubkeyHex: kpB.pubkeyHex)
        let plaintext = String(repeating: "A", count: 1000)
        let encrypted = try NIP44.encrypt(plaintext: plaintext, conversationKey: convKey)
        let decrypted = try NIP44.decrypt(payload: encrypted, conversationKey: convKey)
        XCTAssertEqual(decrypted, plaintext)
    }

    func testDecrypt_wrongKey_throws() throws {
        let kpA = try IdentityManager.shared.nostrKeypair(for: "nip44-wrongkey-a-\(UUID())")
        let kpB = try IdentityManager.shared.nostrKeypair(for: "nip44-wrongkey-b-\(UUID())")
        let kpC = try IdentityManager.shared.nostrKeypair(for: "nip44-wrongkey-c-\(UUID())")
        let convKeyAB = try NIP44.conversationKey(privkeyHex: kpA.privkeyHex, peerPubkeyHex: kpB.pubkeyHex)
        let convKeyAC = try NIP44.conversationKey(privkeyHex: kpA.privkeyHex, peerPubkeyHex: kpC.pubkeyHex)
        let encrypted = try NIP44.encrypt(plaintext: "secret", conversationKey: convKeyAB)
        XCTAssertThrowsError(try NIP44.decrypt(payload: encrypted, conversationKey: convKeyAC),
            "Decryption with wrong key must throw (MAC mismatch)")
    }

    func testCalcPaddedLen_boundaryCases() {
        XCTAssertEqual(NIP44.calcPaddedLen(1), 32)
        XCTAssertEqual(NIP44.calcPaddedLen(32), 32)
        XCTAssertEqual(NIP44.calcPaddedLen(33), 64)
        XCTAssertEqual(NIP44.calcPaddedLen(64), 64)
        XCTAssertEqual(NIP44.calcPaddedLen(65), 96)
    }

    func testEncrypt_producesValidBase64Payload() throws {
        let kpA = try IdentityManager.shared.nostrKeypair(for: "nip44-b64-a-\(UUID())")
        let kpB = try IdentityManager.shared.nostrKeypair(for: "nip44-b64-b-\(UUID())")
        let convKey = try NIP44.conversationKey(privkeyHex: kpA.privkeyHex, peerPubkeyHex: kpB.pubkeyHex)
        let payload = try NIP44.encrypt(plaintext: "test", conversationKey: convKey)
        let decoded = Data(base64Encoded: payload)
        XCTAssertNotNil(decoded, "Payload must be valid base64")
        XCTAssertEqual(decoded?.first, 0x02, "First byte must be version 0x02")
        XCTAssertGreaterThanOrEqual(decoded?.count ?? 0, 99, "Minimum payload size is 99 bytes")
    }
}

// MARK: - NostrRelayManager Message Format Tests

@MainActor
final class NostrRelayManagerMessageTests: XCTestCase {

    func testBuildREQMessage_includesNpubFilter() {
        let npub = "abc123deadbeef0123456789abcdef01234567890123456789abcdef01234567"
        let req = NostrRelayManager.buildREQMessage(subscriptionId: "sub1", npub: npub)
        guard let data = req.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            XCTFail("REQ message must be valid JSON array")
            return
        }
        XCTAssertEqual(json[0] as? String, "REQ")
        XCTAssertEqual(json[1] as? String, "sub1")
        let filter = json[2] as? [String: Any]
        let pTags = filter?["#p"] as? [String]
        XCTAssertEqual(pTags?.first, npub, "Filter must address events to our npub")
    }

    func testBuildEVENTMessage_isValidJSON() throws {
        let eventJSON = """
        {"id":"abc","pubkey":"def","created_at":1234,"kind":4,"tags":[],"content":"hello","sig":"xyz"}
        """
        let msg = NostrRelayManager.buildEVENTMessage(eventJSON: eventJSON)
        guard let data = msg.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            XCTFail("EVENT message must be valid JSON array")
            return
        }
        XCTAssertEqual(json[0] as? String, "EVENT")
    }

    func testParseEVENT_extractsFields() {
        let eventJSON = """
        ["EVENT","sub1",{"id":"aabbcc","pubkey":"ddeeff","created_at":1700000000,"kind":4,"tags":[["p","11223344"]],"content":"encrypted","sig":"aabb"}]
        """
        let event = NostrRelayManager.parseIncomingEvent(message: eventJSON)
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.id, "aabbcc")
        XCTAssertEqual(event?.pubkey, "ddeeff")
        XCTAssertEqual(event?.content, "encrypted")
        XCTAssertEqual(event?.kind, 4)
    }

    func testParseEVENT_nonEventMessage_returnsNil() {
        let okMsg = """
        ["OK","aabb",true,""]
        """
        XCTAssertNil(NostrRelayManager.parseIncomingEvent(message: okMsg))
    }

    func testBackoffDurations() {
        let durations = (0..<6).map { NostrRelayManager.backoffDuration(attempt: $0) }
        XCTAssertEqual(durations[0], 1.0)
        XCTAssertEqual(durations[1], 2.0)
        XCTAssertEqual(durations[2], 4.0)
        XCTAssertLessThanOrEqual(durations[5], 30.0, "Backoff must cap at 30s")
    }
}
