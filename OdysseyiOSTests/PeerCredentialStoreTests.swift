// OdysseyiOSTests/PeerCredentialStoreTests.swift
import XCTest
@testable import OdysseyiOS
import OdysseyCore

final class PeerCredentialStoreTests: XCTestCase {

    private var store: PeerCredentialStore!
    private let testService = "com.odyssey.tests.credentials-\(UUID().uuidString)"

    override func setUp() {
        super.setUp()
        store = PeerCredentialStore(keychainService: testService)
    }

    override func tearDown() {
        try? store.deleteAll()
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeCreds(id: UUID = UUID(), displayName: String = "Test Mac") -> PeerCredentials {
        PeerCredentials(
            id: id,
            displayName: displayName,
            userPublicKeyData: Data(repeating: 0xAB, count: 32),
            tlsCertDER: Data(repeating: 0xCD, count: 512),
            wsToken: "token-\(UUID().uuidString)",
            wsPort: 9849,
            lanHint: "192.168.1.100:9849",
            wanHint: nil,
            turnConfig: nil,
            pairedAt: Date(),
            lastConnectedAt: nil,
            claudeSessionIds: [:]
        )
    }

    // MARK: - Tests

    func testSaveAndLoad() throws {
        let creds = makeCreds()
        try store.save(creds)
        let loaded = try store.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, creds.id)
        XCTAssertEqual(loaded[0].displayName, creds.displayName)
        XCTAssertEqual(loaded[0].wsToken, creds.wsToken)
    }

    func testLoadEmpty() throws {
        let loaded = try store.load()
        XCTAssertTrue(loaded.isEmpty)
    }

    func testMultiplePeers() throws {
        let a = makeCreds(displayName: "Mac A")
        let b = makeCreds(displayName: "Mac B")
        try store.save(a)
        try store.save(b)
        let loaded = try store.load()
        XCTAssertEqual(loaded.count, 2)
    }

    func testSessionIdPersistence() throws {
        var creds = makeCreds(displayName: "Original")
        try store.save(creds)
        creds = PeerCredentials(
            id: creds.id,
            displayName: "Updated",
            userPublicKeyData: creds.userPublicKeyData,
            tlsCertDER: creds.tlsCertDER,
            wsToken: creds.wsToken,
            wsPort: creds.wsPort,
            lanHint: creds.lanHint,
            wanHint: creds.wanHint,
            turnConfig: creds.turnConfig,
            pairedAt: creds.pairedAt,
            lastConnectedAt: Date(),
            claudeSessionIds: ["conv-1": "claude-abc"]
        )
        try store.update(creds)
        let loaded = try store.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].displayName, "Updated")
        XCTAssertEqual(loaded[0].claudeSessionIds["conv-1"], "claude-abc")
    }

    func testDeleteRemovesPeer() throws {
        let a = makeCreds(displayName: "A")
        let b = makeCreds(displayName: "B")
        try store.save(a)
        try store.save(b)
        try store.delete(id: a.id)
        let loaded = try store.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, b.id)
    }

    func testDeleteAll() throws {
        try store.save(makeCreds())
        try store.save(makeCreds())
        try store.deleteAll()
        let loaded = try store.load()
        XCTAssertTrue(loaded.isEmpty)
    }

    func testTurnConfigRoundtrip() throws {
        var creds = makeCreds()
        // Re-create with turnConfig
        let turn = TURNConfig(url: "turn:example.com", username: "user", credential: "pass")
        let credsWithTurn = PeerCredentials(
            id: creds.id,
            displayName: creds.displayName,
            userPublicKeyData: creds.userPublicKeyData,
            tlsCertDER: creds.tlsCertDER,
            wsToken: creds.wsToken,
            wsPort: creds.wsPort,
            lanHint: creds.lanHint,
            wanHint: "203.0.113.1:9849",
            turnConfig: turn,
            pairedAt: creds.pairedAt,
            lastConnectedAt: nil,
            claudeSessionIds: [:]
        )
        try store.save(credsWithTurn)
        let loaded = try store.load()
        XCTAssertEqual(loaded[0].turnConfig?.url, "turn:example.com")
        XCTAssertEqual(loaded[0].wanHint, "203.0.113.1:9849")
    }
}
