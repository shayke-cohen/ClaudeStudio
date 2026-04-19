import XCTest
import SwiftData
@testable import Odyssey

/// Tests for multi-model group functionality:
/// - Provider/model resolution for codex, foundation, mlx providers
/// - Group routing with different-provider coordinators
/// - Multi-model group prompt building
@MainActor
final class MultiModelGroupsTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Agent.self, Session.self, Conversation.self, ConversationMessage.self,
            MessageAttachment.self, Participant.self, Skill.self, MCPServer.self,
            PermissionSet.self, SharedWorkspace.self, BlackboardEntry.self, Peer.self,
            AgentGroup.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    // MARK: - AgentDefaults: Provider Resolution

    func testCodexProviderNormalizesCorrectly() {
        let selection = AgentDefaults.normalizedProviderSelection("codex")
        XCTAssertEqual(selection, .codex)
        XCTAssertEqual(selection.concreteProvider, "codex")
    }

    func testFoundationProviderNormalizesCorrectly() {
        let selection = AgentDefaults.normalizedProviderSelection("foundation")
        XCTAssertEqual(selection, .foundation)
        XCTAssertEqual(selection.concreteProvider, "foundation")
    }

    func testMLXProviderNormalizesCorrectly() {
        let selection = AgentDefaults.normalizedProviderSelection("mlx")
        XCTAssertEqual(selection, .mlx)
        XCTAssertEqual(selection.concreteProvider, "mlx")
    }

    func testSystemProviderHasNoConcreteProvider() {
        let selection = AgentDefaults.normalizedProviderSelection("system")
        XCTAssertEqual(selection, .system)
        XCTAssertNil(selection.concreteProvider)
    }

    func testUnknownProviderFallsBackToSystem() {
        let selection = AgentDefaults.normalizedProviderSelection("unknown-provider")
        XCTAssertEqual(selection, .system)
    }

    func testConcreteProviderCodexReturnsCodex() {
        let provider = AgentDefaults.concreteProvider(from: "codex")
        XCTAssertEqual(provider, "codex")
    }

    func testConcreteProviderFoundationReturnsFoundation() {
        let provider = AgentDefaults.concreteProvider(from: "foundation")
        XCTAssertEqual(provider, "foundation")
    }

    // MARK: - AgentDefaults: Model Compatibility

    func testGpt5CodexIsCompatibleWithCodexProvider() {
        XCTAssertTrue(AgentDefaults.isModel("gpt-5.4", compatibleWith: "codex"))
    }

    func testOpusIsNotCompatibleWithCodexProvider() {
        XCTAssertFalse(AgentDefaults.isModel("opus", compatibleWith: "codex"))
    }

    func testFoundationSystemIsCompatibleWithFoundationProvider() {
        XCTAssertTrue(AgentDefaults.isModel("foundation.system", compatibleWith: "foundation"))
    }

    func testGpt5CodexIsNotCompatibleWithClaudeProvider() {
        XCTAssertFalse(AgentDefaults.isModel("gpt-5.4", compatibleWith: "claude"))
    }

    func testFoundationSystemIsNotCompatibleWithCodexProvider() {
        XCTAssertFalse(AgentDefaults.isModel("foundation.system", compatibleWith: "codex"))
    }

    // MARK: - Dual Coder Debate: Reviewer as coordinator

    func testDualCoderDebateReviewerReceivesUnmentionedMessages() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let codexCoder = Agent(name: "Coder (Codex)", provider: "codex", model: "gpt-5.4")
        let claudeCoder = Agent(name: "Coder", provider: "claude", model: "opus")
        let reviewer = Agent(name: "Reviewer", provider: "claude", model: "sonnet")
        ctx.insert(codexCoder); ctx.insert(claudeCoder); ctx.insert(reviewer)

        let group = AgentGroup(
            name: "Dual Coder Debate",
            groupDescription: "Same problem, two models.",
            icon: "🥊", color: "blue",
            groupInstruction: "Two coders, one reviewer.",
            defaultMission: nil,
            agentIds: [codexCoder.id, claudeCoder.id, reviewer.id],
            sortOrder: 11
        )
        group.origin = .builtin
        group.coordinatorAgentId = reviewer.id
        group.agentRoles = [reviewer.id: "coordinator"]
        ctx.insert(group)

        let (convo, sessions) = try makeGroupConversation(
            ctx: ctx,
            group: group,
            agents: [codexCoder, claudeCoder, reviewer]
        )
        let (s1, s2, s3) = (sessions[0], sessions[1], sessions[2])

        let plan = GroupRoutingPlanner.planUserWave(
            routingMode: .mentionAware,
            sessions: [s1, s2, s3],
            sourceGroup: group,
            mentionedAgents: [],
            mentionedAll: false
        )

        XCTAssertTrue(plan.recipientSessionIds.contains(s3.id),
            "Reviewer (coordinator) should receive when no agent is mentioned")
        XCTAssertEqual(plan.deliveryReason, .coordinatorLead)
    }

    func testDualCoderDebateExplicitMentionRoutesCoder() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let codexCoder = Agent(name: "Coder (Codex)", provider: "codex", model: "gpt-5.4")
        let claudeCoder = Agent(name: "Coder", provider: "claude", model: "opus")
        let reviewer = Agent(name: "Reviewer", provider: "claude", model: "sonnet")
        ctx.insert(codexCoder); ctx.insert(claudeCoder); ctx.insert(reviewer)

        let group = AgentGroup(
            name: "Dual Coder Debate",
            groupDescription: "Same problem, two models.",
            icon: "🥊", color: "blue",
            groupInstruction: "Two coders, one reviewer.",
            defaultMission: nil,
            agentIds: [codexCoder.id, claudeCoder.id, reviewer.id],
            sortOrder: 11
        )
        group.origin = .builtin
        group.coordinatorAgentId = reviewer.id
        group.agentRoles = [reviewer.id: "coordinator"]
        ctx.insert(group)

        let (_, sessions) = try makeGroupConversation(
            ctx: ctx,
            group: group,
            agents: [codexCoder, claudeCoder, reviewer]
        )
        let (s1, _, s3) = (sessions[0], sessions[1], sessions[2])

        let plan = GroupRoutingPlanner.planUserWave(
            routingMode: .mentionAware,
            sessions: sessions,
            sourceGroup: group,
            mentionedAgents: [codexCoder],
            mentionedAll: false
        )

        XCTAssertTrue(plan.recipientSessionIds.contains(s1.id),
            "Explicitly @mentioned Codex Coder should receive message")
        XCTAssertFalse(plan.recipientSessionIds.contains(s3.id),
            "Reviewer should not receive when Codex Coder is explicitly mentioned")
        XCTAssertEqual(plan.deliveryReason, .directMention)
    }

    // MARK: - Local First: Local coder as coordinator (privacy-first)

    func testLocalFirstCoderReceivesUnmentionedMessages() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let localCoder = Agent(name: "Coder (Local)", provider: "foundation", model: "foundation.system")
        let reviewer = Agent(name: "Reviewer", provider: "claude", model: "sonnet")
        ctx.insert(localCoder); ctx.insert(reviewer)

        let group = AgentGroup(
            name: "Local First",
            groupDescription: "Privacy-first workflow.",
            icon: "🔒", color: "gray",
            groupInstruction: "On-device by default.",
            defaultMission: nil,
            agentIds: [localCoder.id, reviewer.id],
            sortOrder: 14
        )
        group.origin = .builtin
        group.coordinatorAgentId = localCoder.id
        group.agentRoles = [localCoder.id: "coordinator"]
        ctx.insert(group)

        let (_, sessions) = try makeGroupConversation(
            ctx: ctx,
            group: group,
            agents: [localCoder, reviewer]
        )
        let (s1, s2) = (sessions[0], sessions[1])

        let plan = GroupRoutingPlanner.planUserWave(
            routingMode: .mentionAware,
            sessions: [s1, s2],
            sourceGroup: group,
            mentionedAgents: [],
            mentionedAll: false
        )

        XCTAssertTrue(plan.recipientSessionIds.contains(s1.id),
            "Coder (Local) should receive messages — it is the coordinator that keeps data on-device")
        XCTAssertFalse(plan.recipientSessionIds.contains(s2.id),
            "Cloud Reviewer should NOT receive messages by default — privacy requires explicit @mention")
    }

    func testLocalFirstCloudReviewerReceivesExplicitMention() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let localCoder = Agent(name: "Coder (Local)", provider: "foundation", model: "foundation.system")
        let reviewer = Agent(name: "Reviewer", provider: "claude", model: "sonnet")
        ctx.insert(localCoder); ctx.insert(reviewer)

        let group = AgentGroup(
            name: "Local First",
            groupDescription: "Privacy-first workflow.",
            icon: "🔒", color: "gray",
            groupInstruction: "On-device by default.",
            defaultMission: nil,
            agentIds: [localCoder.id, reviewer.id],
            sortOrder: 14
        )
        group.origin = .builtin
        group.coordinatorAgentId = localCoder.id
        ctx.insert(group)

        let (_, sessions) = try makeGroupConversation(
            ctx: ctx,
            group: group,
            agents: [localCoder, reviewer]
        )
        let (_, s2) = (sessions[0], sessions[1])

        let plan = GroupRoutingPlanner.planUserWave(
            routingMode: .mentionAware,
            sessions: sessions,
            sourceGroup: group,
            mentionedAgents: [reviewer],
            mentionedAll: false
        )

        XCTAssertTrue(plan.recipientSessionIds.contains(s2.id),
            "Cloud Reviewer should receive when explicitly @mentioned by user")
    }

    // MARK: - Red Team: Attacker as coordinator

    func testRedTeamAttackerReceivesUnmentionedMessages() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let coder = Agent(name: "Coder", provider: "claude", model: "opus")
        let attacker = Agent(name: "Attacker", provider: "codex", model: "gpt-5.4")
        let tester = Agent(name: "Tester", provider: "claude", model: "sonnet")
        ctx.insert(coder); ctx.insert(attacker); ctx.insert(tester)

        let group = AgentGroup(
            name: "Red Team",
            groupDescription: "Build and break.",
            icon: "🎯", color: "red",
            groupInstruction: "Build then attack.",
            defaultMission: nil,
            agentIds: [coder.id, attacker.id, tester.id],
            sortOrder: 15
        )
        group.origin = .builtin
        group.coordinatorAgentId = attacker.id
        group.agentRoles = [attacker.id: "coordinator"]
        ctx.insert(group)

        let (_, sessions) = try makeGroupConversation(
            ctx: ctx,
            group: group,
            agents: [coder, attacker, tester]
        )
        let (_, s2, _) = (sessions[0], sessions[1], sessions[2])

        let plan = GroupRoutingPlanner.planUserWave(
            routingMode: .mentionAware,
            sessions: sessions,
            sourceGroup: group,
            mentionedAgents: [],
            mentionedAll: false
        )

        XCTAssertTrue(plan.recipientSessionIds.contains(s2.id),
            "Attacker (coordinator) should receive unmentioned messages")
    }

    // MARK: - Cost-Tiered Squad: Orchestrator as coordinator, autonomous-capable

    func testCostTieredSquadIsAutonomousCapable() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let orchestrator = Agent(name: "Orchestrator", provider: "claude", model: "opus")
        let coderSonnet = Agent(name: "Coder (Sonnet)", provider: "claude", model: "sonnet")
        let testerHaiku = Agent(name: "Tester (Haiku)", provider: "claude", model: "haiku")
        ctx.insert(orchestrator); ctx.insert(coderSonnet); ctx.insert(testerHaiku)

        let group = AgentGroup(
            name: "Cost-Tiered Squad",
            groupDescription: "Opus plans, Sonnet builds, Haiku tests.",
            icon: "💸", color: "green",
            groupInstruction: "Tiered cost execution.",
            defaultMission: nil,
            agentIds: [orchestrator.id, coderSonnet.id, testerHaiku.id],
            sortOrder: 13
        )
        group.origin = .builtin
        group.autonomousCapable = true
        group.coordinatorAgentId = orchestrator.id
        group.agentRoles = [orchestrator.id: "coordinator"]
        ctx.insert(group)

        XCTAssertTrue(group.autonomousCapable)
        XCTAssertEqual(group.coordinatorAgentId, orchestrator.id)
        XCTAssertEqual(group.agentRoles[orchestrator.id], "coordinator")
    }

    func testCostTieredSquadAutonomousModeRoutesToOrchestrator() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let orchestrator = Agent(name: "Orchestrator", provider: "claude", model: "opus")
        let coderSonnet = Agent(name: "Coder (Sonnet)", provider: "claude", model: "sonnet")
        let testerHaiku = Agent(name: "Tester (Haiku)", provider: "claude", model: "haiku")
        ctx.insert(orchestrator); ctx.insert(coderSonnet); ctx.insert(testerHaiku)

        let group = AgentGroup(
            name: "Cost-Tiered Squad",
            groupDescription: "Tiered cost.",
            icon: "💸", color: "green",
            groupInstruction: "Tiered.",
            defaultMission: nil,
            agentIds: [orchestrator.id, coderSonnet.id, testerHaiku.id],
            sortOrder: 13
        )
        group.origin = .builtin
        group.autonomousCapable = true
        group.coordinatorAgentId = orchestrator.id
        ctx.insert(group)

        let (_, sessions) = try makeGroupConversation(
            ctx: ctx,
            group: group,
            agents: [orchestrator, coderSonnet, testerHaiku]
        )
        let s1 = sessions[0]

        let plan = GroupRoutingPlanner.planUserWave(
            executionMode: .autonomous,
            routingMode: .mentionAware,
            sessions: sessions,
            sourceGroup: group,
            mentionedAgents: [],
            mentionedAll: false
        )

        XCTAssertEqual(plan.recipientSessionIds.count, 1,
            "Autonomous mode should route only to the coordinator")
        XCTAssertTrue(plan.recipientSessionIds.contains(s1.id),
            "Orchestrator should be the sole recipient in autonomous mode")
        XCTAssertEqual(plan.deliveryReason, .coordinatorLead)
    }

    // MARK: - Multi-model group prompt includes all agents

    func testGroupPromptListsAllMembersIncludingCrossProvider() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let codexCoder = Agent(name: "Coder (Codex)", provider: "codex", model: "gpt-5.4")
        codexCoder.agentDescription = "OpenAI Codex engineer"
        let reviewer = Agent(name: "Reviewer", provider: "claude", model: "sonnet")
        reviewer.agentDescription = "Code reviewer"
        ctx.insert(codexCoder); ctx.insert(reviewer)

        let convo = Conversation()
        let s1 = Session(agent: codexCoder, workingDirectory: "/tmp")
        let s2 = Session(agent: reviewer, workingDirectory: "/tmp")
        s1.conversations = [convo]; s2.conversations = [convo]
        convo.sessions = [s1, s2]

        let user = Participant(type: .user, displayName: "You")
        user.conversation = convo
        let p1 = Participant(type: .agentSession(sessionId: s1.id), displayName: codexCoder.name)
        p1.conversation = convo
        let p2 = Participant(type: .agentSession(sessionId: s2.id), displayName: reviewer.name)
        p2.conversation = convo
        convo.participants.append(contentsOf: [user, p1, p2])

        ctx.insert(convo); ctx.insert(s1); ctx.insert(s2)
        ctx.insert(user); ctx.insert(p1); ctx.insert(p2)

        let text = GroupPromptBuilder.buildMessageText(
            conversation: convo,
            targetSession: s1,
            latestUserMessageText: "Implement fizzbuzz.",
            participants: convo.participants
        )

        XCTAssertFalse(text.isEmpty)
        XCTAssertTrue(
            text.contains("Coder (Codex)") || text.contains("Reviewer"),
            "Group prompt should reference team members from the team roster"
        )
    }

    // MARK: - Helpers

    private func makeGroupConversation(
        ctx: ModelContext,
        group: AgentGroup,
        agents: [Agent]
    ) throws -> (Conversation, [Session]) {
        let convo = Conversation()
        convo.sourceGroupId = group.id
        convo.routingMode = .mentionAware

        var sessions: [Session] = []
        let user = Participant(type: .user, displayName: "You")
        user.conversation = convo
        convo.participants.append(user)

        for agent in agents {
            let session = Session(agent: agent, workingDirectory: "/tmp")
            session.conversations = [convo]
            sessions.append(session)

            let participant = Participant(
                type: .agentSession(sessionId: session.id),
                displayName: agent.name
            )
            participant.conversation = convo
            convo.participants.append(participant)
            ctx.insert(session)
            ctx.insert(participant)
        }

        convo.sessions = sessions
        ctx.insert(convo)
        ctx.insert(user)

        return (convo, sessions)
    }
}
