import SwiftData
import XCTest
@testable import Odyssey

@MainActor
final class AppStateRecoveryTests: XCTestCase {

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
        context = nil
        container = nil
    }

    private func makeAgent(name: String) -> Agent {
        let agent = Agent(name: name, systemPrompt: "You are \(name).", model: "sonnet")
        context.insert(agent)
        return agent
    }

    @discardableResult
    private func makeSession(
        agent: Agent?,
        status: SessionStatus,
        claudeSessionId: String?,
        mission: String? = nil,
        topic: String = "Recovery Test"
    ) -> Session {
        let session = Session(agent: agent, mission: mission, workingDirectory: "/tmp/recovery")
        session.status = status
        session.claudeSessionId = claudeSessionId

        let conversation = Conversation(topic: topic)
        session.conversations = [conversation]
        conversation.sessions.append(session)

        context.insert(session)
        context.insert(conversation)
        return session
    }

    private func bulkResumeEntries(from commands: [SidecarCommand]) -> [SessionBulkResumeEntry] {
        for command in commands {
            if case .sessionBulkResume(let sessions) = command {
                return sessions
            }
        }
        return []
    }

    func testRecoverSessions_reconnectsOnlyRecoverableSessions() async throws {
        let activeAgent = makeAgent(name: "ActiveAgent")
        activeAgent.provider = "codex"
        let pausedAgent = makeAgent(name: "PausedAgent")
        let noClaudeAgent = makeAgent(name: "NoClaudeAgent")
        let completedAgent = makeAgent(name: "CompletedAgent")
        let failedAgent = makeAgent(name: "FailedAgent")

        let activeSession = makeSession(agent: activeAgent, status: .active, claudeSessionId: "claude-active", mission: "Keep going")
        let pausedSession = makeSession(agent: pausedAgent, status: .paused, claudeSessionId: "claude-paused")
        _ = makeSession(agent: noClaudeAgent, status: .active, claudeSessionId: nil)
        let completedSession = makeSession(agent: completedAgent, status: .completed, claudeSessionId: "claude-completed")
        let failedSession = makeSession(agent: failedAgent, status: .failed, claudeSessionId: "claude-failed")
        try context.save()

        var commands: [SidecarCommand] = []
        appState.commandCaptureForTesting = { commands.append($0) }
        appState.sessionActivity[activeSession.id.uuidString] = .streaming
        appState.sessionActivity[pausedSession.id.uuidString] = .waitingForResult

        await appState.recoverSessionsForTesting()

        let entries = bulkResumeEntries(from: commands)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(Set(entries.map(\.sessionId)), Set([activeSession.id.uuidString, pausedSession.id.uuidString]))
        XCTAssertEqual(Set(entries.map(\.claudeSessionId)), Set(["claude-active", "claude-paused"]))
        XCTAssertTrue(entries.allSatisfy { !$0.agentConfig.name.isEmpty })
        XCTAssertEqual(
            entries.first(where: { $0.sessionId == activeSession.id.uuidString })?.agentConfig.provider,
            "codex"
        )
        XCTAssertEqual(
            entries.first(where: { $0.sessionId == activeSession.id.uuidString })?.agentConfig.model,
            "gpt-5.4"
        )

        XCTAssertEqual(pausedSession.status, .paused)
        XCTAssertEqual(activeSession.status, .interrupted)
        XCTAssertEqual(completedSession.status, .completed)
        XCTAssertEqual(failedSession.status, .failed)
        XCTAssertEqual(appState.sessionActivity[activeSession.id.uuidString], .idle)
        XCTAssertEqual(appState.sessionActivity[pausedSession.id.uuidString], .idle)
        XCTAssertTrue(appState.createdSessions.contains(activeSession.id.uuidString))
        XCTAssertTrue(appState.createdSessions.contains(pausedSession.id.uuidString))

        XCTAssertTrue(commands.contains {
            if case .agentRegister(let agents) = $0 {
                return !agents.isEmpty
            }
            return false
        })
    }

    func testMarkSessionsStale_marksOnlyActiveSessionsInterrupted() throws {
        let agent = makeAgent(name: "StatusAgent")
        let active = makeSession(agent: agent, status: .active, claudeSessionId: "claude-active")
        let paused = makeSession(agent: agent, status: .paused, claudeSessionId: "claude-paused")
        let completed = makeSession(agent: agent, status: .completed, claudeSessionId: "claude-completed")
        let failed = makeSession(agent: agent, status: .failed, claudeSessionId: "claude-failed")
        try context.save()
        appState.sessionActivity[active.id.uuidString] = .streaming
        appState.sessionActivity[paused.id.uuidString] = .waitingForResult

        appState.markSessionsStaleForTesting()

        XCTAssertEqual(active.status, .interrupted)
        XCTAssertEqual(paused.status, .paused)
        XCTAssertEqual(completed.status, .completed)
        XCTAssertEqual(failed.status, .failed)
        XCTAssertEqual(appState.sessionActivity[active.id.uuidString], .idle)
        XCTAssertEqual(appState.sessionActivity[paused.id.uuidString], .waitingForResult)
    }

    func testRestoreSessionContextAwait_sendsSessionResumeCommand() async throws {
        var commands: [SidecarCommand] = []
        appState.commandCaptureForTesting = { commands.append($0) }
        appState.commandSendOverrideForTesting = { _ in }

        do {
            try await self.appState.restoreSessionContextAwait(
                sessionId: "session-789",
                claudeSessionId: "claude-999"
            )
        } catch {
            XCTFail("Threw unexpected error: \(error)")
        }

        XCTAssertEqual(commands.count, 1)
        guard case .sessionResume(let sessionId, let claudeSessionId) = commands[0] else {
            return XCTFail("Expected session.resume command")
        }
        XCTAssertEqual(sessionId, "session-789")
        XCTAssertEqual(claudeSessionId, "claude-999")
    }

    func testUpdateExecutionMode_setsAutonomousStateAndSendsModeUpdates() async throws {
        let agent = makeAgent(name: "ModeAgent")
        agent.instancePolicy = .pool
        agent.instancePolicyPoolMax = 3
        let session = makeSession(agent: agent, status: .completed, claudeSessionId: "claude-mode")
        guard let conversation = session.conversations.first else {
            return XCTFail("Expected conversation")
        }

        var commands: [SidecarCommand] = []
        appState.commandCaptureForTesting = { commands.append($0) }
        appState.commandSendOverrideForTesting = { _ in }

        await appState.updateExecutionMode(.autonomous, for: conversation)

        XCTAssertEqual(conversation.executionMode, .autonomous)
        XCTAssertTrue(conversation.isAutonomous)
        XCTAssertEqual(session.mode, .autonomous)

        guard let lastCommand = commands.last,
              case .sessionUpdateMode(let sessionId, let interactive, let instancePolicy, let poolMax) = lastCommand else {
            return XCTFail("Expected session.updateMode command")
        }
        XCTAssertEqual(sessionId, session.id.uuidString)
        XCTAssertFalse(interactive)
        XCTAssertEqual(instancePolicy, "spawn")
        XCTAssertNil(poolMax)
    }

    func testUpdateExecutionMode_restoresInteractiveAgentPolicy() async throws {
        let agent = makeAgent(name: "InteractiveAgent")
        agent.instancePolicy = .pool
        agent.instancePolicyPoolMax = 2
        let session = makeSession(agent: agent, status: .completed, claudeSessionId: "claude-interactive")
        session.mode = .autonomous
        guard let conversation = session.conversations.first else {
            return XCTFail("Expected conversation")
        }
        conversation.executionMode = .autonomous

        var commands: [SidecarCommand] = []
        appState.commandCaptureForTesting = { commands.append($0) }
        appState.commandSendOverrideForTesting = { _ in }

        await appState.updateExecutionMode(.interactive, for: conversation)

        XCTAssertEqual(conversation.executionMode, .interactive)
        XCTAssertFalse(conversation.isAutonomous)
        XCTAssertEqual(session.mode, .interactive)

        guard let lastCommand = commands.last,
              case .sessionUpdateMode(_, let interactive, let instancePolicy, let poolMax) = lastCommand else {
            return XCTFail("Expected session.updateMode command")
        }
        XCTAssertTrue(interactive)
        XCTAssertEqual(instancePolicy, "pool")
        XCTAssertEqual(poolMax, 2)
    }

    func testSessionResultEvent_persistsCompletedStatus() throws {
        let agent = makeAgent(name: "ResultAgent")
        let session = makeSession(agent: agent, status: .active, claudeSessionId: "claude-result")
        try context.save()

        appState.handleEventForTesting(.sessionResult(
            sessionId: session.id.uuidString,
            result: "done",
            cost: 0.01,
            tokenCount: 42,
            toolCallCount: 2
        ))

        XCTAssertEqual(session.status, .completed)
        XCTAssertEqual(session.tokenCount, 42)
        XCTAssertEqual(session.totalCost, 0.01)
        XCTAssertEqual(session.toolCallCount, 2)
    }

    func testSessionErrorEvent_persistsFailedStatus() throws {
        let agent = makeAgent(name: "ErrorAgent")
        let session = makeSession(agent: agent, status: .active, claudeSessionId: "claude-error")
        try context.save()

        appState.handleEventForTesting(.sessionError(
            sessionId: session.id.uuidString,
            error: "boom"
        ))

        XCTAssertEqual(session.status, .failed)
    }
}
