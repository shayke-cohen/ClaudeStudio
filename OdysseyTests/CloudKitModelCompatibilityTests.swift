import Foundation
import SwiftData
import XCTest
@testable import Odyssey

/// Tests that SwiftData models meet CloudKit sync requirements.
/// These protect the two-layer architecture (CloudKit data + Nostr messaging).
///
/// CloudKit constraints:
/// - No @Attribute(.unique): would cause fatal error with cloudKitDatabase: .automatic
/// - No cascade deletes: CloudKit doesn't support server-side cascade; must nullify + manually delete
/// - Enum storage: raw String/Int only (no complex types)
///
/// RED → GREEN order:
/// Cascade-delete tests are RED until @Relationship(deleteRule:) is changed to .nullify
/// and cascade logic is moved into delete helpers.
@MainActor
final class CloudKitModelCompatibilityTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Agent.self, Session.self, Conversation.self,
            ConversationMessage.self, MessageAttachment.self,
            Participant.self, Skill.self, Connection.self, MCPServer.self,
            PermissionSet.self, BlackboardEntry.self, AgentGroup.self,
            Project.self, PromptTemplate.self,
            configurations: config
        )
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
    }

    // MARK: - Agent → Sessions relationship (must not cascade)

    func test_agentDelete_doesNotCascadeToSessions() throws {
        let agent = Agent(
            name: "CascadeTestAgent",
            agentDescription: "",
            systemPrompt: "",
            model: "claude-sonnet-4-6"
        )
        context.insert(agent)
        let session = Session(agent: agent)
        agent.sessions.append(session)
        context.insert(session)
        try context.save()

        let sessionId = session.id
        context.delete(agent)
        try context.save()

        // After agent deletion, session should still exist (nullified, not cascaded)
        let descriptor = FetchDescriptor<Session>(
            predicate: #Predicate { $0.id == sessionId }
        )
        let remaining = try context.fetch(descriptor)
        XCTAssertEqual(remaining.count, 1,
            "Session must survive agent deletion — cascade delete is incompatible with CloudKit sync")
        XCTAssertNil(remaining.first?.agent,
            "Session.agent must be nil after agent deletion (nullify, not cascade)")
    }

    // MARK: - Agent → PromptTemplates relationship (must not cascade)

    func test_agentDelete_doesNotCascadeToPromptTemplates() throws {
        let agent = Agent(
            name: "TemplateOwner",
            agentDescription: "",
            systemPrompt: "",
            model: "claude-sonnet-4-6"
        )
        context.insert(agent)
        let template = PromptTemplate(name: "Test Template", prompt: "Hello", agent: agent)
        context.insert(template)
        agent.promptTemplates.append(template)
        try context.save()

        let templateId = template.id
        context.delete(agent)
        try context.save()

        let descriptor = FetchDescriptor<PromptTemplate>(
            predicate: #Predicate { $0.id == templateId }
        )
        let remaining = try context.fetch(descriptor)
        XCTAssertEqual(remaining.count, 1,
            "PromptTemplate must survive agent deletion — use nullify not cascade")
    }

    // MARK: - Conversation → Messages relationship (must not cascade)

    func test_conversationDelete_doesNotCascadeToMessages() throws {
        let conv = Conversation(topic: "CascadeTest")
        context.insert(conv)
        let msg = ConversationMessage(text: "hello", type: .chat, conversation: conv)
        conv.messages.append(msg)
        context.insert(msg)
        try context.save()

        let msgId = msg.id
        context.delete(conv)
        try context.save()

        let descriptor = FetchDescriptor<ConversationMessage>(
            predicate: #Predicate { $0.id == msgId }
        )
        let remaining = try context.fetch(descriptor)
        XCTAssertEqual(remaining.count, 1,
            "ConversationMessage must survive conversation deletion — use nullify not cascade")
    }

    // MARK: - Conversation → Participants relationship (must not cascade)

    func test_conversationDelete_doesNotCascadeToParticipants() throws {
        let conv = Conversation(topic: "ParticipantTest")
        context.insert(conv)
        let participant = Participant(type: .user, displayName: "Alice")
        conv.participants.append(participant)
        context.insert(participant)
        try context.save()

        let participantId = participant.id
        context.delete(conv)
        try context.save()

        let descriptor = FetchDescriptor<Participant>(
            predicate: #Predicate { $0.id == participantId }
        )
        let remaining = try context.fetch(descriptor)
        XCTAssertEqual(remaining.count, 1,
            "Participant must survive conversation deletion — use nullify not cascade")
    }

    // MARK: - ConversationMessage → Attachments relationship (must not cascade)

    func test_messageDelete_doesNotCascadeToAttachments() throws {
        let conv = Conversation(topic: "AttachTest")
        context.insert(conv)
        let msg = ConversationMessage(text: "with attachment", type: .chat, conversation: conv)
        context.insert(msg)
        let attachment = MessageAttachment(
            mediaType: "text/plain",
            fileName: "test.txt",
            fileSize: 5
        )
        msg.attachments.append(attachment)
        context.insert(attachment)
        try context.save()

        let attachmentId = attachment.id
        context.delete(msg)
        try context.save()

        let descriptor = FetchDescriptor<MessageAttachment>(
            predicate: #Predicate { $0.id == attachmentId }
        )
        let remaining = try context.fetch(descriptor)
        XCTAssertEqual(remaining.count, 1,
            "MessageAttachment must survive message deletion — use nullify not cascade")
    }

    // MARK: - Enum raw value round-trips (required for CloudKit compatibility)

    func test_sessionStatus_rawValueRoundTrip() throws {
        let agent = Agent(name: "EnumAgent", agentDescription: "", systemPrompt: "", model: "claude-sonnet-4-6")
        context.insert(agent)
        let session = Session(agent: agent)
        session.status = .active
        context.insert(session)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Session>()).first
        XCTAssertEqual(fetched?.status, .active,
            "SessionStatus must round-trip through SwiftData storage for CloudKit compat")
    }

    func test_conversationStatus_rawValueRoundTrip() throws {
        let conv = Conversation(topic: "EnumTest")
        context.insert(conv)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Conversation>()).first
        XCTAssertNotNil(fetched?.status,
            "ConversationStatus must persist and round-trip for CloudKit compat")
    }

    func test_participantType_rawValueRoundTrip() throws {
        let conv = Conversation(topic: "TypeTest")
        context.insert(conv)
        let participant = Participant(type: .user, displayName: "Bob")
        conv.participants.append(participant)
        context.insert(participant)
        try context.save()

        let descriptor = FetchDescriptor<Participant>()
        let fetched = try context.fetch(descriptor).first
        XCTAssertNotNil(fetched?.typeKind,
            "Participant typeKind (raw enum storage) must persist for CloudKit compat")
    }
}
