import Foundation
import SwiftData
import XCTest
@testable import Odyssey

/// Lightweight SwiftData round-trip tests for models that had no direct
/// coverage: NostrPeer, ConversationMessage.
@MainActor
final class CoreModelTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for:
                Agent.self, Session.self, Skill.self, MCPServer.self,
                PermissionSet.self, AgentGroup.self,
                NostrPeer.self, ConversationMessage.self, Conversation.self,
            configurations: config
        )
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
    }

    // ─── NostrPeer ────────────────────────────────────────────

    func testNostrPeer_roundTrip() throws {
        let peer = NostrPeer(
            displayName: "Alex's Mac",
            pubkeyHex: String(repeating: "a", count: 64),
            relays: ["wss://relay.damus.io", "wss://nos.lol"]
        )
        context.insert(peer)
        try context.save()

        let pubkey = peer.pubkeyHex
        let fetched = try context.fetch(
            FetchDescriptor<NostrPeer>(predicate: #Predicate { $0.pubkeyHex == pubkey })
        ).first
        XCTAssertEqual(fetched?.displayName, "Alex's Mac")
        XCTAssertEqual(fetched?.relays.count, 2)
        XCTAssertNil(fetched?.lastSeenAt)
    }

    func testNostrPeer_updateLastSeen() throws {
        let peer = NostrPeer(
            displayName: "Bob",
            pubkeyHex: String(repeating: "b", count: 64),
            relays: ["wss://relay"]
        )
        context.insert(peer)
        let now = Date()
        peer.lastSeenAt = now
        try context.save()
        XCTAssertNotNil(peer.lastSeenAt)
    }
}
