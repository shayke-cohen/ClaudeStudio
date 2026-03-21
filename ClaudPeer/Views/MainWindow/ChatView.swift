import SwiftUI
import SwiftData

struct ChatView: View {
    let conversationId: UUID
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @State private var inputText = ""
    @State private var isProcessing = false
    @FocusState private var inputFocused: Bool

    @Query private var allConversations: [Conversation]

    private var conversation: Conversation? {
        allConversations.first { $0.id == conversationId }
    }

    private var sortedMessages: [ConversationMessage] {
        (conversation?.messages ?? []).sorted { $0.timestamp < $1.timestamp }
    }

    var body: some View {
        VStack(spacing: 0) {
            chatHeader
            Divider()
            messageList
            Divider()
            inputArea
        }
    }

    @ViewBuilder
    private var chatHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(conversation?.topic ?? "Chat")
                    .font(.headline)
                Text(participantSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let convo = conversation {
                HStack(spacing: 8) {
                    Button {
                        // Fork conversation
                    } label: {
                        Image(systemName: "arrow.branch")
                    }
                    .help("Fork conversation")

                    if convo.status == .active {
                        Button {
                            // Pause
                        } label: {
                            Image(systemName: "pause.fill")
                        }
                        .help("Pause session")
                    }
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    @ViewBuilder
    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(sortedMessages) { message in
                        MessageBubble(
                            message: message,
                            participants: conversation?.participants ?? []
                        )
                        .id(message.id)
                    }

                    if isProcessing {
                        StreamingIndicator()
                            .id("streaming")
                    }
                }
                .padding()
            }
            .onChange(of: sortedMessages.count) { _, _ in
                if let lastId = sortedMessages.last?.id {
                    withAnimation {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var inputArea: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Type a message...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($inputFocused)
                .onSubmit {
                    if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        sendMessage()
                    }
                }

            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.borderless)
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isProcessing)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(12)
        .background(.bar)
    }

    private var participantSummary: String {
        guard let convo = conversation else { return "" }
        let names = convo.participants.map(\.displayName)
        return names.joined(separator: " + ")
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let convo = conversation else { return }
        inputText = ""

        let userParticipant = convo.participants.first { $0.type == .user }
        let message = ConversationMessage(
            senderParticipantId: userParticipant?.id,
            text: text,
            type: .chat,
            conversation: convo
        )
        convo.messages.append(message)
        modelContext.insert(message)
        try? modelContext.save()

        isProcessing = true

        let sessionId = convo.id.uuidString
        if appState.sidecarStatus == .connected {
            if convo.messages.count <= 1 {
                if let session = convo.session, let agent = session.agent {
                    let provisioner = AgentProvisioner(modelContext: modelContext)
                    let (config, _) = provisioner.provision(agent: agent, mission: session.mission)
                    appState.sendToSidecar(.sessionCreate(.init(
                        conversationId: sessionId,
                        agentConfig: config
                    )))
                }
            }
            appState.sendToSidecar(.sessionMessage(.init(
                sessionId: sessionId,
                text: text
            )))
        }

        Task {
            try? await Task.sleep(for: .seconds(1))
            if let streamedText = appState.streamingText[sessionId], !streamedText.isEmpty {
                let agentParticipant = convo.participants.first {
                    if case .agentSession = $0.type { return true }
                    return false
                }
                let response = ConversationMessage(
                    senderParticipantId: agentParticipant?.id,
                    text: streamedText,
                    type: .chat,
                    conversation: convo
                )
                convo.messages.append(response)
                modelContext.insert(response)
                try? modelContext.save()
                appState.streamingText.removeValue(forKey: sessionId)
            }
            isProcessing = false
        }
    }
}
