import SwiftData
import XCTest
@testable import Odyssey

@MainActor
final class AppStateIdleDetectionTests: XCTestCase {

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

    private func makeConversationWithSession() -> (conversationId: String, sessionId: String) {
        let session = Session(agent: nil)
        let convo = Conversation(topic: "Test")
        session.conversations = [convo]
        context.insert(session)
        context.insert(convo)
        try? context.save()
        return (conversationId: convo.id.uuidString, sessionId: session.id.uuidString)
    }

    // MARK: - ID-1: conversationIdleResult populates idleResults

    func testID1_conversationIdleResult_populatesIdleResults() {
        let convId = "test-conv-idle-\(UUID().uuidString)"

        appState.handleEventForTesting(.conversationIdleResult(
            conversationId: convId,
            status: .complete,
            reason: "All objectives were met"
        ))

        XCTAssertNotNil(appState.idleResults[convId])
        XCTAssertEqual(appState.idleResults[convId]?.status, .complete)
        XCTAssertEqual(appState.idleResults[convId]?.reason, "All objectives were met")
    }

    func testID1b_conversationIdleResult_needsMore_status() {
        let convId = "test-conv-needs-\(UUID().uuidString)"

        appState.handleEventForTesting(.conversationIdleResult(
            conversationId: convId,
            status: .needsMore,
            reason: "Work is incomplete"
        ))

        XCTAssertEqual(appState.idleResults[convId]?.status, .needsMore)
        XCTAssertEqual(appState.idleResults[convId]?.reason, "Work is incomplete")
    }

    func testID1c_conversationIdleResult_failed_status() {
        let convId = "test-conv-failed-\(UUID().uuidString)"

        appState.handleEventForTesting(.conversationIdleResult(
            conversationId: convId,
            status: .failed,
            reason: "Could not complete"
        ))

        XCTAssertEqual(appState.idleResults[convId]?.status, .failed)
    }

    // MARK: - ID-2: conversationIdle is a no-op

    func testID2_conversationIdle_doesNotCrashOrMutateIdleResults() {
        let convId = "idle-event-test-\(UUID().uuidString)"
        let initial = appState.idleResults.count

        appState.handleEventForTesting(.conversationIdle(conversationId: convId))

        XCTAssertEqual(appState.idleResults.count, initial)
        XCTAssertNil(appState.idleResults[convId])
    }

    // MARK: - ID-3: evaluatingConversations is cleared on idleResult

    func testID3_idleResult_removesFromEvaluatingConversations() {
        let convId = "eval-track-\(UUID().uuidString)"
        appState.evaluatingConversations.insert(convId)
        XCTAssertTrue(appState.evaluatingConversations.contains(convId))

        appState.handleEventForTesting(.conversationIdleResult(
            conversationId: convId,
            status: .complete,
            reason: "Done"
        ))

        XCTAssertFalse(appState.evaluatingConversations.contains(convId))
    }

    // MARK: - ID-4: notifyUserMessageAppended clears idle state

    func testID4_notifyUserMessageAppended_clearsIdleResult() {
        let (convIdString, _) = makeConversationWithSession()
        guard let convUUID = UUID(uuidString: convIdString) else {
            return XCTFail("Expected valid UUID")
        }

        appState.idleResults[convIdString] = ConversationIdleResult(status: .complete, reason: "done")
        XCTAssertNotNil(appState.idleResults[convIdString])

        let msg = ConversationMessage(type: .text, text: "follow-up question", sender: nil)
        appState.notifyUserMessageAppended(conversationId: convUUID, message: msg)

        XCTAssertNil(appState.idleResults[convIdString])
    }

    func testID4b_notifyUserMessageAppended_clearsEvaluatingConversations() {
        let (convIdString, _) = makeConversationWithSession()
        guard let convUUID = UUID(uuidString: convIdString) else {
            return XCTFail("Expected valid UUID")
        }

        appState.evaluatingConversations.insert(convIdString)
        XCTAssertTrue(appState.evaluatingConversations.contains(convIdString))

        let msg = ConversationMessage(type: .text, text: "new message", sender: nil)
        appState.notifyUserMessageAppended(conversationId: convUUID, message: msg)

        XCTAssertFalse(appState.evaluatingConversations.contains(convIdString))
    }

    // MARK: - ID-5: Multiple conversations are tracked independently

    func testID5_multipleConversationsTrackedIndependently() {
        let id1 = "conv-a-\(UUID().uuidString)"
        let id2 = "conv-b-\(UUID().uuidString)"

        appState.handleEventForTesting(.conversationIdleResult(
            conversationId: id1,
            status: .complete,
            reason: "First done"
        ))
        appState.handleEventForTesting(.conversationIdleResult(
            conversationId: id2,
            status: .failed,
            reason: "Second failed"
        ))

        XCTAssertEqual(appState.idleResults[id1]?.status, .complete)
        XCTAssertEqual(appState.idleResults[id2]?.status, .failed)
    }

    // MARK: - ID-6: idleResult overwrites previous result for same conversation

    func testID6_idleResult_overwritesPreviousResult() {
        let convId = "conv-overwrite-\(UUID().uuidString)"

        appState.handleEventForTesting(.conversationIdleResult(
            conversationId: convId,
            status: .complete,
            reason: "First eval"
        ))
        appState.handleEventForTesting(.conversationIdleResult(
            conversationId: convId,
            status: .needsMore,
            reason: "Second eval"
        ))

        XCTAssertEqual(appState.idleResults[convId]?.status, .needsMore)
        XCTAssertEqual(appState.idleResults[convId]?.reason, "Second eval")
    }
}

// MARK: - SidecarProtocol: conversationEvaluate encoding

final class ConversationEvaluateEncodingTests: XCTestCase {

    func testEncoding_conversationEvaluate_withAllFields() throws {
        let command = SidecarCommand.conversationEvaluate(
            conversationId: "conv-abc",
            goal: "ship the feature",
            coordinatorSessionId: "coord-123",
            sessionIds: ["sess-1", "sess-2"]
        )
        let data = try command.encodeToJSON()
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["type"] as? String, "conversation.evaluate")
        XCTAssertEqual(json["conversationId"] as? String, "conv-abc")
        XCTAssertEqual(json["goal"] as? String, "ship the feature")
        XCTAssertEqual(json["coordinatorSessionId"] as? String, "coord-123")
        let sessionIds = json["sessionIds"] as? [String]
        XCTAssertEqual(sessionIds, ["sess-1", "sess-2"])
    }

    func testEncoding_conversationEvaluate_withNilGoalAndCoordinator() throws {
        let command = SidecarCommand.conversationEvaluate(
            conversationId: "conv-xyz",
            goal: nil,
            coordinatorSessionId: nil,
            sessionIds: ["s1"]
        )
        let data = try command.encodeToJSON()
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["type"] as? String, "conversation.evaluate")
        XCTAssertEqual(json["conversationId"] as? String, "conv-xyz")
        XCTAssertNil(json["goal"] as? String)
        XCTAssertNil(json["coordinatorSessionId"] as? String)
    }

    func testDecoding_conversationIdleEvent() throws {
        let json = """
        {"type":"conversation.idle","conversationId":"conv-decode-idle"}
        """.data(using: .utf8)!

        let wire = try JSONDecoder().decode(IncomingWireMessage.self, from: json)
        let event = wire.toEvent()

        if case .conversationIdle(let cid) = event {
            XCTAssertEqual(cid, "conv-decode-idle")
        } else {
            XCTFail("Expected .conversationIdle, got \(String(describing: event))")
        }
    }

    func testDecoding_conversationIdleResultEvent_complete() throws {
        let json = """
        {"type":"conversation.idleResult","conversationId":"conv-decode-result","status":"complete","reason":"All done"}
        """.data(using: .utf8)!

        let wire = try JSONDecoder().decode(IncomingWireMessage.self, from: json)
        let event = wire.toEvent()

        if case .conversationIdleResult(let cid, let status, let reason) = event {
            XCTAssertEqual(cid, "conv-decode-result")
            XCTAssertEqual(status, .complete)
            XCTAssertEqual(reason, "All done")
        } else {
            XCTFail("Expected .conversationIdleResult, got \(String(describing: event))")
        }
    }

    func testDecoding_conversationIdleResultEvent_needsMore() throws {
        let json = """
        {"type":"conversation.idleResult","conversationId":"c1","status":"needsMore","reason":"Not done"}
        """.data(using: .utf8)!

        let wire = try JSONDecoder().decode(IncomingWireMessage.self, from: json)
        let event = wire.toEvent()

        if case .conversationIdleResult(_, let status, _) = event {
            XCTAssertEqual(status, .needsMore)
        } else {
            XCTFail("Expected .conversationIdleResult")
        }
    }

    func testDecoding_conversationIdleResultEvent_failed() throws {
        let json = """
        {"type":"conversation.idleResult","conversationId":"c2","status":"failed","reason":"Error"}
        """.data(using: .utf8)!

        let wire = try JSONDecoder().decode(IncomingWireMessage.self, from: json)
        let event = wire.toEvent()

        if case .conversationIdleResult(_, let status, _) = event {
            XCTAssertEqual(status, .failed)
        } else {
            XCTFail("Expected .conversationIdleResult")
        }
    }
}

// MARK: - ConversationIdleResult model tests

final class ConversationIdleResultModelTests: XCTestCase {

    func testEquality_sameStatusAndReason() {
        let r1 = ConversationIdleResult(status: .complete, reason: "done")
        let r2 = ConversationIdleResult(status: .complete, reason: "done")
        XCTAssertEqual(r1, r2)
    }

    func testEquality_differentStatus() {
        let r1 = ConversationIdleResult(status: .complete, reason: "done")
        let r2 = ConversationIdleResult(status: .failed, reason: "done")
        XCTAssertNotEqual(r1, r2)
    }

    func testEquality_differentReason() {
        let r1 = ConversationIdleResult(status: .complete, reason: "a")
        let r2 = ConversationIdleResult(status: .complete, reason: "b")
        XCTAssertNotEqual(r1, r2)
    }

    func testStatusRawValues() {
        XCTAssertEqual(ConversationIdleResult.Status.complete.rawValue, "complete")
        XCTAssertEqual(ConversationIdleResult.Status.needsMore.rawValue, "needsMore")
        XCTAssertEqual(ConversationIdleResult.Status.failed.rawValue, "failed")
    }
}
