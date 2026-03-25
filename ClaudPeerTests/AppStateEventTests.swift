import SwiftData
import XCTest
@testable import ClaudPeer

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
            Participant.self, Skill.self, MCPServer.self,
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

    // MARK: - EH: Event Handling

    func testEH1_peerChatEvent_appendsCommsAndPersists() {
        appState.handleEventForTesting(.peerChat(channelId: "ch-1", from: "AgentA", message: "hello"))

        XCTAssertEqual(appState.commsEvents.count, 1)
        if case .chat(let channelId, let from, let message) = appState.commsEvents[0].kind {
            XCTAssertEqual(channelId, "ch-1")
            XCTAssertEqual(from, "AgentA")
            XCTAssertEqual(message, "hello")
        } else {
            XCTFail("Expected .chat event kind")
        }
    }

    func testEH2_peerDelegateEvent_appendsCommsAndCreatesConversation() {
        let parentConvo = Conversation(topic: "Parent")
        context.insert(parentConvo)
        appState.selectedConversationId = parentConvo.id

        appState.handleEventForTesting(.peerDelegate(from: "Orchestrator", to: "Coder", task: "implement login"))

        XCTAssertEqual(appState.commsEvents.count, 1)
        if case .delegation(let from, let to, let task) = appState.commsEvents[0].kind {
            XCTAssertEqual(from, "Orchestrator")
            XCTAssertEqual(to, "Coder")
            XCTAssertEqual(task, "implement login")
        } else {
            XCTFail("Expected .delegation event kind")
        }

        let descriptor = FetchDescriptor<Conversation>(predicate: #Predicate { conv in
            conv.topic == "Orchestrator → Coder"
        })
        let convos = try? context.fetch(descriptor)
        XCTAssertEqual(convos?.count, 1)
        XCTAssertEqual(convos?.first?.parentConversationId, parentConvo.id)
    }

    func testEH3_blackboardUpdateEvent_appendsCommsAndUpsertsEntry() {
        appState.handleEventForTesting(.blackboardUpdate(key: "pipeline.phase", value: "research", writtenBy: "Orchestrator"))

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

        appState.handleEventForTesting(.blackboardUpdate(key: "pipeline.phase", value: "implementation", writtenBy: "Orchestrator"))
        let updated = try? context.fetch(descriptor)
        XCTAssertEqual(updated?.count, 1)
        XCTAssertEqual(updated?.first?.value, "implementation")
    }

    func testEH4_streamTokenEvent_concatenatesText() {
        let sid = UUID().uuidString
        appState.handleEventForTesting(.streamToken(sessionId: sid, text: "Hello"))
        appState.handleEventForTesting(.streamToken(sessionId: sid, text: " World"))

        XCTAssertEqual(appState.streamingText[sid], "Hello World")
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

    func testEH7_sessionForked_doesNotTouchCommsOrStreaming() {
        let before = appState.commsEvents.count
        appState.handleEventForTesting(.sessionForked(parentSessionId: "parent-uuid", childSessionId: "child-uuid"))
        XCTAssertEqual(appState.commsEvents.count, before)
        XCTAssertTrue(appState.streamingText.isEmpty)
    }

    // MARK: - CF: Comms Filtering

    func testCF1_filterByChats_returnsOnlyChatEvents() {
        appState.handleEventForTesting(.peerChat(channelId: "c1", from: "A", message: "hi"))
        appState.handleEventForTesting(.peerDelegate(from: "A", to: "B", task: "do it"))
        appState.handleEventForTesting(.blackboardUpdate(key: "k", value: "v", writtenBy: "A"))
        appState.handleEventForTesting(.peerChat(channelId: "c2", from: "B", message: "bye"))

        let filtered = appState.commsEvents.filter { event in
            if case .chat = event.kind { return true }
            return false
        }
        XCTAssertEqual(filtered.count, 2)
    }

    func testCF2_filterByDelegations_returnsOnlyDelegationEvents() {
        appState.handleEventForTesting(.peerChat(channelId: "c1", from: "A", message: "hi"))
        appState.handleEventForTesting(.peerDelegate(from: "A", to: "B", task: "task1"))
        appState.handleEventForTesting(.peerDelegate(from: "B", to: "C", task: "task2"))

        let filtered = appState.commsEvents.filter { event in
            if case .delegation = event.kind { return true }
            return false
        }
        XCTAssertEqual(filtered.count, 2)
    }

    func testCF3_filterByAll_returnsEverything() {
        appState.handleEventForTesting(.peerChat(channelId: "c1", from: "A", message: "hi"))
        appState.handleEventForTesting(.peerDelegate(from: "A", to: "B", task: "task"))
        appState.handleEventForTesting(.blackboardUpdate(key: "k", value: "v", writtenBy: "A"))

        XCTAssertEqual(appState.commsEvents.count, 3)
    }
}
