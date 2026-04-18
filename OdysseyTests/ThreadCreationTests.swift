import SwiftData
import XCTest
@testable import Odyssey

@MainActor
final class ThreadCreationTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var appState: AppState!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Agent.self, Session.self, Conversation.self,
            ConversationMessage.self, MessageAttachment.self,
            Participant.self, Skill.self, Connection.self, MCPServer.self,
            PermissionSet.self, BlackboardEntry.self, AgentGroup.self,
            NostrPeer.self, PromptTemplate.self,
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

    // MARK: - Unit — Mission trimming

    func testMissionTrimming_emptyString_becomesNil() {
        let trimmed = "".trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(trimmed.isEmpty)
        let sessionMission: String? = trimmed.isEmpty ? nil : trimmed
        XCTAssertNil(sessionMission)
    }

    func testMissionTrimming_whitespaceOnly_becomesNil() {
        let trimmed = "   \n  ".trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(trimmed.isEmpty)
        let sessionMission: String? = trimmed.isEmpty ? nil : trimmed
        XCTAssertNil(sessionMission)
    }

    func testMissionTrimming_withContent_preserved() {
        let raw = "  fix bug  "
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(trimmed.isEmpty)
        let sessionMission: String? = trimmed.isEmpty ? nil : trimmed
        XCTAssertEqual(sessionMission, "fix bug")
    }

    // MARK: - Unit — ThreadKind selection

    func testThreadKind_withAgent_isDirect() {
        let agent: Agent? = Agent(name: "Coder")
        let kind: ThreadKind = agent != nil ? .direct : .freeform
        XCTAssertEqual(kind, .direct)
    }

    func testThreadKind_withoutAgent_isFreeform() {
        let agent: Agent? = nil
        let kind: ThreadKind = agent != nil ? .direct : .freeform
        XCTAssertEqual(kind, .freeform)
    }

    // MARK: - Integration — Agent Thread Creation (SwiftData)

    func testIntegration_agentThread_createsConversationWithDirectKind() throws {
        let agent = Agent(name: "Coder")
        context.insert(agent)

        let session = Session(agent: agent, mission: nil)
        let conversation = Conversation(topic: "Thread", threadKind: .direct)
        session.conversations = [conversation]

        let userParticipant = Participant(type: .user, displayName: "You")
        userParticipant.conversation = conversation
        let agentParticipant = Participant(type: .agentSession(sessionId: session.id), displayName: agent.name)
        agentParticipant.conversation = conversation

        context.insert(conversation)
        context.insert(session)
        context.insert(userParticipant)
        context.insert(agentParticipant)
        try context.save()

        let conversations = try context.fetch(FetchDescriptor<Conversation>())
        XCTAssertEqual(conversations.count, 1)
        XCTAssertEqual(conversations.first?.threadKind, .direct)
    }

    func testIntegration_agentThread_missionPassedToSession() throws {
        let agent = Agent(name: "Coder")
        context.insert(agent)

        let mission = "fix the login bug"
        let session = Session(agent: agent, mission: mission)
        let conversation = Conversation(topic: "Thread", threadKind: .direct)
        session.conversations = [conversation]

        let userParticipant = Participant(type: .user, displayName: "You")
        userParticipant.conversation = conversation
        let agentParticipant = Participant(type: .agentSession(sessionId: session.id), displayName: agent.name)
        agentParticipant.conversation = conversation

        context.insert(conversation)
        context.insert(session)
        context.insert(userParticipant)
        context.insert(agentParticipant)
        try context.save()

        let sessions = try context.fetch(FetchDescriptor<Session>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.mission, "fix the login bug")
    }

    func testIntegration_agentThread_insertsFourObjects() throws {
        let agent = Agent(name: "Coder")
        context.insert(agent)

        let session = Session(agent: agent)
        let conversation = Conversation(topic: "Thread", threadKind: .direct)
        session.conversations = [conversation]

        let userParticipant = Participant(type: .user, displayName: "You")
        userParticipant.conversation = conversation
        let agentParticipant = Participant(type: .agentSession(sessionId: session.id), displayName: agent.name)
        agentParticipant.conversation = conversation

        context.insert(conversation)
        context.insert(session)
        context.insert(userParticipant)
        context.insert(agentParticipant)
        try context.save()

        let participantCount = try context.fetchCount(FetchDescriptor<Participant>())
        XCTAssertEqual(participantCount, 2)
    }

    func testIntegration_agentThread_participantTypesCorrect() throws {
        let agent = Agent(name: "Coder")
        context.insert(agent)

        let session = Session(agent: agent)
        let conversation = Conversation(topic: "Thread", threadKind: .direct)
        session.conversations = [conversation]

        let userParticipant = Participant(type: .user, displayName: "You")
        userParticipant.conversation = conversation
        let agentParticipant = Participant(type: .agentSession(sessionId: session.id), displayName: agent.name)
        agentParticipant.conversation = conversation

        context.insert(conversation)
        context.insert(session)
        context.insert(userParticipant)
        context.insert(agentParticipant)
        try context.save()

        let participants = try context.fetch(FetchDescriptor<Participant>())
        XCTAssertEqual(participants.count, 2)

        let userPs = participants.filter {
            if case .user = $0.type { return true }
            return false
        }
        XCTAssertEqual(userPs.count, 1)

        let agentPs = participants.filter {
            if case .agentSession = $0.type { return true }
            return false
        }
        XCTAssertEqual(agentPs.count, 1)
    }

    func testIntegration_freeformThread_threadKindIsFreeform() throws {
        let conversation = Conversation(topic: "Thread", threadKind: .freeform)
        context.insert(conversation)
        try context.save()

        let conversations = try context.fetch(FetchDescriptor<Conversation>())
        XCTAssertEqual(conversations.count, 1)
        XCTAssertEqual(conversations.first?.threadKind, .freeform)
    }

    // MARK: - API — AppState.startGroupChat

    func testAPI_startGroupChat_returnsConversationId() throws {
        let agent = Agent(name: "Coder")
        context.insert(agent)
        try context.save()

        let group = AgentGroup(name: "Dev Team", agentIds: [agent.id])
        context.insert(group)
        try context.save()

        let result = appState.startGroupChat(
            group: group,
            projectDirectory: "/tmp",
            projectId: nil,
            modelContext: context
        )

        XCTAssertNotNil(result)
    }

    func testAPI_startGroupChat_persistsConversation() throws {
        let agent = Agent(name: "Coder")
        context.insert(agent)
        try context.save()

        let group = AgentGroup(name: "Dev Team", agentIds: [agent.id])
        context.insert(group)
        try context.save()

        appState.startGroupChat(
            group: group,
            projectDirectory: "/tmp",
            projectId: nil,
            modelContext: context
        )

        let conversations = try context.fetch(FetchDescriptor<Conversation>())
        XCTAssertEqual(conversations.count, 1)
        XCTAssertEqual(conversations.first?.threadKind, .group)
    }

    func testAPI_startGroupChat_missionOverrideSetOnSessions() throws {
        let agent = Agent(name: "Coder")
        context.insert(agent)
        try context.save()

        let group = AgentGroup(name: "Dev Team", agentIds: [agent.id])
        context.insert(group)
        try context.save()

        appState.startGroupChat(
            group: group,
            projectDirectory: "/tmp",
            projectId: nil,
            modelContext: context,
            missionOverride: "fix all bugs"
        )

        let sessions = try context.fetch(FetchDescriptor<Session>())
        XCTAssertFalse(sessions.isEmpty)
        let missionedSession = sessions.first { $0.mission == "fix all bugs" }
        XCTAssertNotNil(missionedSession)
    }

    func testAPI_startGroupChat_emptyGroup_returnsNil() throws {
        let group = AgentGroup(name: "Empty Group", agentIds: [])
        context.insert(group)
        try context.save()

        let result = appState.startGroupChat(
            group: group,
            projectDirectory: "/tmp",
            projectId: nil,
            modelContext: context
        )

        XCTAssertNil(result)
    }

    func testAPI_startGroupChat_noMatchingAgents_returnsNil() throws {
        // AgentGroup references a UUID that has no corresponding Agent in the store
        let nonExistentAgentId = UUID()
        let group = AgentGroup(name: "Ghost Team", agentIds: [nonExistentAgentId])
        context.insert(group)
        try context.save()

        let result = appState.startGroupChat(
            group: group,
            projectDirectory: "/tmp",
            projectId: nil,
            modelContext: context
        )

        XCTAssertNil(result)
    }

    // MARK: - Unit — Template Filtering Logic

    func testTemplateFilter_byAgentId_returnsOnlyMatching() throws {
        let agentA = Agent(name: "Agent A")
        let agentB = Agent(name: "Agent B")
        context.insert(agentA)
        context.insert(agentB)

        let templateForA = PromptTemplate(name: "Fix Bug", prompt: "Fix the bug", agent: agentA)
        let templateForB = PromptTemplate(name: "Write Doc", prompt: "Write docs", agent: agentB)
        context.insert(templateForA)
        context.insert(templateForB)
        try context.save()

        let allTemplates = try context.fetch(FetchDescriptor<PromptTemplate>())
        let filtered = allTemplates.filter { $0.agent?.id == agentA.id }
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.name, "Fix Bug")
    }

    func testTemplateFilter_byGroupId_returnsOnlyMatching() throws {
        let groupG = AgentGroup(name: "Security Audit")
        context.insert(groupG)

        let templateForG = PromptTemplate(name: "Full Audit", prompt: "Audit everything", group: groupG)
        let otherTemplate = PromptTemplate(name: "Other", prompt: "Other prompt")
        context.insert(templateForG)
        context.insert(otherTemplate)
        try context.save()

        let allTemplates = try context.fetch(FetchDescriptor<PromptTemplate>())
        let filtered = allTemplates.filter { $0.group?.id == groupG.id }
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.name, "Full Audit")
    }

    func testTemplateFilter_noMatchingAgent_returnsEmpty() throws {
        let agentA = Agent(name: "Agent A")
        let agentB = Agent(name: "Agent B")
        context.insert(agentA)
        context.insert(agentB)

        let templateForA = PromptTemplate(name: "Fix Bug", prompt: "Fix the bug", agent: agentA)
        context.insert(templateForA)
        try context.save()

        let allTemplates = try context.fetch(FetchDescriptor<PromptTemplate>())
        // Filter by agentB which has no templates
        let filtered = allTemplates.filter { $0.agent?.id == agentB.id }
        XCTAssertTrue(filtered.isEmpty)
    }

    func testTemplateFilter_sortOrderRespected() throws {
        let agent = Agent(name: "Coder")
        context.insert(agent)

        let t2 = PromptTemplate(name: "C", prompt: "C body", sortOrder: 2, agent: agent)
        let t0 = PromptTemplate(name: "A", prompt: "A body", sortOrder: 0, agent: agent)
        let t1 = PromptTemplate(name: "B", prompt: "B body", sortOrder: 1, agent: agent)
        context.insert(t2)
        context.insert(t0)
        context.insert(t1)
        try context.save()

        let allTemplates = try context.fetch(FetchDescriptor<PromptTemplate>())
        let filtered = allTemplates
            .filter { $0.agent?.id == agent.id }
            .sorted { $0.sortOrder < $1.sortOrder }

        XCTAssertEqual(filtered.count, 3)
        XCTAssertEqual(filtered[0].sortOrder, 0)
        XCTAssertEqual(filtered[1].sortOrder, 1)
        XCTAssertEqual(filtered[2].sortOrder, 2)
    }

    func testTemplateFilter_freeformContext_returnsEmpty() throws {
        let agent = Agent(name: "Coder")
        context.insert(agent)

        let template = PromptTemplate(name: "Fix Bug", prompt: "Fix the bug", agent: agent)
        context.insert(template)
        try context.save()

        // Simulate freeform context: no primaryAgent, no sourceGroup
        let primaryAgent: Agent? = nil
        let sourceGroupId: UUID? = nil

        let allTemplates = try context.fetch(FetchDescriptor<PromptTemplate>())
        let filtered = allTemplates.filter { t in
            if let agentId = primaryAgent?.id {
                return t.agent?.id == agentId
            }
            if let groupId = sourceGroupId {
                return t.group?.id == groupId
            }
            return false
        }
        XCTAssertTrue(filtered.isEmpty)
    }
}
