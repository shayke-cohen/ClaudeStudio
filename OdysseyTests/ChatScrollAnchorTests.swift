import XCTest
@testable import Odyssey

final class ChatScrollAnchorTests: XCTestCase {

    // MARK: - Visibility filtering

    func testEmptyFrames_returnsNil() {
        XCTAssertNil(ChatScrollAnchor.topVisibleMessageId(from: [], viewportHeight: 800))
    }

    func testAllFramesAboveViewport_returnsNil() {
        // maxY <= 0 means the frame ended above the viewport.
        let frames = [
            ChatVisibleMessageFrame(id: .init(), minY: -200, maxY: -100),
            ChatVisibleMessageFrame(id: .init(), minY: -50, maxY: 0),
        ]
        XCTAssertNil(ChatScrollAnchor.topVisibleMessageId(from: frames, viewportHeight: 800))
    }

    func testAllFramesBelowViewport_returnsNil() {
        // minY >= viewportHeight means the frame starts below the viewport.
        let frames = [
            ChatVisibleMessageFrame(id: .init(), minY: 800, maxY: 900),
            ChatVisibleMessageFrame(id: .init(), minY: 1000, maxY: 1100),
        ]
        XCTAssertNil(ChatScrollAnchor.topVisibleMessageId(from: frames, viewportHeight: 800))
    }

    // MARK: - Topmost selection

    func testReturnsFrameWithSmallestMinY_amongVisible() {
        let bottom = UUID()
        let middle = UUID()
        let top = UUID()
        let frames = [
            ChatVisibleMessageFrame(id: bottom, minY: 600, maxY: 700),
            ChatVisibleMessageFrame(id: top, minY: 50, maxY: 150),
            ChatVisibleMessageFrame(id: middle, minY: 300, maxY: 400),
        ]
        XCTAssertEqual(
            ChatScrollAnchor.topVisibleMessageId(from: frames, viewportHeight: 800),
            top
        )
    }

    func testIgnoresFramesAboveViewport() {
        let scrolledOff = UUID()
        let firstVisible = UUID()
        let frames = [
            // Already scrolled past the top — minY negative, maxY just barely off-screen.
            ChatVisibleMessageFrame(id: scrolledOff, minY: -200, maxY: -10),
            ChatVisibleMessageFrame(id: firstVisible, minY: 20, maxY: 120),
        ]
        XCTAssertEqual(
            ChatScrollAnchor.topVisibleMessageId(from: frames, viewportHeight: 800),
            firstVisible
        )
    }

    func testFramePartiallyAbove_isStillVisibleIfMaxYPositive() {
        let partiallyAbove = UUID()
        let fullyVisible = UUID()
        let frames = [
            // Top edge above the viewport, but bottom edge still inside.
            ChatVisibleMessageFrame(id: partiallyAbove, minY: -50, maxY: 30),
            ChatVisibleMessageFrame(id: fullyVisible, minY: 100, maxY: 200),
        ]
        XCTAssertEqual(
            ChatScrollAnchor.topVisibleMessageId(from: frames, viewportHeight: 800),
            partiallyAbove,
            "A frame whose top is above the viewport is still the topmost visible if maxY > 0"
        )
    }

    // MARK: - Tie-breaking

    func testTiesOnMinY_brokenByIdString() {
        // Two frames with identical minY — the smaller uuid string wins
        // (so the helper is deterministic across renders).
        let id1 = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let id2 = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let frames = [
            ChatVisibleMessageFrame(id: id2, minY: 100, maxY: 200),
            ChatVisibleMessageFrame(id: id1, minY: 100, maxY: 200),
        ]
        XCTAssertEqual(
            ChatScrollAnchor.topVisibleMessageId(from: frames, viewportHeight: 800),
            id1
        )
    }

    // MARK: - Perf: should stay linear

    func testLargeFrameList_completesQuickly() {
        var frames: [ChatVisibleMessageFrame] = []
        let count = 10_000
        for i in 0..<count {
            frames.append(ChatVisibleMessageFrame(
                id: UUID(),
                minY: CGFloat(i * 50),
                maxY: CGFloat(i * 50 + 40)
            ))
        }

        let start = ContinuousClock().now
        _ = ChatScrollAnchor.topVisibleMessageId(from: frames, viewportHeight: 800)
        let elapsed = ContinuousClock().now - start

        XCTAssertLessThan(
            elapsed, .milliseconds(50),
            "10k frames took \(elapsed); should be a single linear pass"
        )
    }
}
