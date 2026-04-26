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
        appState.flushStreamTokenBuffersForTesting()

        XCTAssertEqual(appState.streamingText[sid], "Hello, world!")
    }

    func testStreamingBuffer_manyTokens_producesCorrectResult() {
        let sid = makeSessionId()
        let tokenCount = 500
        let token = "ab"

        for _ in 0..<tokenCount {
            appState.handleEventForTesting(.streamToken(sessionId: sid, text: token))
        }
        appState.flushStreamTokenBuffersForTesting()

        let expected = String(repeating: "ab", count: tokenCount)
        XCTAssertEqual(appState.streamingText[sid], expected)
    }

    func testStreamingBuffer_emptyToken_doesNotBreak() {
        let sid = makeSessionId()
        appState.handleEventForTesting(.streamToken(sessionId: sid, text: ""))
        appState.handleEventForTesting(.streamToken(sessionId: sid, text: "text"))
        appState.flushStreamTokenBuffersForTesting()

        XCTAssertEqual(appState.streamingText[sid], "text")
    }

    func testStreamingBuffer_independentSessions_doNotBleed() {
        let sid1 = makeSessionId()
        let sid2 = makeSessionId()

        appState.handleEventForTesting(.streamToken(sessionId: sid1, text: "session1"))
        appState.handleEventForTesting(.streamToken(sessionId: sid2, text: "session2"))
        appState.flushStreamTokenBuffersForTesting()

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

    // MARK: - Fix 3: thinkingText accumulation (parity with streamingText)

    func testThinkingText_accumulatesTokensCorrectly() {
        let sid = makeSessionId()
        let tokens = ["I'm ", "thinking ", "about ", "this..."]

        for token in tokens {
            appState.handleEventForTesting(.streamThinking(sessionId: sid, text: token))
        }

        XCTAssertEqual(appState.thinkingText[sid], "I'm thinking about this...")
    }

    func testThinkingText_independentSessions_doNotBleed() {
        let sid1 = makeSessionId()
        let sid2 = makeSessionId()

        appState.handleEventForTesting(.streamThinking(sessionId: sid1, text: "thought1"))
        appState.handleEventForTesting(.streamThinking(sessionId: sid2, text: "thought2"))

        XCTAssertEqual(appState.thinkingText[sid1], "thought1")
        XCTAssertEqual(appState.thinkingText[sid2], "thought2")
    }

    /// Regression guard for O(n²) string accumulation. With the buggy
    /// `current + text` pattern, accumulating ~20k thinking tokens copies
    /// ~200M bytes and easily exceeds 500ms. With in-place `append` it is
    /// linear and completes in well under 100ms.
    func testThinkingText_largeAccumulation_isLinear() {
        let sid = makeSessionId()
        let tokenCount = 20_000

        let start = ContinuousClock().now
        for _ in 0..<tokenCount {
            appState.handleEventForTesting(.streamThinking(sessionId: sid, text: "x"))
        }
        let elapsed = ContinuousClock().now - start

        XCTAssertEqual(appState.thinkingText[sid]?.count, tokenCount)
        XCTAssertLessThan(
            elapsed,
            .milliseconds(500),
            "Accumulating \(tokenCount) thinking tokens took \(elapsed); >500ms suggests O(n²) string concat regression"
        )
    }

    // MARK: - Tool call accumulation

    func testToolCalls_appendInOrderAcrossSessions() {
        let s1 = makeSessionId()
        let s2 = makeSessionId()

        appState.handleEventForTesting(.streamToolCall(sessionId: s1, tool: "Read", input: "/a.txt"))
        appState.handleEventForTesting(.streamToolCall(sessionId: s2, tool: "Bash", input: "ls"))
        appState.handleEventForTesting(.streamToolCall(sessionId: s1, tool: "Edit", input: "/a.txt"))

        XCTAssertEqual(appState.toolCalls[s1]?.map(\.tool), ["Read", "Edit"])
        XCTAssertEqual(appState.toolCalls[s2]?.map(\.tool), ["Bash"])
    }

    func testToolResult_attachesToLatestMatchingPendingCall() {
        let sid = makeSessionId()
        appState.handleEventForTesting(.streamToolCall(sessionId: sid, tool: "Read", input: "/a.txt"))
        appState.handleEventForTesting(.streamToolCall(sessionId: sid, tool: "Read", input: "/b.txt"))
        // Result should attach to the *latest* unfilled Read call (b.txt).
        appState.handleEventForTesting(.streamToolResult(sessionId: sid, tool: "Read", output: "B-CONTENT"))

        let calls = appState.toolCalls[sid] ?? []
        XCTAssertEqual(calls.count, 2)
        XCTAssertNil(calls[0].output, "First Read should remain pending; result attaches to most recent unfilled match")
        XCTAssertEqual(calls[1].output, "B-CONTENT")
    }

    func testToolResult_unmatchedToolIsIgnored() {
        let sid = makeSessionId()
        appState.handleEventForTesting(.streamToolCall(sessionId: sid, tool: "Read", input: "x"))
        // A result for a tool that was never called should not crash or attach.
        appState.handleEventForTesting(.streamToolResult(sessionId: sid, tool: "Bash", output: "y"))

        XCTAssertEqual(appState.toolCalls[sid]?.count, 1)
        XCTAssertNil(appState.toolCalls[sid]?.first?.output)
    }

    /// Regression guard for the dict-of-arrays COW pattern on appends.
    func testToolCalls_largeAccumulation_isLinear() {
        let sid = makeSessionId()
        let count = 5000

        let start = ContinuousClock().now
        for i in 0..<count {
            appState.handleEventForTesting(.streamToolCall(
                sessionId: sid, tool: "Tool\(i)", input: "x"
            ))
        }
        let elapsed = ContinuousClock().now - start

        XCTAssertEqual(appState.toolCalls[sid]?.count, count)
        XCTAssertLessThan(
            elapsed,
            .milliseconds(500),
            "Appending \(count) tool calls took \(elapsed); >500ms suggests dict-of-arrays COW regression"
        )
    }

    /// Stress test for interleaved call+result. The old `streamToolResult` did
    /// `var calls = toolCalls[sid]; calls[idx].output = ...; dict = calls`,
    /// which triggers COW on every single result because the dict still holds
    /// a reference. With N=2000 pairs that's O(N²) ≈ 4M element copies.
    /// In-place subscript mutation through the dict keeps it linear.
    func testToolCallResultInterleaved_isLinear() {
        let sid = makeSessionId()
        let pairs = 2000

        let start = ContinuousClock().now
        for i in 0..<pairs {
            let toolName = "Tool\(i)"
            appState.handleEventForTesting(.streamToolCall(sessionId: sid, tool: toolName, input: "in"))
            appState.handleEventForTesting(.streamToolResult(sessionId: sid, tool: toolName, output: "out"))
        }
        let elapsed = ContinuousClock().now - start

        let calls = appState.toolCalls[sid] ?? []
        XCTAssertEqual(calls.count, pairs)
        XCTAssertEqual(calls.filter { $0.output == "out" }.count, pairs,
                       "Every result should attach to its matching pending call")
        XCTAssertLessThan(
            elapsed,
            .milliseconds(1500),
            "Interleaved call+result for \(pairs) pairs took \(elapsed); >1.5s suggests COW on each result"
        )
    }

    // MARK: - 60fps buffer: auto-flush, error discard, performance

    /// The 16ms Timer must fire and flush tokens to streamingText without any
    /// manual flush call. This is the end-to-end auto-flush regression guard.
    func testStreamToken_timerFlushesAutomatically() {
        let sid = makeSessionId()
        appState.handleEventForTesting(.streamToken(sessionId: sid, text: "auto"))
        // streamingText is nil before the timer fires
        XCTAssertNil(appState.streamingText[sid], "Tokens must be buffered before timer fires")
        // Run the main RunLoop long enough for the 16ms timer to fire
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(appState.streamingText[sid], "auto",
                       "Timer should have flushed buffer to streamingText within 50ms")
    }

    /// After a sessionError the pending token buffer must be discarded so stale
    /// partial output from the failed turn never surfaces in streamingText.
    func testStreamToken_sessionError_discardsBuffer() {
        let sid = makeSessionId()
        let uuid = UUID(uuidString: sid)!
        appState.activeSessions[uuid] = AppState.SessionInfo(id: uuid, agentName: "Bot", isStreaming: true)

        appState.handleEventForTesting(.streamToken(sessionId: sid, text: "before-error"))
        // Buffer has content but streamingText is still nil
        XCTAssertNil(appState.streamingText[sid])

        appState.handleEventForTesting(.sessionError(sessionId: sid, error: "network timeout"))
        // Explicit flush — should be a no-op because the error handler discarded the buffer
        appState.flushStreamTokenBuffersForTesting()

        XCTAssertNil(appState.streamingText[sid],
                     "sessionError must discard buffered tokens; streamingText should remain nil")
    }

    /// 10 000 rapid tokens should process quickly AND leave streamingText unchanged
    /// until an explicit flush (proving the per-token Observable write is eliminated).
    func testStreamToken_highVolume_bufferedWithoutObservableWrites() {
        let sid = makeSessionId()
        let count = 10_000
        let start = ContinuousClock().now

        for i in 0..<count {
            appState.handleEventForTesting(.streamToken(sessionId: sid, text: "t\(i)"))
        }
        let elapsed = ContinuousClock().now - start

        // All tokens buffered quickly — no per-token Observable writes to tracked properties
        XCTAssertLessThan(elapsed, .milliseconds(500),
                          "Buffering \(count) tokens took \(elapsed); suggests unexpected per-token work")
        // streamingText must still be nil — no flush has been called
        XCTAssertNil(appState.streamingText[sid],
                     "streamingText must be nil until flush; Observable writes per token would make it non-nil here via timer")

        appState.flushStreamTokenBuffersForTesting()
        let result = appState.streamingText[sid] ?? ""
        XCTAssertTrue(result.count > 0, "Flush must produce non-empty text")
    }

    // MARK: - Cleanup on result

    func testStreamingBuffer_clearedAfterSessionResult() {
        let sid = makeSessionId()
        appState.handleEventForTesting(.streamToken(sessionId: sid, text: "partial"))
        appState.flushStreamTokenBuffersForTesting()
        XCTAssertNotNil(appState.streamingText[sid])

        appState.handleEventForTesting(.sessionResult(
            sessionId: sid,
            result: "final result",
            cost: 0,
            tokenCount: 1,
            toolCallCount: 0
        ))

        // streamingText is kept (used by UI) but internal token array is cleared.
        // The next token starts a new turn; resetStreamingBuffersIfNewTurn clears the stale text.
        appState.handleEventForTesting(.streamToken(sessionId: sid, text: "new"))
        appState.flushStreamTokenBuffersForTesting()
        XCTAssertEqual(appState.streamingText[sid], "new",
                       "After session result, new stream should start fresh from internal accumulator")
    }
}
