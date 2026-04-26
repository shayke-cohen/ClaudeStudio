import SwiftData
import XCTest
@testable import Odyssey

@MainActor
final class AppStateEventTests: XCTestCase {

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

    /// Creates a Session + Conversation pair and returns the session ID string.
    private func makeSessionWithConversation(topic: String = "Test") -> String {
        let session = Session(agent: nil)
        let convo = Conversation(topic: topic)
        session.conversations = [convo]
        context.insert(session)
        context.insert(convo)
        try? context.save()
        return session.id.uuidString
    }

    // MARK: - EH: Event Handling

    /// commsEvents was append-only with no cap; long-running sessions accumulated
    /// thousands of entries and the AgentCommsView re-filtered the whole array on
    /// every body render. Cap to a reasonable history window and drop the oldest.
    func testCommsEvents_cappedAtMaxHistory() {
        let sid = makeSessionWithConversation()
        let cap = AppState.commsEventsHistoryCap
        let overshoot = cap + 200

        for i in 0..<overshoot {
            appState.handleEventForTesting(.peerChat(
                sessionId: sid, channelId: "ch", from: "Agent\(i)", message: "msg\(i)"
            ))
        }

        XCTAssertEqual(appState.commsEvents.count, cap, "Should cap at \(cap)")
        // Oldest dropped, newest retained.
        if case .chat(_, let firstFrom, _) = appState.commsEvents.first?.kind {
            XCTAssertEqual(firstFrom, "Agent\(overshoot - cap)",
                           "First entry should be the oldest *kept* event")
        } else {
            XCTFail("First retained event should be a .chat")
        }
        if case .chat(_, let lastFrom, _) = appState.commsEvents.last?.kind {
            XCTAssertEqual(lastFrom, "Agent\(overshoot - 1)",
                           "Last entry should be the most recent event")
        } else {
            XCTFail("Last retained event should be a .chat")
        }
    }

    func testEH1_peerChatEvent_appendsCommsAndPersists() {
        let sid = makeSessionWithConversation()
        appState.handleEventForTesting(.peerChat(sessionId: sid, channelId: "ch-1", from: "AgentA", message: "hello"))

        XCTAssertEqual(appState.commsEvents.count, 1)
        if case .chat(let channelId, let from, let message) = appState.commsEvents[0].kind {
            XCTAssertEqual(channelId, "ch-1")
            XCTAssertEqual(from, "AgentA")
            XCTAssertEqual(message, "hello")
        } else {
            XCTFail("Expected .chat event kind")
        }

        // Verify message persisted in the session's conversation
        let allMessages = (try? context.fetch(FetchDescriptor<ConversationMessage>())) ?? []
        let peerMessages = allMessages.filter { $0.type == .peerMessage }
        XCTAssertEqual(peerMessages.count, 1)
        XCTAssertEqual(peerMessages.first?.text, "AgentA: hello")
    }

    func testEH2_peerDelegateEvent_appendsCommsAndPersistsInConversation() {
        let sid = makeSessionWithConversation(topic: "Group Chat")
        appState.handleEventForTesting(.peerDelegate(sessionId: sid, from: "Orchestrator", to: "Coder", task: "implement login"))

        XCTAssertEqual(appState.commsEvents.count, 1)
        if case .delegation(let from, let to, let task) = appState.commsEvents[0].kind {
            XCTAssertEqual(from, "Orchestrator")
            XCTAssertEqual(to, "Coder")
            XCTAssertEqual(task, "implement login")
        } else {
            XCTFail("Expected .delegation event kind")
        }

        // Verify delegation message persisted in the session's conversation
        let allMessages = (try? context.fetch(FetchDescriptor<ConversationMessage>())) ?? []
        let delegationMessages = allMessages.filter { $0.type == .delegation }
        XCTAssertEqual(delegationMessages.count, 1)
        XCTAssertTrue(delegationMessages.first?.text.contains("Orchestrator") == true)
        XCTAssertTrue(delegationMessages.first?.text.contains("Coder") == true)
    }

    func testEH3_blackboardUpdateEvent_appendsCommsAndUpsertsEntry() {
        let sid = makeSessionWithConversation()
        appState.handleEventForTesting(.blackboardUpdate(sessionId: sid, key: "pipeline.phase", value: "research", writtenBy: "Orchestrator"))

        XCTAssertEqual(appState.commsEvents.count, 1)
        if case .blackboardUpdate(let key, let value, let writtenBy) = appState.commsEvents[0].kind {
            XCTAssertEqual(key, "pipeline.phase")
            XCTAssertEqual(value, "research")
            XCTAssertEqual(writtenBy, "Orchestrator")
        } else {
            XCTFail("Expected .blackboardUpdate event kind")
        }

        let descriptor = FetchDescriptor<BlackboardEntry>(predicate: #Predicate { e in
            e.key == "pipeline.phase"
        })
        let entries = try? context.fetch(descriptor)
        XCTAssertEqual(entries?.count, 1)
        XCTAssertEqual(entries?.first?.value, "research")

        appState.handleEventForTesting(.blackboardUpdate(sessionId: sid, key: "pipeline.phase", value: "implementation", writtenBy: "Orchestrator"))
        let updated = try? context.fetch(descriptor)
        XCTAssertEqual(updated?.count, 1)
        XCTAssertEqual(updated?.first?.value, "implementation")

        // Verify blackboard messages persisted in conversation
        let allMessages = (try? context.fetch(FetchDescriptor<ConversationMessage>())) ?? []
        let bbMessages = allMessages.filter { $0.type == .blackboardUpdate }
        XCTAssertEqual(bbMessages.count, 2)
        XCTAssertEqual(bbMessages.last?.toolName, "pipeline.phase")
        XCTAssertEqual(bbMessages.last?.toolInput, "Orchestrator")
    }

    func testEH4_streamTokenEvent_concatenatesText() {
        let sid = UUID().uuidString
        appState.handleEventForTesting(.streamToken(sessionId: sid, text: "Hello"))
        appState.handleEventForTesting(.streamToken(sessionId: sid, text: " World"))
        // Tokens are buffered at ≤60 fps; flush manually in tests.
        appState.flushStreamTokenBuffersForTesting()

        XCTAssertEqual(appState.streamingText[sid], "Hello World")
    }

    func testEH4c_streamToken_batchedBeforeFlush() {
        let sid = UUID().uuidString
        for i in 0..<50 {
            appState.handleEventForTesting(.streamToken(sessionId: sid, text: "\(i) "))
        }
        // Before flush, streamingText should be nil (tokens are still buffered).
        XCTAssertNil(appState.streamingText[sid], "streamingText must stay nil until flush")

        appState.flushStreamTokenBuffersForTesting()
        let result = appState.streamingText[sid] ?? ""
        XCTAssertTrue(result.hasPrefix("0 1 2 "), "Tokens should be in order after flush")
        XCTAssertEqual(result.split(separator: " ").count, 50)
    }

    func testEH4d_streamToken_flushedOnSessionResult() {
        let sid = UUID().uuidString
        let uuid = UUID(uuidString: sid) ?? UUID()
        appState.activeSessions[uuid] = AppState.SessionInfo(id: uuid, agentName: "Bot", isStreaming: true)

        appState.handleEventForTesting(.streamToken(sessionId: sid, text: "partial"))
        // sessionResult must flush the buffer so the result handler sees the text.
        appState.handleEventForTesting(.sessionResult(
            sessionId: sid, result: "", cost: 0, tokenCount: 1, toolCallCount: 0
        ))

        XCTAssertEqual(appState.streamingText[sid], "partial",
                       "Buffer must be flushed before sessionResult processing")
    }

    func testEH4b_streamTokenEvent_seedsLiveSessionUsageFromPersistedSession() {
        let sid = makeSessionWithConversation()
        guard let uuid = UUID(uuidString: sid) else {
            return XCTFail("Expected valid UUID session id")
        }

        appState.handleEventForTesting(.streamToken(sessionId: sid, text: "Hello"))

        XCTAssertEqual(appState.activeSessions[uuid]?.agentName, "Agent")
        XCTAssertEqual(appState.activeSessions[uuid]?.tokenCount, 1)
        XCTAssertTrue(appState.activeSessions[uuid]?.isStreaming ?? false)
    }

    func testEH5_sessionResultEvent_clearsStreamingFlags() {
        let sid = UUID()
        appState.activeSessions[sid] = AppState.SessionInfo(id: sid, agentName: "Bot", isStreaming: true)
        appState.thinkingText[sid.uuidString] = "thinking..."

        appState.handleEventForTesting(.sessionResult(sessionId: sid.uuidString, result: "done", cost: 0.01, tokenCount: 100, toolCallCount: 5))

        XCTAssertFalse(appState.activeSessions[sid]?.isStreaming ?? true)
        XCTAssertNil(appState.thinkingText[sid.uuidString])
        if case .result = appState.lastSessionEvent[sid.uuidString] {
            // correct
        } else {
            XCTFail("Expected .result session event")
        }
    }

    func testEH5c_sessionResultEvent_seedsLiveSessionUsageWhenMissing() {
        let sid = makeSessionWithConversation()
        guard let uuid = UUID(uuidString: sid) else {
            return XCTFail("Expected valid UUID session id")
        }

        appState.handleEventForTesting(.sessionResult(
            sessionId: sid,
            result: "done",
            cost: 0.42,
            tokenCount: 321,
            toolCallCount: 7
        ))

        XCTAssertEqual(appState.activeSessions[uuid]?.cost, 0.42)
        XCTAssertEqual(appState.activeSessions[uuid]?.tokenCount, 321)
        XCTAssertEqual(appState.activeSessions[uuid]?.toolCallCount, 7)
        XCTAssertFalse(appState.activeSessions[uuid]?.isStreaming ?? true)
    }

    func testEH5b_sessionResultEvent_clearsPendingQuestionsAndConfirmations() {
        let sid = UUID().uuidString
        appState.pendingQuestions[sid] = AppState.AgentQuestion(
            id: "question-1",
            sessionId: sid,
            question: "Proceed?",
            options: nil,
            multiSelect: false,
            isPrivate: true,
            timestamp: Date(),
            inputType: "text",
            inputConfig: nil
        )
        appState.pendingConfirmations[sid] = AppState.AgentConfirmation(
            id: "confirmation-1",
            sessionId: sid,
            action: "Run command",
            reason: "Needed to continue.",
            riskLevel: "medium",
            details: nil,
            timestamp: Date()
        )

        appState.handleEventForTesting(.sessionResult(
            sessionId: sid,
            result: "done",
            cost: 0.01,
            tokenCount: 100,
            toolCallCount: 5
        ))

        XCTAssertNil(appState.pendingQuestions[sid])
        XCTAssertNil(appState.pendingConfirmations[sid])
        XCTAssertEqual(appState.sessionActivity[sid], .done)
    }

    func testEH5d_markSessionPausedLocallyClearsLiveActivity() {
        let sid = makeSessionWithConversation()
        guard let uuid = UUID(uuidString: sid) else {
            return XCTFail("Expected valid UUID session id")
        }

        appState.activeSessions[uuid] = AppState.SessionInfo(id: uuid, agentName: "Bot", isStreaming: true)
        appState.sessionActivity[sid] = .streaming
        appState.thinkingText[sid] = "thinking..."
        appState.pendingQuestions[sid] = AppState.AgentQuestion(
            id: "question-1",
            sessionId: sid,
            question: "Proceed?",
            options: nil,
            multiSelect: false,
            isPrivate: true,
            timestamp: Date(),
            inputType: "text",
            inputConfig: nil
        )

        appState.markSessionPausedLocally(sid)

        XCTAssertEqual(appState.sessionActivity[sid], .idle)
        XCTAssertFalse(appState.activeSessions[uuid]?.isStreaming ?? true)
        XCTAssertNil(appState.thinkingText[sid])
        XCTAssertNil(appState.pendingQuestions[sid])
    }

    func testEH6_sessionErrorEvent_capturesError() {
        let sid = UUID()
        appState.activeSessions[sid] = AppState.SessionInfo(id: sid, agentName: "Bot", isStreaming: true)

        appState.handleEventForTesting(.sessionError(sessionId: sid.uuidString, error: "something broke"))

        XCTAssertFalse(appState.activeSessions[sid]?.isStreaming ?? true)
        if case .error(let msg) = appState.lastSessionEvent[sid.uuidString] {
            XCTAssertEqual(msg, "something broke")
        } else {
            XCTFail("Expected .error session event")
        }
    }

    func testEH6b_sessionErrorEvent_clearsPendingQuestionsAndConfirmations() {
        let sid = UUID().uuidString
        appState.pendingQuestions[sid] = AppState.AgentQuestion(
            id: "question-1",
            sessionId: sid,
            question: "Proceed?",
            options: nil,
            multiSelect: false,
            isPrivate: true,
            timestamp: Date(),
            inputType: "text",
            inputConfig: nil
        )
        appState.pendingConfirmations[sid] = AppState.AgentConfirmation(
            id: "confirmation-1",
            sessionId: sid,
            action: "Run command",
            reason: "Needed to continue.",
            riskLevel: "high",
            details: nil,
            timestamp: Date()
        )

        appState.handleEventForTesting(.sessionError(sessionId: sid, error: "something broke"))

        XCTAssertNil(appState.pendingQuestions[sid])
        XCTAssertNil(appState.pendingConfirmations[sid])
        XCTAssertEqual(appState.sessionActivity[sid], .error("something broke"))
    }

    func testEH7_sessionForked_doesNotTouchCommsOrStreaming() {
        let before = appState.commsEvents.count
        appState.handleEventForTesting(.sessionForked(parentSessionId: "parent-uuid", childSessionId: "child-uuid"))
        XCTAssertEqual(appState.commsEvents.count, before)
        XCTAssertTrue(appState.streamingText.isEmpty)
    }

    func testEH7b_connectorStatusChanged_upsertsConnectionModel() throws {
        let connection = ConnectorWire(
            id: UUID().uuidString,
            provider: "x",
            installScope: "system",
            displayName: "X Sandbox",
            accountId: "acct-1",
            accountHandle: "@sandbox",
            accountMetadataJSON: nil,
            grantedScopes: ["users.read", "tweet.write"],
            authMode: "pkce-native",
            writePolicy: "require-approval",
            status: "connected",
            statusMessage: "Ready",
            brokerReference: nil,
            auditSummary: nil,
            lastAuthenticatedAt: "2026-04-02T10:00:00Z",
            lastCheckedAt: "2026-04-02T10:05:00Z"
        )

        appState.handleEventForTesting(.connectorStatusChanged(connection: connection))

        let connections = try context.fetch(FetchDescriptor<Connection>())
        XCTAssertEqual(connections.count, 1)
        XCTAssertEqual(connections.first?.provider, .x)
        XCTAssertEqual(connections.first?.status, .connected)
        XCTAssertEqual(connections.first?.displayName, "X Sandbox")
        XCTAssertEqual(connections.first?.accountHandle, "@sandbox")
    }

    func testEH7c_connectorAudit_updatesAuditSummary() throws {
        let connection = Connection(provider: .slack, authMode: .brokered)
        context.insert(connection)
        try context.save()

        appState.handleEventForTesting(.connectorAudit(
            sessionId: nil,
            connectionId: connection.id.uuidString,
            provider: "slack",
            action: "slack_post_message",
            outcome: "allowed",
            summary: "Write action approved."
        ))

        let refreshed = try context.fetch(FetchDescriptor<Connection>()).first
        XCTAssertEqual(refreshed?.auditSummary, "allowed: Write action approved.")
        XCTAssertNotNil(refreshed?.lastCheckedAt)
    }

    // MARK: - CF: Comms Filtering

    func testCF1_filterByChats_returnsOnlyChatEvents() {
        let sid = makeSessionWithConversation()
        appState.handleEventForTesting(.peerChat(sessionId: sid, channelId: "c1", from: "A", message: "hi"))
        appState.handleEventForTesting(.peerDelegate(sessionId: sid, from: "A", to: "B", task: "do it"))
        appState.handleEventForTesting(.blackboardUpdate(sessionId: sid, key: "k", value: "v", writtenBy: "A"))
        appState.handleEventForTesting(.peerChat(sessionId: sid, channelId: "c2", from: "B", message: "bye"))

        let filtered = appState.commsEvents.filter { event in
            if case .chat = event.kind { return true }
            return false
        }
        XCTAssertEqual(filtered.count, 2)
    }

    func testCF2_filterByDelegations_returnsOnlyDelegationEvents() {
        let sid = makeSessionWithConversation()
        appState.handleEventForTesting(.peerChat(sessionId: sid, channelId: "c1", from: "A", message: "hi"))
        appState.handleEventForTesting(.peerDelegate(sessionId: sid, from: "A", to: "B", task: "task1"))
        appState.handleEventForTesting(.peerDelegate(sessionId: sid, from: "B", to: "C", task: "task2"))

        let filtered = appState.commsEvents.filter { event in
            if case .delegation = event.kind { return true }
            return false
        }
        XCTAssertEqual(filtered.count, 2)
    }

    func testCF3_filterByAll_returnsEverything() {
        let sid = makeSessionWithConversation()
        appState.handleEventForTesting(.peerChat(sessionId: sid, channelId: "c1", from: "A", message: "hi"))
        appState.handleEventForTesting(.peerDelegate(sessionId: sid, from: "A", to: "B", task: "task"))
        appState.handleEventForTesting(.blackboardUpdate(sessionId: sid, key: "k", value: "v", writtenBy: "A"))

        XCTAssertEqual(appState.commsEvents.count, 3)
    }
}
