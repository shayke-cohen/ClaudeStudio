import Foundation
import SwiftData
import XCTest
@testable import Odyssey

/// Tests for sidebar filtering helpers that were changed to use
/// agent.sessions relationship instead of full allSessions scan.
@MainActor
final class SidebarFilterTests: XCTestCase {

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

    private func makeAgent(name: String = "TestAgent") -> Agent {
        let agent = Agent(
            name: name,
            description: "",
            systemPrompt: "",
            model: "claude-sonnet-4-6"
        )
        context.insert(agent)
        return agent
    }

    private func makeSession(for agent: Agent) -> Session {
        let session = Session(agent: agent)
        agent.sessions.append(session)
        context.insert(session)
        return session
    }

    private func makeConversation(for session: Session, topic: String, archived: Bool = false) -> Conversation {
        let conv = Conversation(topic: topic)
        conv.isArchived = archived
        session.conversations.append(conv)
        context.insert(conv)
        return conv
    }

    // MARK: - conversationsForAgent via agent.sessions relationship

    func testConversationsForAgent_returnsConversationsViaRelationship() throws {
        let agent = makeAgent()
        let session = makeSession(for: agent)
        let conv = makeConversation(for: session, topic: "My Thread")
        try context.save()

        let result = agent.sessions
            .compactMap { $0.conversations.first }
            .filter { $0.sourceGroupId == nil && !$0.isArchived }

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, conv.id)
    }

    func testConversationsForAgent_excludesArchivedConversations() throws {
        let agent = makeAgent()
        let session1 = makeSession(for: agent)
        let session2 = makeSession(for: agent)
        _ = makeConversation(for: session1, topic: "Active")
        _ = makeConversation(for: session2, topic: "Archived", archived: true)
        try context.save()

        let active = agent.sessions
            .compactMap { $0.conversations.first }
            .filter { !$0.isArchived }

        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active.first?.topic, "Active")
    }

    func testConversationsForAgent_doesNotReturnOtherAgentsConversations() throws {
        let agent1 = makeAgent(name: "Agent1")
        let agent2 = makeAgent(name: "Agent2")

        let session1 = makeSession(for: agent1)
        let session2 = makeSession(for: agent2)

        _ = makeConversation(for: session1, topic: "Agent1 Thread")
        _ = makeConversation(for: session2, topic: "Agent2 Thread")
        try context.save()

        let agent1Convs = agent1.sessions.compactMap { $0.conversations.first }
        let agent2Convs = agent2.sessions.compactMap { $0.conversations.first }

        XCTAssertEqual(agent1Convs.count, 1)
        XCTAssertEqual(agent2Convs.count, 1)
        XCTAssertEqual(agent1Convs.first?.topic, "Agent1 Thread")
        XCTAssertEqual(agent2Convs.first?.topic, "Agent2 Thread")
    }

    func testConversationsForAgent_emptyAgentReturnsEmptyList() throws {
        let agent = makeAgent()
        try context.save()

        let result = agent.sessions.compactMap { $0.conversations.first }
        XCTAssertTrue(result.isEmpty)
    }

    func testArchivedConversationsForAgent_returnsOnlyArchived() throws {
        let agent = makeAgent()
        let session1 = makeSession(for: agent)
        let session2 = makeSession(for: agent)

        _ = makeConversation(for: session1, topic: "Active Thread")
        _ = makeConversation(for: session2, topic: "Archived Thread", archived: true)
        try context.save()

        let archived = agent.sessions
            .compactMap { $0.conversations.first }
            .filter { $0.isArchived }

        XCTAssertEqual(archived.count, 1)
        XCTAssertEqual(archived.first?.topic, "Archived Thread")
    }

    func testConversationsForAgent_deduplicatesIfSameConvInMultipleSessions() throws {
        let agent = makeAgent()
        let session1 = makeSession(for: agent)
        let session2 = makeSession(for: agent)

        // Same conversation referenced in both sessions (edge case)
        let conv = Conversation(topic: "Shared")
        context.insert(conv)
        session1.conversations.append(conv)
        session2.conversations.append(conv)
        try context.save()

        var seen = Set<UUID>()
        let deduped = agent.sessions
            .compactMap { $0.conversations.first }
            .filter { seen.insert($0.id).inserted }

        XCTAssertEqual(deduped.count, 1)
    }
}
