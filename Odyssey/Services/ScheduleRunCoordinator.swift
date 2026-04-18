import Foundation
import SwiftData

@MainActor
final class ScheduleRunCoordinator {
    struct Dependencies {
        var ensureSidecarConnected: @MainActor (AppState) async -> Bool
        var sendCommand: @MainActor (AppState, SidecarCommand) async throws -> Void
        var waitForSessionCompletion: @MainActor (AppState, String) async -> String?
        var ensureWorktree: @MainActor (Conversation, String, ModelContext) async -> String

        static let live = Dependencies(
            ensureSidecarConnected: { appState in
                if appState.sidecarStatus == .connected {
                    return true
                }

                if appState.sidecarStatus == .disconnected {
                    appState.connectSidecar()
                }

                for _ in 0..<30 {
                    if appState.sidecarStatus == .connected {
                        return true
                    }
                    try? await Task.sleep(for: .milliseconds(500))
                }
                return false
            },
            sendCommand: { appState, command in
                guard let manager = appState.sidecarManager else {
                    throw SidecarManager.SidecarError.notConnected
                }
                try await manager.send(command)
            },
            waitForSessionCompletion: { appState, sidecarKey in
                let maxWaitIterations = 600
                for _ in 0..<maxWaitIterations {
                    if let event = appState.lastSessionEvent[sidecarKey] {
                        switch event {
                        case .result:
                            return nil
                        case .error(let message):
                            return message
                        }
                    }
                    try? await Task.sleep(for: .milliseconds(100))
                }
                return "Timed out waiting for scheduled run response"
            },
            ensureWorktree: { conversation, projectDirectory, modelContext in
                await WorktreeManager.ensureWorktree(
                    for: conversation,
                    projectDirectory: projectDirectory,
                    modelContext: modelContext
                )
            }
        )
    }

    private unowned let appState: AppState
    private let modelContext: ModelContext
    private let dependencies: Dependencies

    init(
        appState: AppState,
        modelContext: ModelContext,
        dependencies: Dependencies = .live
    ) {
        self.appState = appState
        self.modelContext = modelContext
        self.dependencies = dependencies
    }

    func execute(
        schedule: ScheduledMission,
        run: ScheduledMissionRun,
        windowState: WindowState? = nil
    ) async {
        let scheduleId = schedule.id
        let runCount = ((try? modelContext.fetch(
            FetchDescriptor<ScheduledMissionRun>(
                predicate: #Predicate { $0.scheduleId == scheduleId }
            )
        ).count) ?? 1)
        let prompt = ScheduledMissionPromptRenderer.render(
            schedule: schedule,
            runCount: runCount,
            now: run.startedAt
        )

        guard await dependencies.ensureSidecarConnected(appState) else {
            markRunFailed(run, schedule: schedule, error: "Sidecar not connected")
            return
        }

        guard let conversation = prepareConversation(
            for: schedule,
            prompt: prompt,
            run: run,
            windowState: windowState
        ) else {
            markRunFailed(run, schedule: schedule, error: "Unable to resolve schedule target")
            return
        }

        let targetSessions = conversation.sessions.sorted { $0.startedAt < $1.startedAt }
        guard !targetSessions.isEmpty else {
            markRunFailed(run, schedule: schedule, error: "No sessions available for the schedule target")
            return
        }

        let worktreePath = await dependencies.ensureWorktree(
            conversation,
            schedule.projectDirectory,
            modelContext
        )

        for session in targetSessions where session.workingDirectory != worktreePath {
            session.workingDirectory = worktreePath
        }
        try? modelContext.save()

        let provisioner = AgentProvisioner(modelContext: modelContext)
        let participants = conversation.participants
        let sourceGroup = schedule.targetGroupId.flatMap { groupId in
            let descriptor = FetchDescriptor<AgentGroup>(predicate: #Predicate { $0.id == groupId })
            return try? modelContext.fetch(descriptor).first
        }
        let userWavePlan = GroupRoutingPlanner.planUserWave(
            executionMode: conversation.executionMode,
            routingMode: conversation.routingMode,
            sessions: targetSessions,
            sourceGroup: sourceGroup,
            mentionedAgents: [],
            mentionedAll: false
        )

        var lastAssistantMessage: ConversationMessage?

        for session in targetSessions where userWavePlan.recipientSessionIds.contains(session.id) {
            let sidecarKey = session.id.uuidString
            appState.streamingText.removeValue(forKey: sidecarKey)
            appState.thinkingText.removeValue(forKey: sidecarKey)
            appState.lastSessionEvent.removeValue(forKey: sidecarKey)
            appState.sessionActivity[sidecarKey] = .idle

            var createConfig: AgentConfig?
            if !appState.createdSessions.contains(sidecarKey) {
                if session.agent != nil {
                    createConfig = provisioner.config(for: session)
                } else {
                    createConfig = makeFreeformAgentConfig(for: session)
                }
            }

            let agentRole: GroupRole? = {
                guard let sourceGroup, let agentId = session.agent?.id else { return nil }
                return sourceGroup.roleFor(agentId: agentId)
            }()

            let teamMembers: [GroupPromptBuilder.TeamMemberInfo] = conversation.sessions
                .filter { $0.id != session.id }
                .compactMap { other in
                    guard let agent = other.agent else { return nil }
                    let role = sourceGroup?.roleFor(agentId: agent.id) ?? .participant
                    return .init(name: agent.name, description: agent.agentDescription, role: role)
                }

            let basePrompt = GroupPromptBuilder.buildMessageText(
                conversation: conversation,
                targetSession: session,
                latestUserMessageText: prompt,
                participants: participants,
                highlightedMentionAgentNames: userWavePlan.mentionedAgentNames,
                mentionedAll: userWavePlan.mentionedAll,
                routingMode: conversation.routingMode,
                deliveryReason: userWavePlan.deliveryReason,
                groupInstruction: sourceGroup?.groupInstruction,
                role: agentRole,
                teamMembers: teamMembers
            )
            let promptText = conversation.sessions.count > 1
                ? ExecutionModePromptBuilder.wrapCoordinatorPrompt(
                    basePrompt,
                    mode: conversation.executionMode,
                    coordinatorName: userWavePlan.coordinatorAgentName
                )
                : ExecutionModePromptBuilder.wrapDirectPrompt(
                    basePrompt,
                    mode: conversation.executionMode
                )

            do {
                if let createConfig {
                    try await dependencies.sendCommand(appState, .sessionCreate(
                        conversationId: sidecarKey,
                        agentConfig: createConfig
                    ))
                    appState.createdSessions.insert(sidecarKey)
                }
                try await dependencies.sendCommand(appState, .sessionMessage(
                    sessionId: sidecarKey,
                    text: promptText,
                    attachments: [],
                    planMode: false
                ))
            } catch {
                markRunFailed(run, schedule: schedule, error: "Failed to send scheduled prompt: \(error.localizedDescription)")
                return
            }

            let completionError = await dependencies.waitForSessionCompletion(appState, sidecarKey)
            lastAssistantMessage = finalizeAssistantStreamIntoMessage(
                conversation: conversation,
                session: session,
                sidecarKey: sidecarKey,
                errorMessage: completionError
            )

            if let errorMessage = completionError {
                markRunFailed(
                    run,
                    schedule: schedule,
                    error: ScheduledMissionPromptRenderer.shortSummary(
                        from: errorMessage.isEmpty ? "Scheduled run failed" : errorMessage
                    ),
                    conversationId: conversation.id,
                    summary: lastAssistantMessage.map { ScheduledMissionPromptRenderer.shortSummary(from: $0.text) }
                )
                return
            }
        }

        markRunSucceeded(
            run,
            schedule: schedule,
            conversationId: conversation.id,
            summary: lastAssistantMessage.map { ScheduledMissionPromptRenderer.shortSummary(from: $0.text) }
        )
    }

    private func prepareConversation(
        for schedule: ScheduledMission,
        prompt: String,
        run: ScheduledMissionRun,
        windowState: WindowState?
    ) -> Conversation? {
        let conversation: Conversation?

        switch schedule.runMode {
        case .reuseConversation:
            guard let targetConversationId = schedule.targetConversationId else { return nil }
            let descriptor = FetchDescriptor<Conversation>(predicate: #Predicate { $0.id == targetConversationId })
            conversation = try? modelContext.fetch(descriptor).first

        case .freshConversation:
            switch schedule.targetKind {
            case .agent:
                guard let targetAgentId = schedule.targetAgentId else { return nil }
                let descriptor = FetchDescriptor<Agent>(predicate: #Predicate { $0.id == targetAgentId })
                guard let agent = try? modelContext.fetch(descriptor).first else { return nil }
                conversation = createAgentConversation(
                    agent: agent,
                    projectDirectory: schedule.projectDirectory,
                    projectId: schedule.projectId
                )

            case .group:
                guard let targetGroupId = schedule.targetGroupId else { return nil }
                let descriptor = FetchDescriptor<AgentGroup>(predicate: #Predicate { $0.id == targetGroupId })
                guard let group = try? modelContext.fetch(descriptor).first else { return nil }
                let conversationId: UUID?
                if schedule.usesAutonomousMode {
                    conversationId = appState.startAutonomousGroupChat(
                        group: group,
                        mission: prompt,
                        projectDirectory: schedule.projectDirectory,
                        projectId: schedule.projectId,
                        modelContext: modelContext
                    )
                } else {
                    conversationId = appState.startGroupChat(
                        group: group,
                        projectDirectory: schedule.projectDirectory,
                        projectId: schedule.projectId,
                        modelContext: modelContext
                    )
                }
                if let conversationId {
                    let conversationDescriptor = FetchDescriptor<Conversation>(
                        predicate: #Predicate { $0.id == conversationId }
                    )
                    conversation = try? modelContext.fetch(conversationDescriptor).first
                } else {
                    conversation = nil
                }

            case .conversation:
                return nil
            case .project:
                return nil
            }
        }

        guard let conversation else { return nil }
        if conversation.projectId == nil {
            conversation.projectId = schedule.projectId
        }
        if schedule.usesAutonomousMode {
            conversation.executionMode = .autonomous
            for session in conversation.sessions {
                session.mode = .autonomous
            }
        }
        conversation.threadKind = .scheduled
        run.conversationId = conversation.id
        if let windowState {
            windowState.selectedConversationId = conversation.id
        }

        if schedule.runMode == .reuseConversation {
            let boundary = ConversationMessage(
                senderParticipantId: nil,
                text: "Scheduled run started for \(schedule.name).",
                type: .system,
                conversation: conversation
            )
            conversation.messages.append(boundary)
            modelContext.insert(boundary)
        }

        let userParticipant: Participant
        if let existing = conversation.participants.first(where: { $0.type == .user }) {
            userParticipant = existing
        } else {
            let participant = Participant(type: .user, displayName: "You")
            participant.conversation = conversation
            conversation.participants.append(participant)
            modelContext.insert(participant)
            userParticipant = participant
        }

        if conversation.messages.first(where: { $0.type == .chat }) == nil, (conversation.topic ?? "").isEmpty {
            conversation.topic = schedule.name
        }

        let promptMessage = ConversationMessage(
            senderParticipantId: userParticipant.id,
            text: prompt,
            type: .chat,
            conversation: conversation
        )
        conversation.messages.append(promptMessage)
        modelContext.insert(promptMessage)
        try? modelContext.save()
        return conversation
    }

    private func createAgentConversation(agent: Agent, projectDirectory: String, projectId: UUID? = nil) -> Conversation {
        let provisioner = AgentProvisioner(modelContext: modelContext)
        let (_, session) = provisioner.provision(
            agent: agent,
            mission: nil,
            workingDirOverride: projectDirectory
        )

        let conversation = Conversation(
            topic: agent.name,
            projectId: projectId,
            threadKind: .scheduled
        )
        let userParticipant = Participant(type: .user, displayName: "You")
        let agentParticipant = Participant(
            type: .agentSession(sessionId: session.id),
            displayName: agent.name
        )
        userParticipant.conversation = conversation
        agentParticipant.conversation = conversation
        conversation.participants = [userParticipant, agentParticipant]
        session.conversations = [conversation]
        conversation.sessions.append(session)

        modelContext.insert(session)
        modelContext.insert(conversation)
        try? modelContext.save()
        return conversation
    }

    @discardableResult
    private func finalizeAssistantStreamIntoMessage(
        conversation: Conversation,
        session: Session,
        sidecarKey: String,
        errorMessage: String?
    ) -> ConversationMessage? {
        let streamedText = appState.streamingText[sidecarKey] ?? ""
        let hasImages = !(appState.streamingImages[sidecarKey]?.isEmpty ?? true)
        let hasFileCards = !(appState.streamingFileCards[sidecarKey]?.isEmpty ?? true)
        guard !streamedText.isEmpty || errorMessage != nil || hasImages || hasFileCards else {
            return nil
        }

        let responseText = streamedText.isEmpty ? (errorMessage ?? "") : streamedText
        let seenThroughMessage = conversation.messages
            .filter { $0.type == .chat }
            .sorted { lhs, rhs in
                if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .last

        if errorMessage == nil,
           !hasImages,
           !hasFileCards,
           GroupPromptBuilder.isNoReplySentinel(responseText) {
            GroupPromptBuilder.markSessionCaughtUp(session: session, through: seenThroughMessage)
            appState.streamingText.removeValue(forKey: sidecarKey)
            appState.thinkingText.removeValue(forKey: sidecarKey)
            appState.lastSessionEvent.removeValue(forKey: sidecarKey)
            return nil
        }
        let participant = conversation.participants.first {
            if case .agentSession(let sessionId) = $0.type {
                return sessionId == session.id
            }
            return false
        }

        let response = ConversationMessage(
            senderParticipantId: participant?.id,
            text: responseText,
            type: .chat,
            conversation: conversation
        )
        if let thinking = appState.thinkingText[sidecarKey], !thinking.isEmpty {
            response.thinkingText = thinking
        }
        conversation.messages.append(response)
        modelContext.insert(response)
        GroupPromptBuilder.advanceWatermark(session: session, assistantMessage: response)

        if let images = appState.streamingImages[sidecarKey] {
            for image in images {
                guard let data = Data(base64Encoded: image.data) else { continue }
                let ext = image.mediaType.components(separatedBy: "/").last ?? "png"
                let name = "agent-image-\(UUID().uuidString.prefix(8)).\(ext)"
                let attachment = AttachmentStore.save(data: data, mediaType: image.mediaType, fileName: name)
                attachment.message = response
                response.attachments.append(attachment)
                modelContext.insert(attachment)
            }
            appState.streamingImages.removeValue(forKey: sidecarKey)
        }

        if let cards = appState.streamingFileCards[sidecarKey] {
            for card in cards {
                let mediaType = card.type == "html" ? "text/html" : "application/pdf"
                let attachment = MessageAttachment(mediaType: mediaType, fileName: card.name, fileSize: 0)
                attachment.localFilePath = card.path
                attachment.message = response
                response.attachments.append(attachment)
                modelContext.insert(attachment)
            }
            appState.streamingFileCards.removeValue(forKey: sidecarKey)
        }

        try? modelContext.save()
        appState.streamingText.removeValue(forKey: sidecarKey)
        appState.thinkingText.removeValue(forKey: sidecarKey)
        appState.lastSessionEvent.removeValue(forKey: sidecarKey)
        return response
    }

    private func markRunSucceeded(
        _ run: ScheduledMissionRun,
        schedule: ScheduledMission,
        conversationId: UUID?,
        summary: String?
    ) {
        run.status = .succeeded
        run.completedAt = Date()
        run.conversationId = conversationId
        run.summary = summary
        run.errorMessage = nil
        schedule.lastSucceededAt = run.completedAt
        schedule.updatedAt = run.completedAt ?? Date()
        try? modelContext.save()
    }

    private func markRunFailed(
        _ run: ScheduledMissionRun,
        schedule: ScheduledMission,
        error: String,
        conversationId: UUID? = nil,
        summary: String? = nil
    ) {
        run.status = .failed
        run.completedAt = Date()
        run.conversationId = conversationId
        run.summary = summary
        run.errorMessage = error
        schedule.lastFailedAt = run.completedAt
        schedule.updatedAt = run.completedAt ?? Date()
        try? modelContext.save()
    }

    private func makeFreeformAgentConfig(for session: Session) -> AgentConfig {
        var systemPrompt = AgentDefaults.defaultFreeformSystemPrompt
        if let mission = session.mission?.trimmingCharacters(in: .whitespacesAndNewlines),
           !mission.isEmpty {
            systemPrompt += "\n\n# Current Mission\n\(mission)\n"
        }
        return AgentDefaults.makeFreeformAgentConfig(
            provider: session.provider,
            model: session.model,
            workingDirectory: session.workingDirectory,
            systemPrompt: systemPrompt,
            interactive: session.mode == .interactive ? true : nil,
            instancePolicy: session.mode == .worker ? "singleton" : (session.mode == .autonomous ? "spawn" : nil)
        )
    }
}
