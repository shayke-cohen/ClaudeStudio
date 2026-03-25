import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AppKit

struct ChatView: View {
    let conversationId: UUID
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @State private var inputText = ""
    @State private var isProcessing = false
    @State private var lastTokenTime: Date?
    @State private var processingStartTime: Date?
    @State private var isEditingTopic = false
    @State private var editedTopic = ""
    @State private var showClearConfirmation = false
    @State private var pendingAttachments: [(id: UUID, data: Data, mediaType: String, fileName: String)] = []
    @State private var showFileImporter = false
    @State private var previewAttachment: MessageAttachment?
    @State private var previewImageFromPending: (data: Data, mediaType: String)?
    @State private var delegateTarget: Agent?
    @State private var isStreamingThinkingExpanded = false
    /// Sidecar `Session.id` string currently receiving stream (sequential multi-agent).
    @State private var activeStreamSessionKey: String?
    @State private var streamingDisplayName: String = "Claude"
    @State private var showSlashHelp = false
    @State private var showUnknownSlash = false
    @State private var unknownSlashName = ""
    @State private var showMentionError = false
    @State private var mentionErrorDetail = ""
    @State private var showAddAgentsSheet = false
    /// Retained while the system share sheet is visible so temp export files can be cleaned up.
    @State private var shareCoordinator: ShareTempFileCoordinator?
    @State private var showAllDoneBanner = false
    @State private var allDoneBannerTimer: Task<Void, Never>?
    @State private var planModeEnabled = false
    /// The ID of the last assistant message produced while plan mode was active (for showing the Execute Plan action bar).
    @State private var lastPlanResponseMessageId: UUID?
    @State private var showAttachRepoSheet = false
    @FocusState private var topicFieldFocused: Bool

    @Query private var allConversations: [Conversation]
    @Query private var allAgents: [Agent]
    @Query private var allGroups: [AgentGroup]
    @Query(sort: \Session.startedAt) private var allSessions: [Session]

    private var conversation: Conversation? {
        allConversations.first { $0.id == conversationId }
    }

    /// Sessions for this conversation — relationship first, manual query fallback.
    private var conversationSessions: [Session] {
        let relSessions = conversation?.sessions ?? []
        if !relSessions.isEmpty { return relSessions }
        return allSessions.filter { session in
            session.conversations.contains { $0.id == conversationId }
        }
    }

    private var sortedMessages: [ConversationMessage] {
        (conversation?.messages ?? []).sorted { $0.timestamp < $1.timestamp }
    }

    private var hasUserChatMessages: Bool {
        sortedMessages.contains { $0.type == .chat }
    }

    private var primarySession: Session? {
        conversationSessions.min { $0.startedAt < $1.startedAt }
    }

    private var currentModel: String? {
        primarySession?.agent?.model
    }

    private var aggregatedLiveCost: Double {
        guard let convo = conversation else { return 0 }
        var sum = 0.0
        for s in convo.sessions {
            sum += appState.activeSessions[s.id]?.cost ?? s.totalCost
        }
        return sum
    }

    private var liveCost: Double? {
        let c = aggregatedLiveCost
        return c > 0 ? c : nil
    }

    private var streamSessionKeyForUI: String? {
        activeStreamSessionKey ?? primarySession?.id.uuidString
    }

    private var liveStreamingText: String? {
        guard let key = streamSessionKeyForUI else { return nil }
        let text = appState.streamingText[key]
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    private var liveThinkingText: String? {
        guard let key = streamSessionKeyForUI else { return nil }
        let text = appState.thinkingText[key]
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    private var mentionAutocompleteAgents: [Agent] {
        guard let r = inputText.range(of: #"@([^\s@]*)$"#, options: .regularExpression) else { return [] }
        let token = String(inputText[r]).dropFirst().lowercased()
        guard !token.isEmpty else { return Array(allAgents.prefix(8)) }
        return allAgents.filter { $0.name.lowercased().hasPrefix(token) }.prefix(8).map { $0 }
    }

    private var sendingToSubtitle: String? {
        guard let c = conversation, c.sessions.count > 1 else { return nil }
        let names = c.sessions.compactMap { $0.agent?.name ?? "Assistant" }
        return "Group — " + names.joined(separator: ", ") + " · peer replies reach everyone"
    }

    /// Maps participantId → AgentAppearance for multi-agent conversations. `nil` for single-agent.
    private var participantAppearanceMap: [UUID: AgentAppearance]? {
        guard let convo = conversation, convo.sessions.count > 1 else { return nil }
        var map: [UUID: AgentAppearance] = [:]
        for participant in convo.participants {
            if let sessionId = participant.typeSessionId,
               let session = convo.sessions.first(where: { $0.id == sessionId }),
               let agent = session.agent {
                map[participant.id] = AgentAppearance(
                    color: Color.fromAgentColor(agent.color),
                    icon: agent.icon
                )
            }
        }
        return map.isEmpty ? nil : map
    }

    /// Resolves the active streaming agent's appearance for multi-agent conversations.
    private var streamingAgentAppearance: AgentAppearance? {
        guard let convo = conversation, convo.sessions.count > 1 else { return nil }
        guard let key = activeStreamSessionKey,
              let sessionId = UUID(uuidString: key),
              let session = convo.sessions.first(where: { $0.id == sessionId }),
              let agent = session.agent else { return nil }
        return AgentAppearance(color: Color.fromAgentColor(agent.color), icon: agent.icon)
    }

    private var streamingAppendix: ChatTranscriptStreamingAppendix? {
        guard isProcessing else { return nil }
        let key = streamSessionKeyForUI ?? ""
        let text = appState.streamingText[key] ?? ""
        let thinking = appState.thinkingText[key] ?? ""
        let app = ChatTranscriptStreamingAppendix(text: text, thinking: thinking, displayName: streamingDisplayName)
        return app.isEmpty ? nil : app
    }

    private var canExportChat: Bool {
        !sortedMessages.isEmpty || streamingAppendix != nil
    }

    private func chatExportSnapshot() -> ChatTranscriptSnapshot? {
        guard let convo = conversation else { return nil }
        let appendix = streamingAppendix
        if sortedMessages.isEmpty, appendix == nil { return nil }
        return ChatTranscriptExport.snapshot(
            conversation: convo,
            messages: sortedMessages,
            participants: convo.participants,
            streamingAppendix: appendix
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            chatHeader
            Divider()
            messageList
            Divider()
            inputArea
        }
        .task {
            try? await Task.sleep(for: .milliseconds(300))
            checkForPendingResponse()
        }
        .onReceive(appState.$lastSessionEvent) { events in
            checkForCompletion(events: events)
        }
        .onReceive(appState.$streamingText) { texts in
            if let key = streamSessionKeyForUI, texts[key] != nil {
                lastTokenTime = Date()
            }
        }
        .onReceive(appState.$sidecarStatus) { status in
            if status != .connected && isProcessing {
                isProcessing = false
                processingStartTime = nil
            }
        }
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
            guard isProcessing, let start = processingStartTime else { return }
            let elapsed = Date().timeIntervalSince(start)
            let key = streamSessionKeyForUI ?? ""
            let hasStreamingText = !(appState.streamingText[key]?.isEmpty ?? true)
            if elapsed > 120 && !hasStreamingText {
                print("[ChatView] Timeout: no response after \(Int(elapsed))s for \(key)")
                isProcessing = false
                processingStartTime = nil
                if !key.isEmpty {
                    appState.lastSessionEvent[key] = .error("No response received (timeout)")
                }
            }
        }
        .onChange(of: sortedMessages.count) { oldCount, newCount in
            if oldCount == 0, newCount > 0 {
                checkForPendingResponse()
            }
        }
        .onChange(of: appState.sessionActivity) { _, _ in
            if let convo = conversation {
                let summary = appState.conversationActivity(for: convo)
                if case .allDone = summary.aggregate, summary.totalSessions > 0, !showAllDoneBanner {
                    withAnimation(.easeInOut(duration: 0.3)) { showAllDoneBanner = true }
                    allDoneBannerTimer?.cancel()
                    allDoneBannerTimer = Task {
                        try? await Task.sleep(for: .seconds(5))
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            withAnimation(.easeInOut(duration: 0.5)) { showAllDoneBanner = false }
                        }
                    }
                }
            }
        }
        .task(id: isProcessing) {
            guard isProcessing else { return }
            while isProcessing {
                try? await Task.sleep(for: .seconds(3))
                guard isProcessing else { return }
                let key = streamSessionKeyForUI ?? ""
                let hasText = appState.streamingText[key] != nil
                let stale = lastTokenTime.map { Date().timeIntervalSince($0) > 3 } ?? false
                if hasText && stale {
                    collectResponseIfSingle()
                    return
                }
            }
        }
        .alert("Clear Messages?", isPresented: $showClearConfirmation) {
            Button("Clear All", role: .destructive) { clearMessages() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All messages in this conversation will be deleted. The conversation will remain.")
        }
        .sheet(item: $previewAttachment) { attachment in
            ImagePreviewOverlay(attachment: attachment)
        }
        .sheet(isPresented: Binding(
            get: { previewImageFromPending != nil },
            set: { if !$0 { previewImageFromPending = nil } }
        )) {
            if let pending = previewImageFromPending {
                ImagePreviewOverlay(imageData: pending.data, mediaType: pending.mediaType)
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: AttachmentStore.supportedContentTypes,
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
        .sheet(item: $delegateTarget) { agent in
            DelegateSheet(
                agent: agent,
                initialTask: inputText.trimmingCharacters(in: .whitespacesAndNewlines),
                sourceSessionId: primarySession?.id ?? conversationId
            ) {
                inputText = ""
            }
            .environmentObject(appState)
        }
        .sheet(isPresented: $showAddAgentsSheet) {
            AddAgentsToChatSheet(conversationId: conversationId)
                .environmentObject(appState)
                .environment(\.modelContext, modelContext)
        }
        .sheet(isPresented: $showAttachRepoSheet) {
            AttachRepoSheet(conversationId: conversationId)
                .environmentObject(appState)
                .environment(\.modelContext, modelContext)
        }
        .alert("Commands", isPresented: $showSlashHelp) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("/help — this list\n/topic <name> or /rename <name> — rename conversation\n/agents — add agents to this chat\n@AgentName — add that agent to the group if missing; everyone still receives each message")
        }
        .alert("Unknown command", isPresented: $showUnknownSlash) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Unknown command /\(unknownSlashName). Try /help.")
        }
        .alert("Mention", isPresented: $showMentionError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(mentionErrorDetail)
        }
    }

    // MARK: - Chat Header

    @ViewBuilder
    private var chatHeader: some View {
        VStack(spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                agentIconButton

                if isEditingTopic {
                    TextField("Conversation name", text: $editedTopic)
                        .textFieldStyle(.roundedBorder)
                        .font(.headline)
                        .focused($topicFieldFocused)
                        .frame(maxWidth: 300)
                        .onSubmit { commitRename() }
                        .onExitCommand { cancelRename() }
                        .xrayId("chat.topicField")
                } else {
                    Text(conversation?.topic ?? "Chat")
                        .font(.headline)
                        .lineLimit(1)
                        .xrayId("chat.topicTitle")
                }

                Spacer()

                if planModeEnabled {
                    Text("Plan Mode")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.orange, in: Capsule())
                        .xrayId("chat.planModeBadge")
                }

                if let model = currentModel {
                    Text(modelShortName(model))
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .clipShape(Capsule())
                        .xrayId("chat.modelPill")
                }

                if let cost = liveCost, cost > 0 {
                    Text(String(format: "$%.4f", cost))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .xrayId("chat.liveCostLabel")
                }

                if let convo = conversation {
                    headerActions(convo)
                }
            }

            if let mission = primarySession?.mission, !mission.isEmpty {
                HStack {
                    Text(mission)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .xrayId("chat.missionPreview")
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    @ViewBuilder
    private var agentIconButton: some View {
        if let convo = conversation, convo.sessions.count > 1 {
            HStack(spacing: -6) {
                ForEach(convo.sessions.prefix(4), id: \.id) { s in
                    if let ag = s.agent {
                        Image(systemName: ag.icon)
                            .foregroundStyle(Color.fromAgentColor(ag.color))
                            .font(.caption)
                            .padding(4)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                if convo.sessions.count > 4 {
                    Text("+\(convo.sessions.count - 4)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .xrayId("chat.groupAgentIcons")
        } else if let agent = primarySession?.agent {
            Button {
                appState.showAgentLibrary = true
            } label: {
                Image(systemName: agent.icon)
                    .foregroundStyle(Color.fromAgentColor(agent.color))
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help("Open agent: \(agent.name)")
            .xrayId("chat.agentIconButton")
            .accessibilityLabel("Open agent \(agent.name)")
        } else {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .foregroundStyle(.blue)
                .font(.title3)
                .xrayId("chat.chatIcon")
        }
    }

    @ViewBuilder
    private func headerActions(_ convo: Conversation) -> some View {
        HStack(spacing: 6) {
            if convo.status == .active {
                Button { pauseSession() } label: {
                    Image(systemName: "pause.fill")
                }
                .help("Pause session")
                .xrayId("chat.pauseButton")
                .accessibilityLabel("Pause session")

                Button { closeConversation(convo) } label: {
                    Image(systemName: "stop.circle")
                }
                .help("Close session")
                .xrayId("chat.closeSessionButton")
                .accessibilityLabel("Close session")
            } else if convo.sessions.contains(where: { $0.status == .paused }) {
                Button { resumeSession() } label: {
                    Image(systemName: "play.fill")
                }
                .help("Resume session")
                .xrayId("chat.resumeButton")
                .accessibilityLabel("Resume session")
            }

            Menu {
                if !convo.sessions.isEmpty {
                    Button { forkConversation() } label: {
                        Label("Fork Conversation", systemImage: "arrow.branch")
                    }
                    .xrayId("chat.moreOptions.fork")
                }
                Button {
                    editedTopic = convo.topic ?? ""
                    isEditingTopic = true
                    topicFieldFocused = true
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                .xrayId("chat.moreOptions.rename")
                Button { duplicateConversation(convo) } label: {
                    Label("Duplicate", systemImage: "doc.on.doc")
                }
                .xrayId("chat.moreOptions.duplicate")
                Divider()
                Menu {
                    Button {
                        Task { await exportChatTranscript(kind: .markdown, destination: .save) }
                    } label: {
                        Label("Markdown…", systemImage: "doc.richtext")
                    }
                    .disabled(!canExportChat)
                    .xrayId("chat.export.markdown")
                    Button {
                        Task { await exportChatTranscript(kind: .html, destination: .save) }
                    } label: {
                        Label("HTML…", systemImage: "doc.richtext")
                    }
                    .disabled(!canExportChat)
                    .xrayId("chat.export.html")
                    Button {
                        Task { await exportChatTranscript(kind: .pdf, destination: .save) }
                    } label: {
                        Label("PDF…", systemImage: "doc.fill")
                    }
                    .disabled(!canExportChat)
                    .xrayId("chat.export.pdf")
                } label: {
                    Label("Export", systemImage: "square.and.arrow.down")
                }
                .disabled(!canExportChat)
                .xrayId("chat.exportSubmenu")
                .accessibilityLabel("Export chat")
                Menu {
                    Button {
                        Task { await exportChatTranscript(kind: .markdown, destination: .share) }
                    } label: {
                        Label("Markdown", systemImage: "doc.richtext")
                    }
                    .disabled(!canExportChat)
                    .xrayId("chat.share.markdown")
                    Button {
                        Task { await exportChatTranscript(kind: .html, destination: .share) }
                    } label: {
                        Label("HTML", systemImage: "doc.richtext")
                    }
                    .disabled(!canExportChat)
                    .xrayId("chat.share.html")
                    Button {
                        Task { await exportChatTranscript(kind: .pdf, destination: .share) }
                    } label: {
                        Label("PDF", systemImage: "doc.fill")
                    }
                    .disabled(!canExportChat)
                    .xrayId("chat.share.pdf")
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .disabled(!canExportChat)
                .xrayId("chat.shareSubmenu")
                .accessibilityLabel("Share chat")
                Divider()
                Button { showAttachRepoSheet = true } label: {
                    Label("Attach GitHub Repo", systemImage: "arrow.triangle.branch")
                }
                .xrayId("chat.moreOptions.attachRepo")
                Divider()
                Toggle(isOn: Binding(
                    get: { AppSettings.store.object(forKey: AppSettings.notificationsEnabledKey) as? Bool ?? true },
                    set: { AppSettings.store.set($0, forKey: AppSettings.notificationsEnabledKey) }
                )) {
                    Label("Notifications", systemImage: "bell")
                }
                .xrayId("chat.moreOptions.notificationsToggle")
                Toggle(isOn: Binding(
                    get: { AppSettings.store.object(forKey: AppSettings.notificationSoundEnabledKey) as? Bool ?? true },
                    set: { AppSettings.store.set($0, forKey: AppSettings.notificationSoundEnabledKey) }
                )) {
                    Label("Sound", systemImage: "speaker.wave.2")
                }
                .xrayId("chat.moreOptions.soundToggle")
                Divider()
                Button { showClearConfirmation = true } label: {
                    Label("Clear Messages", systemImage: "trash")
                }
                .xrayId("chat.moreOptions.clearMessages")
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 20)
            .help("More options")
            .xrayId("chat.moreOptionsMenu")
            .accessibilityLabel("More options")
        }
        .buttonStyle(.borderless)
    }

    // MARK: - Message List

    @ViewBuilder
    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if !hasUserChatMessages && !isProcessing {
                        chatEmptyState
                    }

                    ForEach(sortedMessages) { message in
                        MessageBubble(
                            message: message,
                            participants: conversation?.participants ?? [],
                            agentAppearances: participantAppearanceMap,
                            onTapAttachment: { attachment in
                                previewAttachment = attachment
                            },
                            onForkFromHere: {
                                forkFromMessage(message)
                            }
                        )
                        .id(message.id)

                        if message.id == lastPlanResponseMessageId, !isProcessing {
                            planActionBar
                        }
                    }

                    if let convo = conversation, convo.sessions.count > 1 {
                        AgentActivityBar(
                            sessions: convo.sessions,
                            sessionActivity: appState.sessionActivity
                        )
                        .id("agentActivityBar")
                    }

                    if isProcessing {
                        streamingBubble
                            .id("streaming")
                    }

                    ForEach(pendingQuestionsForCurrentConversation) { question in
                        AgentQuestionBubble(
                            question: question,
                            agentName: agentNameForQuestion(question),
                            agentColor: agentColorForQuestion(question)
                        ) { answer, selectedOptions in
                            appState.answerQuestion(
                                sessionId: question.sessionId,
                                questionId: question.id,
                                answer: answer,
                                selectedOptions: selectedOptions
                            )
                        }
                        .id("agentQuestion-\(question.id)")
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    if showAllDoneBanner {
                        SessionSummaryCard(
                            sessions: sessionsForSummary,
                            toolCalls: toolCallsForSummary,
                            duration: summaryDuration
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .id("allDoneBanner")
                    }
                }
                .padding()
            }
            .xrayId("chat.messageScrollView")
            .onChange(of: sortedMessages.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: liveStreamingText) { _, _ in
                if isProcessing {
                    scrollToBottom(proxy)
                }
            }
        }
    }

    // MARK: - Input Area

    private var canSend: Bool {
        let hasText = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return (hasText || !pendingAttachments.isEmpty) && !isProcessing
    }

    @ViewBuilder
    private var inputArea: some View {
        VStack(spacing: 0) {
            if !pendingAttachments.isEmpty {
                pendingAttachmentStrip
            }

            if let sub = sendingToSubtitle {
                Text(sub)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .xrayId("chat.sendingToHint")
            }

            if !mentionAutocompleteAgents.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(mentionAutocompleteAgents) { agent in
                            Button {
                                insertMentionCompletion(agentName: agent.name)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(agent.name)
                                        .font(.caption)
                                    Text(agentMentionHint(for: agent))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.quaternary, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .xrayId("chat.mentionSuggestion.\(agent.id.uuidString)")
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
                .xrayId("chat.mentionSuggestions")
            }

            if !hasUserChatMessages && !isProcessing && mentionAutocompleteAgents.isEmpty {
                actionChipsStrip
            }

            HStack(alignment: .bottom, spacing: 8) {
                Button {
                    showFileImporter = true
                } label: {
                    Image(systemName: "paperclip")
                        .font(.body)
                }
                .buttonStyle(.borderless)
                .xrayId("chat.attachButton")
                .accessibilityLabel("Attach file")
                .help("Attach file")
                .disabled(isProcessing)

                delegateMenu

                Button {
                    planModeEnabled.toggle()
                } label: {
                    Image(systemName: planModeEnabled ? "doc.text.magnifyingglass" : "doc.text.magnifyingglass")
                        .font(.body)
                        .foregroundStyle(planModeEnabled ? .orange : .secondary)
                }
                .buttonStyle(.borderless)
                .xrayId("chat.planModeToggle")
                .accessibilityLabel("Toggle plan mode")
                .help(planModeEnabled ? "Plan mode on — agent will read and plan only" : "Plan mode off — agent can make changes")
                .disabled(isProcessing)

                PasteableTextField(
                    text: $inputText,
                    onImagePaste: { data, mediaType in
                        guard AttachmentStore.validate(data: data, mediaType: mediaType) else { return }
                        pendingAttachments.append((id: UUID(), data: data, mediaType: mediaType, fileName: "pasted.png"))
                    },
                    onSubmit: { if canSend { sendMessage() } },
                    canSubmitOnReturn: { canSend }
                )
                .xrayId("chat.messageInput")
                .help("Return sends when there is text or attachments. Shift-Return inserts a new line. ⌘↩ also sends.")

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.borderless)
                .xrayId("chat.sendButton")
                .accessibilityLabel("Send message")
                .disabled(!canSend)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Send message (Return or ⌘Return)")
            }
            .padding(12)
        }
        .background(.bar)
        .onDrop(of: [.image, .fileURL, .plainText, .pdf], isTargeted: nil) { providers in
            handleDrop(providers)
            return true
        }
    }

    @ViewBuilder
    private var planActionBar: some View {
        HStack(spacing: 12) {
            Button {
                executePlan()
            } label: {
                Label("Execute Plan", systemImage: "play.fill")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .xrayId("chat.executePlanButton")

            Button {
                // Keep plan mode on, just clear the action bar so user can type a follow-up
                lastPlanResponseMessageId = nil
            } label: {
                Label("Refine Plan", systemImage: "pencil")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .xrayId("chat.refinePlanButton")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var pendingAttachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(pendingAttachments.enumerated()), id: \.element.id) { index, item in
                    ZStack(alignment: .topTrailing) {
                        if item.mediaType.hasPrefix("image/"), let nsImage = NSImage(data: item.data) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .onTapGesture {
                                    previewImageFromPending = (data: item.data, mediaType: item.mediaType)
                                }
                                .xrayId("chat.pendingAttachment.\(index)")
                        } else {
                            VStack(spacing: 2) {
                                Image(systemName: iconForMediaType(item.mediaType))
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                                Text(item.fileName)
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(maxWidth: 56)
                            }
                            .frame(width: 60, height: 60)
                            .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
                            .xrayId("chat.pendingAttachment.\(index)")
                        }

                        Button {
                            pendingAttachments.removeAll { $0.id == item.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.white)
                                .background(Circle().fill(.black.opacity(0.6)))
                        }
                        .buttonStyle(.borderless)
                        .offset(x: 4, y: -4)
                        .xrayId("chat.pendingAttachment.remove.\(index)")
                        .accessibilityLabel("Remove attachment")
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .xrayId("chat.pendingAttachments")
    }

    @ViewBuilder
    private var delegateMenu: some View {
        let inChatAgentIds = Set(conversationSessions.compactMap(\.agent?.id))
        let eligibleAgents = allAgents.filter { !inChatAgentIds.contains($0.id) }

        Menu {
            Section("Delegate to...") {
                ForEach(eligibleAgents, id: \.id) { agent in
                    Button {
                        delegateTarget = agent
                    } label: {
                        Label(agent.name, systemImage: agent.icon)
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.triangle.branch")
                .font(.body)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 20)
        .xrayId("chat.delegateButton")
        .accessibilityLabel("Delegate to agent")
        .help("Delegate task to another agent")
        .disabled(isProcessing || appState.sidecarStatus != .connected || eligibleAgents.isEmpty)
    }

    private func iconForMediaType(_ mediaType: String) -> String {
        switch mediaType {
        case "text/plain", "text/markdown": return "doc.text"
        case "application/pdf": return "doc.richtext"
        default: return mediaType.hasPrefix("image/") ? "photo" : "doc"
        }
    }

    // MARK: - Chat Empty State

    private var sourceGroup: AgentGroup? {
        guard let gid = conversation?.sourceGroupId else { return nil }
        return allGroups.first { $0.id == gid }
    }

    private var emptyStateSuggestions: AgentSuggestions.SuggestionSet {
        if let group = sourceGroup {
            return AgentSuggestions.groupSuggestions(for: group)
        }
        if let agent = primarySession?.agent {
            return AgentSuggestions.suggestions(for: agent)
        }
        return AgentSuggestions.freeformSuggestions
    }

    @ViewBuilder
    private var chatEmptyState: some View {
        VStack(spacing: 16) {
            if let group = sourceGroup {
                groupEmptyStateHeader(group)
            } else if let agent = primarySession?.agent {
                VStack(spacing: 8) {
                    Image(systemName: agent.icon)
                        .font(.system(size: 36))
                        .foregroundStyle(Color.fromAgentColor(agent.color))
                        .frame(width: 64, height: 64)
                        .background(Color.fromAgentColor(agent.color).opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                    Text(agent.name)
                        .font(.title3)
                        .fontWeight(.semibold)

                    if !agent.agentDescription.isEmpty {
                        Text(agent.agentDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .frame(maxWidth: 400)
                    }
                }
                .xrayId("chat.emptyState.agentInfo")
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.blue)
                        .frame(width: 64, height: 64)
                        .background(Color.blue.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    Text("Quick Chat")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("Ask anything \u{2014} no agent profile attached.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .xrayId("chat.emptyState.freeformInfo")
            }

            let suggestions = emptyStateSuggestions

            VStack(spacing: 8) {
                Text("Try asking")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.tertiary)

                VStack(spacing: 6) {
                    ForEach(Array(suggestions.starters.prefix(4).enumerated()), id: \.offset) { index, prompt in
                        Button {
                            inputText = prompt
                        } label: {
                            HStack {
                                Text(prompt)
                                    .font(.callout)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(.background)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .xrayId("chat.emptyState.starter.\(index)")
                    }
                }
                .frame(maxWidth: 440)
            }
            .xrayId("chat.emptyState.suggestions")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
        .padding(.bottom, 20)
        .xrayId("chat.emptyState")
    }

    @ViewBuilder
    private func groupEmptyStateHeader(_ group: AgentGroup) -> some View {
        VStack(spacing: 8) {
            Text(group.icon)
                .font(.system(size: 40))
                .frame(width: 64, height: 64)
                .background(Color.fromAgentColor(group.color).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 16))

            Text(group.name)
                .font(.title3)
                .fontWeight(.semibold)

            if !group.groupDescription.isEmpty {
                Text(group.groupDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: 400)
            }

            let agentNames = group.agentIds.compactMap { agentId in
                allAgents.first { $0.id == agentId }?.name
            }
            if !agentNames.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "person.3")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(agentNames.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .xrayId("chat.emptyState.groupInfo")
    }

    // MARK: - Action Chips

    @ViewBuilder
    private var actionChipsStrip: some View {
        let suggestions = emptyStateSuggestions

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(suggestions.chips, id: \.self) { chip in
                    Button {
                        inputText = chip
                    } label: {
                        Text(chip)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.accentColor.opacity(0.1))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .xrayId("chat.actionChip.\(chip.lowercased().replacingOccurrences(of: " ", with: "-"))")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .xrayId("chat.actionChips")
    }

    // MARK: - Image Input Handlers

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                loadImageFromProvider(provider)
            } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                    guard let urlData = data as? Data,
                          let url = URL(dataRepresentation: urlData, relativeTo: nil) else { return }
                    let ext = url.pathExtension.lowercased()
                    guard AttachmentStore.supportedExtensions.contains(ext) else { return }
                    guard let fileData = try? Data(contentsOf: url) else { return }
                    let mediaType = AttachmentStore.mediaTypeForURL(url)
                    guard AttachmentStore.validate(data: fileData, mediaType: mediaType) else { return }
                    DispatchQueue.main.async {
                        pendingAttachments.append((id: UUID(), data: fileData, mediaType: mediaType, fileName: url.lastPathComponent))
                    }
                }
            }
        }
    }

    private func loadImageFromProvider(_ provider: NSItemProvider) {
        let imageTypes: [UTType] = [.png, .jpeg, .tiff, .gif]
        for type in imageTypes {
            if provider.hasItemConformingToTypeIdentifier(type.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                    guard let data, AttachmentStore.validate(data: data, mediaType: "image/png") else { return }
                    let resolved: (Data, String)
                    if type == .tiff {
                        guard let nsImage = NSImage(data: data),
                              let converted = AttachmentStore.mediaTypeFromNSImage(nsImage) else { return }
                        resolved = converted
                    } else {
                        resolved = (data, AttachmentStore.mediaTypeFromData(data))
                    }
                    DispatchQueue.main.async {
                        pendingAttachments.append((id: UUID(), data: resolved.0, mediaType: resolved.1, fileName: "pasted.png"))
                    }
                }
                return
            }
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let data = try? Data(contentsOf: url) else { continue }
            let mediaType = AttachmentStore.mediaTypeForURL(url)
            guard AttachmentStore.validate(data: data, mediaType: mediaType) else { continue }
            pendingAttachments.append((id: UUID(), data: data, mediaType: mediaType, fileName: url.lastPathComponent))
        }
    }

    // MARK: - Streaming Bubble

    @ViewBuilder
    private var streamingBubble: some View {
        let appearance = streamingAgentAppearance
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: appearance?.icon ?? "cpu")
                        .font(.caption2)
                        .foregroundStyle(appearance?.color ?? .purple)
                    Text(streamingDisplayName)
                        .font(.caption)
                        .foregroundStyle(appearance?.color ?? .secondary)
                    if let key = activeStreamSessionKey,
                       let state = appState.sessionActivity[key] {
                        Text(state.displayLabel)
                            .font(.caption2)
                            .foregroundStyle(state.displayColor.opacity(0.8))
                    }
                }

                if let thinking = liveThinkingText {
                    streamingThinkingSection(thinking)
                }

                if let text = liveStreamingText {
                    MarkdownContent(text: text)
                } else if liveThinkingText == nil {
                    StreamingIndicator()
                }
            }
            .padding(.horizontal, appearance != nil ? 10 : 0)
            .padding(.vertical, appearance != nil ? 6 : 0)
            .background(appearance.map { $0.color.opacity(0.08) } ?? Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Spacer(minLength: 60)
        }
        .xrayId("chat.streamingBubble")
    }

    @ViewBuilder
    private func streamingThinkingSection(_ thinking: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isStreamingThinkingExpanded.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "brain")
                        .font(.caption2)
                        .foregroundStyle(.indigo)
                    Text("Thinking...")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.indigo)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isStreamingThinkingExpanded ? 90 : 0))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
            }
            .buttonStyle(.plain)
            .xrayId("chat.streamingThinkingToggle")
            .accessibilityLabel(isStreamingThinkingExpanded ? "Collapse thinking" : "Expand thinking")

            if isStreamingThinkingExpanded {
                Divider()
                ScrollView {
                    Text(thinking)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .italic()
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                }
                .frame(maxHeight: 200)
            }
        }
        .background(.indigo.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(.indigo.opacity(0.15), lineWidth: 0.5)
        )
    }

    // MARK: - Session Summary Helpers

    private var sessionsForSummary: [AppState.SessionInfo] {
        guard let convo = conversation else { return [] }
        return convo.sessions.compactMap { session in
            appState.activeSessions[session.id]
        }
    }

    private var toolCallsForSummary: [String: [AppState.ToolCallInfo]] {
        guard let convo = conversation else { return [:] }
        var result: [String: [AppState.ToolCallInfo]] = [:]
        for session in convo.sessions {
            let key = session.id.uuidString
            if let calls = appState.toolCalls[key] {
                result[key] = calls
            }
        }
        return result
    }

    private var summaryDuration: TimeInterval? {
        guard let start = processingStartTime else { return nil }
        return Date().timeIntervalSince(start)
    }

    // MARK: - Agent Question Helpers

    private var pendingQuestionsForCurrentConversation: [AppState.AgentQuestion] {
        guard let convo = conversation else { return [] }
        return convo.sessions.compactMap { session in
            appState.pendingQuestions[session.id.uuidString]
        }
    }

    private func agentNameForQuestion(_ question: AppState.AgentQuestion) -> String {
        guard let convo = conversation else { return "Agent" }
        if let session = convo.sessions.first(where: { $0.id.uuidString == question.sessionId }) {
            return session.agent?.name ?? "Agent"
        }
        return "Agent"
    }

    private func agentColorForQuestion(_ question: AppState.AgentQuestion) -> Color? {
        guard let convo = conversation, convo.sessions.count > 1,
              let session = convo.sessions.first(where: { $0.id.uuidString == question.sessionId }),
              let agent = session.agent else { return nil }
        return Color.fromAgentColor(agent.color)
    }

    // MARK: - Helpers

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if isProcessing {
            withAnimation { proxy.scrollTo("streaming", anchor: .bottom) }
        } else if let lastId = sortedMessages.last?.id {
            withAnimation { proxy.scrollTo(lastId, anchor: .bottom) }
        }
    }

    private var participantSummary: String {
        guard let convo = conversation else { return "" }
        let names = convo.participants.map(\.displayName)
        return names.joined(separator: " + ")
    }

    private func modelShortName(_ model: String) -> String {
        if model.contains("sonnet") { return "sonnet" }
        if model.contains("opus") { return "opus" }
        if model.contains("haiku") { return "haiku" }
        return model
    }

    private func commitRename() {
        let name = editedTopic.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty, let convo = conversation {
            convo.topic = name
            try? modelContext.save()
        }
        isEditingTopic = false
    }

    private func cancelRename() {
        isEditingTopic = false
    }

    // MARK: - Auto Naming

    private func autoNameConversation(_ convo: Conversation, firstMessage: String) {
        guard convo.topic == "New Chat" || convo.topic == nil else { return }

        let trimmed = firstMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let truncated: String
        if trimmed.count <= 50 {
            truncated = trimmed
        } else {
            let cutoff = trimmed.index(trimmed.startIndex, offsetBy: 50)
            let substring = trimmed[..<cutoff]
            if let lastSpace = substring.lastIndex(of: " ") {
                truncated = String(substring[..<lastSpace]) + "..."
            } else {
                truncated = String(substring) + "..."
            }
        }

        let agentName = convo.primarySession?.agent?.name
        convo.topic = agentName.map { "\($0): \(truncated)" } ?? truncated
    }

    private func agentMentionHint(for agent: Agent) -> String {
        conversation?.sessions.contains(where: { $0.agent?.id == agent.id }) == true ? "In chat" : "Adds on send"
    }

    private func insertMentionCompletion(agentName: String) {
        guard let r = inputText.range(of: #"@([^\s@]*)$"#, options: .regularExpression) else { return }
        inputText.replaceSubrange(r, with: "@\(agentName) ")
    }

    /// Freeform / quick chat: ensure one `Session` + Claude participant exist before first model call.
    private func ensureFreeformSidecarSession(in convo: Conversation) -> Session? {
        if let existing = convo.primarySession, convo.sessions.count == 1, existing.agent == nil {
            return existing
        }
        if let s = convo.primarySession, s.agent != nil { return s }
        let session = Session(
            agent: nil,
            mission: nil,
            mode: .interactive,
            workingDirectory: appState.instanceWorkingDirectory ?? NSHomeDirectory()
        )
        session.conversations = [convo]
        convo.sessions.append(session)
        let agentParticipant = Participant(
            type: .agentSession(sessionId: session.id),
            displayName: "Claude"
        )
        agentParticipant.conversation = convo
        convo.participants.append(agentParticipant)
        modelContext.insert(session)
        modelContext.insert(agentParticipant)
        try? modelContext.save()
        return session
    }

    private func participantForSession(_ session: Session, in convo: Conversation) -> Participant? {
        convo.participants.first {
            if case .agentSession(let sid) = $0.type { return sid == session.id }
            return false
        }
    }

    // MARK: - Plan Mode Actions

    private func executePlan() {
        planModeEnabled = false
        lastPlanResponseMessageId = nil
        inputText = "Go ahead and execute the plan above."
        sendMessage()
    }

    // MARK: - Send Message

    private func sendMessage() {
        let rawInput = inputText
        let text = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = pendingAttachments
        guard !text.isEmpty || !attachments.isEmpty, let convo = conversation else {
            return
        }

        if text.first == "/", !text.hasPrefix("//"), let slash = ChatSendRouting.parseSlashCommand(rawInput) {
            switch slash {
            case .help:
                showSlashHelp = true
            case .topic(let title):
                let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty {
                    convo.topic = t
                    try? modelContext.save()
                }
            case .agents:
                showAddAgentsSheet = true
            case .unknown(let name):
                unknownSlashName = name
                showUnknownSlash = true
            }
            if case .topic = slash, text.split(separator: " ").count <= 1, slash != .help {
                // /topic with no title — still consume input? skip clear
            }
            inputText = ""
            pendingAttachments = []
            return
        }

        inputText = ""
        pendingAttachments = []

        let mentionNames = ChatSendRouting.mentionedAgentNames(in: text)
        let (resolvedMentionAgents, unknownMentions) = ChatSendRouting.resolveMentionedAgents(
            names: mentionNames,
            agents: allAgents
        )
        if !unknownMentions.isEmpty {
            mentionErrorDetail = "Unknown agent(s): \(unknownMentions.joined(separator: ", "))"
            showMentionError = true
            return
        }

        for ag in resolvedMentionAgents {
            if convo.sessions.contains(where: { $0.agent?.id == ag.id }) { continue }
            let primaryWd = (convo.primarySession?.workingDirectory ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let wd = !primaryWd.isEmpty ? primaryWd : ""
            let session = Session(
                agent: ag,
                mission: convo.primarySession?.mission,
                mode: convo.primarySession?.mode ?? .interactive,
                workingDirectory: wd
            )
            session.conversations = [convo]
            convo.sessions.append(session)
            let p = Participant(type: .agentSession(sessionId: session.id), displayName: ag.name)
            p.conversation = convo
            convo.participants.append(p)
            modelContext.insert(session)
            modelContext.insert(p)
        }
        GroupWorkingDirectory.ensureShared(
            for: convo,
            instanceDefault: appState.instanceWorkingDirectory,
            modelContext: modelContext
        )
        try? modelContext.save()

        var targetSessions: [Session] = conversationSessions.sorted(by: { $0.startedAt < $1.startedAt })
        if targetSessions.isEmpty {
            if let s = ensureFreeformSidecarSession(in: convo) {
                targetSessions = [s]
            }
        }

        guard !targetSessions.isEmpty else {
            mentionErrorDetail = "No agent session to send to. Pick an agent or use New Session."
            showMentionError = true
            return
        }

        let userParticipant = convo.participants.first { $0.type == .user }
        let isFirstChat = convo.messages.filter({ $0.type == .chat }).isEmpty

        let message = ConversationMessage(
            senderParticipantId: userParticipant?.id,
            text: text,
            type: .chat,
            conversation: convo
        )

        var wireAttachments: [WireAttachment] = []
        for item in attachments {
            let attachment = AttachmentStore.save(data: item.data, mediaType: item.mediaType, fileName: item.fileName)
            attachment.message = message
            message.attachments.append(attachment)
            modelContext.insert(attachment)
            wireAttachments.append(WireAttachment(
                data: item.data.base64EncodedString(),
                mediaType: item.mediaType,
                fileName: item.fileName
            ))
        }

        convo.messages.append(message)
        modelContext.insert(message)
        if isFirstChat {
            let nameHint: String
            if text.isEmpty {
                let fileCount = attachments.count
                nameHint = "Shared \(fileCount) file\(fileCount == 1 ? "" : "s")"
            } else {
                nameHint = text
            }
            autoNameConversation(convo, firstMessage: nameHint)
        }

        try? modelContext.save()

        guard appState.sidecarStatus == .connected,
              let manager = appState.sidecarManager else {
            isProcessing = false
            mentionErrorDetail = "Sidecar not connected. Check the connection status and try again."
            showMentionError = true
            return
        }

        isProcessing = true
        processingStartTime = Date()

        let mentionHighlightNames = resolvedMentionAgents.map(\.name)
        let currentPlanMode = planModeEnabled
        Task { @MainActor in
            await runSequentialAgentTurns(
                convo: convo,
                targetSessions: targetSessions,
                latestUserText: text,
                highlightedMentionAgentNames: mentionHighlightNames,
                wireAttachments: wireAttachments,
                manager: manager,
                planMode: currentPlanMode
            )
        }
    }

    @MainActor
    private func runSequentialAgentTurns(
        convo: Conversation,
        targetSessions: [Session],
        latestUserText: String,
        highlightedMentionAgentNames: [String],
        wireAttachments: [WireAttachment],
        manager: SidecarManager,
        planMode: Bool = false
    ) async {
        GroupWorkingDirectory.ensureShared(
            for: convo,
            instanceDefault: appState.instanceWorkingDirectory,
            modelContext: modelContext
        )
        for session in targetSessions {
            do {
                try await GitWorkspacePreparer.prepareIfNeeded(session: session, modelContext: modelContext)
            } catch {
                isProcessing = false
                activeStreamSessionKey = nil
                let key = session.id.uuidString
                appState.lastSessionEvent[key] = .error("Workspace: \(error.localizedDescription)")
                return
            }
        }
        let participants = convo.participants
        let provisioner = AgentProvisioner(modelContext: modelContext)
        let fanOutContext = GroupPeerFanOutContext()

        for (index, session) in targetSessions.enumerated() {
            let sidecarKey = session.id.uuidString
            activeStreamSessionKey = sidecarKey
            streamingDisplayName = session.agent?.name ?? "Claude"

            appState.streamingText.removeValue(forKey: sidecarKey)
            appState.thinkingText.removeValue(forKey: sidecarKey)
            appState.lastSessionEvent.removeValue(forKey: sidecarKey)
            appState.sessionActivity[sidecarKey] = .idle

            var createConfig: AgentConfig?
            if !appState.createdSessions.contains(sidecarKey) {
                if let agent = session.agent {
                    let (cfg, _) = provisioner.provision(
                        agent: agent,
                        mission: session.mission,
                        workingDirOverride: session.workingDirectory
                    )
                    createConfig = cfg
                } else {
                    createConfig = makeFreeformAgentConfig()
                }
            }

            let sourceGroup: AgentGroup? = {
                guard let gid = convo.sourceGroupId else { return nil }
                let desc = FetchDescriptor<AgentGroup>(predicate: #Predicate { $0.id == gid })
                return try? modelContext.fetch(desc).first
            }()
            let groupInstruction = sourceGroup?.groupInstruction
            let agentRole: GroupRole? = {
                guard let group = sourceGroup, let agentId = session.agent?.id else { return nil }
                return group.roleFor(agentId: agentId)
            }()

            let promptText = GroupPromptBuilder.buildMessageText(
                conversation: convo,
                targetSession: session,
                latestUserMessageText: latestUserText,
                participants: participants,
                highlightedMentionAgentNames: highlightedMentionAgentNames,
                groupInstruction: groupInstruction,
                role: agentRole
            )

            do {
                if let config = createConfig {
                    try await manager.send(.sessionCreate(
                        conversationId: sidecarKey,
                        agentConfig: config
                    ))
                    appState.createdSessions.insert(sidecarKey)
                }
                try await manager.send(.sessionMessage(
                    sessionId: sidecarKey,
                    text: promptText,
                    attachments: wireAttachments,
                    planMode: planMode
                ))
            } catch {
                isProcessing = false
                activeStreamSessionKey = nil
                appState.lastSessionEvent[sidecarKey] = .error("Failed to send: \(error.localizedDescription)")
                return
            }

            await waitForSessionCompletion(sidecarKey: sidecarKey)

            guard let stillConvo = conversation, stillConvo.id == convo.id else {
                isProcessing = false
                activeStreamSessionKey = nil
                return
            }

            if let reply = finalizeAssistantStreamIntoMessage(
                convo: stillConvo,
                session: session,
                sidecarKey: sidecarKey
            ) {
                if planMode {
                    lastPlanResponseMessageId = reply.id
                }
                let pendingUserTurnIds = Set(targetSessions.suffix(from: index + 1).map(\.id))
                await fanOutPeerNotifications(
                    fromSession: session,
                    triggerMessage: reply,
                    convo: stillConvo,
                    skipRecipientSessionIds: pendingUserTurnIds,
                    manager: manager,
                    provisioner: provisioner,
                    participants: participants,
                    context: fanOutContext
                )
            }
        }

        isProcessing = false
        activeStreamSessionKey = nil
        streamingDisplayName = "Claude"
    }

    private func makeFreeformAgentConfig() -> AgentConfig {
        AgentConfig(
            name: "Claude",
            systemPrompt: "You are a helpful assistant. Be concise and clear.",
            allowedTools: [],
            mcpServers: [],
            model: "claude-sonnet-4-6",
            maxTurns: 1,
            maxBudget: nil,
            maxThinkingTokens: 10000,
            workingDirectory: appState.instanceWorkingDirectory ?? NSHomeDirectory(),
            skills: []
        )
    }

    /// Delivers peer messages to other agents (`may_reply`); skips recipients that still have their user-turn prompt pending in `runSequentialAgentTurns`.
    @MainActor
    private func fanOutPeerNotifications(
        fromSession: Session,
        triggerMessage: ConversationMessage,
        convo: Conversation,
        skipRecipientSessionIds: Set<UUID>,
        manager: SidecarManager,
        provisioner: AgentProvisioner,
        participants: [Participant],
        context: GroupPeerFanOutContext
    ) async {
        guard convo.sessions.count > 1 else { return }

        // Check auto-reply toggle on the source group
        if let gid = convo.sourceGroupId {
            let desc = FetchDescriptor<AgentGroup>(predicate: #Predicate { $0.id == gid })
            if let group = try? modelContext.fetch(desc).first, !group.autoReplyEnabled {
                return
            }
        }

        let senderLabel = GroupPromptBuilder.senderDisplayLabel(for: triggerMessage, participants: participants)
        let sortedOthers = convo.sessions
            .filter { $0.id != fromSession.id && !skipRecipientSessionIds.contains($0.id) }
            .sorted { $0.startedAt < $1.startedAt }

        for other in sortedOthers {
            guard context.trySchedulePeerDelivery(targetSessionId: other.id, triggerMessageId: triggerMessage.id) else {
                continue
            }

            let key = other.id.uuidString
            activeStreamSessionKey = key
            streamingDisplayName = other.agent?.name ?? "Claude"
            appState.streamingText.removeValue(forKey: key)
            appState.thinkingText.removeValue(forKey: key)
            appState.lastSessionEvent.removeValue(forKey: key)
            appState.sessionActivity[key] = .idle

            var createConfig: AgentConfig?
            if !appState.createdSessions.contains(key) {
                if let agent = other.agent {
                    let (cfg, _) = provisioner.provision(
                        agent: agent,
                        mission: other.mission,
                        workingDirOverride: other.workingDirectory
                    )
                    createConfig = cfg
                } else {
                    createConfig = makeFreeformAgentConfig()
                }
            }

            let peerRole: GroupRole? = {
                guard let gid = convo.sourceGroupId else { return nil }
                let desc = FetchDescriptor<AgentGroup>(predicate: #Predicate { $0.id == gid })
                guard let group = try? modelContext.fetch(desc).first,
                      let agentId = other.agent?.id else { return nil }
                return group.roleFor(agentId: agentId)
            }()

            let prompt = GroupPromptBuilder.buildPeerNotifyPrompt(
                senderLabel: senderLabel,
                peerMessageText: triggerMessage.text,
                recipientSession: other,
                role: peerRole
            )

            do {
                if let config = createConfig {
                    try await manager.send(.sessionCreate(
                        conversationId: key,
                        agentConfig: config
                    ))
                    appState.createdSessions.insert(key)
                }
                try await manager.send(.sessionMessage(
                    sessionId: key,
                    text: prompt,
                    attachments: []
                ))
            } catch {
                appState.lastSessionEvent[key] = .error("Peer notify failed: \(error.localizedDescription)")
                continue
            }

            await waitForSessionCompletion(sidecarKey: key)

            guard let liveConvo = conversation, liveConvo.id == convo.id else { return }

            if let peerReply = finalizeAssistantStreamIntoMessage(convo: liveConvo, session: other, sidecarKey: key) {
                await fanOutPeerNotifications(
                    fromSession: other,
                    triggerMessage: peerReply,
                    convo: liveConvo,
                    skipRecipientSessionIds: [],
                    manager: manager,
                    provisioner: provisioner,
                    participants: participants,
                    context: context
                )
            }
        }
    }

    private func waitForSessionCompletion(sidecarKey: String) async {
        let maxWait = 600
        var iterations = 0
        while iterations < maxWait {
            if let ev = await MainActor.run(body: { appState.lastSessionEvent[sidecarKey] }) {
                switch ev {
                case .result, .error:
                    return
                }
            }
            try? await Task.sleep(for: .milliseconds(100))
            iterations += 1
        }
    }

    // MARK: - Session Events

    private func checkForPendingResponse() {
        guard let key = streamSessionKeyForUI else { return }
        if let event = appState.lastSessionEvent[key] {
            isProcessing = true
            switch event {
            case .result:
                collectResponseIfSingle()
            case .error(let msg):
                collectResponseIfSingle(errorMessage: msg)
            }
            return
        }

        if let text = appState.streamingText[key], !text.isEmpty, !isProcessing {
            isProcessing = true
        }
    }

    private func checkForCompletion(events: [String: AppState.SessionEventKind]? = nil) {
        guard let key = streamSessionKeyForUI else { return }
        let source = events ?? appState.lastSessionEvent
        guard let event = source[key] else { return }

        isProcessing = true
        switch event {
        case .result:
            collectResponseIfSingle()
        case .error(let msg):
            collectResponseIfSingle(errorMessage: msg)
        }
    }

    /// Legacy path when not using sequential multi-send (e.g. recovery).
    private func collectResponseIfSingle(errorMessage: String? = nil) {
        guard let key = streamSessionKeyForUI,
              let convo = conversation,
              let session = convo.sessions.first(where: { $0.id.uuidString == key }) else {
            isProcessing = false
            return
        }
        _ = finalizeAssistantStreamIntoMessage(convo: convo, session: session, sidecarKey: key, errorMessage: errorMessage)
        isProcessing = false
        activeStreamSessionKey = nil
    }

    @discardableResult
    private func finalizeAssistantStreamIntoMessage(
        convo: Conversation,
        session: Session,
        sidecarKey: String,
        errorMessage: String? = nil
    ) -> ConversationMessage? {
        var err = errorMessage
        if err == nil, case .error(let m) = appState.lastSessionEvent[sidecarKey] {
            err = m
        }
        let streamedText = appState.streamingText[sidecarKey] ?? ""
        let hasImages = !(appState.streamingImages[sidecarKey]?.isEmpty ?? true)
        let hasFileCards = !(appState.streamingFileCards[sidecarKey]?.isEmpty ?? true)
        guard !streamedText.isEmpty || err != nil || hasImages || hasFileCards else {
            return nil
        }
        let responseText = !streamedText.isEmpty ? streamedText : (err ?? "")

        let agentParticipant = participantForSession(session, in: convo)
        let response = ConversationMessage(
            senderParticipantId: agentParticipant?.id,
            text: responseText,
            type: .chat,
            conversation: convo
        )
        let thinking = appState.thinkingText[sidecarKey]
        if let thinking, !thinking.isEmpty {
            response.thinkingText = thinking
        }
        convo.messages.append(response)
        modelContext.insert(response)
        GroupPromptBuilder.advanceWatermark(session: session, assistantMessage: response)

        // Finalize accumulated agent images into MessageAttachment records
        if let images = appState.streamingImages[sidecarKey] {
            for img in images {
                guard let data = Data(base64Encoded: img.data) else { continue }
                let ext = img.mediaType.components(separatedBy: "/").last ?? "png"
                let name = "agent-image-\(UUID().uuidString.prefix(8)).\(ext)"
                let attachment = AttachmentStore.save(data: data, mediaType: img.mediaType, fileName: name)
                attachment.message = response
                modelContext.insert(attachment)
                response.attachments.append(attachment)
            }
            appState.streamingImages.removeValue(forKey: sidecarKey)
        }

        // Finalize accumulated file cards into MessageAttachment records
        if let cards = appState.streamingFileCards[sidecarKey] {
            for card in cards {
                let mt = card.type == "html" ? "text/html" : "application/pdf"
                let attachment = MessageAttachment(mediaType: mt, fileName: card.name, fileSize: 0)
                attachment.localFilePath = card.path
                attachment.message = response
                modelContext.insert(attachment)
                response.attachments.append(attachment)
            }
            appState.streamingFileCards.removeValue(forKey: sidecarKey)
        }

        try? modelContext.save()
        appState.streamingText.removeValue(forKey: sidecarKey)
        appState.thinkingText.removeValue(forKey: sidecarKey)
        appState.lastSessionEvent.removeValue(forKey: sidecarKey)
        isStreamingThinkingExpanded = false
        return response
    }

    // MARK: - Actions

    private enum ChatTranscriptExportKind {
        case markdown, html, pdf
    }

    private enum ChatTranscriptExportDestination {
        case save, share
    }

    private func exportChatTranscript(kind: ChatTranscriptExportKind, destination: ChatTranscriptExportDestination) async {
        guard let snap = chatExportSnapshot() else { return }
        let base = ChatTranscriptExport.suggestedBaseFileName(for: snap)
        switch (kind, destination) {
        case (.markdown, .save):
            let md = ChatTranscriptExport.markdown(snap)
            guard let url = await ChatExportPresenters.runSavePanel(
                suggestedFileName: "\(base).md",
                allowedTypes: [ChatExportPresenters.markdownType]
            ) else { return }
            do {
                try Data(md.utf8).write(to: url, options: .atomic)
            } catch {
                print("[ChatView] Export markdown failed: \(error)")
            }
        case (.html, .save):
            let html = ChatTranscriptExport.html(snap)
            guard let url = await ChatExportPresenters.runSavePanel(
                suggestedFileName: "\(base).html",
                allowedTypes: [.html]
            ) else { return }
            do {
                try Data(html.utf8).write(to: url, options: .atomic)
            } catch {
                print("[ChatView] Export HTML failed: \(error)")
            }
        case (.pdf, .save):
            let html = ChatTranscriptExport.html(snap)
            let renderer = ChatTranscriptPDFRenderer()
            do {
                let data = try await renderer.renderPDF(html: html)
                guard let url = await ChatExportPresenters.runSavePanel(
                    suggestedFileName: "\(base).pdf",
                    allowedTypes: [.pdf]
                ) else { return }
                try data.write(to: url, options: .atomic)
            } catch {
                print("[ChatView] Export PDF failed: \(error)")
            }
        case (.markdown, .share):
            let md = ChatTranscriptExport.markdown(snap)
            let data = Data(md.utf8)
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).md")
            do {
                try data.write(to: temp, options: .atomic)
                let coord = ShareTempFileCoordinator(url: temp) { self.shareCoordinator = nil }
                shareCoordinator = coord
                ChatExportPresenters.presentSharePicker(for: temp, coordinator: coord)
            } catch {
                print("[ChatView] Share markdown failed: \(error)")
            }
        case (.html, .share):
            let html = ChatTranscriptExport.html(snap)
            let data = Data(html.utf8)
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).html")
            do {
                try data.write(to: temp, options: .atomic)
                let coord = ShareTempFileCoordinator(url: temp) { self.shareCoordinator = nil }
                shareCoordinator = coord
                ChatExportPresenters.presentSharePicker(for: temp, coordinator: coord)
            } catch {
                print("[ChatView] Share HTML failed: \(error)")
            }
        case (.pdf, .share):
            let html = ChatTranscriptExport.html(snap)
            let renderer = ChatTranscriptPDFRenderer()
            do {
                let data = try await renderer.renderPDF(html: html)
                let temp = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pdf")
                try data.write(to: temp, options: .atomic)
                let coord = ShareTempFileCoordinator(url: temp) { self.shareCoordinator = nil }
                shareCoordinator = coord
                ChatExportPresenters.presentSharePicker(for: temp, coordinator: coord)
            } catch {
                print("[ChatView] Share PDF failed: \(error)")
            }
        }
    }

    private func forkConversation() {
        guard let newConvo = cloneConversationForFork(from: conversation, throughMessage: nil),
              let oldPrimary = conversation?.primarySession,
              let newPrimary = newConvo.primarySession else { return }
        appState.selectedConversationId = newConvo.id
        Task {
            try? await appState.sidecarManager?.send(.sessionFork(
                parentSessionId: oldPrimary.id.uuidString,
                childSessionId: newPrimary.id.uuidString
            ))
        }
    }

    private func forkFromMessage(_ pivot: ConversationMessage) {
        guard let newConvo = cloneConversationForFork(from: conversation, throughMessage: pivot),
              let oldPrimary = conversation?.primarySession,
              let newPrimary = newConvo.primarySession else { return }
        appState.selectedConversationId = newConvo.id
        Task {
            try? await appState.sidecarManager?.send(.sessionFork(
                parentSessionId: oldPrimary.id.uuidString,
                childSessionId: newPrimary.id.uuidString
            ))
        }
    }

    /// Duplicate conversation structure and optionally copy messages up to `throughMessage` (inclusive).
    private func cloneConversationForFork(from source: Conversation?, throughMessage: ConversationMessage?) -> Conversation? {
        guard let source else { return nil }
        let topicBase = source.topic ?? "Chat"
        let newConvo = Conversation(topic: topicBase + " (fork)")
        newConvo.parentConversationId = source.id

        let userParticipant = Participant(type: .user, displayName: "You")
        userParticipant.conversation = newConvo
        newConvo.participants.append(userParticipant)

        var oldToNewSession: [UUID: Session] = [:]
        for oldSession in source.sessions.sorted(by: { $0.startedAt < $1.startedAt }) {
            let newSession = Session(
                agent: oldSession.agent,
                mission: oldSession.mission,
                mode: oldSession.mode,
                workingDirectory: oldSession.workingDirectory,
                workspaceType: oldSession.workspaceType
            )
            let agent = oldSession.agent
            newSession.conversations = [newConvo]
            newConvo.sessions.append(newSession)
            oldToNewSession[oldSession.id] = newSession

            let p = Participant(type: .agentSession(sessionId: newSession.id), displayName: agent?.name ?? "Agent")
            p.conversation = newConvo
            newConvo.participants.append(p)
            modelContext.insert(newSession)
        }

        let ordered = source.messages.sorted { $0.timestamp < $1.timestamp }
        let slice: [ConversationMessage]
        if let pivot = throughMessage, let idx = ordered.firstIndex(where: { $0.id == pivot.id }) {
            slice = Array(ordered[...idx])
        } else {
            slice = ordered
        }

        for oldMsg in slice where oldMsg.type == .chat {
            let newSender: UUID? = {
                guard let sid = oldMsg.senderParticipantId,
                      let oldP = source.participants.first(where: { $0.id == sid }) else { return userParticipant.id }
                if oldP.type == .user { return userParticipant.id }
                if case .agentSession(let osid) = oldP.type,
                   let ns = oldToNewSession[osid],
                   let np = participantForSession(ns, in: newConvo) {
                    return np.id
                }
                return userParticipant.id
            }()
            let nm = ConversationMessage(senderParticipantId: newSender, text: oldMsg.text, type: .chat, conversation: newConvo)
            nm.timestamp = oldMsg.timestamp
            nm.thinkingText = oldMsg.thinkingText
            newConvo.messages.append(nm)
            modelContext.insert(nm)
        }

        modelContext.insert(newConvo)
        try? modelContext.save()
        return newConvo
    }

    private func pauseSession() {
        guard let convo = conversation else { return }
        for session in convo.sessions {
            let key = session.id.uuidString
            appState.sendToSidecar(.sessionPause(sessionId: key))
            appState.pendingQuestions.removeValue(forKey: key)
            session.status = .paused
        }
        try? modelContext.save()
    }

    private func resumeSession() {
        guard let convo = conversation,
              let session = convo.primarySession,
              let claudeSessionId = session.claudeSessionId else { return }
        let sessionId = session.id.uuidString
        appState.sendToSidecar(.sessionResume(sessionId: sessionId, claudeSessionId: claudeSessionId))
        session.status = .active
        convo.status = .active
        try? modelContext.save()
    }

    private func closeConversation(_ convo: Conversation) {
        convo.status = .closed
        convo.closedAt = Date()
        for session in convo.sessions {
            let key = session.id.uuidString
            appState.sendToSidecar(.sessionPause(sessionId: key))
            appState.pendingQuestions.removeValue(forKey: key)
            session.status = .paused
        }
        try? modelContext.save()
    }

    private func clearMessages() {
        guard let convo = conversation else { return }
        for message in convo.messages {
            modelContext.delete(message)
        }
        convo.messages.removeAll()
        try? modelContext.save()
    }

    private func duplicateConversation(_ convo: Conversation) {
        let newConvo = Conversation(topic: (convo.topic ?? "Untitled") + " (copy)")
        let userParticipant = Participant(type: .user, displayName: "You")
        userParticipant.conversation = newConvo
        newConvo.participants.append(userParticipant)

        for session in convo.sessions.sorted(by: { $0.startedAt < $1.startedAt }) {
            let newSession = Session(
                agent: session.agent,
                mission: session.mission,
                mode: session.mode,
                workingDirectory: session.workingDirectory,
                workspaceType: session.workspaceType
            )
            newSession.conversations = [newConvo]
            newConvo.sessions.append(newSession)

            let displayName = session.agent?.name ?? "Agent"
            let agentParticipant = Participant(
                type: .agentSession(sessionId: newSession.id),
                displayName: displayName
            )
            agentParticipant.conversation = newConvo
            newConvo.participants.append(agentParticipant)
            modelContext.insert(newSession)
        }

        modelContext.insert(newConvo)
        try? modelContext.save()
        appState.selectedConversationId = newConvo.id
    }
}