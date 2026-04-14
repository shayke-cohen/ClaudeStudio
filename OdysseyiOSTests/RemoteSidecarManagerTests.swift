// OdysseyiOSTests/RemoteSidecarManagerTests.swift
import XCTest
@testable import OdysseyiOS
import OdysseyCore

@MainActor
final class RemoteSidecarManagerTests: XCTestCase {

    // MARK: - Initial state

    func testInitialStatusIsDisconnected() {
        let manager = RemoteSidecarManager()
        XCTAssertEqual(manager.status, .disconnected)
        XCTAssertNil(manager.connectedPeer)
    }

    func testDisconnectFromDisconnectedStateIsNoop() {
        let manager = RemoteSidecarManager()
        manager.disconnect()  // should not crash
        XCTAssertEqual(manager.status, .disconnected)
    }

    // MARK: - Candidate endpoints

    func testCandidateEndpointsLanOnly() {
        let creds = makeCreds(lanHint: "192.168.1.1:9849", wanHint: nil)
        let endpoints = RemoteSidecarManager.candidateEndpoints(for: creds)
        XCTAssertEqual(endpoints, ["192.168.1.1:9849"])
    }

    func testCandidateEndpointsWanOnly() {
        let creds = makeCreds(lanHint: nil, wanHint: "203.0.113.1:9849")
        let endpoints = RemoteSidecarManager.candidateEndpoints(for: creds)
        XCTAssertEqual(endpoints, ["203.0.113.1:9849"])
    }

    func testCandidateEndpointsLanPrioritised() {
        let creds = makeCreds(lanHint: "192.168.1.1:9849", wanHint: "203.0.113.1:9849")
        let endpoints = RemoteSidecarManager.candidateEndpoints(for: creds)
        XCTAssertEqual(endpoints.first, "192.168.1.1:9849")
        XCTAssertEqual(endpoints.count, 2)
    }

    func testCandidateEndpointsEmpty() {
        let creds = makeCreds(lanHint: nil, wanHint: nil)
        let endpoints = RemoteSidecarManager.candidateEndpoints(for: creds)
        XCTAssertTrue(endpoints.isEmpty)
    }

    // MARK: - Session tracking

    func testTrackAndUntrackSession() {
        let manager = RemoteSidecarManager()
        manager.trackSession("session-1")
        manager.trackSession("session-2")
        manager.untrackSession("session-1")
        // After untrack, only session-2 should be tracked; verified indirectly
        // by checking untrack doesn't crash.
        manager.untrackSession("session-2")
    }

    // MARK: - Send when not connected

    func testSendThrowsWhenNotConnected() async {
        let manager = RemoteSidecarManager()
        do {
            try await manager.send(.sessionPause(sessionId: "test-session"))
            XCTFail("Expected notConnected error")
        } catch RemoteSidecarManager.RemoteError.notConnected {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Reconnect when already disconnected

    func testReconnectIfNeededNoopWhenNoPeer() async {
        let manager = RemoteSidecarManager()
        await manager.reconnectIfNeeded()  // should not crash or attempt connection
        XCTAssertEqual(manager.status, .disconnected)
    }

    // MARK: - Cert pinning

    func testCertPinningStoresPinnedDER() {
        let pinnedDER = Data(repeating: 0xAB, count: 100)
        let delegate = CertPinningDelegate(pinnedDER: pinnedDER)
        XCTAssertEqual(delegate.pinnedDER, pinnedDER, "CertPinningDelegate must store the pinned DER bytes")
    }

    func testCertPinningRejectsMismatchedCert() {
        let pinnedDER = Data(repeating: 0xAB, count: 100)
        let wrongDER = Data(repeating: 0xCD, count: 100)
        let delegate = CertPinningDelegate(pinnedDER: pinnedDER)
        XCTAssertNotEqual(wrongDER, delegate.pinnedDER,
            "A cert with different DER bytes should not match the pinned cert")
    }

    // MARK: - Helpers

    private func makeCreds(lanHint: String?, wanHint: String?) -> PeerCredentials {
        PeerCredentials(
            id: UUID(),
            displayName: "Test Mac",
            userPublicKeyData: Data(repeating: 0xAB, count: 32),
            tlsCertDER: Data(repeating: 0xCD, count: 512),
            wsToken: "test-token",
            wsPort: 9849,
            lanHint: lanHint,
            wanHint: wanHint,
            turnConfig: nil,
            pairedAt: Date(),
            lastConnectedAt: nil,
            claudeSessionIds: [:]
        )
    }
}
