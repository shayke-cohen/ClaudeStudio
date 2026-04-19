import XCTest
import SwiftData
@testable import Odyssey

@MainActor
final class GroupWorkflowTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Agent.self, Session.self, Conversation.self, ConversationMessage.self,
            MessageAttachment.self, Participant.self, Skill.self, MCPServer.self,
            PermissionSet.self, SharedWorkspace.self, BlackboardEntry.self, Peer.self,
            AgentGroup.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    // MARK: - WorkflowStep

    func testWorkflowStepCodable() throws {
        let step = WorkflowStep(
            agentId: UUID(),
            instruction: "Do something",
            condition: "if approved",
            autoAdvance: true,
            stepLabel: "Step 1",
            artifactGate: WorkflowArtifactGate(
                profile: "architecture-decision",
                approvalRequired: true,
                publishRepoDoc: true,
                blockedDownstreamAgentNames: ["Coder"]
            )
        )

        let data = try JSONEncoder().encode(step)
        let decoded = try JSONDecoder().decode(WorkflowStep.self, from: data)

        XCTAssertEqual(decoded.instruction, "Do something")
        XCTAssertEqual(decoded.condition, "if approved")
        XCTAssertTrue(decoded.autoAdvance)
        XCTAssertEqual(decoded.stepLabel, "Step 1")
        XCTAssertEqual(decoded.agentId, step.agentId)
        XCTAssertEqual(decoded.artifactGate?.profile, "architecture-decision")
        XCTAssertEqual(decoded.artifactGate?.blockedDownstreamAgentNames, ["Coder"])
    }

    func testWorkflowStepArrayCodable() throws {
        let steps = [
            WorkflowStep(agentId: UUID(), instruction: "First", autoAdvance: true),
            WorkflowStep(agentId: UUID(), instruction: "Second", autoAdvance: false),
        ]

        let data = try JSONEncoder().encode(steps)
        let decoded = try JSONDecoder().decode([WorkflowStep].self, from: data)

        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0].instruction, "First")
        XCTAssertEqual(decoded[1].instruction, "Second")
    }

    // MARK: - GroupWorkflowEngine

    func testInteractiveProductManagerStepPausesBeforeCoderEvenIfAutoAdvanceIsTrue() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let productManager = Agent(name: "Product Manager")
        let coder = Agent(name: "Coder")
        ctx.insert(productManager)
        ctx.insert(coder)

        let pmSession = Session(agent: productManager, workingDirectory: "/tmp")
        let coderSession = Session(agent: coder, workingDirectory: "/tmp")
        ctx.insert(pmSession)
        ctx.insert(coderSession)

        let conversation = Conversation(topic: "New feature")
        conversation.executionMode = .interactive
        conversation.sessions = [pmSession, coderSession]
        pmSession.conversations = [conversation]
        coderSession.conversations = [conversation]

        let group = AgentGroup(name: "PM + Dev")
        group.agentIds = [productManager.id, coder.id]
        group.workflow = [
            WorkflowStep(agentId: productManager.id, instruction: "Prepare the product spec.", autoAdvance: true, stepLabel: "Product Spec"),
            WorkflowStep(agentId: coder.id, instruction: "Implement the approved spec.", autoAdvance: true, stepLabel: "Implement"),
        ]
        ctx.insert(conversation)
        ctx.insert(group)
        try ctx.save()

        let engine = GroupWorkflowEngine(
            conversation: conversation,
            group: group,
            workflow: try XCTUnwrap(group.workflow),
            appState: AppState(),
            modelContext: ctx
        )

        var visitedAgents: [String] = []
        await engine.execute(userMessage: "Build onboarding", manager: SidecarManager()) { session, _, _ in
            visitedAgents.append(session.agent?.name ?? "Unknown")
            return "PRD and wireframes are ready for approval."
        }

        XCTAssertEqual(visitedAgents, ["Product Manager"])
        XCTAssertEqual(conversation.workflowCurrentStep, 1)
        XCTAssertEqual(conversation.workflowCompletedSteps ?? [], [0])
        XCTAssertEqual(conversation.messages?.last?.type, .system)
        XCTAssertTrue(conversation.messages?.last?.text.contains("Review the PRD and wireframes") == true)
    }

    func testInteractiveDesignerStepPausesBeforeCoderWhenArtifactGateMetadataIsPresent() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let designer = Agent(name: "Designer")
        let coder = Agent(name: "Coder")
        ctx.insert(designer)
        ctx.insert(coder)

        let designerSession = Session(agent: designer, workingDirectory: "/tmp")
        let coderSession = Session(agent: coder, workingDirectory: "/tmp")
        ctx.insert(designerSession)
        ctx.insert(coderSession)

        let conversation = Conversation(topic: "Improve onboarding UI")
        conversation.executionMode = .interactive
        conversation.sessions = [designerSession, coderSession]
        designerSession.conversations = [conversation]
        coderSession.conversations = [conversation]

        let group = AgentGroup(name: "Design Review")
        group.agentIds = [designer.id, coder.id]
        group.workflow = [
            WorkflowStep(
                agentId: designer.id,
                instruction: "Prepare UX spec",
                autoAdvance: true,
                stepLabel: "UX Review",
                artifactGate: WorkflowArtifactGate(
                    profile: "ux-spec",
                    approvalRequired: true,
                    publishRepoDoc: true,
                    blockedDownstreamAgentNames: ["Coder"]
                )
            ),
            WorkflowStep(agentId: coder.id, instruction: "Assess feasibility", autoAdvance: true, stepLabel: "Feasibility"),
        ]
        ctx.insert(conversation)
        ctx.insert(group)
        try ctx.save()

        let engine = GroupWorkflowEngine(
            conversation: conversation,
            group: group,
            workflow: try XCTUnwrap(group.workflow),
            appState: AppState(),
            modelContext: ctx
        )

        var visitedAgents: [String] = []
        await engine.execute(userMessage: "Modernize onboarding", manager: SidecarManager()) { session, _, _ in
            visitedAgents.append(session.agent?.name ?? "Unknown")
            return "Design spec and wireframes are ready."
        }

        XCTAssertEqual(visitedAgents, ["Designer"])
        XCTAssertEqual(conversation.workflowCurrentStep, 1)
        XCTAssertTrue(conversation.messages?.last?.text.contains("design spec, flows, and wireframes") == true)
    }

    func testInteractiveTesterLegacyInferencePausesBeforeDevOps() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let tester = Agent(name: "Tester")
        let devOps = Agent(name: "DevOps")
        ctx.insert(tester)
        ctx.insert(devOps)

        let testerSession = Session(agent: tester, workingDirectory: "/tmp")
        let devOpsSession = Session(agent: devOps, workingDirectory: "/tmp")
        ctx.insert(testerSession)
        ctx.insert(devOpsSession)

        let conversation = Conversation(topic: "Deploy release")
        conversation.executionMode = .interactive
        conversation.sessions = [testerSession, devOpsSession]
        testerSession.conversations = [conversation]
        devOpsSession.conversations = [conversation]

        let group = AgentGroup(name: "Full Stack Team")
        group.agentIds = [tester.id, devOps.id]
        group.workflow = [
            WorkflowStep(agentId: tester.id, instruction: "Prepare signoff", autoAdvance: true, stepLabel: "Test"),
            WorkflowStep(agentId: devOps.id, instruction: "Deploy", autoAdvance: true, stepLabel: "Deploy"),
        ]
        ctx.insert(conversation)
        ctx.insert(group)
        try ctx.save()

        let engine = GroupWorkflowEngine(
            conversation: conversation,
            group: group,
            workflow: try XCTUnwrap(group.workflow),
            appState: AppState(),
            modelContext: ctx
        )

        var visitedAgents: [String] = []
        await engine.execute(userMessage: "Ship release", manager: SidecarManager()) { session, _, _ in
            visitedAgents.append(session.agent?.name ?? "Unknown")
            return "Validation complete."
        }

        XCTAssertEqual(visitedAgents, ["Tester"])
        XCTAssertEqual(conversation.workflowCurrentStep, 1)
        XCTAssertTrue(conversation.messages?.last?.text.contains("test strategy or signoff summary") == true)
    }

    func testAutonomousProductManagerStepStillAutoAdvancesIntoCoder() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let productManager = Agent(name: "Product Manager")
        let coder = Agent(name: "Coder")
        ctx.insert(productManager)
        ctx.insert(coder)

        let pmSession = Session(agent: productManager, workingDirectory: "/tmp")
        let coderSession = Session(agent: coder, workingDirectory: "/tmp")
        ctx.insert(pmSession)
        ctx.insert(coderSession)

        let conversation = Conversation(topic: "Autonomous build")
        conversation.executionMode = .autonomous
        conversation.sessions = [pmSession, coderSession]
        pmSession.conversations = [conversation]
        coderSession.conversations = [conversation]

        let group = AgentGroup(name: "PM + Dev")
        group.agentIds = [productManager.id, coder.id]
        group.workflow = [
            WorkflowStep(agentId: productManager.id, instruction: "Prepare the product spec.", autoAdvance: true, stepLabel: "Product Spec"),
            WorkflowStep(agentId: coder.id, instruction: "Implement the approved spec.", autoAdvance: true, stepLabel: "Implement"),
        ]
        ctx.insert(conversation)
        ctx.insert(group)
        try ctx.save()

        let engine = GroupWorkflowEngine(
            conversation: conversation,
            group: group,
            workflow: try XCTUnwrap(group.workflow),
            appState: AppState(),
            modelContext: ctx
        )

        var visitedAgents: [String] = []
        await engine.execute(userMessage: "Build onboarding", manager: SidecarManager()) { session, _, _ in
            visitedAgents.append(session.agent?.name ?? "Unknown")
            return session.agent?.name == "Product Manager" ? "PRD approved." : "Implementation complete."
        }

        XCTAssertEqual(visitedAgents, ["Product Manager", "Coder"])
        XCTAssertNil(conversation.workflowCurrentStep)
        XCTAssertEqual(Set(conversation.workflowCompletedSteps ?? []), Set([0, 1]))
        XCTAssertEqual(conversation.messages?.last?.text, "Workflow complete (2 steps).")
    }

    // MARK: - GroupPromptBuilder.buildWorkflowStepPrompt

    func testWorkflowStepPromptBasic() {
        let step = WorkflowStep(agentId: UUID(), instruction: "Review the code", autoAdvance: true, stepLabel: "Code Review")

        let prompt = GroupPromptBuilder.buildWorkflowStepPrompt(
            step: step,
            stepIndex: 1,
            totalSteps: 4,
            userMessage: "Build a login page",
            previousStepOutput: nil
        )

        XCTAssertTrue(prompt.contains("Step 2/4"))
        XCTAssertTrue(prompt.contains("Code Review"))
        XCTAssertTrue(prompt.contains("Review the code"))
        XCTAssertTrue(prompt.contains("Build a login page"))
        XCTAssertFalse(prompt.contains("Previous step output"))
    }

    func testWorkflowStepPromptWithPreviousOutput() {
        let step = WorkflowStep(agentId: UUID(), instruction: "Test the implementation", autoAdvance: true, stepLabel: "Testing")

        let prompt = GroupPromptBuilder.buildWorkflowStepPrompt(
            step: step,
            stepIndex: 2,
            totalSteps: 3,
            userMessage: "Build feature X",
            previousStepOutput: "I implemented feature X with 3 files changed."
        )

        XCTAssertTrue(prompt.contains("Step 3/3"))
        XCTAssertTrue(prompt.contains("Previous step output"))
        XCTAssertTrue(prompt.contains("I implemented feature X"))
    }

    func testWorkflowStepPromptWithGroupInstruction() {
        let step = WorkflowStep(agentId: UUID(), instruction: "Plan the work", autoAdvance: true)

        let prompt = GroupPromptBuilder.buildWorkflowStepPrompt(
            step: step,
            stepIndex: 0,
            totalSteps: 2,
            userMessage: "Refactor auth",
            previousStepOutput: nil,
            groupInstruction: "This group focuses on security."
        )

        XCTAssertTrue(prompt.contains("[Group Context]"))
        XCTAssertTrue(prompt.contains("security"))
    }

    func testWorkflowStepPromptWithRole() {
        let step = WorkflowStep(agentId: UUID(), instruction: "Coordinate the team", autoAdvance: true)

        let prompt = GroupPromptBuilder.buildWorkflowStepPrompt(
            step: step,
            stepIndex: 0,
            totalSteps: 1,
            userMessage: "Ship v2",
            previousStepOutput: nil,
            role: .coordinator
        )

        XCTAssertTrue(prompt.contains("[Your Role: Coordinator]"))
        XCTAssertTrue(prompt.contains("coordinator"))
    }

    // MARK: - GroupPromptBuilder.buildCoordinatorPrompt

    func testCoordinatorPromptBasic() {
        let prompt = GroupPromptBuilder.buildCoordinatorPrompt(
            mission: "Build a REST API for user management",
            teamAgents: [
                (name: "Coder", description: "Writes code"),
                (name: "Tester", description: "Validates quality"),
            ],
            groupInstruction: nil
        )

        XCTAssertTrue(prompt.contains("Autonomous Mission"))
        XCTAssertTrue(prompt.contains("Build a REST API"))
        XCTAssertTrue(prompt.contains("Coder: Writes code"))
        XCTAssertTrue(prompt.contains("Tester: Validates quality"))
        XCTAssertTrue(prompt.contains("peer_delegate_task"))
        XCTAssertTrue(prompt.contains("MISSION COMPLETE"))
    }

    func testCoordinatorPromptWithGroupInstruction() {
        let prompt = GroupPromptBuilder.buildCoordinatorPrompt(
            mission: "Deploy to prod",
            teamAgents: [(name: "DevOps", description: "Handles infra")],
            groupInstruction: "Follow security best practices."
        )

        XCTAssertTrue(prompt.contains("[Group Context]"))
        XCTAssertTrue(prompt.contains("security best practices"))
    }

    // MARK: - GroupPromptBuilder role injection

    func testBuildMessageTextWithRole() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let a1 = Agent(name: "A1")
        let a2 = Agent(name: "A2")
        ctx.insert(a1)
        ctx.insert(a2)

        let s1 = Session(agent: a1, workingDirectory: "/tmp")
        let s2 = Session(agent: a2, workingDirectory: "/tmp")
        ctx.insert(s1)
        ctx.insert(s2)

        let convo = Conversation()
        s1.conversations = [convo]
        s2.conversations = [convo]
        convo.sessions = [s1, s2]

        let user = Participant(type: .user, displayName: "You")
        user.conversation = convo
        convo.participants = (convo.participants ?? []) + [user]

        let p1 = Participant(type: .agentSession(sessionId: s1.id), displayName: a1.name)
        p1.conversation = convo
        convo.participants = (convo.participants ?? []) + [p1]

        let p2 = Participant(type: .agentSession(sessionId: s2.id), displayName: a2.name)
        p2.conversation = convo
        convo.participants = (convo.participants ?? []) + [p2]

        let msg = ConversationMessage(senderParticipantId: user.id, text: "Hello", type: .chat, conversation: convo)
        convo.messages = (convo.messages ?? []) + [msg]
        ctx.insert(convo)
        ctx.insert(user)
        ctx.insert(p1)
        ctx.insert(p2)
        ctx.insert(msg)

        let text = GroupPromptBuilder.buildMessageText(
            conversation: convo,
            targetSession: s1,
            latestUserMessageText: "Hello",
            participants: convo.participants ?? [],
            role: .coordinator
        )

        XCTAssertTrue(text.contains("[Your Role: Coordinator]"))
        XCTAssertTrue(text.contains("coordinator"))
    }

    func testBuildMessageTextParticipantRoleNoBlock() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let a1 = Agent(name: "A1")
        let a2 = Agent(name: "A2")
        ctx.insert(a1)
        ctx.insert(a2)

        let s1 = Session(agent: a1, workingDirectory: "/tmp")
        let s2 = Session(agent: a2, workingDirectory: "/tmp")
        ctx.insert(s1)
        ctx.insert(s2)

        let convo = Conversation()
        s1.conversations = [convo]
        s2.conversations = [convo]
        convo.sessions = [s1, s2]

        let user = Participant(type: .user, displayName: "You")
        user.conversation = convo
        convo.participants = (convo.participants ?? []) + [user]
        ctx.insert(convo)
        ctx.insert(user)

        let text = GroupPromptBuilder.buildMessageText(
            conversation: convo,
            targetSession: s1,
            latestUserMessageText: "Hello",
            participants: convo.participants ?? [],
            role: .participant
        )

        XCTAssertFalse(text.contains("[Your Role:"))
    }

    // MARK: - Peer notify with role

    func testPeerNotifyObserverRole() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let agent = Agent(name: "Watcher")
        ctx.insert(agent)
        let session = Session(agent: agent, workingDirectory: "/tmp")
        ctx.insert(session)

        let prompt = GroupPromptBuilder.buildPeerNotifyPrompt(
            senderLabel: "Coder",
            peerMessageText: "I finished the implementation.",
            recipientSession: session,
            role: .observer
        )

        XCTAssertTrue(prompt.contains("observer"))
        XCTAssertTrue(prompt.contains("directly addressed"))
    }

    func testPeerNotifyScribeRole() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let agent = Agent(name: "Scribe")
        ctx.insert(agent)
        let session = Session(agent: agent, workingDirectory: "/tmp")
        ctx.insert(session)

        let prompt = GroupPromptBuilder.buildPeerNotifyPrompt(
            senderLabel: "PM",
            peerMessageText: "We decided to use approach B.",
            recipientSession: session,
            role: .scribe
        )

        XCTAssertTrue(prompt.contains("scribe"))
        XCTAssertTrue(prompt.contains("blackboard"))
    }
}
