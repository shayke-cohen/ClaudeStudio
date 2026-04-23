import SwiftUI
import SwiftData
import WebKit

import OSLog
import OdysseyCore

private let logger = Logger(subsystem: "com.odyssey.app", category: "AppState")

@Observable
@MainActor
final class AppState {
    enum SidecarCommandError: Error {
        case unavailable
    }

    enum SidecarStatus: Equatable {
        case disconnected
        case connecting
        case connected
        case error(String)
    }

    var sidecarStatus: SidecarStatus = .disconnected
    var activeSessions: [UUID: SessionInfo] = [:]

    /// Conversation IDs currently visible in any window — used for notification/unread gating.
    var visibleConversationIds: Set<UUID> = []
    var streamingText: [String: String] = [:]
    private var streamingTokens: [String: [String]] = [:]
    var thinkingText: [String: String] = [:]
    var streamingImages: [String: [(data: String, mediaType: String)]] = [:]
    var streamingFileCards: [String: [(path: String, type: String, name: String)]] = [:]
    var lastSessionEvent: [String: SessionEventKind] = [:]
    private(set) var allocatedWsPort: Int = 0
    private(set) var allocatedHttpPort: Int = 0

    var toolCalls: [String: [ToolCallInfo]] = [:]
    var sessionActivity: [String: SessionActivityState] = [:]
    var commsEvents: [CommsEvent] = []
    var fileTreeRefreshTrigger: Int = 0
    /// Set when gh.issue.created fires — sheet observes this to dismiss on success
    var lastCreatedIssueUrl: String? = nil
    var generatedAgentSpec: GeneratedAgentSpec?
    var isGeneratingAgent: Bool = false
    var generateAgentError: String?
    var generatedGroupSpec: GeneratedGroupSpec?
    var isGeneratingGroup: Bool = false
    var generateGroupError: String?
    var generatedSkillSpec: GeneratedSkillSpec?
    var isGeneratingSkill: Bool = false
    var generateSkillError: String?
    var generatedTemplateSpec: GeneratedTemplateSpec?
    var isGeneratingTemplate: Bool = false
    var generateTemplateError: String?
    /// Set to true to open the "Add to Residents" sheet. AppXray tests use setState to set this.
    var showAddResidentSheet: Bool = false
    /// Set to true to open the Add Agents to Chat sheet in the active ChatView. AppXray tests use setState to set this.
    var showAddAgentsToChatSheet: Bool = false
    /// Set to true to open the Agent Creation sheet from sidebar. AppXray tests use setState to set this.
    var showAgentCreationSheet: Bool = false
    /// Set to true to open the Group Creation sheet from sidebar. AppXray tests use setState to set this.
    var showGroupCreationSheet: Bool = false
    /// Sidebar search text — exposed to AppXray for UI testing.
    var sidebarSearchText: String = ""

    var pendingQuestions: [String: AgentQuestion] = [:]
    var pendingConfirmations: [String: AgentConfirmation] = [:]
    var progressTrackers: [String: ProgressTracker] = [:]
    var pendingSuggestions: [String: [SuggestionItem]] = [:]
    var completedPlans: [String: CompletedPlan] = [:]
    var idleResults: [String: ConversationIdleResult] = [:]
    var evaluatingConversations: Set<String> = []
    private(set) var workerStandbySessions: Set<String> = []
    var presenceStore: [String: PresenceStatus] = [:]
    /// Nostr public key hex (x-only, BIP-340) for this instance — used in invite generation.
    var nostrPublicKeyHex: String? = nil
    /// Number of currently connected Nostr relays (updated via nostr.status events).
    var nostrRelayCount: Int = 0
    /// Total number of configured Nostr relays.
    var nostrRelayTotal: Int = 0
    /// Odyssey instances discovered via the Nostr directory (in-memory, rebuilt on each launch).
    var nostrDirectoryPeers: [DirectoryPeer] = []

    struct DirectoryPeer: Identifiable, Sendable {
        var id: String { pubkeyHex }
        let pubkeyHex: String
        let displayName: String
        let relays: [String]
        let agents: [String]
        let seenAt: Date
    }
    // launchError and autoSendText moved to WindowState (per-window)

    /// File-based config sync service (set by OdysseyApp on appear)
    var configSyncService: ConfigSyncService?
    weak var sharedRoomService: SharedRoomService?

    var createdSessions: Set<String> = []
    var generateAgentRequestId: String?
    var generateGroupRequestId: String?
    var generateSkillRequestId: String?
    var generateTemplateRequestId: String?

    /// Session IDs for shared-room sessions created via the test API (no ChatView to persist responses).
    /// AppState auto-persists agent messages for sessions in this set on `sessionResult`.
    var sharedRoomAutoFinalizeSessionIds: Set<String> = []

    // MARK: - Voice
    let voiceInput = VoiceInputService()
    let tts = TextToSpeechService()
    var isVoiceModeActive: Bool = false

    // MARK: - Browser state (keyed by sessionId)
    var browserControllers: [String: WKWebViewBrowserController] = [:]
    var browserCoordinators: [String: BrowserOverlayCoordinator] = [:]
    var activeBrowserSessionId: String? = nil
    var activeBrowserPanelVisible: Bool = false
    /// Tracks session IDs for which a `.browserSession` inline card has already been emitted,
    /// so we only ever emit one card per browser session.
    private var browserSessionMessageEmitted: Set<String> = []

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

    enum SessionEventKind: Equatable {
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
    private var pendingTokenCounts: [UUID: Int] = [:]
    private var pendingPersistFlushTask: Task<Void, Never>?

    private(set) var sidecarManager: SidecarManager?
    private var nostrEventRelay: NostrEventRelay?
    private var eventTask: Task<Void, Never>?
    private var conversationSyncTimer: Task<Void, Never>?
    var modelContext: ModelContext?
    private(set) var transportManager: TransportManager
    private(set) var scheduleEngine: ScheduleEngine?
    private(set) var scheduleRunCoordinator: ScheduleRunCoordinator?
    #if DEBUG
    var commandCaptureForTesting: ((SidecarCommand) -> Void)?
    var commandSendOverrideForTesting: ((SidecarCommand) async -> Void)?
    #endif

    init() {
        self.transportManager = TransportManager(instanceName: InstanceConfig.name)
        transportManager.onPresenceChanged = { @MainActor [weak self] userId, status in
            self?.presenceStore[userId] = status
        }
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
            conversation.participants = (conversation.participants ?? []) + [userParticipant]

            if intent.prompt != nil || launchMode != .interactive {
                let freeformSession = Session(
                    agent: nil,
                    mission: intent.prompt,
                    mode: sessionMode(for: launchMode),
                    workingDirectory: projectDir
                )
                freeformSession.conversations = [conversation]
                conversation.sessions = (conversation.sessions ?? []) + [freeformSession]
                let agentParticipant = Participant(
                    type: .agentSession(sessionId: freeformSession.id),
                    displayName: AgentDefaults.displayName(forProvider: freeformSession.provider)
                )
                agentParticipant.conversation = conversation
                conversation.participants = (conversation.participants ?? []) + [agentParticipant]
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
            let payload = try InvitePayload.decode(encoded)
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

        // Resolve only the agents that belong to this group — avoids a full-table scan.
        let groupAgentIds = group.agentIds
        let agentDescriptor = FetchDescriptor<Agent>(
            predicate: #Predicate { groupAgentIds.contains($0.id) }
        )
        let fetchedAgents = (try? modelContext.fetch(agentDescriptor)) ?? []
        guard !fetchedAgents.isEmpty else { return nil }
        // Preserve the ordering defined in group.agentIds.
        let agentById = Dictionary(uniqueKeysWithValues: fetchedAgents.map { ($0.id, $0) })
        let resolvedAgents = groupAgentIds.compactMap { agentById[$0] }

        // Phase 1 — fast stub: create conversation and navigate immediately.
        let conversation = Conversation(
            topic: executionMode == .autonomous ? "\(group.name) — Autonomous" : nil,
            projectId: projectId,
            threadKind: executionMode == .autonomous ? .autonomous : .group
        )
        conversation.routingMode = .mentionAware
        conversation.sourceGroupId = group.id
        conversation.executionMode = executionMode
        conversation.goal = missionOverride.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }

        let userParticipant = Participant(type: .user, displayName: "You")
        userParticipant.conversation = conversation
        conversation.participants = (conversation.participants ?? []) + [userParticipant]

        let instruction = group.groupInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        if !instruction.isEmpty {
            let sysMsg = ConversationMessage(
                senderParticipantId: nil,
                text: instruction,
                type: .system,
                conversation: conversation
            )
            conversation.messages = (conversation.messages ?? []) + [sysMsg]
        }

        modelContext.insert(conversation)
        let conversationId = conversation.id

        // Phase 2 — deferred: provision agents, seed vault, save. Still @MainActor so no
        // data races with SwiftData, but runs after the caller has navigated to the conversation.
        let trimmedMissionOverride = missionOverride?.trimmingCharacters(in: .whitespacesAndNewlines)
        let mission = (trimmedMissionOverride?.isEmpty == false ? trimmedMissionOverride : nil) ?? group.defaultMission
        let sharedGroupDir: String = {
            if let groupHome = group.defaultWorkingDirectory, !groupHome.isEmpty {
                return (groupHome as NSString).expandingTildeInPath
            }
            return projectDirectory
        }()
        let execMode = executionMode

        Task { @MainActor [weak self] in
            guard let self else { return }
            if !sharedGroupDir.isEmpty {
                ResidentAgentSupport.seedGroupVaultIfNeeded(
                    in: sharedGroupDir,
                    groupName: group.name,
                    agentNames: resolvedAgents.map(\.name)
                )
            }
            let provisioner = AgentProvisioner(modelContext: modelContext)
            for agent in resolvedAgents {
                let (_, session) = provisioner.provision(
                    agent: agent,
                    mission: mission,
                    mode: sessionMode(for: execMode),
                    workingDirOverride: sharedGroupDir.isEmpty ? nil : sharedGroupDir
                )
                session.conversations = [conversation]
                conversation.sessions = (conversation.sessions ?? []) + [session]

                let agentParticipant = Participant(
                    type: .agentSession(sessionId: session.id),
                    displayName: agent.name
                )
                agentParticipant.conversation = conversation
                conversation.participants = (conversation.participants ?? []) + [agentParticipant]
                modelContext.insert(session)
            }
            try? modelContext.save()
            await sidecarManager?.pushConversationSync(modelContext: modelContext)
        }

        return conversationId
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

        let updates = (conversation.sessions ?? []).map { session -> (sessionId: String, settings: AgentProvisioner.RuntimeModeSettings) in
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
        guard let primarySession = (conversation.sessions ?? []).min(by: { $0.startedAt < $1.startedAt }) else { return }
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

        let agentNamesForDirectory: [String]
        if let ctx = modelContext {
            let descriptor = FetchDescriptor<Agent>()
            agentNamesForDirectory = ((try? ctx.fetch(descriptor)) ?? []).map { $0.name }
        } else {
            agentNamesForDirectory = []
        }

        let config = SidecarManager.Config(
            wsPort: wsPort,
            httpPort: httpPort,
            logDirectory: InstanceConfig.logDirectory.path,
            dataDirectory: InstanceConfig.baseDirectory.path,
            bunPathOverride: bunOverride?.isEmpty == true ? nil : bunOverride,
            sidecarPathOverride: sidecarPathOverride?.isEmpty == true ? nil : sidecarPathOverride,
            localAgentHostPathOverride: localAgentHostOverride?.isEmpty == true ? nil : localAgentHostOverride,
            mlxRunnerPathOverride: mlxRunnerOverride?.isEmpty == true ? nil : mlxRunnerOverride,
            instanceName: InstanceConfig.name,
            agentNames: agentNamesForDirectory
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
                startNostrRelay(for: manager)
                // Conversation sync and timer are handled by the .connected event handler
                // which fires from the sidecar.ready handshake during start().
            } catch {
                sidecarStatus = .error(error.localizedDescription)
            }
        }
    }

    func disconnectSidecar() {
        eventTask?.cancel()
        eventTask = nil
        nostrEventRelay?.stop()
        nostrEventRelay = nil
        sidecarManager?.stop()
        sidecarManager = nil
        sidecarStatus = .disconnected
    }

    private func startNostrRelay(for manager: SidecarManager) {
        guard let kp = try? IdentityManager.shared.nostrKeypair(for: InstanceConfig.name) else { return }
        let relays = AppSettings.nostrRelays()
        let relay = NostrEventRelay(sidecarManager: manager)
        nostrEventRelay = relay
        relay.start(privkeyHex: kp.privkeyHex, pubkeyHex: kp.pubkeyHex, relays: relays)
        // Publish Nostr directory profile if enabled (default: enabled when key is absent)
        let rawValue = InstanceConfig.userDefaults.object(forKey: AppSettings.nostrDirectoryEnabledKey)
        let directoryEnabled = rawValue == nil ? true : InstanceConfig.userDefaults.bool(forKey: AppSettings.nostrDirectoryEnabledKey)
        guard directoryEnabled else { return }
        let displayName = InstanceConfig.userDefaults.string(forKey: AppSettings.sharedRoomDisplayNameKey)
            ?? Host.current().localizedName
            ?? "Odyssey"
        let agentNames: [String]
        if let ctx = modelContext {
            let descriptor = FetchDescriptor<Agent>()
            agentNames = ((try? ctx.fetch(descriptor)) ?? []).map { $0.name }
        } else {
            agentNames = []
        }
        Task {
            try? await manager.send(.nostrProfilePublish(displayName: displayName, agentNames: agentNames))
        }
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
              let convo = (session.conversations ?? []).first else { return }

        let agentName = session.agent?.name ?? "Agent"
        let agentParticipant = (convo.participants ?? []).first { p in
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
        convo.messages = (convo.messages ?? []) + [msg]
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
              let convo = (session.conversations ?? []).first else { return }

        let agentParticipant = (convo.participants ?? []).first { p in
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
        convo.messages = (convo.messages ?? []) + [msg]
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
              let convo = (session.conversations ?? []).first else { return }

        let agentParticipant = (convo.participants ?? []).first { p in
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
        convo.messages = (convo.messages ?? []) + [msg]
        ctx.insert(msg)
        schedulePersistentSave()
    }

    private func resolvedGenerationModel() -> String {
        let provider = AgentDefaults.defaultProvider()
        if provider == ProviderSelection.claude.rawValue || provider == ProviderSelection.system.rawValue {
            return AgentDefaults.defaultModel(for: ProviderSelection.claude.rawValue)
        }
        return AgentDefaults.defaultModel(for: ProviderSelection.claude.rawValue)
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
            availableMCPs: mcps,
            model: resolvedGenerationModel()
        ))
    }

    func requestGroupGeneration(prompt: String, agents: [AgentCatalogEntry]) {
        let requestId = UUID().uuidString
        generateGroupRequestId = requestId
        isGeneratingGroup = true
        generateGroupError = nil
        generatedGroupSpec = nil
        sendToSidecar(.generateGroup(
            requestId: requestId,
            prompt: prompt,
            availableAgents: agents,
            model: resolvedGenerationModel()
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
            availableMCPs: mcps,
            model: resolvedGenerationModel()
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
            agentSystemPrompt: agentSystemPrompt,
            model: resolvedGenerationModel()
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

    func sendGHPollerConfig() {
        let settings = GHPollerSettings.shared
        guard !settings.inboxRepo.isEmpty || !settings.trustedGitHubUsers.isEmpty else { return }

        var projectRepos: [GHProjectRepoWire] = []
        if let ctx = modelContext,
           let projects = try? ctx.fetch(FetchDescriptor<Project>()) {
            for project in projects {
                guard let repo = project.githubRepo, !repo.isEmpty else { continue }
                var agentName: String? = nil
                if let agentId = project.githubDefaultAgentId,
                   let agent = try? ctx.fetch(FetchDescriptor<Agent>(predicate: #Predicate { $0.id == agentId })).first {
                    agentName = agent.name
                }
                let trusted = project.githubTrustedUsers.isEmpty ? settings.trustedGitHubUsers : project.githubTrustedUsers
                projectRepos.append(GHProjectRepoWire(repo: repo, defaultAgentName: agentName, trustedUsers: trusted))
            }
        }

        sendToSidecar(.ghPollerConfig(
            inboxRepo: settings.inboxRepo,
            projectRepos: projectRepos,
            trustedUsers: settings.trustedGitHubUsers,
            intervalSeconds: settings.pollIntervalSeconds
        ))
        Log.appState.info("Sent GH poller config: inbox=\(settings.inboxRepo), projects=\(projectRepos.count)")
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
        let sessionStates: [(agentName: String, state: SessionActivityState)] = (conversation.sessions ?? []).map { session in
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
                    coordinatorSessionId = (freshConvo.sessions ?? [])
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
                sessionIds: (freshConvo.sessions ?? []).map { $0.id.uuidString }
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

    // MARK: - Browser helpers

    @MainActor
    func browserController(for sessionId: String) -> WKWebViewBrowserController {
        if let existing = browserControllers[sessionId] { return existing }

        // Determine session mode from project settings via the session's conversation
        var mode: BrowserSessionStore.SessionMode = .project
        var storeKey: String = sessionId
        if let convo = conversationForSession(sessionId: sessionId),
           let projectId = convo.projectId,
           let ctx = modelContext {
            let descriptor = FetchDescriptor<Project>(predicate: #Predicate { p in p.id == projectId })
            if let project = try? ctx.fetch(descriptor).first {
                mode = BrowserSessionStore.SessionMode(rawValue: project.browserSessionMode) ?? .project
                switch mode {
                case .project:
                    storeKey = projectId.uuidString
                case .thread:
                    storeKey = sessionId
                }
            }
        }

        let store = BrowserSessionStore.shared.store(for: storeKey)
        let controller = WKWebViewBrowserController(dataStore: store)
        browserControllers[sessionId] = controller
        browserCoordinators[sessionId] = BrowserOverlayCoordinator()
        return controller
    }

    /// Emits a `.browserSession` ConversationMessage into the session's conversation the first
    /// time a browser event fires for a given `sessionId`. Subsequent calls for the same
    /// sessionId are no-ops (guarded by `browserSessionMessageEmitted`).
    private func emitBrowserSessionCardIfNeeded(sessionId: String) {
        guard !browserSessionMessageEmitted.contains(sessionId) else { return }
        guard let ctx = modelContext, let uuid = UUID(uuidString: sessionId) else { return }

        let descriptor = FetchDescriptor<Session>(predicate: #Predicate { s in s.id == uuid })
        guard let session = try? ctx.fetch(descriptor).first,
              let convo = session.conversations?.first else { return }

        browserSessionMessageEmitted.insert(sessionId)

        let msg = ConversationMessage(
            senderParticipantId: nil,
            text: "Browser session started",
            type: .browserSession,
            conversation: convo
        )
        msg.toolOutput = sessionId
        convo.messages = (convo.messages ?? []) + [msg]
        ctx.insert(msg)
        try? ctx.save()

        let convId = convo.id
        Task { await sidecarManager?.pushMessageAppend(conversationId: convId, message: msg) }
    }

    private func handleEvent(_ event: SidecarEvent) {
        switch event {
        case .streamToken(let sessionId, let text):
            streamingTokens[sessionId, default: []].append(text)
            // Append directly instead of O(n) re-join on every token
            if streamingText[sessionId] != nil {
                streamingText[sessionId]!.append(text)
            } else {
                streamingText[sessionId] = text
            }
            if let uuid = ensureActiveSessionInfo(sessionId: sessionId) {
                if activeSessions[uuid]?.isStreaming != true {
                    activeSessions[uuid]?.isStreaming = true
                }
                // Batch token count — only publish every ~10 tokens to reduce dictionary mutations
                pendingTokenCounts[uuid, default: 0] += max(1, text.count / 4)
                if pendingTokenCounts[uuid, default: 0] >= 10 {
                    activeSessions[uuid]?.tokenCount += pendingTokenCounts[uuid]!
                    pendingTokenCounts[uuid] = 0
                }
            }
            if sessionActivity[sessionId] != .streaming {
                sessionActivity[sessionId] = .streaming
            }

        case .streamThinking(let sessionId, let text):
            let current = thinkingText[sessionId] ?? ""
            thinkingText[sessionId] = current + text
            if let uuid = ensureActiveSessionInfo(sessionId: sessionId) {
                activeSessions[uuid]?.isStreaming = true
            }
            if sessionActivity[sessionId] != .thinking {
                sessionActivity[sessionId] = .thinking
            }

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
                // Flush any pending batched token counts before overwriting with final values
                pendingTokenCounts.removeValue(forKey: uuid)
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
            streamingTokens.removeValue(forKey: sessionId)
            clearPendingUserInput(for: sessionId)
            sessionActivity[sessionId] = .done
            handleVoiceModeCompletion(sessionId: sessionId)
            checkConversationIdle(for: sessionId)
            notifyIfNeeded(sessionId: sessionId) { name, topic in
                ChatNotificationManager.shared.notifySessionCompleted(agentName: name, conversationTopic: topic)
            }
            // Flush any coalesced peer/blackboard saves before the batched completion save
            flushPendingPersistentSave()
            // Batch session-end persistence into one fetch + one save instead of 3 separate cycles
            persistSessionCompletion(sessionId: sessionId, status: .completed, tokenCount: tokenCount, cost: cost, toolCallCount: toolCallCount)
            cleanupWorktreeIfNeeded(sessionId: sessionId)
            if sharedRoomAutoFinalizeSessionIds.contains(sessionId) {
                sharedRoomAutoFinalizeSessionIds.remove(sessionId)
                finalizeSharedRoomAgentMessage(sessionId: sessionId)
            }
            if let ctx = modelContext {
                Task { await sidecarManager?.pushConversationSync(modelContext: ctx) }
            }

        case .sessionError(let sessionId, let error):
            // Stale session references from previous app sessions are harmless — clean up silently.
            if error.contains("Session not found") {
                Log.appState.debug("Session \(sessionId, privacy: .public): stale reference, cleaning up")
                thinkingText.removeValue(forKey: sessionId)
                streamingTokens.removeValue(forKey: sessionId)
                streamingImages.removeValue(forKey: sessionId)
                streamingFileCards.removeValue(forKey: sessionId)
                clearPendingUserInput(for: sessionId)
                workerStandbySessions.remove(sessionId)
                break
            }
            workerStandbySessions.remove(sessionId)
            if let uuid = ensureActiveSessionInfo(sessionId: sessionId) {
                activeSessions[uuid]?.isStreaming = false
            }
            lastSessionEvent[sessionId] = .error(error)
            thinkingText.removeValue(forKey: sessionId)
            streamingTokens.removeValue(forKey: sessionId)
            streamingImages.removeValue(forKey: sessionId)
            streamingFileCards.removeValue(forKey: sessionId)
            clearPendingUserInput(for: sessionId)
            sessionActivity[sessionId] = .error(error)
            checkConversationIdle(for: sessionId)
            notifyIfNeeded(sessionId: sessionId) { name, _ in
                ChatNotificationManager.shared.notifySessionError(agentName: name, error: error)
            }
            Log.appState.error("Session \(sessionId, privacy: .public) error: \(error, privacy: .public)")
            flushPendingPersistentSave()
            persistSessionCompletion(sessionId: sessionId, status: .failed)
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

        case .generatedGroup(let requestId, let spec):
            guard requestId == generateGroupRequestId else { return }
            generatedGroupSpec = spec
            isGeneratingGroup = false
            generateGroupRequestId = nil

        case .generateGroupError(let requestId, let error):
            guard requestId == generateGroupRequestId else { return }
            generateGroupError = error
            isGeneratingGroup = false
            generateGroupRequestId = nil
            Log.appState.error("Group generation error: \(error, privacy: .public)")

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

        case .taskCreated, .taskUpdated, .taskListResult:
            break

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

        case .nostrDirectoryPeer(let pubkeyHex, let displayName, let relays, let agents, let seenAt):
            let entry = DirectoryPeer(
                pubkeyHex: pubkeyHex,
                displayName: displayName,
                relays: relays,
                agents: agents,
                seenAt: ISO8601DateFormatter().date(from: seenAt) ?? Date()
            )
            if let idx = nostrDirectoryPeers.firstIndex(where: { $0.pubkeyHex == pubkeyHex }) {
                nostrDirectoryPeers[idx] = entry
            } else {
                nostrDirectoryPeers.append(entry)
            }

        case .nostrDMReceived(let senderPubkeyHex, let conversationId, let text, let senderName):
            guard let ctx = modelContext else { break }
            // Find the conversation by ID first, fall back to locating any conversation with this peer
            let convUUID = UUID(uuidString: conversationId)
            let allConvos = (try? ctx.fetch(FetchDescriptor<Conversation>())) ?? []
            let targetConvo: Conversation? = allConvos.first { c in
                if let uuid = convUUID, c.id == uuid { return true }
                return (c.participants ?? []).contains {
                    $0.typeKind == "nostrPeer" && $0.typeParticipantId == senderPubkeyHex
                }
            }
            guard let convo = targetConvo else { break }
            // Find or create the peer participant as message sender
            var peerParticipant = (convo.participants ?? []).first {
                $0.typeKind == "nostrPeer" && $0.typeParticipantId == senderPubkeyHex
            }
            if peerParticipant == nil {
                let name = senderName ?? String(senderPubkeyHex.prefix(12))
                let newParticipant = Participant(
                    type: .nostrPeer(pubkeyHex: senderPubkeyHex),
                    displayName: name
                )
                newParticipant.conversation = convo
                convo.participants = (convo.participants ?? []) + [newParticipant]
                ctx.insert(newParticipant)
                peerParticipant = newParticipant
            }
            let msg = ConversationMessage(
                senderParticipantId: peerParticipant?.id,
                text: text,
                type: .chat,
                conversation: convo
            )
            convo.messages = (convo.messages ?? []) + [msg]
            ctx.insert(msg)
            try? ctx.save()

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
                for msg in (convo.messages ?? []) { ctx.delete(msg) }
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
            registerAgentDefinitions()
            registerConnections()
            sendGHPollerConfig()
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
                        await self.sidecarManager?.pushConversationSync(modelContext: ctx, pushMessages: false)
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

        // ─── Browser event handlers ───────────────────────────────────────────

        case .browserNavigate(let sessionId, let url):
            activeBrowserSessionId = sessionId
            emitBrowserSessionCardIfNeeded(sessionId: sessionId)
            Task {
                let controller = browserController(for: sessionId)
                browserCoordinators[sessionId]?.logAction("Navigate: \(url)")
                do {
                    struct NavigatePayload: Codable {
                        let title: String
                        let finalUrl: String
                    }
                    let result = try await controller.navigate(to: URL(string: url) ?? URL(string: "about:blank")!)
                    let payloadData = try JSONEncoder().encode(NavigatePayload(title: result.title, finalUrl: result.finalURL.absoluteString))
                    let payload = String(data: payloadData, encoding: .utf8) ?? "{}"
                    sendToSidecar(.browserResult(sessionId: sessionId, commandType: "browser.navigate", payload: payload))
                } catch {
                    sendToSidecar(.browserError(sessionId: sessionId, commandType: "browser.navigate", error: error.localizedDescription))
                }
            }

        case .browserClick(let sessionId, let selector):
            Task {
                let controller = browserController(for: sessionId)
                browserCoordinators[sessionId]?.logAction("Click: \(selector)")
                do {
                    try await controller.click(selector: selector)
                    sendToSidecar(.browserResult(sessionId: sessionId, commandType: "browser.click", payload: "{}"))
                } catch {
                    sendToSidecar(.browserError(sessionId: sessionId, commandType: "browser.click", error: error.localizedDescription))
                }
            }

        case .browserType(let sessionId, let selector, let text):
            Task {
                let controller = browserController(for: sessionId)
                browserCoordinators[sessionId]?.logAction("Type into: \(selector)")
                do {
                    try await controller.type(selector: selector, text: text)
                    sendToSidecar(.browserResult(sessionId: sessionId, commandType: "browser.type", payload: "{}"))
                } catch {
                    sendToSidecar(.browserError(sessionId: sessionId, commandType: "browser.type", error: error.localizedDescription))
                }
            }

        case .browserScroll(let sessionId, let direction, let px):
            Task {
                let controller = browserController(for: sessionId)
                let dir: ScrollDirection = direction == "up" ? .up : .down
                browserCoordinators[sessionId]?.logAction("Scroll \(direction) \(px)px")
                do {
                    try await controller.scroll(direction: dir, px: px)
                    sendToSidecar(.browserResult(sessionId: sessionId, commandType: "browser.scroll", payload: "{}"))
                } catch {
                    sendToSidecar(.browserError(sessionId: sessionId, commandType: "browser.scroll", error: error.localizedDescription))
                }
            }

        case .browserScreenshot(let sessionId):
            Task {
                let controller = browserController(for: sessionId)
                do {
                    let data = try await controller.screenshot()
                    let b64 = data.base64EncodedString()
                    sendToSidecar(.browserResult(sessionId: sessionId, commandType: "browser.screenshot", payload: b64))
                } catch {
                    sendToSidecar(.browserError(sessionId: sessionId, commandType: "browser.screenshot", error: error.localizedDescription))
                }
            }

        case .browserReadDom(let sessionId):
            Task {
                let controller = browserController(for: sessionId)
                do {
                    let dom = try await controller.readDOM()
                    sendToSidecar(.browserResult(sessionId: sessionId, commandType: "browser.readDom", payload: dom))
                } catch {
                    sendToSidecar(.browserError(sessionId: sessionId, commandType: "browser.readDom", error: error.localizedDescription))
                }
            }

        case .browserGetConsoleLogs(let sessionId):
            Task {
                let controller = browserController(for: sessionId)
                do {
                    let logs = try await controller.getConsoleLogs()
                    let data = try JSONEncoder().encode(logs)
                    let str = String(data: data, encoding: .utf8) ?? "[]"
                    sendToSidecar(.browserResult(sessionId: sessionId, commandType: "browser.getConsoleLogs", payload: str))
                } catch {
                    sendToSidecar(.browserError(sessionId: sessionId, commandType: "browser.getConsoleLogs", error: error.localizedDescription))
                }
            }

        case .browserGetNetworkLogs(let sessionId):
            Task {
                let controller = browserController(for: sessionId)
                do {
                    let logs = try await controller.getNetworkLogs()
                    struct NetworkEntryEncodable: Codable {
                        let url: String
                        let statusCode: Int?
                    }
                    let encodable = logs.map { NetworkEntryEncodable(url: $0.url, statusCode: $0.statusCode) }
                    let data = try JSONEncoder().encode(encodable)
                    let str = String(data: data, encoding: .utf8) ?? "[]"
                    sendToSidecar(.browserResult(sessionId: sessionId, commandType: "browser.getNetworkLogs", payload: str))
                } catch {
                    sendToSidecar(.browserError(sessionId: sessionId, commandType: "browser.getNetworkLogs", error: error.localizedDescription))
                }
            }

        case .browserWaitFor(let sessionId, let selector, let timeoutMs):
            Task {
                let controller = browserController(for: sessionId)
                do {
                    try await controller.waitFor(selector: selector, timeoutMs: timeoutMs)
                    sendToSidecar(.browserResult(sessionId: sessionId, commandType: "browser.waitFor", payload: "{}"))
                } catch {
                    sendToSidecar(.browserError(sessionId: sessionId, commandType: "browser.waitFor", error: error.localizedDescription))
                }
            }

        case .browserYieldToUser(let sessionId, let message):
            Task {
                let controller = browserController(for: sessionId)
                let coordinator = browserCoordinators[sessionId]
                coordinator?.agentYielded(message: message, controller: controller)
                do {
                    try await controller.yieldToUser(message: message)
                    sendToSidecar(.browserResult(sessionId: sessionId, commandType: "browser.yieldToUser", payload: "\"User resumed\""))
                } catch {
                    sendToSidecar(.browserError(sessionId: sessionId, commandType: "browser.yieldToUser", error: error.localizedDescription))
                }
            }

        case .browserRenderHtml(let sessionId, let html, _):
            activeBrowserSessionId = sessionId
            emitBrowserSessionCardIfNeeded(sessionId: sessionId)
            Task {
                let controller = browserController(for: sessionId)
                browserCoordinators[sessionId]?.logAction("Render HTML")
                do {
                    let result = try await controller.renderHTML(html, title: nil)
                    sendToSidecar(.browserResult(sessionId: sessionId, commandType: "browser.renderHtml", payload: result))
                } catch {
                    sendToSidecar(.browserError(sessionId: sessionId, commandType: "browser.renderHtml", error: error.localizedDescription))
                }
            }

        case .browserTakeControl(let sessionId):
            _ = browserCoordinators[sessionId]?.userTookOver()
            sendToSidecar(.browserStateChange(sessionId: sessionId, state: "userDriving"))

        case .browserResume(let sessionId):
            if let controller = browserControllers[sessionId] {
                _ = browserCoordinators[sessionId]?.userResumed(controller: controller)
            } else {
                logger.warning("AppState: browserResume: no controller for sessionId \(sessionId)")
            }
            sendToSidecar(.browserStateChange(sessionId: sessionId, state: "agentDriving"))

        case .pairingConfirmed:
            Log.appState.info("Pairing confirmed")

        case .scheduleCreate(let payload):
            handleScheduleCreate(payload: payload)
        case .scheduleUpdate(let scheduleId, let payload):
            handleScheduleUpdate(scheduleId: scheduleId, payload: payload)
        case .scheduleDelete(let scheduleId):
            handleScheduleDelete(scheduleId: scheduleId)
        case .scheduleTrigger(let scheduleId):
            handleScheduleTrigger(scheduleId: scheduleId)

        case .ghIssueTriggered(let issueUrl, let issueNumber, let repo, let title, let conversationId, let sessionId, let agentName):
            Log.github.info("gh.issue.triggered #\(issueNumber, privacy: .public) \(repo, privacy: .public) conv=\(conversationId, privacy: .public)")
            handleGHIssueTriggered(issueUrl: issueUrl, issueNumber: issueNumber, repo: repo, title: title, conversationId: conversationId, sessionId: sessionId, agentName: agentName)

        case .ghIssueComment(_, let commentBody, let author, let conversationId):
            Log.github.info("gh.issue.comment from \(author, privacy: .public) conv=\(conversationId, privacy: .public)")
            handleGHIssueComment(commentBody: commentBody, author: author, conversationId: conversationId)

        case .ghIssueCreated(let issueUrl, let issueNumber, let repo, let conversationId):
            Log.github.info("gh.issue.created #\(issueNumber, privacy: .public) \(repo, privacy: .public)")
            handleGHIssueCreated(issueUrl: issueUrl, issueNumber: issueNumber, repo: repo, conversationId: conversationId)

        case .ghIssueClosed(let repo, let number):
            Log.github.info("gh.issue.closed #\(number, privacy: .public) \(repo, privacy: .public)")
            handleGHIssueClosed(repo: repo, number: number)
        }
    }

    // MARK: - GitHub Issue Bridge Event Handlers

    @MainActor
    private func handleGHIssueTriggered(issueUrl: String, issueNumber: Int, repo: String, title: String, conversationId: String, sessionId: String, agentName: String) {
        guard let ctx = modelContext,
              let convUUID = UUID(uuidString: conversationId),
              let sessUUID = UUID(uuidString: sessionId) else { return }

        // Don't create duplicate if already exists
        let existingDescriptor = FetchDescriptor<Conversation>(predicate: #Predicate { $0.id == convUUID })
        if (try? ctx.fetch(existingDescriptor).first) != nil { return }

        // Look up agent by name
        let agentDescriptor = FetchDescriptor<Agent>(predicate: #Predicate { $0.name == agentName })
        guard let agent = (try? ctx.fetch(agentDescriptor).first) else {
            Log.github.warning("gh.issue.triggered: agent '\(agentName, privacy: .public)' not found in SwiftData")
            return
        }

        // Create Session record matching the sidecar's running session
        let session = Session(agent: agent, mission: "GitHub Issue #\(issueNumber): \(title)", mode: .autonomous, workingDirectory: agent.defaultWorkingDirectory ?? "")
        session.id = sessUUID

        // Create Conversation
        let conversation = Conversation(topic: "GH #\(issueNumber): \(title)", sessions: [session], projectId: nil, threadKind: .autonomous)
        conversation.id = convUUID
        conversation.githubIssueUrl = issueUrl
        conversation.githubIssueNumber = issueNumber
        conversation.githubIssueRepo = repo

        ctx.insert(session)
        ctx.insert(conversation)
        try? ctx.save()

        ChatNotificationManager.shared.notifyGHIssueTriggered(issueNumber: issueNumber, repo: repo, title: title)
        Log.github.info("gh.issue.triggered: created conv=\(conversationId, privacy: .public) sess=\(sessionId, privacy: .public)")
    }

    private func handleGHIssueComment(commentBody: String, author: String, conversationId: String) {
        guard let ctx = modelContext,
              let uuid = UUID(uuidString: conversationId) else { return }
        let descriptor = FetchDescriptor<Conversation>(predicate: #Predicate { $0.id == uuid })
        guard let convo = try? ctx.fetch(descriptor).first,
              let session = convo.primarySession else {
            Log.github.warning("gh.issue.comment: conversation or session not found for id=\(conversationId, privacy: .public)")
            return
        }
        let messageText = "[\(author) via GitHub]: \(commentBody)"
        sendToSidecar(.sessionMessage(sessionId: session.id.uuidString, text: messageText))
    }

    private func handleGHIssueCreated(issueUrl: String, issueNumber: Int, repo: String, conversationId: String?) {
        lastCreatedIssueUrl = issueUrl
        guard let ctx = modelContext,
              let cidStr = conversationId,
              let uuid = UUID(uuidString: cidStr) else { return }
        let descriptor = FetchDescriptor<Conversation>(predicate: #Predicate { $0.id == uuid })
        guard let convo = try? ctx.fetch(descriptor).first else {
            Log.github.warning("gh.issue.created: conversation not found for id=\(cidStr, privacy: .public)")
            return
        }
        convo.githubIssueUrl = issueUrl
        convo.githubIssueNumber = issueNumber
        convo.githubIssueRepo = repo
        try? ctx.save()
        Log.github.info("gh.issue.created: linked conv=\(cidStr, privacy: .public) to issue #\(issueNumber, privacy: .public) in \(repo, privacy: .public)")
    }

    // MARK: - GH Inbox Actions

    @MainActor
    func ghIssueRunNow(_ conv: Conversation, agentOverride: Agent? = nil) {
        guard let ctx = modelContext else { return }

        // Store agent override if provided
        if let override = agentOverride {
            conv.ghOverrideAgentId = override.id
            try? ctx.save()
        }

        // Resolve target agent: override arg → stored override → existing session's agent
        let targetAgent: Agent? = {
            if let a = agentOverride { return a }
            if let overrideId = conv.ghOverrideAgentId {
                let d = FetchDescriptor<Agent>(predicate: #Predicate { $0.id == overrideId })
                if let a = try? ctx.fetch(d).first { return a }
            }
            return conv.primarySession?.agent
        }()

        guard let agent = targetAgent else {
            Log.github.warning("ghIssueRunNow: no agent resolved for conv \(conv.id)")
            return
        }

        let existingSession = conv.primarySession

        // Already running — nothing to do
        if existingSession?.status == .active {
            Log.github.info("ghIssueRunNow: session already active for conv \(conv.id)")
            return
        }

        // Resume if a pausable session with a claudeSessionId exists
        if let session = existingSession,
           let claudeSessionId = session.claudeSessionId,
           session.status == .paused || session.status == .interrupted {
            session.status = .active
            try? ctx.save()
            sendToSidecar(.sessionResume(sessionId: session.id.uuidString, claudeSessionId: claudeSessionId))
            Log.github.info("ghIssueRunNow: resumed session \(session.id) for conv \(conv.id)")
            return
        }

        // Create a new session
        let provisioner = AgentProvisioner(modelContext: ctx)
        let mission = conv.topic ?? conv.githubIssueNumber.map { "GitHub Issue #\($0)" } ?? "GitHub Issue"
        let (config, newSession) = provisioner.provision(agent: agent, mission: mission, mode: .autonomous)

        newSession.conversations = [conv]
        conv.sessions = (conv.sessions ?? []) + [newSession]
        ctx.insert(newSession)
        try? ctx.save()

        sendToSidecar(.sessionCreate(conversationId: newSession.id.uuidString, agentConfig: config))
        Log.github.info("ghIssueRunNow: created session \(newSession.id) for conv \(conv.id)")
    }

    @MainActor
    private func handleGHIssueClosed(repo: String, number: Int) {
        guard let ctx = modelContext else { return }
        let descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate { $0.githubIssueNumber == number && $0.githubIssueRepo == repo }
        )
        guard let conv = (try? ctx.fetch(descriptor))?.first else {
            Log.github.warning("gh.issue.closed: no conversation for #\(number) in \(repo)")
            return
        }
        conv.isArchived = true
        try? ctx.save()
        Log.github.info("gh.issue.closed: archived conv \(conv.id) for #\(number) in \(repo)")
    }

    // MARK: - Schedule Event Handlers

    private func handleScheduleCreate(payload: String) {
        guard let ctx = modelContext,
              let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        let name = json["name"] as? String ?? "New Schedule"
        let targetKindRaw = json["targetKind"] as? String ?? "agent"
        let targetKind = ScheduledMissionTargetKind(rawValue: targetKindRaw) ?? .agent
        let targetName = json["targetName"] as? String ?? ""
        let promptTemplate = json["promptTemplate"] as? String ?? ""
        let projectDirectory = json["projectDirectory"] as? String ?? ""

        // Resolve agent/group ID by name
        var agentId: UUID?
        var groupId: UUID?
        switch targetKind {
        case .agent:
            let d = FetchDescriptor<Agent>()
            agentId = (try? ctx.fetch(d))?.first(where: { $0.name == targetName })?.id
        case .group:
            let d = FetchDescriptor<AgentGroup>()
            groupId = (try? ctx.fetch(d))?.first(where: { $0.name == targetName })?.id
        default: break
        }

        let schedule = ScheduledMission(name: name, targetKind: targetKind, projectDirectory: projectDirectory, promptTemplate: promptTemplate)
        schedule.targetAgentId = agentId
        schedule.targetGroupId = groupId

        if let cadenceRaw = json["cadenceKind"] as? String,
           let cadence = ScheduledMissionCadenceKind(rawValue: cadenceRaw) {
            schedule.cadenceKind = cadence
        }
        if let h = json["intervalHours"] as? Int { schedule.intervalHours = h }
        if let h = json["localHour"] as? Int { schedule.localHour = h }
        if let m = json["localMinute"] as? Int { schedule.localMinute = m }
        if let days = json["daysOfWeek"] as? [String] {
            schedule.daysOfWeek = days.compactMap { label in
                ScheduledMissionWeekday.allCases.first { $0.shortLabel.lowercased() == label.lowercased() }
            }
        }
        if let runModeRaw = json["runMode"] as? String,
           let runMode = ScheduledMissionRunMode(rawValue: runModeRaw) {
            schedule.runMode = runMode
        }
        if let auto = json["usesAutonomousMode"] as? Bool { schedule.usesAutonomousMode = auto }

        ctx.insert(schedule)
        scheduleEngine?.syncSchedule(schedule)
        Log.appState.info("Schedule created: \(name)")
    }

    private func handleScheduleUpdate(scheduleId: String, payload: String) {
        guard let ctx = modelContext,
              let uuid = UUID(uuidString: scheduleId),
              let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let descriptor = FetchDescriptor<ScheduledMission>(predicate: #Predicate { $0.id == uuid })
        guard let schedule = try? ctx.fetch(descriptor).first else {
            Log.appState.warning("Schedule not found for update: \(scheduleId)")
            return
        }
        if let v = json["name"] as? String { schedule.name = v }
        if let v = json["isEnabled"] as? Bool { schedule.isEnabled = v }
        if let v = json["promptTemplate"] as? String { schedule.promptTemplate = v }
        if let v = json["projectDirectory"] as? String { schedule.projectDirectory = v }
        if let v = json["intervalHours"] as? Int { schedule.intervalHours = v }
        if let v = json["localHour"] as? Int { schedule.localHour = v }
        if let v = json["localMinute"] as? Int { schedule.localMinute = v }
        if let days = json["daysOfWeek"] as? [String] {
            schedule.daysOfWeek = days.compactMap { label in
                ScheduledMissionWeekday.allCases.first { $0.shortLabel.lowercased() == label.lowercased() }
            }
        }
        if let v = json["cadenceKind"] as? String, let c = ScheduledMissionCadenceKind(rawValue: v) { schedule.cadenceKind = c }
        if let v = json["runMode"] as? String, let r = ScheduledMissionRunMode(rawValue: v) { schedule.runMode = r }
        if let v = json["usesAutonomousMode"] as? Bool { schedule.usesAutonomousMode = v }
        scheduleEngine?.syncSchedule(schedule)
        Log.appState.info("Schedule updated: \(scheduleId)")
    }

    private func handleScheduleDelete(scheduleId: String) {
        guard let ctx = modelContext,
              let uuid = UUID(uuidString: scheduleId) else { return }
        let descriptor = FetchDescriptor<ScheduledMission>(predicate: #Predicate { $0.id == uuid })
        guard let schedule = try? ctx.fetch(descriptor).first else {
            Log.appState.warning("Schedule not found for delete: \(scheduleId)")
            return
        }
        scheduleEngine?.removeSchedule(schedule)
        ctx.delete(schedule)
        try? ctx.save()
        scheduleEngine?.exportSchedules()
        Log.appState.info("Schedule deleted: \(scheduleId)")
    }

    private func handleScheduleTrigger(scheduleId: String) {
        guard let uuid = UUID(uuidString: scheduleId) else { return }
        scheduleEngine?.runNow(scheduleId: uuid)
        Log.appState.info("Schedule triggered: \(scheduleId)")
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
              let conversation = (requestingSession.conversations ?? []).first else {
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
        if (conversation.sessions ?? []).contains(where: { $0.agent?.id == agent.id }) {
            Log.appState.info("handleInviteAgent: '\(agentName, privacy: .public)' already in conversation")
            return
        }

        // Provision a new session for the invited agent.
        // Resolve WD: project root > invited agent's own default. Never inherit from requesting session.
        let provisioner = AgentProvisioner(modelContext: ctx)
        let inviteWorkingDirOverride: String?
        if let projectId = conversation.projectId {
            let projectDescriptor = FetchDescriptor<Project>(predicate: #Predicate { p in p.id == projectId })
            inviteWorkingDirOverride = (try? ctx.fetch(projectDescriptor).first)?.rootPath
        } else {
            inviteWorkingDirOverride = agent.defaultWorkingDirectory
        }
        let (config, newSession) = provisioner.provision(
            agent: agent,
            mission: requestingSession.mission,
            workingDirOverride: inviteWorkingDirOverride
        )

        newSession.conversations = [conversation]
        conversation.sessions = (conversation.sessions ?? []) + [newSession]
        conversation.threadKind = .group

        let participant = Participant(type: .agentSession(sessionId: newSession.id), displayName: agent.name)
        participant.conversation = conversation
        conversation.participants = (conversation.participants ?? []) + [participant]

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

    private func markConversationUnreadIfNeeded(sessionId: String) {
        guard let ctx = modelContext, let uuid = UUID(uuidString: sessionId) else { return }
        let descriptor = FetchDescriptor<Session>(predicate: #Predicate { s in s.id == uuid })
        guard let session = try? ctx.fetch(descriptor).first,
              let convo = (session.conversations ?? []).first,
              !visibleConversationIds.contains(convo.id) else { return }
        convo.isUnread = true
        try? ctx.save()
    }

    /// Batched session-end persistence: one fetch + one save instead of 3 separate cycles.
    private func persistSessionCompletion(
        sessionId: String,
        status: SessionStatus,
        tokenCount: Int? = nil,
        cost: Double? = nil,
        toolCallCount: Int? = nil
    ) {
        guard let ctx = modelContext, let uuid = UUID(uuidString: sessionId) else { return }
        let descriptor = FetchDescriptor<Session>(predicate: #Predicate { $0.id == uuid })
        guard let session = try? ctx.fetch(descriptor).first else { return }

        // Status
        session.status = status
        session.lastActiveAt = Date()

        // Usage (if provided — on completion, not error)
        if let tokenCount { session.tokenCount = tokenCount }
        if let cost { session.totalCost = cost }
        if let toolCallCount { session.toolCallCount = toolCallCount }

        // Unread flag
        if let convo = (session.conversations ?? []).first,
           !visibleConversationIds.contains(convo.id) {
            convo.isUnread = true
        }

        try? ctx.save()
    }

    /// Fire a notification only when the session's conversation is not currently viewed or app is in background.
    private func notifyIfNeeded(sessionId: String, _ action: (String, String?) -> Void) {
        let appIsActive = NSApplication.shared.isActive
        guard let ctx = modelContext, let uuid = UUID(uuidString: sessionId) else { return }
        let descriptor = FetchDescriptor<Session>(predicate: #Predicate { s in s.id == uuid })
        guard let session = try? ctx.fetch(descriptor).first,
              let convo = (session.conversations ?? []).first else { return }
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
        let agentParticipant = (convo.participants ?? []).first {
            guard case .agentSession(let sid) = $0.type, let suid = sessionUUID else { return false }
            return sid == suid
        }
        let response = ConversationMessage(
            senderParticipantId: agentParticipant?.id,
            text: responseText,
            type: .chat,
            conversation: convo
        )
        convo.messages = (convo.messages ?? []) + [response]
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
        return (try? ctx.fetch(descriptor).first)?.conversations?.first
    }

    // MARK: - Voice Mode Helpers

    private func handleVoiceModeCompletion(sessionId: String) {
        guard isVoiceModeActive else { return }
        guard UserDefaults.standard.object(forKey: "voice.autoSpeak") as? Bool ?? true else { return }
        guard let responseText = streamingText[sessionId], !responseText.isEmpty else { return }
        tts.speak(responseText, messageId: UUID())
    }

    // MARK: - Coalesced SwiftData Save

    /// Debounces rapid peer/blackboard/richContent events into a single save.
    /// Rapid bursts (e.g. multi-agent chat with peer messages) used to trigger
    /// one main-thread SQLite transaction per event; now they coalesce.
    private func schedulePersistentSave() {
        pendingPersistFlushTask?.cancel()
        pendingPersistFlushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let self else { return }
            self.flushPendingPersistentSave()
        }
    }

    /// Flushes any pending coalesced save immediately.
    /// Called on terminal events (sessionResult/sessionError) so persistence
    /// is guaranteed before downstream snapshots are pushed.
    func flushPendingPersistentSave() {
        pendingPersistFlushTask?.cancel()
        pendingPersistFlushTask = nil
        guard let ctx = modelContext, ctx.hasChanges else { return }
        try? ctx.save()
    }

    private func persistPeerChatMessage(sessionId: String, channelId: String, from: String, message: String) {
        guard let ctx = modelContext,
              let convo = conversationForSession(sessionId: sessionId) else { return }
        let msg = ConversationMessage(text: "\(from): \(message)", type: .peerMessage, conversation: convo)
        msg.toolName = channelId
        ctx.insert(msg)
        schedulePersistentSave()
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
        schedulePersistentSave()
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
        schedulePersistentSave()
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
