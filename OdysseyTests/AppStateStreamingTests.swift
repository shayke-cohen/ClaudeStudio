import SwiftData
import XCTest
@testable import Odyssey

/// Tests for streaming performance fixes:
/// - Fix 1: O(n²) buffer replaced with array accumulator
/// - Fix 2: sessionActivity not written redundantly on every token
@MainActor
final class AppStateStreamingTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var appState: AppState!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Agent.self, Session.self, Conversation.self,
            ConversationMessage.self, MessageAttachment.self,
            Participant.self, Skill.self, Connection.self, MCPServer.self,
            PermissionSet.self, BlackboardEntry.self,
            configurations: config
        )
        context = container.mainContext
        appState = AppState()
        appState.modelContext = context
    }

    override func tearDown() async throws {
        appState = nil
        container = nil
        context = nil
    }

    // MARK: - Helpers

    private func makeSessionId() -> String {
        UUID().uuidString
    }

    // MARK: - Fix 1: Buffer accumulation

    func testStreamingBuffer_accumulatesTokensCorrectly() {
        let sid = makeSessionId()
        let tokens = ["Hello", ", ", "world", "!"]

        for token in tokens {
            appState.handleEventForTesting(.streamToken(sessionId: sid, text: token))
        }

        XCTAssertEqual(appState.streamingText[sid], "Hello, world!")
    }

    func testStreamingBuffer_manyTokens_producesCorrectResult() {
        let sid = makeSessionId()
        let tokenCount = 500
        let token = "ab"

        for _ in 0..<tokenCount {
            appState.handleEventForTesting(.streamToken(sessionId: sid, text: token))
        }

        let expected = String(repeating: "ab", count: tokenCount)
        XCTAssertEqual(appState.streamingText[sid], expected)
    }

    func testStreamingBuffer_emptyToken_doesNotBreak() {
        let sid = makeSessionId()
        appState.handleEventForTesting(.streamToken(sessionId: sid, text: ""))
        appState.handleEventForTesting(.streamToken(sessionId: sid, text: "text"))

        XCTAssertEqual(appState.streamingText[sid], "text")
    }

    func testStreamingBuffer_independentSessions_doNotBleed() {
        let sid1 = makeSessionId()
        let sid2 = makeSessionId()

        appState.handleEventForTesting(.streamToken(sessionId: sid1, text: "session1"))
        appState.handleEventForTesting(.streamToken(sessionId: sid2, text: "session2"))

        XCTAssertEqual(appState.streamingText[sid1], "session1")
        XCTAssertEqual(appState.streamingText[sid2], "session2")
    }

    // MARK: - Fix 2: sessionActivity dedup

    func testSessionActivity_setToStreamingOnFirstToken() {
        let sid = makeSessionId()
        XCTAssertNil(appState.sessionActivity[sid])

        appState.handleEventForTesting(.streamToken(sessionId: sid, text: "hi"))

        XCTAssertEqual(appState.sessionActivity[sid], .streaming)
    }

    func testSessionActivity_thinkingDedup() {
        let sid = makeSessionId()
        appState.handleEventForTesting(.streamThinking(sessionId: sid, text: "thinking..."))
        XCTAssertEqual(appState.sessionActivity[sid], .thinking)

        // Additional thinking tokens should not change the value (same reference)
        appState.handleEventForTesting(.streamThinking(sessionId: sid, text: "more thinking"))
        XCTAssertEqual(appState.sessionActivity[sid], .thinking)
    }

    func testSessionActivity_streamingDedup_multipleTokens() {
        let sid = makeSessionId()

        // Fire 10 tokens — activity should be .streaming throughout
        for i in 0..<10 {
            appState.handleEventForTesting(.streamToken(sessionId: sid, text: "tok\(i)"))
            XCTAssertEqual(appState.sessionActivity[sid], .streaming,
                           "Expected .streaming after token \(i)")
        }
    }

    // MARK: - Cleanup on result

    func testStreamingBuffer_clearedAfterSessionResult() {
        let sid = makeSessionId()
        appState.handleEventForTesting(.streamToken(sessionId: sid, text: "partial"))
        XCTAssertNotNil(appState.streamingText[sid])

        appState.handleEventForTesting(.sessionResult(
            sessionId: sid,
            result: "final result",
            cost: 0,
            tokenCount: 1,
            toolCallCount: 0
        ))

        // streamingText is kept (used by UI) but internal token array is cleared
        // Verify that a subsequent stream on the same session starts fresh
        appState.handleEventForTesting(.streamToken(sessionId: sid, text: "new"))
        XCTAssertEqual(appState.streamingText[sid], "new",
                       "After session result, new stream should start fresh from internal accumulator")
    }
}
