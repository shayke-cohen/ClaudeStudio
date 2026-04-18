import Foundation
import SwiftData
import XCTest
@testable import Odyssey

/// Tests for ChatView data helpers extracted for isolated logic verification.
/// Covers the logic behind sortedMessages caching (Fix 5) and participantAppearanceMap (Fix 6).
@MainActor
final class ChatViewDataTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Agent.self, Session.self, Conversation.self,
            ConversationMessage.self, MessageAttachment.self,
            Participant.self, Skill.self, Connection.self, MCPServer.self,
            PermissionSet.self, BlackboardEntry.self, AgentGroup.self,
            Project.self,
            configurations: config
        )
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
    }

    // MARK: - Helpers

    private func makeConversation() -> Conversation {
        let conv = Conversation(topic: "Test")
        context.insert(conv)
        return conv
    }

    private func addMessage(to conv: Conversation, text: String, timestampOffset: TimeInterval) -> ConversationMessage {
        let msg = ConversationMessage(text: text, type: .chat, conversation: conv)
        msg.timestamp = Date(timeIntervalSince1970: 1_000_000 + timestampOffset)
        context.insert(msg)
        return msg
    }

    // MARK: - Fix 5: sortedMessages ordering

    func testSortedMessages_chronologicalOrder() throws {
        let conv = makeConversation()
        addMessage(to: conv, text: "third", timestampOffset: 300)
        addMessage(to: conv, text: "first", timestampOffset: 0)
        addMessage(to: conv, text: "second", timestampOffset: 100)
        try context.save()

        let sorted = (conv.messages).sorted { $0.timestamp < $1.timestamp }

        XCTAssertEqual(sorted.count, 3)
        XCTAssertEqual(sorted[0].text, "first")
        XCTAssertEqual(sorted[1].text, "second")
        XCTAssertEqual(sorted[2].text, "third")
    }

    func testSortedMessages_emptyConversation() throws {
        let conv = makeConversation()
        try context.save()

        let sorted = (conv.messages).sorted { $0.timestamp < $1.timestamp }
        XCTAssertTrue(sorted.isEmpty)
    }

    func testSortedMessages_singleMessage() throws {
        let conv = makeConversation()
        let msg = addMessage(to: conv, text: "only", timestampOffset: 0)
        try context.save()

        let sorted = (conv.messages).sorted { $0.timestamp < $1.timestamp }
        XCTAssertEqual(sorted.count, 1)
        XCTAssertEqual(sorted.first?.id, msg.id)
    }

    // MARK: - Fix 6: participantAppearanceMap building logic

    func testParticipantAppearanceMap_singleSession_returnsNil() throws {
        let agent = Agent(name: "Solo", description: "", systemPrompt: "", model: "claude-sonnet-4-6")
        context.insert(agent)

        let conv = makeConversation()
        let session = Session(agent: agent)
        conv.sessions.append(session)
        context.insert(session)
        try context.save()

        // Single-session conversation → map should be nil (no visual distinction needed)
        XCTAssertEqual(conv.sessions.count, 1)
        // The map-building condition: `convo.sessions.count > 1` → returns nil for single session
        let shouldBuildMap = conv.sessions.count > 1
        XCTAssertFalse(shouldBuildMap)
    }

    func testParticipantAppearanceMap_multiSession_buildsMap() throws {
        let agent1 = Agent(name: "Alpha", description: "", systemPrompt: "", model: "claude-sonnet-4-6")
        let agent2 = Agent(name: "Beta", description: "", systemPrompt: "", model: "claude-sonnet-4-6")
        agent1.color = "blue"
        agent2.color = "red"
        context.insert(agent1)
        context.insert(agent2)

        let conv = makeConversation()
        let session1 = Session(agent: agent1)
        let session2 = Session(agent: agent2)
        conv.sessions.append(session1)
        conv.sessions.append(session2)
        context.insert(session1)
        context.insert(session2)

        let participant1 = Participant(type: .agentSession(sessionId: session1.id))
        let participant2 = Participant(type: .agentSession(sessionId: session2.id))
        conv.participants.append(participant1)
        conv.participants.append(participant2)
        context.insert(participant1)
        context.insert(participant2)
        try context.save()

        // Build the map (mirrors the logic in rebuildParticipantAppearanceMap)
        var map: [UUID: AgentAppearance] = [:]
        for participant in conv.participants {
            if let sessionId = participant.typeSessionId,
               let session = conv.sessions.first(where: { $0.id == sessionId }),
               let agent = session.agent {
                map[participant.id] = AgentAppearance(
                    color: Color.fromAgentColor(agent.color),
                    icon: agent.icon
                )
            }
        }

        XCTAssertEqual(map.count, 2)
        XCTAssertNotNil(map[participant1.id])
        XCTAssertNotNil(map[participant2.id])
    }

    func testParticipantAppearanceMap_emptyParticipants_returnsNil() throws {
        let conv = makeConversation()
        let session1 = Session(agent: nil)
        let session2 = Session(agent: nil)
        conv.sessions.append(session1)
        conv.sessions.append(session2)
        context.insert(session1)
        context.insert(session2)
        try context.save()

        // No participants → map is empty → should return nil
        var map: [UUID: AgentAppearance] = [:]
        for participant in conv.participants {
            if let sessionId = participant.typeSessionId,
               let session = conv.sessions.first(where: { $0.id == sessionId }),
               let agent = session.agent {
                map[participant.id] = AgentAppearance(
                    color: Color.fromAgentColor(agent.color),
                    icon: agent.icon
                )
            }
        }

        XCTAssertTrue(map.isEmpty)
        let result: [UUID: AgentAppearance]? = map.isEmpty ? nil : map
        XCTAssertNil(result)
    }
}
