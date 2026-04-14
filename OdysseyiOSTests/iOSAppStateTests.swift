// OdysseyiOSTests/iOSAppStateTests.swift
import XCTest
@testable import OdysseyiOS
import OdysseyCore

@MainActor
final class iOSAppStateTests: XCTestCase {

    // MARK: - Streaming buffer

    func testStreamingBufferAccumulatesTokens() {
        let state = iOSAppState()
        state.handleEvent(.streamToken(sessionId: "conv-1", text: "Hello"))
        state.handleEvent(.streamToken(sessionId: "conv-1", text: " world"))
        XCTAssertEqual(state.streamingBuffers["conv-1"], "Hello world",
            "Stream tokens should be concatenated in streamingBuffers")
    }

    func testStreamingBufferClearedOnSessionResult() {
        let state = iOSAppState()
        state.handleEvent(.streamToken(sessionId: "conv-1", text: "Hello"))
        state.handleEvent(.sessionResult(sessionId: "conv-1", result: "done",
                                         cost: 0.01, tokenCount: 10, toolCallCount: 0))
        XCTAssertNil(state.streamingBuffers["conv-1"],
            "Streaming buffer must be cleared when session.result is received")
    }

    func testInitialConnectionStatus() {
        let state = iOSAppState()
        XCTAssertEqual(state.connectionStatus, .disconnected)
    }

    // MARK: - Base URL construction

    func testCurrentBaseURLWithLanHint() {
        // We cannot call private currentBaseURL directly; verify indirectly via
        // the public interface. Here we verify that loadMessages returns empty
        // when disconnected (no baseURL available).
        let state = iOSAppState()
        // No peer connected → currentBaseURL returns nil → loadMessages returns []
        let expectation = expectation(description: "loadMessages returns empty")
        Task { @MainActor in
            let msgs = await state.loadMessages(for: "test-id")
            XCTAssertTrue(msgs.isEmpty)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 3)
    }

    // MARK: - Conversations / projects empty when disconnected

    func testLoadConversationsWhenDisconnected() async {
        let state = iOSAppState()
        await state.loadConversations()
        XCTAssertTrue(state.conversations.isEmpty)
    }

    func testLoadProjectsWhenDisconnected() async {
        let state = iOSAppState()
        await state.loadProjects()
        XCTAssertTrue(state.projects.isEmpty)
    }
}
