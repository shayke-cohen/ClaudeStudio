import SwiftUI
import SwiftData
import Combine

@MainActor
final class AppState: ObservableObject {
    enum SidecarStatus: Equatable {
        case disconnected
        case connecting
        case connected
        case error(String)
    }

    @Published var sidecarStatus: SidecarStatus = .disconnected
    @Published var selectedConversationId: UUID? {
        didSet {
            if selectedConversationId != nil { selectedGroupId = nil }
            if let id = selectedConversationId { markConversationRead(id: id) }
        }
    }
    @Published var selectedGroupId: UUID? {
        didSet { if selectedGroupId != nil { selectedConversationId = nil } }
    }
    @Published var showAgentLibrary = false
    @Published var showGroupLibrary = false
    @Published var showNewSessionSheet = false
    @Published var showPeerNetwork = false
    @Published var showAgentComms = false
    @Published var showDirectoryPicker = false
    @Published var showWorkshop = false
    @Published private(set) var instanceWorkingDirectory: String?
    @Published var activeSessions: [UUID: SessionInfo] = [:]
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
    @Published var pendingQuestions: [String: AgentQuestion] = [:]
    @Published var pendingConfirmations: [String: AgentConfirmation] = [:]
    @Published var progressTrackers: [String: ProgressTracker] = [:]
    @Published var pendingSuggestions: [String: [SuggestionItem]] = [:]

    /// File-based config sync service (set by ClaudPeerApp on appear)
    var configSyncService: ConfigSyncService?

    var createdSessions: Set<String> = []
    var generateAgentRequestId: String?

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

    private(set) var sidecarManager: SidecarManager?
    private var eventTask: Task<Void, Never>?
    var modelContext: ModelContext?

    func loadInstanceWorkingDirectory() {
        instanceWorkingDirectory = InstanceConfig.userDefaults.string(
            forKey: AppSettings.instanceWorkingDirectoryKey
        )
        if instanceWorkingDirectory == nil {
            showDirectoryPicker = true
        }
    }

    func setInstanceWorkingDirectory(_ path: String) {
        instanceWorkingDirectory = path
        InstanceConfig.userDefaults.set(path, forKey: AppSettings.instanceWorkingDirectoryKey)
    }

    // MARK: - Group Chat

    func startGroupChat(group: AgentGroup, modelContext: ModelContext) {
        guard !group.agentIds.isEmpty else { return }

        let allAgents = (try? modelContext.fetch(FetchDescriptor<Agent>())) ?? []
        let agentById = Dictionary(uniqueKeysWithValues: allAgents.map { ($0.id, $0) })
        let resolvedAgents = group.agentIds.compactMap { agentById[$0] }
        guard !resolvedAgents.isEmpty else { return }

        let conversation = Conversation(topic: group.name)
        conversation.sourceGroupId = group.id

        let userParticipant = Participant(type: .user, displayName: "You")
        userParticipant.conversation = conversation
        conversation.participants.append(userParticipant)

        // Inject group instruction as first system message
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
        let mission = group.defaultMission

        for agent in resolvedAgents {
            let (_, session) = provisioner.provision(agent: agent, mission: mission)
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

        GroupWorkingDirectory.ensureShared(
            for: conversation,
            instanceDefault: instanceWorkingDirectory,
            modelContext: modelContext
        )

        selectedConversationId = conversation.id
    }

    func startAutonomousGroupChat(group: AgentGroup, mission: String, modelContext: ModelContext) {
        guard group.autonomousCapable, !group.agentIds.isEmpty else { return }

        let allAgents = (try? modelContext.fetch(FetchDescriptor<Agent>())) ?? []
        let agentById = Dictionary(uniqueKeysWithValues: allAgents.map { ($0.id, $0) })
        let resolvedAgents = group.agentIds.compactMap { agentById[$0] }
        guard !resolvedAgents.isEmpty else { return }

        let conversation = Conversation(topic: "\(group.name) — Autonomous")
        conversation.sourceGroupId = group.id
        conversation.isAutonomous = true

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

        for agent in resolvedAgents {
            let (_, session) = provisioner.provision(agent: agent, mission: mission)
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

        GroupWorkingDirectory.ensureShared(
            for: conversation,
            instanceDefault: instanceWorkingDirectory,
            modelContext: modelContext
        )

        selectedConversationId = conversation.id
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
            sidecarPathOverride: sidecarPathOverride?.isEmpty == true ? nil : sidecarPathOverride
        )
        let manager = SidecarManager(config: config)
        self.sidecarManager = manager
        Task {
            do {
                try await manager.start()
                sidecarStatus = .connected
                listenForEvents(from: manager)
                registerAgentDefinitions()
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
        guard let manager = sidecarManager else { return }
        Task {
            try? await manager.send(command)
        }
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
        ctx.insert(msg)
        try? ctx.save()

        streamingText.removeValue(forKey: sessionId)
        thinkingText.removeValue(forKey: sessionId)
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

    private func registerAgentDefinitions() {
        guard let ctx = modelContext else { return }
        let descriptor = FetchDescriptor<Agent>()
        guard let agents = try? ctx.fetch(descriptor), !agents.isEmpty else { return }

        let provisioner = AgentProvisioner(modelContext: ctx)
        let defs: [AgentDefinitionWire] = agents.compactMap { agent in
            let (config, _) = provisioner.provision(agent: agent, mission: nil)
            return AgentDefinitionWire(name: agent.name, config: config)
        }

        sendToSidecar(.agentRegister(agents: defs))
        print("[AppState] Registered \(defs.count) agent definitions with sidecar")
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
            if let uuid = UUID(uuidString: sessionId) {
                activeSessions[uuid]?.isStreaming = true
                // Rough estimate: ~4 chars per output token, refined on completion
                activeSessions[uuid]?.tokenCount += max(1, text.count / 4)
            }
            sessionActivity[sessionId] = .streaming

        case .streamThinking(let sessionId, let text):
            let current = thinkingText[sessionId] ?? ""
            thinkingText[sessionId] = current + text
            activeSessions[UUID(uuidString: sessionId) ?? UUID()]?.isStreaming = true
            sessionActivity[sessionId] = .thinking

        case .streamToolCall(let sessionId, let tool, let input):
            var calls = toolCalls[sessionId] ?? []
            calls.append(ToolCallInfo(tool: tool, input: input, timestamp: Date()))
            toolCalls[sessionId] = calls
            if let uuid = UUID(uuidString: sessionId) {
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
            if let uuid = UUID(uuidString: sessionId) {
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
            sessionActivity[sessionId] = .done
            markConversationUnreadIfNeeded(sessionId: sessionId)
            notifyIfNeeded(sessionId: sessionId) { name, topic in
                ChatNotificationManager.shared.notifySessionCompleted(agentName: name, conversationTopic: topic)
            }
            persistSessionUsage(sessionId: sessionId, tokenCount: tokenCount, cost: cost, toolCallCount: toolCallCount)
            cleanupWorktreeIfNeeded(sessionId: sessionId)

        case .sessionError(let sessionId, let error):
            activeSessions[UUID(uuidString: sessionId) ?? UUID()]?.isStreaming = false
            lastSessionEvent[sessionId] = .error(error)
            thinkingText.removeValue(forKey: sessionId)
            streamingImages.removeValue(forKey: sessionId)
            streamingFileCards.removeValue(forKey: sessionId)
            sessionActivity[sessionId] = .error(error)
            notifyIfNeeded(sessionId: sessionId) { name, _ in
                ChatNotificationManager.shared.notifySessionError(agentName: name, error: error)
            }
            print("[AppState] Session \(sessionId) error: \(error)")
            cleanupWorktreeIfNeeded(sessionId: sessionId)

        case .peerChat(let channelId, let from, let message):
            commsEvents.append(CommsEvent(
                timestamp: Date(),
                kind: .chat(channelId: channelId, from: from, message: message)
            ))
            persistPeerChatMessage(channelId: channelId, from: from, message: message)

        case .peerDelegate(let from, let to, let task):
            commsEvents.append(CommsEvent(
                timestamp: Date(),
                kind: .delegation(from: from, to: to, task: task)
            ))
            persistDelegationEvent(from: from, to: to, task: task)

        case .blackboardUpdate(let key, let value, let writtenBy):
            commsEvents.append(CommsEvent(
                timestamp: Date(),
                kind: .blackboardUpdate(key: key, value: value, writtenBy: writtenBy)
            ))
            persistBlackboardUpdate(key: key, value: value, writtenBy: writtenBy)

        case .sessionForked(let parentSessionId, let childSessionId):
            print("[AppState] session.forked parent=\(parentSessionId) child=\(childSessionId)")

        case .sessionReused(let originalSessionId, let reusedSessionId):
            print("[AppState] session.reused original=\(originalSessionId) → reused=\(reusedSessionId)")

        case .streamImage(let sessionId, let imageData, let mediaType, _):
            streamingImages[sessionId, default: []].append((data: imageData, mediaType: mediaType))

        case .streamFileCard(let sessionId, let filePath, let fileType, let fileName):
            streamingFileCards[sessionId, default: []].append((path: filePath, type: fileType, name: fileName))

        case .agentQuestion(let sessionId, let questionId, let question, let options, let multiSelect, let isPrivate, let inputType, let inputConfig):
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
            print("[AppState] stream.richContent format=\(format) session=\(sessionId)")
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
            print("[AppState] Agent generation error: \(error)")

        case .connected:
            sidecarStatus = .connected
            disconnectTimer?.invalidate()
            disconnectTimer = nil
            Task { await recoverSessions() }

        case .disconnected:
            sidecarStatus = .disconnected
            pendingQuestions.removeAll()
            startDisconnectTimer()
        }
    }

    #if DEBUG
    /// Exposed for unit testing — calls handleEvent directly.
    func handleEventForTesting(_ event: SidecarEvent) {
        handleEvent(event)
    }
    #endif

    // MARK: - Session crash recovery

    private var disconnectTimer: Timer?

    /// After sidecar reconnects, re-register agents and resume active sessions with their Claude SDK session IDs.
    private func recoverSessions() async {
        guard let ctx = modelContext, let manager = sidecarManager else { return }

        // 1. Re-register agent definitions so sidecar knows about them
        registerAgentDefinitions()

        // 2. Find sessions that were active and have a Claude SDK session ID
        let descriptor = FetchDescriptor<Session>()
        guard let allSessions = try? ctx.fetch(descriptor) else { return }
        let resumable = allSessions.filter {
            ($0.status == .active || $0.status == .paused) && $0.claudeSessionId != nil
        }
        guard !resumable.isEmpty else { return }

        let provisioner = AgentProvisioner(modelContext: ctx)
        var entries: [SessionBulkResumeEntry] = []
        for session in resumable {
            guard let agent = session.agent, let claudeId = session.claudeSessionId else { continue }
            let (config, _) = provisioner.provision(agent: agent, mission: session.mission)
            entries.append(SessionBulkResumeEntry(
                sessionId: session.id.uuidString,
                claudeSessionId: claudeId,
                agentConfig: config
            ))
            // Ensure session is marked active again if it was paused by disconnect
            if session.status == .paused {
                session.status = .active
            }
        }

        guard !entries.isEmpty else { return }
        try? ctx.save()
        try? await manager.send(.sessionBulkResume(sessions: entries))
        print("[AppState] Recovered \(entries.count) sessions after reconnect")
    }

    /// Mark active sessions as paused after prolonged sidecar disconnect (60s).
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
            session.status = .paused
        }
        try? ctx.save()
        print("[AppState] Marked active sessions as paused after prolonged disconnect")
    }

    // MARK: - Worktree cleanup

    private func cleanupWorktreeIfNeeded(sessionId: String) {
        guard let ctx = modelContext, let uuid = UUID(uuidString: sessionId) else { return }
        let descriptor = FetchDescriptor<Session>(predicate: #Predicate { s in s.id == uuid })
        guard let session = try? ctx.fetch(descriptor).first else { return }
        Task { await WorktreeCleanup.cleanupIfNeeded(session: session) }
    }

    // MARK: - Unread state

    private func markConversationRead(id: UUID) {
        guard let ctx = modelContext else { return }
        let descriptor = FetchDescriptor<Conversation>(predicate: #Predicate { c in c.id == id })
        guard let convo = try? ctx.fetch(descriptor).first, convo.isUnread else { return }
        convo.isUnread = false
        try? ctx.save()
    }

    private func markConversationUnreadIfNeeded(sessionId: String) {
        guard let ctx = modelContext, let uuid = UUID(uuidString: sessionId) else { return }
        let descriptor = FetchDescriptor<Session>(predicate: #Predicate { s in s.id == uuid })
        guard let session = try? ctx.fetch(descriptor).first,
              let convo = session.conversations.first,
              convo.id != selectedConversationId else { return }
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
        guard convo.id != selectedConversationId || !appIsActive else { return }
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

    // MARK: - Persistence helpers for inter-agent events

    private func persistPeerChatMessage(channelId: String, from: String, message: String) {
        guard let ctx = modelContext else { return }

        let descriptor = FetchDescriptor<Conversation>(predicate: #Predicate { conv in
            conv.topic == channelId
        })
        let existing = try? ctx.fetch(descriptor).first

        if let convo = existing {
            let msg = ConversationMessage(text: "[\(from)] \(message)", type: .chat, conversation: convo)
            ctx.insert(msg)
        }
        try? ctx.save()
    }

    private func persistDelegationEvent(from: String, to: String, task: String) {
        guard let ctx = modelContext else { return }

        let convo = Conversation(topic: "\(from) → \(to)")
        convo.parentConversationId = selectedConversationId
        ctx.insert(convo)

        let msg = ConversationMessage(
            text: "[Delegation] \(from) delegated to \(to): \(task)",
            type: .delegation,
            conversation: convo
        )
        ctx.insert(msg)
        try? ctx.save()
    }

    private func persistBlackboardUpdate(key: String, value: String, writtenBy: String) {
        guard let ctx = modelContext else { return }

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
        try? ctx.save()
    }
}
