import SwiftData
import XCTest
@testable import ClaudeStudio

@MainActor
final class ScheduleRunCoordinatorTests: XCTestCase {
    private final class CommandRecorder {
        var commands: [SidecarCommand] = []
    }

    private var container: ModelContainer!
    private var context: ModelContext!
    private var appState: AppState!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: ScheduledMission.self,
            ScheduledMissionRun.self,
            Agent.self,
            Session.self,
            Conversation.self,
            ConversationMessage.self,
            MessageAttachment.self,
            Participant.self,
            AgentGroup.self,
            Skill.self,
            MCPServer.self,
            PermissionSet.self,
            configurations: config
        )
        context = container.mainContext
        appState = AppState()
        appState.modelContext = context
    }

    override func tearDown() async throws {
        appState = nil
        context = nil
        container = nil
    }

    private func makeDependencies(
        recorder: CommandRecorder,
        ensureConnected: @escaping @MainActor (AppState) async -> Bool = { _ in true },
        completion: @escaping @MainActor (AppState, String) async -> String? = { _, _ in nil },
        onMessage: @escaping @MainActor (AppState, String, String) -> Void = { appState, sessionId, _ in
            appState.streamingText[sessionId] = "Scheduled response"
            appState.lastSessionEvent[sessionId] = .result
        }
    ) -> ScheduleRunCoordinator.Dependencies {
        .init(
            ensureSidecarConnected: ensureConnected,
            sendCommand: { appState, command in
                recorder.commands.append(command)
                if case .sessionMessage(let sessionId, let text, _, _) = command {
                    onMessage(appState, sessionId, text)
                }
            },
            waitForSessionCompletion: completion,
            ensureWorktree: { _, projectDirectory, _ in projectDirectory }
        )
    }

    private func makeAgent(named name: String = "Coder") -> Agent {
        let agent = Agent(name: name)
        context.insert(agent)
        return agent
    }

    private func makeRun(for schedule: ScheduledMission, scheduledFor: Date = Date(timeIntervalSince1970: 3600)) -> ScheduledMissionRun {
        let run = ScheduledMissionRun(
            scheduleId: schedule.id,
            occurrenceKey: ScheduledMissionRun.occurrenceKey(scheduleId: schedule.id, scheduledFor: scheduledFor),
            status: .running,
            triggerSource: .timer,
            scheduledFor: scheduledFor
        )
        context.insert(run)
        return run
    }

    private func makeConversation(for agent: Agent, topic: String = "Existing conversation") -> Conversation {
        let session = Session(agent: agent, workingDirectory: "/tmp/repo")
        let conversation = Conversation(topic: topic)
        let userParticipant = Participant(type: .user, displayName: "You")
        let agentParticipant = Participant(type: .agentSession(sessionId: session.id), displayName: agent.name)
        userParticipant.conversation = conversation
        agentParticipant.conversation = conversation
        conversation.participants = [userParticipant, agentParticipant]
        conversation.sessions = [session]
        session.conversations = [conversation]
        context.insert(session)
        context.insert(conversation)
        try? context.save()
        return conversation
    }

    func testExecuteFreshAgentScheduleCreatesConversationAndSucceeds() async throws {
        let agent = makeAgent()
        let schedule = ScheduledMission(
            name: "Hourly bug triage",
            targetKind: .agent,
            projectDirectory: "/tmp/repo",
            promptTemplate: "Inspect {{projectDirectory}} at {{now}}"
        )
        schedule.targetAgentId = agent.id
        context.insert(schedule)
        let run = makeRun(for: schedule)
        try context.save()

        let recorder = CommandRecorder()
        let coordinator = ScheduleRunCoordinator(
            appState: appState,
            modelContext: context,
            dependencies: makeDependencies(recorder: recorder)
        )

        await coordinator.execute(schedule: schedule, run: run)

        XCTAssertEqual(run.status, .succeeded)
        XCTAssertNotNil(run.conversationId)
        XCTAssertEqual(recorder.commands.count, 2)
        guard let conversationId = run.conversationId else {
            return XCTFail("Expected linked conversation")
        }
        let conversation = try XCTUnwrap(
            context.fetch(FetchDescriptor<Conversation>(predicate: #Predicate { $0.id == conversationId })).first
        )
        XCTAssertEqual(conversation.sessions.count, 1)
        XCTAssertEqual(conversation.messages.filter { $0.type == .chat }.count, 2)
        XCTAssertEqual(conversation.messages.last?.text, "Scheduled response")
        XCTAssertEqual(run.summary, "Scheduled response")
    }

    func testExecuteFreshGroupScheduleCreatesGroupConversationAndSendsToEachSession() async throws {
        let agentA = makeAgent(named: "Coder")
        let agentB = makeAgent(named: "Reviewer")
        let group = AgentGroup(name: "Full Stack", agentIds: [agentA.id, agentB.id])
        context.insert(group)

        let schedule = ScheduledMission(
            name: "Morning feature sweep",
            targetKind: .group,
            projectDirectory: "/tmp/group-repo",
            promptTemplate: "Review new work in {{projectDirectory}}"
        )
        schedule.targetGroupId = group.id
        context.insert(schedule)
        let run = makeRun(for: schedule)
        try context.save()

        let recorder = CommandRecorder()
        let coordinator = ScheduleRunCoordinator(
            appState: appState,
            modelContext: context,
            dependencies: makeDependencies(
                recorder: recorder,
                onMessage: { appState, sessionId, _ in
                    appState.streamingText[sessionId] = "Reply for \(sessionId)"
                    appState.lastSessionEvent[sessionId] = .result
                }
            )
        )

        await coordinator.execute(schedule: schedule, run: run)

        XCTAssertEqual(run.status, .succeeded)
        guard let conversationId = run.conversationId else {
            return XCTFail("Expected group conversation")
        }
        let conversation = try XCTUnwrap(
            context.fetch(FetchDescriptor<Conversation>(predicate: #Predicate { $0.id == conversationId })).first
        )
        XCTAssertEqual(conversation.sourceGroupId, group.id)
        XCTAssertTrue(conversation.selectiveRepliesEnabled)
        XCTAssertEqual(conversation.sessions.count, 2)
        let chatMessages = conversation.messages.filter { $0.type == .chat }
        XCTAssertEqual(chatMessages.count, 3)
        XCTAssertEqual(recorder.commands.count, 4)
    }

    func testExecuteFreshGroupScheduleSuppressesNoReplySentinel() async throws {
        let agentA = makeAgent(named: "Coder")
        let agentB = makeAgent(named: "Reviewer")
        let group = AgentGroup(name: "Full Stack", agentIds: [agentA.id, agentB.id])
        context.insert(group)

        let schedule = ScheduledMission(
            name: "Morning feature sweep",
            targetKind: .group,
            projectDirectory: "/tmp/group-repo",
            promptTemplate: "Review new work in {{projectDirectory}}"
        )
        schedule.targetGroupId = group.id
        context.insert(schedule)
        let run = makeRun(for: schedule)
        try context.save()

        let recorder = CommandRecorder()
        let coordinator = ScheduleRunCoordinator(
            appState: appState,
            modelContext: context,
            dependencies: makeDependencies(
                recorder: recorder,
                onMessage: { appState, sessionId, text in
                    if text.contains("You are @Reviewer.") {
                        appState.streamingText[sessionId] = GroupPromptBuilder.noReplySentinel
                    } else {
                        appState.streamingText[sessionId] = "Coder reply"
                    }
                    appState.lastSessionEvent[sessionId] = .result
                }
            )
        )

        await coordinator.execute(schedule: schedule, run: run)

        let conversationId = try XCTUnwrap(run.conversationId)
        let conversation = try XCTUnwrap(
            context.fetch(FetchDescriptor<Conversation>(predicate: #Predicate { $0.id == conversationId })).first
        )
        let chatMessages = conversation.messages.filter { $0.type == .chat }
        XCTAssertEqual(chatMessages.count, 2)
        XCTAssertEqual(chatMessages.last?.text, "Coder reply")
    }

    func testExecuteReuseConversationAppendsBoundaryAndPrompt() async throws {
        let agent = makeAgent()
        let conversation = makeConversation(for: agent)
        let sessionId = try XCTUnwrap(conversation.sessions.first?.id.uuidString)
        appState.createdSessions.insert(sessionId)

        let schedule = ScheduledMission(
            name: "Security review",
            targetKind: .conversation,
            projectDirectory: "/tmp/repo",
            promptTemplate: "Continue from {{lastRunAt}}"
        )
        schedule.runMode = .reuseConversation
        schedule.targetConversationId = conversation.id
        context.insert(schedule)
        let run = makeRun(for: schedule)
        try context.save()

        let recorder = CommandRecorder()
        let coordinator = ScheduleRunCoordinator(
            appState: appState,
            modelContext: context,
            dependencies: makeDependencies(recorder: recorder)
        )

        await coordinator.execute(schedule: schedule, run: run)

        XCTAssertEqual(run.status, .succeeded)
        XCTAssertEqual(recorder.commands.count, 1)
        XCTAssertTrue(conversation.messages.contains { $0.type == .system && $0.text.contains("Scheduled run started") })
        XCTAssertEqual(conversation.messages.filter { $0.type == .chat }.count, 2)
    }

    func testExecuteFailsWhenTargetCannotBeResolved() async throws {
        let schedule = ScheduledMission(
            name: "Missing agent",
            targetKind: .agent,
            projectDirectory: "/tmp/repo",
            promptTemplate: "Prompt"
        )
        schedule.targetAgentId = UUID()
        context.insert(schedule)
        let run = makeRun(for: schedule)
        try context.save()

        let recorder = CommandRecorder()
        let coordinator = ScheduleRunCoordinator(
            appState: appState,
            modelContext: context,
            dependencies: makeDependencies(recorder: recorder)
        )

        await coordinator.execute(schedule: schedule, run: run)

        XCTAssertEqual(run.status, .failed)
        XCTAssertEqual(run.errorMessage, "Unable to resolve schedule target")
        XCTAssertTrue(recorder.commands.isEmpty)
    }

    func testExecuteFailsWhenSidecarCannotConnect() async throws {
        let agent = makeAgent()
        let schedule = ScheduledMission(
            name: "Connection failure",
            targetKind: .agent,
            projectDirectory: "/tmp/repo",
            promptTemplate: "Prompt"
        )
        schedule.targetAgentId = agent.id
        context.insert(schedule)
        let run = makeRun(for: schedule)
        try context.save()

        let recorder = CommandRecorder()
        let coordinator = ScheduleRunCoordinator(
            appState: appState,
            modelContext: context,
            dependencies: makeDependencies(
                recorder: recorder,
                ensureConnected: { _ in false }
            )
        )

        await coordinator.execute(schedule: schedule, run: run)

        XCTAssertEqual(run.status, .failed)
        XCTAssertEqual(run.errorMessage, "Sidecar not connected")
        XCTAssertTrue(recorder.commands.isEmpty)
    }
}
