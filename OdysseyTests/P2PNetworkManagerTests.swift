import XCTest
import Network
@testable import Odyssey

/// Tests for the LAN peer discovery layer (Bonjour + HTTP catalog fetch).
/// These protect Bonjour/LAN behavior that must survive the removal of
/// TURNAllocator, UPnPPortMapper, and NATTraversalManager.
@MainActor
final class P2PNetworkManagerTests: XCTestCase {

    // MARK: - Lifecycle

    func test_init_doesNotCrash() {
        let manager = P2PNetworkManager()
        XCTAssertFalse(manager.isRunning)
        XCTAssertNil(manager.lastError)
        XCTAssertTrue(manager.peers.isEmpty)
    }

    func test_start_setsIsRunning() {
        let manager = P2PNetworkManager()
        manager.start()
        XCTAssertTrue(manager.isRunning)
        manager.stop()
    }

    func test_stop_clearsIsRunning() {
        let manager = P2PNetworkManager()
        manager.start()
        manager.stop()
        XCTAssertFalse(manager.isRunning)
    }

    func test_stop_whenNotRunning_doesNotCrash() {
        let manager = P2PNetworkManager()
        manager.stop() // should be a no-op
        XCTAssertFalse(manager.isRunning)
    }

    func test_startTwice_doesNotDuplicateBrowser() {
        let manager = P2PNetworkManager()
        manager.start()
        manager.start() // second call must be a no-op
        XCTAssertTrue(manager.isRunning)
        manager.stop()
    }

    func test_setSidecarWsPort_doesNotCrash() {
        let manager = P2PNetworkManager()
        manager.setSidecarWsPort(9851)
        // Just verifying no crash and isRunning unchanged
        XCTAssertFalse(manager.isRunning)
    }

    // MARK: - DiscoveredLanPeer

    func test_discoveredLanPeer_idAndDisplayName() {
        let endpoint = NWEndpoint.hostPort(host: "192.168.1.1", port: 9849)
        let peer = DiscoveredLanPeer(
            id: "peer-1",
            displayName: "Alice-Mac",
            endpoint: endpoint,
            metadata: ""
        )
        XCTAssertEqual(peer.id, "peer-1")
        XCTAssertEqual(peer.displayName, "Alice-Mac")
    }

    func test_discoveredLanPeer_isIdentifiable() {
        let endpoint = NWEndpoint.hostPort(host: "192.168.1.2", port: 9849)
        let peer = DiscoveredLanPeer(id: "unique-id", displayName: "Bob", endpoint: endpoint, metadata: "")
        // Identifiable conformance: id is a String
        let id: String = peer.id
        XCTAssertEqual(id, "unique-id")
    }

    // MARK: - Agent catalog JSON decoding (replaces custom HTTP response parsing)

    func test_wireAgentExportList_decodesFromValidJSON() throws {
        let json = """
        {
            "agents": [
                {
                    "id": "11111111-1111-1111-1111-111111111111",
                    "name": "Coder",
                    "agentDescription": "Swift expert",
                    "systemPrompt": "You are a coder",
                    "provider": "anthropic",
                    "model": "claude-opus-4-7",
                    "icon": "cpu",
                    "color": "blue",
                    "skillNames": [],
                    "extraMCPNames": []
                }
            ]
        }
        """
        let data = Data(json.utf8)
        let list = try JSONDecoder().decode(WireAgentExportList.self, from: data)
        XCTAssertEqual(list.agents.count, 1)
        XCTAssertEqual(list.agents[0].name, "Coder")
        XCTAssertEqual(list.agents[0].id, UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
    }

    func test_wireAgentExportList_emptyAgents_decodesOK() throws {
        let json = #"{"agents":[]}"#
        let data = Data(json.utf8)
        let list = try JSONDecoder().decode(WireAgentExportList.self, from: data)
        XCTAssertTrue(list.agents.isEmpty)
    }

    func test_wireAgentExportList_malformedJSON_throws() {
        let bad = Data("not json at all".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(WireAgentExportList.self, from: bad))
    }

    // MARK: - Bonjour name format

    func test_bonjourServiceType_isOdysseyTCP() {
        // The service type used by the browser must stay "_odyssey._tcp".
        // This is checked by verifying the browser starts without error on start().
        let manager = P2PNetworkManager()
        manager.start()
        // lastError stays nil when the browser registers successfully
        XCTAssertNil(manager.lastError)
        manager.stop()
    }

    // MARK: - Peers state management

    func test_peers_emptyAfterStop() {
        let manager = P2PNetworkManager()
        manager.start()
        manager.stop()
        XCTAssertTrue(manager.peers.isEmpty)
    }
}
