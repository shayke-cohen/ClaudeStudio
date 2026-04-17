import SwiftUI
import SwiftData
import Combine
import OSLog
import OdysseyCore

private let logger = Logger(subsystem: "com.odyssey.app", category: "AppState")

@MainActor
final class AppState: ObservableObject {
    enum SidecarCommandError: Error {
        case unavailable
    }

    enum SidecarStatus: Equatable {
        case disconnected
        case connecting
        case connected
        case error(String)
    }

    @Published var sidecarStatus: SidecarStatus = .disconnected
    @Published var activeSessions: [UUID: SessionInfo] = [:]

    /// Conversation IDs currently visible in any window — used for notification/unread gating.
    @Published var visibleConversationIds: Set<UUID> = []
    @Published var streamingText: [String: String] = [:]
    @Published var thinkingText: [String: String] = [:]
    @Published var streamingImages: [String: [(data: String, mediaType: String)]] = [:]
    @Published var streamingFileCards: [String: [(path: String, type: String, name: String)]] = [:]
    @Published var lastSessionEvent: [String: SessionEventKind] = [:]
    @Published private(set) var allocatedWsPort: Int = 0
    @Published private(set) var allocatedHttpPort: Int = 0

    @Published var toolCalls: [String: [ToolCallInfo]] = [:]
    @Published var sessionActivity: [String: SessionActivityState] = [:]
    @Published var commsEvents: [CommsEvent] = []
    @Published var fileTreeRefreshTrigger: Int = 0
    @Published var generatedAgentSpec: GeneratedAgentSpec?
    @Published var isGeneratingAgent: Bool = false
    @Published var generateAgentError: String?
    @Published var generatedSkillSpec: GeneratedSkillSpec?
    @Published var isGeneratingSkill: Bool = false
    @Published var generateSkillError: String?
    @Published var generatedTemplateSpec: GeneratedTemplateSpec?
    @Published var isGeneratingTemplate: Bool = false
    @Published var generateTemplateError: String?
    /// Set to true to open the "Add to Residents" sheet. AppXray tests use setState to set this.
    @Published var showAddResidentSheet: Bool = false
    @Published var pendingQuestions: [String: AgentQuestion] = [:]
    @Published var pendingConfirmations: [String: AgentConfirmation] = [:]
    @Published var progressTrackers: [String: ProgressTracker] = [:]
    @Published var pendingSuggestions: [String: [SuggestionItem]] = [:]
    @Published var completedPlans: [String: CompletedPlan] = [:]
    @Published var idleResults: [String: ConversationIdleResult] = [:]
    @Published var evaluatingConversations: Set<String> = []
    @Published private(set) var workerStandbySessions: Set<String> = []
    @Published var presenceStore: [String: PresenceStatus] = [:]
    /// Nostr public key hex (x-only, BIP-340) for this instance — used in invite generation.
    @Published var nostrPublicKeyHex: String? = nil
    /// Number of currently connected Nostr relays (updated via nostr.status events).
    @Published var nostrRelayCount: Int = 0
    /// Total number of configured Nostr relays.
    @Published var nostrRelayTotal: Int = 0
    // launchError and autoSendText moved to WindowState (per-window)

    /// File-based config sync service (set by OdysseyApp on appear)
    var configSyncService: ConfigSyncService?
    weak var sharedRoomService: SharedRoomService?

    var createdSessions: Set<String> = []
    var generateAgentRequestId: String?
    var generateSkillRequestId: String?
    var generateTemplateRequestId: String?

    /// Session IDs for shared-room sessions created via the test API (no ChatView to persist responses).
    /// AppState auto-persists agent messages for sessions in this set on `sessionResult`.
    var sharedRoomAutoFinalizeSessionIds: Set<String> = []

    struct AgentQuestion: Identifiable {
        let id: String  // questionId
        let sessionId: String
        let question: String
        let options: [QuestionOption]?
        let multiSelect: Bool
        let isPrivate: Bool
        let timestamp: Date
        let inputType: String?
        let inputConfig: QuestionInputConfig?
    }

    struct AgentConfirmation: Identifiable {
        let id: String  // confirmationId
        let sessionId: String
        let action: String
        let reason: String
        let riskLevel: String
        let details: String?
        let timestamp: Date
    }

    struct ProgressTracker: Identifiable {
        let id: String  // progressId
        let title: String
        let steps: [ProgressStep]
    }

    struct CompletedPlan {
        let sessionId: String
        let plan: String?
        let allowedPrompts: [PlanAllowedPrompt]?
    }

    enum SessionEventKind {
        case result
        case error(String)
    }

    // MARK: - Activity State

    enum SessionActivityState: Equatable, Sendable {
        case idle
        case thinking
        case streaming
        case callingTool(toolName: String)
        case waitingForResult
        case askingUser
        case done
        case error(String)

        var isActive: Bool {
            switch self {
            case .thinking, .streaming, .callingTool, .waitingForResult, .askingUser: return true
            case .idle, .done, .error: return false
            }
        }

        var displayLabel: String {
            switch self {
            case .idle: return "Idle"
            case .thinking: return "Thinking\u{2026}"
            case .streaming: return "Writing\u{2026}"
            case .callingTool(let tool): return "Running \(tool)"
            case .waitingForResult: return "Processing\u{2026}"
            case .askingUser: return "Waiting for you\u{2026}"
            case .done: return "Done"
            case .error: return "Error"
            }
        }

        var displayColor: Color {
            switch self {
            case .idle: return .gray
            case .thinking: return .indigo
            case .streaming: return .blue
            case .callingTool: return .orange
            case .waitingForResult: return .yellow
            case .askingUser: return .purple
            case .done: return .green
            case .error: return .red
            }
        }
    }

    enum ConversationAggregateState: Equatable {
        case idle
        case working(count: Int)
        case allDone
        case completedWithErrors(errorCount: Int)
    }

    struct ConversationActivitySummary {
        let perSession: [(agentName: String, state: SessionActivityState)]
        let aggregate: ConversationAggregateState
        let totalSessions: Int
        let activeCount: Int
    }

    struct SessionInfo: Identifiable {
        let id: UUID
        let agentName: String
        var tokenCount: Int = 0
        var cost: Double = 0
        var toolCallCount: Int = 0
        var isStreaming: Bool = false
    }

    struct ToolCallInfo: Identifiable {
        let id = UUID()
        let tool: String
        let input: String
        var output: String?
        let timestamp: Date
    }

    struct CommsEvent: Identifiable {
        let id = UUID()
        let timestamp: Date
        let kind: CommsEventKind
    }

    enum CommsEventKind {
        case chat(channelId: String, from: String, message: String)
        case delegation(from: String, to: String, task: String)
        case blackboardUpdate(key: String, value: String, writtenBy: String)
    }

    private static let fileModifyingTools: Set<String> = [
        "write", "edit", "multiedit", "multi_edit", "create", "mv", "cp",
        "writefile", "createfile", "renamefile", "deletefile"
    ]
    private static let iso8601 = ISO8601DateFormatter()

    private(set) var sidecarManager: SidecarManager?
    private var eventTask: Task<Void, Never>?
    private var conversationSyncTimer: Task<Void, Never>?
    var modelContext: ModelContext?
    private(set) lazy var transportManager: TransportManager = {
        let tm = TransportManager(instanceName: InstanceConfig.name)
        tm.onPresenceChanged = { @MainActor [weak self] userId, status in
            self?.presenceStore[userId] = status
        }
        return tm
    }()
    private(set) var scheduleEngine: ScheduleEngine?
    private(set) var scheduleRunCoordinator: ScheduleRunCoordinator?
    #if DEBUG
    var commandCaptureForTesting: ((SidecarCommand) -> Void)?
    var commandSendOverrideForTesting: ((SidecarCommand) async -> Void)?
    #endif

    init() {
        if let kp = try? IdentityManager.shared.nostrKeypair(for: InstanceConfig.name) {
            nostrPublicKeyHex = kp.pubkeyHex
        }
    }

    // instanceWorkingDirectory, loadInstanceWorkingDirectory, setInstanceWorkingDirectory
    // moved to WindowState.projectDirectory (per-window)

    // MARK: - Launch Intent

    private func configureConversation(
        _ conversation: Conversation,
        projectId: UUID?,
        threadKind: ThreadKind
    ) {
        conversation.projectId = projectId
        conversation.threadKind = threadKind
    }

    /// Executes a parsed launch intent (from CLI args or URL scheme).
    /// Must be called after `modelContext` is set.
    /// Updates the given WindowState with the result (selected conversation, auto-send text, errors).
    func executeLaunchIntent(_ intent: LaunchIntent, modelContext: ModelContext, windowState: WindowState) {
        let projectDir = intent.workingDirectory ?? windowState.projectDirectory

        switch intent.mode {
        case .roomJoin(let payload):
            guard let sharedRoomService else {
                windowState.launchError = "Shared room service is not available."
                return
            }
            Task { @MainActor in
                do {
                    let conversation = try await sharedRoomService.acceptInvite(
                        roomId: payload.roomId,
                        inviteId: payload.inviteId,
                        inviteToken: payload.inviteToken,
                        projectId: windowState.selectedProjectId
                    )
                    windowState.selectedConversationId = conversation.id
                } catch {
                    windowState.launchError = error.localizedDescription
                }
            }
            return
        case .chat:
            let launchMode: ConversationExecutionMode = intent.autonomous ? .autonomous : .interactive
            let conversation = Conversation(
                topic: "New Thread",
                projectId: windowState.selectedProjectId,
                threadKind: .freeform
            )
            conversation.executionMode = launchMode
            let userParticipant = Participant(type: .user, displayName: "You")
            userParticipant.conversation = conversation
            conversation.participants.append(userParticipant)

            if intent.prompt != nil || launchMode != .interactive {
                let freeformSession = Session(
                    agent: nil,
                    mission: intent.prompt,
                    mode: sessionMode(for: launchMode),
                    workingDirectory: projectDir
                )
                freeformSession.conversations = [conversation]
                conversation.sessions.append(freeformSession)
                let agentParticipant = Participant(
                    type: .agentSession(sessionId: freeformSession.id),
                    displayName: AgentDefaults.displayName(forProvider: freeformSession.provider)
                )
                agentParticipant.conversation = conversation
                conversation.participants.append(agentParticipant)
                modelContext.insert(freeformSession)
            }

            modelContext.insert(conversation)
            try? modelContext.save()
            Task { await sidecarManager?.pushConversationSync(modelContext: modelContext) }
            windowState.selectedConversationId = conversation.id

            if intent.prompt != nil {
                windowState.autoSendText = intent.prompt
            }

        case .agent(let name):
            let descriptor = FetchDescriptor<Agent>()
            let allAgents = (try? modelContext.fetch(descriptor)) ?? []
            guard let agent = allAgents.first(where: {
                $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
            }) else {
                windowState.launchError = "Agent not found: \"\(name)\""
                return
            }

            let provisioner = AgentProvisioner(modelContext: modelContext)
            let launchMode: ConversationExecutionMode = intent.autonomous ? .autonomous : .interactive
            let (_, session) = provisioner.provision(
                agent: agent,
                mission: intent.prompt,
                mode: sessionMode(for: launchMode),
                workingDirOverride: projectDir
            )

            let conversation = Conversation(
                topic: agent.name,
                projectId: windowState.selectedProjectId,
                threadKind: .direct
            )
            conversation.executionMode = launchMode
            let userParticipant = Participant(type: .user, displayName: "You")
            let agentParticipant = Participant(
                type: .agentSession(sessionId: session.id),
                displayName: agent.name
            )
            userParticipant.conversation = conversation
            agentParticipant.conversation = conversation
            conversation.participants = [userParticipant, agentParticipant]
            session.conversations = [conversation]

            modelContext.insert(session)
            modelContext.insert(conversation)
            try? modelContext.save()
            Task { await sidecarManager?.pushConversationSync(modelContext: modelContext) }
            windowState.selectedConversationId = conversation.id

            if intent.prompt != nil {
                windowState.autoSendText = intent.prompt
            }

        case .group(let name):
            let descriptor = FetchDescriptor<AgentGroup>()
            let allGroups = (try? modelContext.fetch(descriptor)) ?? []
            guard let group = allGroups.first(where: {
                $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
            }) else {
                windowState.launchError = "Group not found: \"\(name)\""
                return
            }

            if intent.autonomous, let prompt = intent.prompt {
                let convoId = startAutonomousGroupChat(
                    group: group,
                    mission: prompt,
                    projectDirectory: projectDir,
                    projectId: windowState.selectedProjectId,
                    modelContext: modelContext
                )
                windowState.selectedConversationId = convoId
                windowState.autoSendText = prompt
            } else {
                let convoId = startGroupChat(
                    group: group,
                    projectDirectory: projectDir,
                    projectId: windowState.selectedProjectId,
                    modelContext: modelContext
                )
                windowState.selectedConversationId = convoId
                if intent.prompt != nil {
                    windowState.autoSendText = intent.prompt
                }
            }

        case .schedule(let id):
            scheduleEngine?.runLaunchdSchedule(
                scheduleId: id,
                occurrence: intent.occurrence,
                windowState: windowState
            )

        case .connectInvite(let encoded):
            Task { @MainActor in
                await handleConnectInvite(encoded: encoded, windowState: windowState)
            }
        }
    }

    func configureScheduling(modelContext: ModelContext) {
        if scheduleEngine != nil { return }
        let coordinator = ScheduleRunCoordinator(appState: self, modelContext: modelContext)
        let engine = ScheduleEngine(modelContext: modelContext, coordinator: coordinator)
        self.scheduleRunCoordinator = coordinator
        self.scheduleEngine = engine
        engine.start()
    }

    func syncScheduledMission(_ schedule: ScheduledMission) {
        scheduleEngine?.syncSchedule(schedule)
    }

    func removeScheduledMission(_ schedule: ScheduledMission) {
        scheduleEngine?.removeSchedule(schedule)
    }

    func runScheduledMissionNow(_ scheduleId: UUID, windowState: WindowState? = nil) {
        scheduleEngine?.runNow(scheduleId: scheduleId, windowState: windowState)
    }

    #if DEBUG
    func setScheduleTestingHooks(engine: ScheduleEngine?, coordinator: ScheduleRunCoordinator?) {
        self.scheduleEngine = engine
        self.scheduleRunCoordinator = coordinator
    }
    #endif

    // MARK: - Connect Invite Handler

    /// Handles an `odyssey://connect?invite=<base64url>` deep link.
    /// Decodes and verifies the invite, then logs for debugging.
    /// TODO (Phase 2b follow-up): present pairing confirmation sheet.
    private func handleConnectInvite(encoded: String, windowState: WindowState) async {
        let inviteLogger = Logger(subsystem: "com.odyssey.app", category: "LaunchIntent")
        do {
            let payload = try InviteCodeGenerator.decode(encoded)
            try InviteCodeGenerator.verify(payload)
            inviteLogger.info("Received valid connect invite from '\(payload.displayName, privacy: .public)'")
        } catch {
            inviteLogger.error("connectInvite handling failed: \(error.localizedDescription)")
            windowState.launchError = "Invite handling failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Group Chat

    @discardableResult
    func startGroupChat(
        group: AgentGroup,
        projectDirectory: String,
        projectId: UUID?,
        modelContext: ModelContext,
        missionOverride: String? = nil,
        executionMode: ConversationExecutionMode = .interactive
    ) -> UUID? {
        guard !group.agentIds.isEmpty else { return nil }
        if executionMode != .interactive,
           group.coordinatorAgentId == nil,
           !group.autonomousCapable {
            return nil
        }

        let allAgents = (try? modelContext.fetch(FetchDescriptor<Agent>())) ?? []
        let agentById = Dictionary(uniqueKeysWithValues: allAgents.map { ($0.id, $0) })
        let resolvedAgents = group.agentIds.compactMap { agentById[$0] }
        guard !resolvedAgents.isEmpty else { return nil }

        let conversation = Conversation(
            topic: executionMode == .autonomous ? "\(group.name) — Autonomous" : group.name,
            projectId: projectId,
            threadKind: executionMode == .autonomous ? .autonomous : .group
        )
        conversation.routingMode = .mentionAware
        conversation.sourceGroupId = group.id
        conversation.executionMode = executionMode
        conversation.goal = missionOverride.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }

        let userParticipant = Participant(type: .user, displayName: "You")
        userParticipant.conversation = conversation
        conversation.participants.append(userParticipant)

        let instruction = group.groupInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        if !instruction.isEmpty {
            let sysMsg = ConversationMessage(
                senderParticipantId: nil,
                text: instruction,
                type: .system,
                conversation: conversation
            )
            conversation.messages.append(sysMsg)
        }

        let provisioner = AgentProvisioner(modelContext: modelContext)
        let trimmedMissionOverride = missionOverride?.trimmingCharacters(in: .whitespacesAndNewlines)
        let mission = (trimmedMissionOverride?.isEmpty == false ? trimmedMissionOverride : nil) ?? group.defaultMission

        for agent in resolvedAgents {
            let (_, session) = provisioner.provision(
                agent: agent,
                mission: mission,
                mode: sessionMode(for: executionMode),
                workingDirOverride: projectDirectory
            )
            session.conversations = [conversation]
            conversation.sessions.append(session)

            let agentParticipant = Participant(
                type: .agentSession(sessionId: session.id),
                displayName: agent.name
            )
            agentParticipant.conversation = conversation
            conversation.participants.append(agentParticipant)
            modelContext.insert(session)
        }

        modelContext.insert(conversation)
        try? modelContext.save()
        Task { await sidecarManager?.pushConversationSync(modelContext: modelContext) }
        return conversation.id
    }

    @discardableResult
    func startAutonomousGroupChat(
        group: AgentGroup,
        mission: String,
        projectDirectory: String,
        projectId: UUID?,
        modelContext: ModelContext
    ) -> UUID? {
        guard group.autonomousCapable else { return nil }
        return startGroupChat(
            group: group,
            projectDirectory: projectDirectory,
            projectId: projectId,
            modelContext: modelContext,
            missionOverride: mission,
            executionMode: .autonomous
        )
    }

    func enterWorkerStandby(sessionId: String) {
        workerStandbySessions.insert(sessionId)
        sessionActivity[sessionId] = .idle
        lastSessionEvent.removeValue(forKey: sessionId)
    }

    func leaveWorkerStandby(sessionId: String) {
        workerStandbySessions.remove(sessionId)
    }

    func isWorkerStandingBy(sessionId: String) -> Bool {
        workerStandbySessions.contains(sessionId)
    }

    private func sessionMode(for executionMode: ConversationExecutionMode) -> SessionMode {
        switch executionMode {
        case .interactive:
            return .interactive
        case .autonomous:
            return .autonomous
        case .worker:
            return .worker
        }
    }

    func updateExecutionMode(
        _ executionMode: ConversationExecutionMode,
        for conversation: Conversation
    ) async {
        let targetSessionMode = sessionMode(for: executionMode)
        conversation.executionMode = executionMode

        let updates = conversation.sessions.map { session -> (sessionId: String, settings: AgentProvisioner.RuntimeModeSettings) in
            session.mode = targetSessionMode
            let settings = AgentProvisioner.runtimeModeSettings(agent: session.agent, mode: targetSessionMode)
            return (session.id.uuidString, settings)
        }

        try? modelContext?.save()

        for update in updates {
            try? await sendToSidecarAwait(.sessionUpdateMode(
                sessionId: update.sessionId,
                interactive: update.settings.interactive,
                instancePolicy: update.settings.instancePolicy,
                instancePolicyPoolMax: update.settings.instancePolicyPoolMax
            ))
        }
    }

    func setDelegationMode(for conversation: Conversation, mode: DelegationMode, targetAgentName: String? = nil) {
        guard let primarySession = conversation.sessions.min(by: { $0.startedAt < $1.startedAt }) else { return }
        conversation.delegationMode = mode
        conversation.delegationTargetAgentName = targetAgentName
        sendToSidecar(.setDelegationMode(
            sessionId: primarySession.id.uuidString,
            mode: mode,
            targetAgentName: targetAgentName
        ))
    }

    func connectSidecar() {
        guard sidecarStatus == .disconnected || {
            if case .error = sidecarStatus { return true }
            return false
        }() else { return }

        sidecarStatus = .connecting

        let defaults = InstanceConfig.userDefaults
        let preferredWsPort = defaults.object(forKey: AppSettings.wsPortKey) as? Int ?? AppSettings.defaultWsPort
        let preferredHttpPort = defaults.object(forKey: AppSettings.httpPortKey) as? Int ?? AppSettings.defaultHttpPort
        let bunOverride = defaults.string(forKey: AppSettings.bunPathOverrideKey)
        let sidecarPathOverride = defaults.string(forKey: AppSettings.sidecarPathKey)
        let localAgentHostOverride = defaults.string(forKey: AppSettings.localAgentHostPathOverrideKey)
        let mlxRunnerOverride = defaults.string(forKey: AppSettings.mlxRunnerPathOverrideKey)

        let wsPort = InstanceConfig.isDefault ? preferredWsPort : InstanceConfig.findFreePort()
        let httpPort = InstanceConfig.isDefault ? preferredHttpPort : InstanceConfig.findFreePort()
        allocatedWsPort = wsPort
        allocatedHttpPort = httpPort

        let config = SidecarManager.Config(
            wsPort: wsPort,
            httpPort: httpPort,
            logDirectory: InstanceConfig.logDirectory.path,
            dataDirectory: InstanceConfig.baseDirectory.path,
            bunPathOverride: bunOverride?.isEmpty == true ? nil : bunOverride,
            sidecarPathOverride: sidecarPathOverride?.isEmpty == true ? nil : sidecarPathOverride,
            localAgentHostPathOverride: localAgentHostOverride?.isEmpty == true ? nil : localAgentHostOverride,
            mlxRunnerPathOverride: mlxRunnerOverride?.isEmpty == true ? nil : mlxRunnerOverride
        )
        let manager = SidecarManager(config: config)
        self.sidecarManager = manager
        Task {
            do {
                try await manager.start()
                try? await syncSidecarRuntimeConfig()
                sidecarStatus = .connected
                listenForEvents(from: manager)
                registerAgentDefinitions()
                registerConnections()
                // Push conversation/project snapshot so iOS can read them immediately
                if let ctx = modelContext {
                    await manager.pushConversationSync(modelContext: ctx, pushMessages: true)
                }
                // Start periodic sync timer for the initial connection
                conversationSyncTimer?.cancel()
                conversationSyncTimer = Task { [weak self] in
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(30))
                        guard let self, !Task.isCancelled else { break }
                        if let ctx = self.modelContext {
                            await self.sidecarManager?.pushConversationSync(modelContext: ctx, pushMessages: true)
                        }
                    }
                }
            } catch {
                sidecarStatus = .error(error.localizedDescription)
            }
        }
    }

    func disconnectSidecar() {
        eventTask?.cancel()
        eventTask = nil
        sidecarManager?.stop()
        sidecarManager = nil
        sidecarStatus = .disconnected
    }

    func sendToSidecar(_ command: SidecarCommand) {
        Task {
            try? await sendToSidecarAwait(command)
        }
    }

    func restoreSessionContext(sessionId: String, claudeSessionId: String) {
        sendToSidecar(.sessionResume(sessionId: sessionId, claudeSessionId: claudeSessionId))
    }

    func sendToSidecarAwait(_ command: SidecarCommand) async throws {
        #if DEBUG
        commandCaptureForTesting?(command)
        if let override = commandSendOverrideForTesting {
            await override(command)
            return
        }
        #endif
        guard let manager = sidecarManager else {
            throw SidecarCommandError.unavailable
        }
        try await manager.send(command)
    }

    func syncSidecarRuntimeConfig() async throws {
        guard sidecarManager != nil else {
            throw SidecarCommandError.unavailable
        }

        let normalizedOllamaBaseURL = OllamaCatalogService.normalizedBaseURL(
            InstanceConfig.userDefaults.string(forKey: AppSettings.ollamaBaseURLKey)
        )
        let ollamaEnabled = OllamaCatalogService.modelsEnabled(defaults: InstanceConfig.userDefaults)
        try await sendToSidecarAwait(.configSetOllama(
            enabled: ollamaEnabled,
            baseURL: normalizedOllamaBaseURL
        ))
    }

    func restoreSessionContextAwait(sessionId: String, claudeSessionId: String) async throws {
        try await sendToSidecarAwait(.sessionResume(sessionId: sessionId, claudeSessionId: claudeSessionId))
    }

    func delegateTask(sourceSessionId: UUID, toAgent: String, task: String, context: String?, waitForResult: Bool) {
        sendToSidecar(.delegateTask(
            sessionId: sourceSessionId.uuidString,
            toAgent: toAgent,
            task: task,
            context: context,
            waitForResult: waitForResult
        ))
    }

    func answerQuestion(sessionId: String, questionId: String, answer: String, selectedOptions: [String]? = nil) {
        let question = pendingQuestions[sessionId]

        sendToSidecar(.questionAnswer(
            sessionId: sessionId,
            questionId: questionId,
            answer: answer,
            selectedOptions: selectedOptions
        ))
        pendingQuestions.removeValue(forKey: sessionId)
        sessionActivity[sessionId] = .waitingForResult

        // Always persist Q&A so the user can see what was asked/answered
        if let q = question {
            persistQuestionAnswer(sessionId: sessionId, question: q.question, answer: answer)
        }
    }

    private func persistQuestionAnswer(sessionId: String, question: String, answer: String) {
        guard let ctx = modelContext, let uuid = UUID(uuidString: sessionId) else { return }
        let descriptor = FetchDescriptor<Session>(predicate: #Predicate { s in s.id == uuid })
        guard let session = try? ctx.fetch(descriptor).first,
              let convo = session.conversations.first else { return }

        let agentName = session.agent?.name ?? "Agent"
        let agentParticipant = convo.participants.first { p in
            if case .agentSession(let sid) = p.type { return sid == uuid }
            return false
        }

        let msg = ConversationMessage(
            senderParticipantId: agentParticipant?.id,
            text: question,
            type: .question,
            conversation: convo
        )
        msg.toolName = agentName
        msg.toolInput = answer
        convo.messages.append(msg)
        ctx.insert(msg)
        try? ctx.save()
    }

    /// Flush any accumulated streaming text/thinking into a persisted ConversationMessage
    /// so intermediate agent output between ask_user calls is visible in the chat.
    private func flushStreamingContent(sessionId: String) {
        let text = streamingText[sessionId] ?? ""
        let thinking = thinkingText[sessionId]
        guard !text.isEmpty || (thinking != nil && !thinking!.isEmpty) else { return }
        guard let ctx = modelContext, let uuid = UUID(uuidString: sessionId) else { return }

        let descriptor = FetchDescriptor<Session>(predicate: #Predicate { s in s.id == uuid })
        guard let session = try? ctx.fetch(descriptor).first,
              let convo = session.conversations.first else { return }

        let agentParticipant = convo.participants.first { p in
            if case .agentSession(let sid) = p.type { return sid == uuid }
            return false
        }

        let msg = ConversationMessage(
            senderParticipantId: agentParticipant?.id,
            text: text,
            type: .chat,
            conversation: convo
        )
        if let thinking, !thinking.isEmpty {
            msg.thinkingText = thinking
        }
        convo.messages.append(msg)
        ctx.insert(msg)
        try? ctx.save()

        let convId = convo.id
        Task { await sidecarManager?.pushMessageAppend(conversationId: convId, message: msg) }

        streamingText.removeValue(forKey: sessionId)
        thinkingText.removeValue(forKey: sessionId)
    }

    /// Notify the sidecar that a user message has been persisted.
    /// Called from ChatView after inserting the user's ConversationMessage.
    func notifyUserMessageAppended(conversationId: UUID, message: ConversationMessage) {
        idleResults.removeValue(forKey: conversationId.uuidString)
        evaluatingConversations.remove(conversationId.uuidString)
        Task { await sidecarManager?.pushMessageAppend(conversationId: conversationId, message: message) }
    }

    func answerConfirmation(sessionId: String, confirmationId: String, approved: Bool, modifiedAction: String? = nil) {
        sendToSidecar(.confirmationAnswer(
            sessionId: sessionId,
            confirmationId: confirmationId,
            approved: approved,
            modifiedAction: modifiedAction
        ))
        pendingConfirmations.removeValue(forKey: sessionId)
        sessionActivity[sessionId] = .waitingForResult
    }

    private func persistRichContent(sessionId: String, format: String, title: String?, content: String, height: Int?) {
        guard let ctx = modelContext, let uuid = UUID(uuidString: sessionId) else { return }
        let descriptor = FetchDescriptor<Session>(predicate: #Predicate { s in s.id == uuid })
        guard let session = try? ctx.fetch(descriptor).first,
              let convo = session.conversations.first else { return }

        let agentParticipant = convo.participants.first { p in
            if case .agentSession(let sid) = p.type { return sid == uuid }
            return false
        }

        let msg = ConversationMessage(
            senderParticipantId: agentParticipant?.id,
            text: content,
            type: .richContent,
            conversation: convo
        )
        msg.toolName = format
        msg.toolInput = title
        msg.toolOutput = height.map { String($0) }
        convo.messages.append(msg)
        ctx.insert(msg)
        try? ctx.save()
    }

    func requestAgentGeneration(prompt: String, skills: [SkillCatalogEntry], mcps: [MCPCatalogEntry]) {
        let requestId = UUID().uuidString
        generateAgentRequestId = requestId
        isGeneratingAgent = true
        generateAgentError = nil
        generatedAgentSpec = nil
        sendToSidecar(.generateAgent(
            requestId: requestId,
            prompt: prompt,
            availableSkills: skills,
            availableMCPs: mcps
        ))
    }

    func requestSkillGeneration(prompt: String, categories: [String], mcps: [MCPCatalogEntry]) {
        let requestId = UUID().uuidString
        generateSkillRequestId = requestId
        isGeneratingSkill = true
        generateSkillError = nil
        generatedSkillSpec = nil
        sendToSidecar(.generateSkill(
            requestId: requestId,
            prompt: prompt,
            availableCategories: categories,
            availableMCPs: mcps
        ))
    }

    func requestTemplateGeneration(requestId: String? = nil, intent: String, agentName: String, agentSystemPrompt: String) {
        let rid = requestId ?? UUID().uuidString
        generateTemplateRequestId = rid
        isGeneratingTemplate = true
        generateTemplateError = nil
        generatedTemplateSpec = nil
        sendToSidecar(.generateTemplate(
            requestId: rid,
            intent: intent,
            agentName: agentName,
            agentSystemPrompt: agentSystemPrompt
        ))
    }

    private func clearPendingUserInput(for sessionId: String) {
        pendingQuestions.removeValue(forKey: sessionId)
        pendingConfirmations.removeValue(forKey: sessionId)
    }

    func syncConnectionToSidecar(_ connection: Connection) {
        let credentials = try? ConnectionVault.loadCredentials(connectionId: connection.id)
        sendToSidecar(.connectorCompleteAuth(
            connection: connection.asWire(),
            credentials: credentials?.asWire()
        ))
    }

    private func registerAgentDefinitions() {
        guard let ctx = modelContext else { return }
        let descriptor = FetchDescriptor<Agent>()
        guard let agents = try? ctx.fetch(descriptor), !agents.isEmpty else { return }

        let provisioner = AgentProvisioner(modelContext: ctx)
        let defs: [AgentDefinitionWire] = agents.compactMap { agent in
            let (config, _) = provisioner.provision(agent: agent, mission: nil)
            return AgentDefinitionWire(
                name: agent.name,
                config: config,
                instancePolicy: agent.instancePolicyWireValue
            )
        }

        sendToSidecar(.agentRegister(agents: defs))
        Log.appState.info("Registered \(defs.count) agent definitions with sidecar")
    }

    private func registerConnections() {
        guard let ctx = modelContext else { return }
        let descriptor = FetchDescriptor<Connection>()
        guard let connections = try? ctx.fetch(descriptor), !connections.isEmpty else { return }

        for connection in connections {
            let credentials = try? ConnectionVault.loadCredentials(connectionId: connection.id)
            if connection.status == .authorizing {
                sendToSidecar(.connectorBeginAuth(connection: connection.asWire()))
            } else {
                sendToSidecar(.connectorCompleteAuth(
                    connection: connection.asWire(),
                    credentials: credentials?.asWire()
                ))
            }
        }
    }

    private func registerAgentDefinitionsAwait() async {
        guard let ctx = modelContext else { return }
        let descriptor = FetchDescriptor<Agent>()
        guard let agents = try? ctx.fetch(descriptor), !agents.isEmpty else { return }

        let provisioner = AgentProvisioner(modelContext: ctx)
        let defs: [AgentDefinitionWire] = agents.compactMap { agent in
            let (config, _) = provisioner.provision(agent: agent, mission: nil)
            return AgentDefinitionWire(
                name: agent.name,
                config: config,
                instancePolicy: agent.instancePolicyWireValue
            )
        }

        try? await sendToSidecarAwait(.agentRegister(agents: defs))
        Log.appState.info("Registered \(defs.count) agent definitions with sidecar")
    }

    // MARK: - Conversation Activity

    func conversationActivity(for conversation: Conversation) -> ConversationActivitySummary {
        let sessionStates: [(agentName: String, state: SessionActivityState)] = conversation.sessions.map { session in
            let key = session.id.uuidString
            let state = sessionActivity[key] ?? .idle
            return (agentName: session.agent?.name ?? "Agent", state: state)
        }

        let activeCount = sessionStates.filter { $0.state.isActive }.count
        let doneCount = sessionStates.filter { $0.state == .done }.count
        let errorCount = sessionStates.filter {
            if case .error = $0.state { return true }
            return false
        }.count
        let total = sessionStates.count

        let aggregate: ConversationAggregateState
        if total == 0 {
            aggregate = .idle
        } else if activeCount > 0 {
            aggregate = .working(count: activeCount)
        } else if errorCount > 0, doneCount + errorCount >= total {
            aggregate = .completedWithErrors(errorCount: errorCount)
        } else if doneCount >= total {
            aggregate = .allDone
        } else {
            aggregate = .idle
        }

        return ConversationActivitySummary(
            perSession: sessionStates,
            aggregate: aggregate,
            totalSessions: total,
            activeCount: activeCount
        )
    }

    func clearSessionActivity(for sessionIds: [String]) {
        for key in sessionIds {
            sessionActivity.removeValue(forKey: key)
        }
    }

    private func checkConversationIdle(for sessionId: String) {
        guard let conversation = conversationForSession(sessionId: sessionId) else { return }
        let convId = conversation.id.uuidString
        guard !evaluatingConversations.contains(convId) else { return }

        let summary = conversationActivity(for: conversation)
        switch summary.aggregate {
        case .allDone, .completedWithErrors: break
        default: return
        }

        evaluatingConversations.insert(convId)

        Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard self.evaluatingConversations.contains(convId) else { return }
            guard let ctx = self.modelContext else { return }

            // Re-fetch conversation after the suspension point to avoid stale SwiftData access.
            guard let convUUID = UUID(uuidString: convId) else { return }
            let convDescriptor = FetchDescriptor<Conversation>(predicate: #Predicate { $0.id == convUUID })
            guard let freshConvo = try? ctx.fetch(convDescriptor).first else { return }

            var coordinatorSessionId: String? = nil
            if let groupId = freshConvo.sourceGroupId {
                let descriptor = FetchDescriptor<AgentGroup>(predicate: #Predicate { $0.id == groupId })
                if let sourceGroup = try? ctx.fetch(descriptor).first,
                   let coordinatorId = sourceGroup.coordinatorAgentId {
                    coordinatorSessionId = freshConvo.sessions
                        .first(where: { $0.agent?.id == coordinatorId })?
                        .id.uuidString
                }
            }

            let evalMsg = ConversationMessage(
                text: "__idle_evaluation__",
                type: .systemEvaluation,
                conversation: freshConvo
            )
            ctx.insert(evalMsg)
            try? ctx.save()

            self.sendToSidecar(.conversationEvaluate(
                conversationId: convId,
                goal: freshConvo.goal,
                coordinatorSessionId: coordinatorSessionId,
                sessionIds: freshConvo.sessions.map { $0.id.uuidString }
            ))
        }
    }

    func markSessionPausedLocally(_ sessionId: String) {
        if let uuid = UUID(uuidString: sessionId) {
            if activeSessions[uuid] == nil {
                _ = ensureActiveSessionInfo(sessionId: sessionId)
            }
            activeSessions[uuid]?.isStreaming = false
        }
        thinkingText.removeValue(forKey: sessionId)
        clearPendingUserInput(for: sessionId)
        workerStandbySessions.remove(sessionId)
        sessionActivity[sessionId] = .idle
    }

    private func listenForEvents(from manager: SidecarManager) {
        eventTask = Task {
            for await event in manager.events {
                handleEvent(event)
            }
        }
    }

    private func handleEvent(_ event: SidecarEvent) {
        switch event {
        case .streamToken(let sessionId, let text):
            let current = streamingText[sessionId] ?? ""
            streamingText[sessionId] = current + text
            if let uuid = ensureActiveSessionInfo(sessionId: sessionId) {
                activeSessions[uuid]?.isStreaming = true
                // Rough estimate: ~4 chars per output token, refined on completion
                activeSessions[uuid]?.tokenCount += max(1, text.count / 4)
            }
            sessionActivity[sessionId] = .streaming

        case .streamThinking(let sessionId, let text):
            let current = thinkingText[sessionId] ?? ""
            thinkingText[sessionId] = current + text
            if let uuid = ensureActiveSessionInfo(sessionId: sessionId) {
                activeSessions[uuid]?.isStreaming = true
            }
            sessionActivity[sessionId] = .thinking

        case .streamToolCall(let sessionId, let tool, let input):
            var calls = toolCalls[sessionId] ?? []
            calls.append(ToolCallInfo(tool: tool, input: input, timestamp: Date()))
            toolCalls[sessionId] = calls
            if let uuid = ensureActiveSessionInfo(sessionId: sessionId) {
                activeSessions[uuid]?.toolCallCount += 1
            }
            sessionActivity[sessionId] = .callingTool(toolName: tool)

        case .streamToolResult(let sessionId, let tool, let output):
            if var calls = toolCalls[sessionId],
               let idx = calls.lastIndex(where: { $0.tool == tool && $0.output == nil }) {
                calls[idx].output = output
                toolCalls[sessionId] = calls
            }
            if Self.fileModifyingTools.contains(tool.lowercased()) {
                fileTreeRefreshTrigger += 1
            }
            sessionActivity[sessionId] = .waitingForResult

        case .sessionResult(let sessionId, let resultText, let cost, let tokenCount, let toolCallCount):
            workerStandbySessions.remove(sessionId)
            if let uuid = ensureActiveSessionInfo(sessionId: sessionId) {
                activeSessions[uuid]?.isStreaming = false
                activeSessions[uuid]?.cost = cost
                activeSessions[uuid]?.tokenCount = tokenCount
                activeSessions[uuid]?.toolCallCount = toolCallCount
            }
            if streamingText[sessionId]?.isEmpty != false, !resultText.isEmpty {
                streamingText[sessionId] = resultText
            }
            lastSessionEvent[sessionId] = .result
            thinkingText.removeValue(forKey: sessionId)
            clearPendingUserInput(for: sessionId)
            sessionActivity[sessionId] = .done
            checkConversationIdle(for: sessionId)
            markConversationUnreadIfNeeded(sessionId: sessionId)
            notifyIfNeeded(sessionId: sessionId) { name, topic in
                ChatNotificationManager.shared.notifySessionCompleted(agentName: name, conversationTopic: topic)
            }
            updatePersistedSessionStatus(sessionId: sessionId, status: .completed)
            persistSessionUsage(sessionId: sessionId, tokenCount: tokenCount, cost: cost, toolCallCount: toolCallCount)
            cleanupWorktreeIfNeeded(sessionId: sessionId)
            if sharedRoomAutoFinalizeSessionIds.contains(sessionId) {
                sharedRoomAutoFinalizeSessionIds.remove(sessionId)
                finalizeSharedRoomAgentMessage(sessionId: sessionId)
            }
            if let ctx = modelContext {
                Task { await sidecarManager?.pushConversationSync(modelContext: ctx) }
            }

        case .sessionError(let sessionId, let error):
            workerStandbySessions.remove(sessionId)
            if let uuid = ensureActiveSessionInfo(sessionId: sessionId) {
                activeSessions[uuid]?.isStreaming = false
            }
            lastSessionEvent[sessionId] = .error(error)
            thinkingText.removeValue(forKey: sessionId)
            streamingImages.removeValue(forKey: sessionId)
            streamingFileCards.removeValue(forKey: sessionId)
            clearPendingUserInput(for: sessionId)
            sessionActivity[sessionId] = .error(error)
            checkConversationIdle(for: sessionId)
            notifyIfNeeded(sessionId: sessionId) { name, _ in
                ChatNotificationManager.shared.notifySessionError(agentName: name, error: error)
            }
            Log.appState.error("Session \(sessionId, privacy: .public) error: \(error, privacy: .public)")
            updatePersistedSessionStatus(sessionId: sessionId, status: .failed)
            cleanupWorktreeIfNeeded(sessionId: sessionId)

        case .peerChat(let sessionId, let channelId, let from, let message):
            commsEvents.append(CommsEvent(
                timestamp: Date(),
                kind: .chat(channelId: channelId, from: from, message: message)
            ))
            persistPeerChatMessage(sessionId: sessionId, channelId: channelId, from: from, message: message)

        case .peerDelegate(let sessionId, let from, let to, let task):
            commsEvents.append(CommsEvent(
                timestamp: Date(),
                kind: .delegation(from: from, to: to, task: task)
            ))
            persistDelegationEvent(sessionId: sessionId, from: from, to: to, task: task)

        case .blackboardUpdate(let sessionId, let key, let value, let writtenBy):
            commsEvents.append(CommsEvent(
                timestamp: Date(),
                kind: .blackboardUpdate(key: key, value: value, writtenBy: writtenBy)
            ))
            persistBlackboardUpdate(sessionId: sessionId, key: key, value: value, writtenBy: writtenBy)

        case .sessionForked(let parentSessionId, let childSessionId):
            Log.appState.info("session.forked parent=\(parentSessionId, privacy: .public) child=\(childSessionId, privacy: .public)")

        case .sessionReused(let originalSessionId, let reusedSessionId):
            Log.appState.info("session.reused original=\(originalSessionId, privacy: .public) → reused=\(reusedSessionId, privacy: .public)")

        case .streamImage(let sessionId, let imageData, let mediaType, _):
            streamingImages[sessionId, default: []].append((data: imageData, mediaType: mediaType))

        case .streamFileCard(let sessionId, let filePath, let fileType, let fileName):
            streamingFileCards[sessionId, default: []].append((path: filePath, type: fileType, name: fileName))

        case .agentQuestion(let sessionId, let questionId, let question, let options, let multiSelect, let isPrivate, let inputType, let inputConfig, _, _):
            flushStreamingContent(sessionId: sessionId)
            pendingQuestions[sessionId] = AgentQuestion(
                id: questionId,
                sessionId: sessionId,
                question: question,
                options: options,
                multiSelect: multiSelect,
                isPrivate: isPrivate,
                timestamp: Date(),
                inputType: inputType,
                inputConfig: inputConfig
            )
            sessionActivity[sessionId] = .askingUser
            markConversationUnreadIfNeeded(sessionId: sessionId)
            notifyIfNeeded(sessionId: sessionId) { name, _ in
                ChatNotificationManager.shared.notifyAgentQuestion(agentName: name, question: question)
            }

        case .agentConfirmation(let sessionId, let confirmationId, let action, let reason, let riskLevel, let details):
            flushStreamingContent(sessionId: sessionId)
            pendingConfirmations[sessionId] = AgentConfirmation(
                id: confirmationId,
                sessionId: sessionId,
                action: action,
                reason: reason,
                riskLevel: riskLevel,
                details: details,
                timestamp: Date()
            )
            sessionActivity[sessionId] = .askingUser

        case .streamRichContent(let sessionId, let format, let title, let content, let height):
            Log.appState.debug("stream.richContent format=\(format, privacy: .public) session=\(sessionId, privacy: .public)")
            persistRichContent(sessionId: sessionId, format: format, title: title, content: content, height: height)

        case .streamProgress(let sessionId, let progressId, let title, let steps):
            progressTrackers[sessionId] = ProgressTracker(id: progressId, title: title, steps: steps)

        case .streamSuggestions(let sessionId, let suggestions):
            pendingSuggestions[sessionId] = suggestions

        case .generatedAgent(let requestId, let spec):
            guard requestId == generateAgentRequestId else { return }
            generatedAgentSpec = spec
            isGeneratingAgent = false
            generateAgentRequestId = nil

        case .generateAgentError(let requestId, let error):
            guard requestId == generateAgentRequestId else { return }
            generateAgentError = error
            isGeneratingAgent = false
            generateAgentRequestId = nil
            Log.appState.error("Agent generation error: \(error, privacy: .public)")

        case .generatedSkill(let requestId, let spec):
            guard requestId == generateSkillRequestId else { return }
            generatedSkillSpec = spec
            isGeneratingSkill = false
            generateSkillRequestId = nil

        case .generateSkillError(let requestId, let error):
            guard requestId == generateSkillRequestId else { return }
            generateSkillError = error
            isGeneratingSkill = false
            generateSkillRequestId = nil
            Log.appState.error("Skill generation error: \(error, privacy: .public)")

        case .generatedTemplate(let requestId, let spec):
            guard requestId == generateTemplateRequestId else { return }
            generatedTemplateSpec = spec
            isGeneratingTemplate = false
            generateTemplateRequestId = nil

        case .generateTemplateError(let requestId, let error):
            guard requestId == generateTemplateRequestId else { return }
            generateTemplateError = error
            isGeneratingTemplate = false
            generateTemplateRequestId = nil
            Log.appState.error("Template generation error: \(error, privacy: .public)")

        case .planComplete(let sessionId, let plan, let allowedPrompts):
            flushStreamingContent(sessionId: sessionId)
            completedPlans[sessionId] = CompletedPlan(
                sessionId: sessionId, plan: plan, allowedPrompts: allowedPrompts
            )

        case .conversationInviteAgent(let sessionId, let agentName):
            handleInviteAgent(sessionId: sessionId, agentName: agentName)
            persistAgentInvite(sessionId: sessionId, invitedAgent: agentName, invitedBy: "Group")

        case .taskCreated(let sessionId, let task):
            persistTask(task, sessionId: sessionId)
            persistTaskEvent(sessionId: sessionId, task: task, action: "created")

        case .taskUpdated(let sessionId, let task):
            persistTask(task, sessionId: sessionId)
            persistTaskEvent(sessionId: sessionId, task: task, action: task.status)

        case .taskListResult(let tasks):
            for task in tasks { persistTask(task, sessionId: nil) }

        case .connectorListResult:
            break

        case .connectorStatusChanged(let connection):
            upsertConnection(connection)

        case .connectorAudit(_, let connectionId, _, _, let outcome, let summary):
            recordConnectorAudit(connectionId: connectionId, outcome: outcome, summary: summary)

        case .workspaceCreated(let sessionId, let workspaceName, let agentName):
            persistWorkspaceEvent(sessionId: sessionId, workspaceName: workspaceName, agentName: agentName, action: "created")

        case .workspaceJoined(let sessionId, let workspaceName, let agentName):
            persistWorkspaceEvent(sessionId: sessionId, workspaceName: workspaceName, agentName: agentName, action: "joined")

        case .agentInvited(let sessionId, let invitedAgent, let invitedBy):
            persistAgentInvite(sessionId: sessionId, invitedAgent: invitedAgent, invitedBy: invitedBy)

        case .iosPushRegistered(let apnsToken, let success, let error):
            if success {
                logger.info("AppState: iOS push registered for token \(apnsToken.prefix(8))…")
            } else {
                logger.warning("AppState: iOS push registration failed: \(error ?? "unknown")")
            }

        case .nostrStatus(let connected, let total):
            nostrRelayCount = connected
            nostrRelayTotal = total
            // TODO(nostr-relay): When invite acceptance is implemented on the Mac side,
            // call sidecarManager?.send(.nostrAddPeer(name:pubkeyHex:relays:)) after
            // successfully verifying an accepted InvitePayload that contains nostrPubkey.
            // The iOS side sends invites; the Mac side currently only generates them.

        case .agentQuestionRouting(let sessionId, let questionId, let targetAgentName):
            if let conversation = conversationForSession(sessionId: sessionId) {
                conversation.pendingQuestionRouting[questionId] = targetAgentName
            }

        case .agentQuestionResolved(let sessionId, let questionId, let answeredBy, let isFallback, let answer):
            if let conversation = conversationForSession(sessionId: sessionId) {
                conversation.pendingQuestionRouting.removeValue(forKey: questionId)
                conversation.resolvedQuestions[questionId] = ResolvedQuestionInfo(answeredBy: answeredBy, isFallback: isFallback, answer: answer)
            }

        case .conversationCleared(let conversationId):
            if let ctx = modelContext,
               let uuid = UUID(uuidString: conversationId),
               let convo = try? ctx.fetch(FetchDescriptor<Conversation>()).first(where: { $0.id == uuid }) {
                for msg in convo.messages { ctx.delete(msg) }
                try? ctx.save()
            }

        case .conversationIdle:
            break

        case .conversationIdleResult(let conversationId, let status, let reason):
            evaluatingConversations.remove(conversationId)
            idleResults[conversationId] = ConversationIdleResult(status: status, reason: reason)

        case .connected:
            sidecarStatus = .connected
            disconnectTimer?.invalidate()
            disconnectTimer = nil
            Task { await recoverSessions() }
            sendToSidecar(.taskList(filter: nil))
            registerAgentDefinitions()
            registerConnections()
            if let ctx = modelContext {
                Task { await sidecarManager?.pushConversationSync(modelContext: ctx, pushMessages: true) }
            }
            // Re-register all stored Nostr peers so the sidecar knows them after restarts/reconnects
            if let ctx = modelContext {
                let peers = NostrPeer.all(in: ctx)
                if !peers.isEmpty {
                    Task {
                        for peer in peers {
                            try? await sidecarManager?.send(.nostrAddPeer(
                                name: peer.displayName,
                                pubkeyHex: peer.pubkeyHex,
                                relays: peer.relays
                            ))
                        }
                        Log.sidecar.info("Re-registered \(peers.count) Nostr peer(s) with sidecar")
                    }
                }
            }
            Task {
                transportManager.onInboundMessage = { [weak self] msg in
                    await self?.handleInboundTransportMessage(msg)
                }
                await transportManager.start()
            }
            conversationSyncTimer?.cancel()
            conversationSyncTimer = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(30))
                    guard let self, !Task.isCancelled else { break }
                    if let ctx = self.modelContext {
                        await self.sidecarManager?.pushConversationSync(modelContext: ctx, pushMessages: true)
                    }
                }
            }

        case .disconnected:
            sidecarStatus = .disconnected
            conversationSyncTimer?.cancel()
            conversationSyncTimer = nil
            pendingQuestions.removeAll()
            pendingConfirmations.removeAll()
            startDisconnectTimer()
        }
    }

    private func upsertConnection(_ wire: ConnectorWire) {
        guard let ctx = modelContext else { return }
        let connectionId = UUID(uuidString: wire.id) ?? UUID()
        let descriptor = FetchDescriptor<Connection>(predicate: #Predicate { connection in
            connection.id == connectionId
        })
        let fetched = try? ctx.fetch(descriptor).first
        let connection = fetched ?? Connection(
            provider: ConnectionProvider(rawValue: wire.provider) ?? .slack,
            authMode: ConnectionAuthMode(rawValue: wire.authMode) ?? .brokered
        )

        if fetched == nil {
            connection.id = connectionId
            ctx.insert(connection)
        }

        connection.provider = ConnectionProvider(rawValue: wire.provider) ?? connection.provider
        connection.installScope = ConnectionInstallScope(rawValue: wire.installScope) ?? .system
        connection.displayName = wire.displayName
        connection.accountId = wire.accountId
        connection.accountHandle = wire.accountHandle
        connection.accountMetadataJSON = wire.accountMetadataJSON
        connection.grantedScopes = wire.grantedScopes
        connection.authMode = ConnectionAuthMode(rawValue: wire.authMode) ?? connection.authMode
        connection.writePolicy = ConnectionWritePolicy(rawValue: wire.writePolicy) ?? connection.writePolicy
        connection.status = ConnectionStatus(rawValue: wire.status) ?? connection.status
        connection.statusMessage = wire.statusMessage
        connection.brokerReference = wire.brokerReference
        connection.auditSummary = wire.auditSummary
        connection.lastAuthenticatedAt = wire.lastAuthenticatedAt.flatMap(Self.iso8601.date(from:))
        connection.lastCheckedAt = wire.lastCheckedAt.flatMap(Self.iso8601.date(from:))
        connection.updatedAt = Date()
        try? ctx.save()
    }

    private func recordConnectorAudit(connectionId: String, outcome: String, summary: String) {
        guard let ctx = modelContext, let uuid = UUID(uuidString: connectionId) else { return }
        let descriptor = FetchDescriptor<Connection>(predicate: #Predicate { connection in
            connection.id == uuid
        })
        guard let connection = try? ctx.fetch(descriptor).first else { return }
        connection.auditSummary = "\(outcome): \(summary)"
        connection.lastCheckedAt = Date()
        connection.updatedAt = Date()
        try? ctx.save()
    }

    // MARK: - Group Invite Agent

    private func handleInviteAgent(sessionId: String, agentName: String) {
        guard let ctx = modelContext else { return }
        guard let sessionUUID = UUID(uuidString: sessionId) else { return }

        // Find the conversation that the requesting session belongs to
        let sessionDescriptor = FetchDescriptor<Session>(predicate: #Predicate { s in s.id == sessionUUID })
        guard let requestingSession = try? ctx.fetch(sessionDescriptor).first,
              let conversation = requestingSession.conversations.first else {
            Log.appState.warning("handleInviteAgent: no conversation found for session \(sessionId, privacy: .public)")
            return
        }

        // Find the agent by name
        let agentDescriptor = FetchDescriptor<Agent>()
        guard let agents = try? ctx.fetch(agentDescriptor),
              let agent = agents.first(where: { $0.name.localizedCaseInsensitiveCompare(agentName) == .orderedSame }) else {
            Log.appState.warning("handleInviteAgent: agent '\(agentName, privacy: .public)' not found")
            return
        }

        // Check if agent is already in the conversation
        if conversation.sessions.contains(where: { $0.agent?.id == agent.id }) {
            Log.appState.info("handleInviteAgent: '\(agentName, privacy: .public)' already in conversation")
            return
        }

        // Provision a new session for the invited agent
        let provisioner = AgentProvisioner(modelContext: ctx)
        let primaryWd = requestingSession.workingDirectory
        let (config, newSession) = provisioner.provision(
            agent: agent,
            mission: requestingSession.mission,
            workingDirOverride: primaryWd.isEmpty ? nil : primaryWd
        )

        newSession.conversations = [conversation]
        conversation.sessions.append(newSession)
        conversation.threadKind = .group

        let participant = Participant(type: .agentSession(sessionId: newSession.id), displayName: agent.name)
        participant.conversation = conversation
        conversation.participants.append(participant)

        ctx.insert(newSession)
        ctx.insert(participant)
        try? ctx.save()

        // Send sessionCreate to the sidecar so the agent is ready to receive messages
        sendToSidecar(.sessionCreate(
            conversationId: newSession.id.uuidString,
            agentConfig: config
        ))

        Log.appState.info("handleInviteAgent: added '\(agentName, privacy: .public)' to conversation \(conversation.id, privacy: .public)")
    }

    // MARK: - Task Board

    private func persistTask(_ wire: TaskWireSwift, sessionId: String?) {
        guard let ctx = modelContext else { return }
        guard let taskId = UUID(uuidString: wire.id) else { return }
        let projectId = wire.projectId.flatMap(UUID.init) ?? inferredProjectId(for: wire, sessionId: sessionId, in: ctx)
        let assignedAgentUUID = wire.assignedAgentId.flatMap(UUID.init)
        let assignedAgentName = wire.assignedAgentName ?? (assignedAgentUUID == nil ? wire.assignedAgentId : nil)

        let descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { t in t.id == taskId })

        if let existing = try? ctx.fetch(descriptor).first {
            if let projectId {
                existing.projectId = projectId
            }
            existing.title = wire.title
            existing.taskDescription = wire.description
            existing.status = TaskStatus(rawValue: wire.status) ?? .ready
            existing.priority = TaskPriority(rawValue: wire.priority) ?? .medium
            existing.labels = wire.labels
            existing.result = wire.result
            existing.parentTaskId = wire.parentTaskId.flatMap(UUID.init)
            existing.assignedAgentId = assignedAgentUUID
            existing.assignedAgentName = assignedAgentName
            existing.assignedGroupId = wire.assignedGroupId.flatMap(UUID.init)
            existing.conversationId = wire.conversationId.flatMap(UUID.init)
            existing.startedAt = wire.startedAt.flatMap { ISO8601DateFormatter().date(from: $0) }
            existing.completedAt = wire.completedAt.flatMap { ISO8601DateFormatter().date(from: $0) }
        } else {
            let item = TaskItem(
                title: wire.title,
                taskDescription: wire.description,
                priority: TaskPriority(rawValue: wire.priority) ?? .medium,
                labels: wire.labels,
                status: TaskStatus(rawValue: wire.status) ?? .backlog
            )
            item.id = taskId
            item.projectId = projectId
            item.parentTaskId = wire.parentTaskId.flatMap(UUID.init)
            item.assignedAgentId = assignedAgentUUID
            item.assignedAgentName = assignedAgentName
            item.assignedGroupId = wire.assignedGroupId.flatMap(UUID.init)
            item.conversationId = wire.conversationId.flatMap(UUID.init)
            item.result = wire.result
            item.startedAt = wire.startedAt.flatMap { ISO8601DateFormatter().date(from: $0) }
            item.completedAt = wire.completedAt.flatMap { ISO8601DateFormatter().date(from: $0) }
            ctx.insert(item)
        }
        try? ctx.save()
    }

    private func inferredProjectId(
        for wire: TaskWireSwift,
        sessionId: String?,
        in modelContext: ModelContext
    ) -> UUID? {
        if let conversationId = wire.conversationId.flatMap(UUID.init) {
            let descriptor = FetchDescriptor<Conversation>(predicate: #Predicate { $0.id == conversationId })
            if let conversation = try? modelContext.fetch(descriptor).first {
                return conversation.projectId
            }
        }

        if let sessionId, let sessionUUID = UUID(uuidString: sessionId) {
            let descriptor = FetchDescriptor<Session>(predicate: #Predicate { $0.id == sessionUUID })
            if let session = try? modelContext.fetch(descriptor).first {
                return session.conversations.first?.projectId
            }
        }

        return nil
    }

    func createTask(
        title: String,
        description: String,
        priority: TaskPriority,
        labels: [String],
        markReady: Bool,
        projectId: UUID?
    ) {
        let id = UUID()
        let status: TaskStatus = markReady ? .ready : .backlog
        let now = ISO8601DateFormatter().string(from: Date())

        let wire = TaskWireSwift(
            id: id.uuidString,
            projectId: projectId?.uuidString,
            title: title,
            description: description,
            status: status.rawValue,
            priority: priority.rawValue,
            labels: labels,
            result: nil,
            parentTaskId: nil,
            assignedAgentId: nil,
            assignedAgentName: nil,
            assignedGroupId: nil,
            conversationId: nil,
            createdAt: now,
            startedAt: nil,
            completedAt: nil
        )
        sendToSidecar(.taskCreate(task: wire))
        persistTask(wire, sessionId: nil)
    }

    func updateTaskStatus(_ task: TaskItem, status: TaskStatus) {
        let wire = TaskWireSwift(
            id: task.id.uuidString,
            projectId: task.projectId?.uuidString,
            title: task.title,
            description: task.taskDescription,
            status: status.rawValue,
            priority: task.priority.rawValue,
            labels: task.labels,
            result: task.result,
            parentTaskId: task.parentTaskId?.uuidString,
            assignedAgentId: task.assignedAgentId?.uuidString,
            assignedAgentName: task.assignedAgentName,
            assignedGroupId: task.assignedGroupId?.uuidString,
            conversationId: task.conversationId?.uuidString,
            createdAt: ISO8601DateFormatter().string(from: task.createdAt),
            startedAt: task.startedAt.map { ISO8601DateFormatter().string(from: $0) },
            completedAt: task.completedAt.map { ISO8601DateFormatter().string(from: $0) }
        )
        sendToSidecar(.taskUpdate(taskId: task.id.uuidString, updates: wire))
        task.status = status
        if status == .inProgress && task.startedAt == nil { task.startedAt = Date() }
        if status == .done || status == .failed { task.completedAt = Date() }
        if status == .ready || status == .backlog {
            task.startedAt = nil
            task.completedAt = nil
            task.assignedAgentId = nil
            task.assignedAgentName = nil
            task.assignedGroupId = nil
        }
        try? modelContext?.save()
    }

    /// Launch an Orchestrator session to process a specific task.
    /// Marks the task as ready if it's in backlog, then creates a new Orchestrator
    /// conversation with a prompt instructing it to claim and execute the task.
    func runTaskWithOrchestrator(_ task: TaskItem, modelContext: ModelContext, windowState: WindowState) {
        // Ensure task is ready for the orchestrator
        if task.status == .backlog {
            updateTaskStatus(task, status: .ready)
        }

        // Find the Orchestrator agent
        let descriptor = FetchDescriptor<Agent>()
        guard let agents = try? modelContext.fetch(descriptor),
              let orchestrator = agents.first(where: { $0.name.lowercased() == "orchestrator" }) else {
            Log.appState.error("runTaskWithOrchestrator: Orchestrator agent not found")
            return
        }

        // Provision a new session
        let provisioner = AgentProvisioner(modelContext: modelContext)
        let (_, session) = provisioner.provision(agent: orchestrator, mission: task.title)

        // Create conversation
        let conversation = Conversation(
            topic: "Task: \(task.title)",
            projectId: task.projectId ?? windowState.selectedProjectId,
            threadKind: .direct
        )
        let userParticipant = Participant(type: .user, displayName: "You")
        let agentParticipant = Participant(
            type: .agentSession(sessionId: session.id),
            displayName: orchestrator.name
        )
        userParticipant.conversation = conversation
        agentParticipant.conversation = conversation
        conversation.participants = [userParticipant, agentParticipant]
        session.conversations = [conversation]

        modelContext.insert(session)
        modelContext.insert(conversation)

        // Link task to this conversation
        task.conversationId = conversation.id
        try? modelContext.save()
        Task { await sidecarManager?.pushConversationSync(modelContext: modelContext) }

        windowState.selectedConversationId = conversation.id

        let prompt = """
        Check the task board and process the task with ID: \(task.id.uuidString)

        Task: \(task.title)
        Description: \(task.taskDescription)
        Priority: \(task.priority.rawValue)

        Use task_board_claim to claim it, then plan and execute it by delegating to the appropriate agents.
        """
        windowState.autoSendText = prompt
    }

    #if DEBUG
    /// Exposed for unit testing — calls handleEvent directly.
    func handleEventForTesting(_ event: SidecarEvent) {
        handleEvent(event)
    }

    func recoverSessionsForTesting() async {
        await recoverSessions()
    }

    func markSessionsStaleForTesting() {
        markSessionsStale()
    }
    #endif

    // MARK: - Session crash recovery

    private var disconnectTimer: Timer?

    /// After sidecar reconnects, re-register agents and restore Claude context for recoverable sessions.
    private func recoverSessions() async {
        guard let ctx = modelContext, canSendCommands else { return }

        // 1. Re-register agent definitions so sidecar knows about them
        await registerAgentDefinitionsAwait()

        // 2. Find sessions that were active and have a Claude SDK session ID
        let descriptor = FetchDescriptor<Session>()
        guard let allSessions = try? ctx.fetch(descriptor) else { return }
        let resumable = allSessions.filter {
            ($0.status == .active || $0.status == .paused || $0.status == .interrupted) && $0.claudeSessionId != nil
        }
        guard !resumable.isEmpty else { return }

        let provisioner = AgentProvisioner(modelContext: ctx)
        var entries: [SessionBulkResumeEntry] = []
        for session in resumable {
            guard session.agent != nil,
                  let claudeId = session.claudeSessionId,
                  let config = provisioner.config(for: session) else { continue }
            entries.append(SessionBulkResumeEntry(
                sessionId: session.id.uuidString,
                claudeSessionId: claudeId,
                agentConfig: config
            ))
            createdSessions.insert(session.id.uuidString)
            sessionActivity[session.id.uuidString] = .idle

            // A previously active session was interrupted by losing the sidecar;
            // restore Claude context, but do not claim the run is still live.
            if session.status == .active {
                session.status = .interrupted
            }
        }

        guard !entries.isEmpty else { return }
        try? ctx.save()
        try? await sendToSidecarAwait(.sessionBulkResume(sessions: entries))
        Log.appState.info("Recovered \(entries.count) sessions after reconnect")
    }

    /// Mark active sessions as interrupted after prolonged sidecar disconnect (60s).
    private func startDisconnectTimer() {
        disconnectTimer?.invalidate()
        disconnectTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.markSessionsStale()
            }
        }
    }

    private func markSessionsStale() {
        guard let ctx = modelContext else { return }
        let descriptor = FetchDescriptor<Session>()
        guard let sessions = try? ctx.fetch(descriptor) else { return }
        for session in sessions where session.status == .active {
            session.status = .interrupted
            sessionActivity[session.id.uuidString] = .idle
        }
        try? ctx.save()
        Log.appState.warning("Marked active sessions as interrupted after prolonged disconnect")
    }

    private var canSendCommands: Bool {
        if sidecarManager != nil { return true }
        #if DEBUG
        return commandSendOverrideForTesting != nil || commandCaptureForTesting != nil
        #else
        return false
        #endif
    }

    // MARK: - Worktree cleanup

    private func cleanupWorktreeIfNeeded(sessionId: String) {
        // Session-level worktrees have been removed.
        // Per-conversation worktrees are managed by WorktreeManager.
    }

    private func updatePersistedSessionStatus(sessionId: String, status: SessionStatus) {
        guard let ctx = modelContext, let uuid = UUID(uuidString: sessionId) else { return }
        let descriptor = FetchDescriptor<Session>(predicate: #Predicate { $0.id == uuid })
        guard let session = try? ctx.fetch(descriptor).first else { return }
        session.status = status
        session.lastActiveAt = Date()
        try? ctx.save()
    }

    // MARK: - Unread state

    private func markConversationUnreadIfNeeded(sessionId: String) {
        guard let ctx = modelContext, let uuid = UUID(uuidString: sessionId) else { return }
        let descriptor = FetchDescriptor<Session>(predicate: #Predicate { s in s.id == uuid })
        guard let session = try? ctx.fetch(descriptor).first,
              let convo = session.conversations.first,
              !visibleConversationIds.contains(convo.id) else { return }
        convo.isUnread = true
        try? ctx.save()
    }

    /// Fire a notification only when the session's conversation is not currently viewed or app is in background.
    private func notifyIfNeeded(sessionId: String, _ action: (String, String?) -> Void) {
        let appIsActive = NSApplication.shared.isActive
        guard let ctx = modelContext, let uuid = UUID(uuidString: sessionId) else { return }
        let descriptor = FetchDescriptor<Session>(predicate: #Predicate { s in s.id == uuid })
        guard let session = try? ctx.fetch(descriptor).first,
              let convo = session.conversations.first else { return }
        guard !visibleConversationIds.contains(convo.id) || !appIsActive else { return }
        let agentName = session.agent?.name ?? "Agent"
        action(agentName, convo.topic)
    }

    // MARK: - Session usage persistence

    private func persistSessionUsage(sessionId: String, tokenCount: Int, cost: Double, toolCallCount: Int) {
        guard let ctx = modelContext, let uuid = UUID(uuidString: sessionId) else { return }
        let descriptor = FetchDescriptor<Session>(predicate: #Predicate { s in s.id == uuid })
        guard let session = try? ctx.fetch(descriptor).first else { return }
        session.tokenCount = tokenCount
        session.totalCost = cost
        session.toolCallCount = toolCallCount
        session.lastActiveAt = Date()
        try? ctx.save()
    }

    private func ensureActiveSessionInfo(sessionId: String) -> UUID? {
        guard let uuid = UUID(uuidString: sessionId) else { return nil }
        if activeSessions[uuid] != nil { return uuid }

        guard let session = fetchSession(id: uuid) else {
            activeSessions[uuid] = SessionInfo(id: uuid, agentName: "Agent")
            return uuid
        }

        activeSessions[uuid] = SessionInfo(
            id: uuid,
            agentName: session.agent?.name ?? "Agent",
            tokenCount: session.tokenCount,
            cost: session.totalCost,
            toolCallCount: session.toolCallCount,
            isStreaming: false
        )
        return uuid
    }

    private func fetchSession(id: UUID) -> Session? {
        guard let ctx = modelContext else { return nil }
        let descriptor = FetchDescriptor<Session>(predicate: #Predicate { session in
            session.id == id
        })
        return try? ctx.fetch(descriptor).first
    }

    // MARK: - Shared room auto-finalize (test API path, no ChatView)

    /// Persists the agent's streamed response as a ConversationMessage and publishes
    /// it to the shared room store. Called when a session in `sharedRoomAutoFinalizeSessionIds`
    /// completes — i.e., when the test API dispatched the session and there is no ChatView
    /// available to handle the result.
    private func finalizeSharedRoomAgentMessage(sessionId: String) {
        guard let ctx = modelContext,
              let convo = conversationForSession(sessionId: sessionId),
              convo.isSharedRoom
        else { return }

        let responseText = streamingText[sessionId] ?? ""
        streamingText.removeValue(forKey: sessionId)
        thinkingText.removeValue(forKey: sessionId)
        lastSessionEvent.removeValue(forKey: sessionId)
        guard !responseText.isEmpty else { return }

        let sessionUUID = UUID(uuidString: sessionId)
        let agentParticipant = convo.participants.first {
            guard case .agentSession(let sid) = $0.type, let suid = sessionUUID else { return false }
            return sid == suid
        }
        let response = ConversationMessage(
            senderParticipantId: agentParticipant?.id,
            text: responseText,
            type: .chat,
            conversation: convo
        )
        convo.messages.append(response)
        ctx.insert(response)
        try? ctx.save()

        if let srs = sharedRoomService {
            Task { await srs.publishLocalMessage(response, in: convo) }
        }
    }

    // MARK: - Persistence helpers for inter-agent events

    private func conversationForSession(sessionId: String) -> Conversation? {
        guard let ctx = modelContext, let uuid = UUID(uuidString: sessionId) else { return nil }
        let descriptor = FetchDescriptor<Session>(predicate: #Predicate { $0.id == uuid })
        return (try? ctx.fetch(descriptor).first)?.conversations.first
    }

    private func persistPeerChatMessage(sessionId: String, channelId: String, from: String, message: String) {
        guard let ctx = modelContext,
              let convo = conversationForSession(sessionId: sessionId) else { return }
        let msg = ConversationMessage(text: "\(from): \(message)", type: .peerMessage, conversation: convo)
        msg.toolName = channelId
        ctx.insert(msg)
        try? ctx.save()
    }

    private func persistDelegationEvent(sessionId: String, from: String, to: String, task: String) {
        guard let ctx = modelContext,
              let convo = conversationForSession(sessionId: sessionId) else { return }
        let msg = ConversationMessage(
            text: "\(from) → \(to): \(task)",
            type: .delegation,
            conversation: convo
        )
        ctx.insert(msg)
        try? ctx.save()
    }

    private func persistBlackboardUpdate(sessionId: String, key: String, value: String, writtenBy: String) {
        guard let ctx = modelContext else { return }

        // Upsert BlackboardEntry
        let descriptor = FetchDescriptor<BlackboardEntry>(predicate: #Predicate { entry in
            entry.key == key
        })
        if let existing = try? ctx.fetch(descriptor).first {
            existing.value = value
            existing.writtenBy = writtenBy
            existing.updatedAt = Date()
        } else {
            let entry = BlackboardEntry(key: key, value: value, writtenBy: writtenBy)
            ctx.insert(entry)
        }

        // Also inject as ConversationMessage in the source session's conversation
        if let convo = conversationForSession(sessionId: sessionId) {
            let preview = value.count > 100 ? String(value.prefix(100)) + "…" : value
            let msg = ConversationMessage(
                text: "\(writtenBy) wrote \(key): \(preview)",
                type: .blackboardUpdate,
                conversation: convo
            )
            msg.toolName = key
            msg.toolInput = writtenBy
            ctx.insert(msg)
        }
        try? ctx.save()
    }

    private func persistTaskEvent(sessionId: String?, task: TaskWireSwift, action: String) {
        guard let ctx = modelContext, let sid = sessionId,
              let convo = conversationForSession(sessionId: sid) else { return }
        let statusLabel = action == "created" ? "Created" : action.capitalized
        let msg = ConversationMessage(
            text: "\(statusLabel): \(task.title)",
            type: .taskEvent,
            conversation: convo
        )
        msg.toolName = task.priority
        ctx.insert(msg)
        try? ctx.save()
    }

    private func persistWorkspaceEvent(sessionId: String, workspaceName: String, agentName: String, action: String) {
        guard let ctx = modelContext,
              let convo = conversationForSession(sessionId: sessionId) else { return }
        let msg = ConversationMessage(
            text: "\(agentName) \(action) workspace \"\(workspaceName)\"",
            type: .workspaceEvent,
            conversation: convo
        )
        ctx.insert(msg)
        try? ctx.save()
    }

    private func persistAgentInvite(sessionId: String, invitedAgent: String, invitedBy: String) {
        guard let ctx = modelContext,
              let convo = conversationForSession(sessionId: sessionId) else { return }
        let msg = ConversationMessage(
            text: "\(invitedBy) invited \(invitedAgent)",
            type: .agentInvite,
            conversation: convo
        )
        ctx.insert(msg)
        try? ctx.save()
    }

    // MARK: - Transport inbound

    @MainActor
    private func handleInboundTransportMessage(_ msg: InboundTransportMessage) async {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<Conversation>()
        let conversations = (try? context.fetch(descriptor)) ?? []
        guard let conversation = conversations.first(where: {
            $0.roomOriginMatrixId == msg.roomId
        }) else {
            logger.warning("AppState: no conversation found for Matrix room \(msg.roomId)")
            return
        }
        await sharedRoomService?.applyRemoteTransportMessage(msg, to: conversation, context: context)
    }
}
