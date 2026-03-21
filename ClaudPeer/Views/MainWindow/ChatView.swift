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
    @State private var sessionCreated = false
    @State private var lastTokenTime: Date?
    @State private var isEditingTopic = false
    @State private var editedTopic = ""
    @State private var showClearConfirmation = false
    @State private var pendingAttachments: [(id: UUID, data: Data, mediaType: String, fileName: String)] = []
    @State private var showFileImporter = false
    @State private var previewAttachment: MessageAttachment?
    @State private var previewImageFromPending: (data: Data, mediaType: String)?
    @FocusState private var topicFieldFocused: Bool

    @Query private var allConversations: [Conversation]

    private var conversation: Conversation? {
        allConversations.first { $0.id == conversationId }
    }

    private var sortedMessages: [ConversationMessage] {
        (conversation?.messages ?? []).sorted { $0.timestamp < $1.timestamp }
    }

    private var currentModel: String? {
        conversation?.session?.agent?.model
    }

    private var liveCost: Double? {
        appState.activeSessions[conversationId]?.cost
    }

    private var liveStreamingText: String? {
        let text = appState.streamingText[conversationId.uuidString]
        guard let text, !text.isEmpty else { return nil }
        return text
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
            let sessionId = conversationId.uuidString
            if texts[sessionId] != nil {
                lastTokenTime = Date()
            }
        }
        .onReceive(appState.$sidecarStatus) { status in
            if status != .connected && isProcessing {
                isProcessing = false
            }
        }
        .onChange(of: sortedMessages.count) { oldCount, newCount in
            if oldCount == 0, newCount > 0 {
                checkForPendingResponse()
            }
        }
        .task(id: isProcessing) {
            guard isProcessing else { return }
            while isProcessing {
                try? await Task.sleep(for: .seconds(3))
                guard isProcessing else { return }
                let sessionId = conversationId.uuidString
                let hasText = appState.streamingText[sessionId] != nil
                let stale = lastTokenTime.map { Date().timeIntervalSince($0) > 3 } ?? false
                if hasText && stale {
                    collectResponse()
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
    }

    // MARK: - Chat Header

    @ViewBuilder
    private var chatHeader: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                if isEditingTopic {
                    TextField("Conversation name", text: $editedTopic)
                        .textFieldStyle(.roundedBorder)
                        .font(.headline)
                        .focused($topicFieldFocused)
                        .frame(maxWidth: 300)
                        .onSubmit { commitRename() }
                        .onExitCommand { cancelRename() }
                        .accessibilityIdentifier("chat.topicField")
                } else {
                    Text(conversation?.topic ?? "Chat")
                        .font(.headline)
                        .lineLimit(1)
                        .accessibilityIdentifier("chat.topicTitle")
                    Button {
                        editedTopic = conversation?.topic ?? ""
                        isEditingTopic = true
                        topicFieldFocused = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Rename conversation")
                    .accessibilityIdentifier("chat.editTopicButton")
                    .accessibilityLabel("Rename conversation")
                }

                Spacer()

                if let model = currentModel {
                    Text(modelShortName(model))
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .clipShape(Capsule())
                        .accessibilityIdentifier("chat.modelPill")
                }

                if let cost = liveCost, cost > 0 {
                    Text(String(format: "$%.4f", cost))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .accessibilityIdentifier("chat.liveCostLabel")
                }
            }

            HStack(spacing: 4) {
                Text(participantSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("chat.participantSummary")
                Spacer()

                if let convo = conversation {
                    headerActions(convo)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    @ViewBuilder
    private func headerActions(_ convo: Conversation) -> some View {
        HStack(spacing: 6) {
            Button { forkConversation() } label: {
                Image(systemName: "arrow.branch")
            }
            .help("Fork conversation")
            .accessibilityIdentifier("chat.forkButton")
            .accessibilityLabel("Fork conversation")

            if convo.status == .active {
                Button { pauseSession() } label: {
                    Image(systemName: "pause.fill")
                }
                .help("Pause session")
                .accessibilityIdentifier("chat.pauseButton")
                .accessibilityLabel("Pause session")

                Button { closeConversation(convo) } label: {
                    Image(systemName: "stop.circle")
                }
                .help("Close session")
                .accessibilityIdentifier("chat.closeSessionButton")
                .accessibilityLabel("Close session")
            } else if convo.session?.status == .paused {
                Button { resumeSession() } label: {
                    Image(systemName: "play.fill")
                }
                .help("Resume session")
                .accessibilityIdentifier("chat.resumeButton")
                .accessibilityLabel("Resume session")
            }

            Menu {
                Button { showClearConfirmation = true } label: {
                    Label("Clear Messages", systemImage: "trash")
                }
                .accessibilityIdentifier("chat.moreOptions.clearMessages")
                Button { duplicateConversation(convo) } label: {
                    Label("Duplicate", systemImage: "doc.on.doc")
                }
                .accessibilityIdentifier("chat.moreOptions.duplicate")
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 20)
            .help("More options")
            .accessibilityIdentifier("chat.moreOptionsMenu")
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
                    ForEach(sortedMessages) { message in
                        MessageBubble(
                            message: message,
                            participants: conversation?.participants ?? [],
                            onTapAttachment: { attachment in
                                previewAttachment = attachment
                            }
                        )
                        .id(message.id)
                    }

                    if isProcessing {
                        streamingBubble
                            .id("streaming")
                    }
                }
                .padding()
            }
            .accessibilityIdentifier("chat.messageScrollView")
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

            HStack(alignment: .bottom, spacing: 8) {
                Button {
                    showFileImporter = true
                } label: {
                    Image(systemName: "paperclip")
                        .font(.body)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("chat.attachButton")
                .accessibilityLabel("Attach file")
                .help("Attach file")
                .disabled(isProcessing)

                PasteableTextField(
                    text: $inputText,
                    onImagePaste: { data, mediaType in
                        guard AttachmentStore.validate(data: data, mediaType: mediaType) else { return }
                        pendingAttachments.append((id: UUID(), data: data, mediaType: mediaType, fileName: "pasted.png"))
                    },
                    onSubmit: { if canSend { sendMessage() } }
                )
                .accessibilityIdentifier("chat.messageInput")

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("chat.sendButton")
                .accessibilityLabel("Send message")
                .disabled(!canSend)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Send message (⌘Return)")
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
                                .accessibilityIdentifier("chat.pendingAttachment.\(index)")
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
                            .accessibilityIdentifier("chat.pendingAttachment.\(index)")
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
                        .accessibilityIdentifier("chat.pendingAttachment.remove.\(index)")
                        .accessibilityLabel("Remove attachment")
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .accessibilityIdentifier("chat.pendingAttachments")
    }

    private func iconForMediaType(_ mediaType: String) -> String {
        switch mediaType {
        case "text/plain", "text/markdown": return "doc.text"
        case "application/pdf": return "doc.richtext"
        default: return mediaType.hasPrefix("image/") ? "photo" : "doc"
        }
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
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "cpu")
                        .font(.caption2)
                        .foregroundStyle(.purple)
                    Text("Claude")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let text = liveStreamingText {
                    MarkdownContent(text: text)
                } else {
                    StreamingIndicator()
                }
            }

            Spacer(minLength: 60)
        }
        .accessibilityIdentifier("chat.streamingBubble")
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

        let agentName = convo.session?.agent?.name
        convo.topic = agentName.map { "\($0): \(truncated)" } ?? truncated
    }

    // MARK: - Agent Participant

    private func ensureAgentParticipant(in convo: Conversation) -> Participant {
        if let existing = convo.participants.first(where: {
            if case .agentSession = $0.type { return true }
            return false
        }) {
            return existing
        }
        let agentParticipant = Participant(
            type: .agentSession(sessionId: convo.id),
            displayName: "Claude"
        )
        agentParticipant.conversation = convo
        convo.participants.append(agentParticipant)
        modelContext.insert(agentParticipant)
        try? modelContext.save()
        return agentParticipant
    }

    // MARK: - Send Message

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = pendingAttachments
        guard !text.isEmpty || !attachments.isEmpty, let convo = conversation else { return }
        inputText = ""
        pendingAttachments = []

        let isFirstMessage = convo.messages.filter({ $0.type == .chat }).isEmpty
        let userParticipant = convo.participants.first { $0.type == .user }
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

        if isFirstMessage {
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

        isProcessing = true

        let sessionId = convo.id.uuidString
        guard appState.sidecarStatus == .connected,
              let manager = appState.sidecarManager else {
            isProcessing = false
            return
        }

        _ = ensureAgentParticipant(in: convo)

        var createConfig: AgentConfig?
        if !sessionCreated {
            if let session = convo.session, let agent = session.agent {
                let provisioner = AgentProvisioner(modelContext: modelContext)
                let (provConfig, _) = provisioner.provision(agent: agent, mission: session.mission)
                createConfig = provConfig
            } else {
                createConfig = AgentConfig(
                    name: "Claude",
                    systemPrompt: "You are a helpful assistant. Be concise and clear.",
                    allowedTools: [],
                    mcpServers: [],
                    model: "claude-sonnet-4-6",
                    maxTurns: 1,
                    maxBudget: nil,
                    workingDirectory: NSHomeDirectory(),
                    skills: []
                )
            }
        }

        appState.streamingText.removeValue(forKey: sessionId)
        appState.lastSessionEvent.removeValue(forKey: sessionId)

        Task {
            if let config = createConfig {
                try? await manager.send(.sessionCreate(
                    conversationId: sessionId,
                    agentConfig: config
                ))
                await MainActor.run { sessionCreated = true }
            }
            try? await manager.send(.sessionMessage(
                sessionId: sessionId,
                text: text,
                attachments: wireAttachments
            ))
        }
    }

    // MARK: - Session Events

    private func checkForPendingResponse() {
        let sessionId = conversationId.uuidString
        if let event = appState.lastSessionEvent[sessionId] {
            isProcessing = true
            switch event {
            case .result:
                collectResponse()
            case .error(let msg):
                collectResponse(errorMessage: msg)
            }
            return
        }

        if let text = appState.streamingText[sessionId], !text.isEmpty, !isProcessing {
            isProcessing = true
        }
    }

    private func checkForCompletion(events: [String: AppState.SessionEventKind]? = nil) {
        let sessionId = conversationId.uuidString
        let source = events ?? appState.lastSessionEvent
        guard let event = source[sessionId] else { return }

        isProcessing = true
        switch event {
        case .result:
            collectResponse()
        case .error(let msg):
            collectResponse(errorMessage: msg)
        }
    }

    private func collectResponse(errorMessage: String? = nil) {
        guard isProcessing else { return }
        let sessionId = conversationId.uuidString
        guard let convo = conversation else { return }

        let streamedText = appState.streamingText[sessionId] ?? ""
        guard !streamedText.isEmpty || errorMessage != nil else {
            isProcessing = false
            return
        }
        let responseText = !streamedText.isEmpty ? streamedText : (errorMessage ?? "(no response)")

        let agentParticipant = convo.participants.first {
            if case .agentSession = $0.type { return true }
            return false
        }
        let response = ConversationMessage(
            senderParticipantId: agentParticipant?.id,
            text: responseText,
            type: .chat,
            conversation: convo
        )
        convo.messages.append(response)
        modelContext.insert(response)
        try? modelContext.save()
        appState.streamingText.removeValue(forKey: sessionId)
        appState.lastSessionEvent.removeValue(forKey: sessionId)
        isProcessing = false
    }

    // MARK: - Actions

    private func forkConversation() {
        let sessionId = conversationId.uuidString
        appState.sendToSidecar(.sessionFork(sessionId: sessionId))
    }

    private func pauseSession() {
        let sessionId = conversationId.uuidString
        appState.sendToSidecar(.sessionPause(sessionId: sessionId))
        conversation?.session?.status = .paused
        try? modelContext.save()
    }

    private func resumeSession() {
        guard let convo = conversation,
              let session = convo.session,
              let claudeSessionId = session.claudeSessionId else { return }
        let sessionId = convo.id.uuidString
        appState.sendToSidecar(.sessionResume(sessionId: sessionId, claudeSessionId: claudeSessionId))
        session.status = .active
        convo.status = .active
        try? modelContext.save()
    }

    private func closeConversation(_ convo: Conversation) {
        convo.status = .closed
        convo.closedAt = Date()
        if let session = convo.session {
            appState.sendToSidecar(.sessionPause(sessionId: convo.id.uuidString))
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

        if let session = convo.session, let agent = session.agent {
            let newSession = Session(agent: agent, mode: session.mode)
            newSession.mission = session.mission
            newSession.workingDirectory = session.workingDirectory
            newSession.workspaceType = session.workspaceType
            newConvo.session = newSession
            newSession.conversations = [newConvo]

            let agentParticipant = Participant(
                type: .agentSession(sessionId: newSession.id),
                displayName: agent.name
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