import SwiftUI
import SwiftData

/// Shows a "potential" chat for a selected agent or group.
/// The actual conversation and sessions are only created when the user sends the first message.
struct PendingChatView: View {
    let agent: Agent?
    let group: AgentGroup?

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query private var allAgents: [Agent]
    @State private var inputText = ""

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            pendingHeader
            Divider()
            ScrollView {
                emptyStateContent
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            Divider()
            chipsStrip
            inputArea
        }
        .xrayId("pendingChat")
    }

    // MARK: - Header

    @ViewBuilder
    private var pendingHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            if let group {
                Text(group.icon)
                    .font(.title3)
                Text(group.name)
                    .font(.headline)
                    .lineLimit(1)
            } else if let agent {
                Image(systemName: agent.icon)
                    .foregroundStyle(Color.fromAgentColor(agent.color))
                    .font(.title3)
                Text(agent.name)
                    .font(.headline)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .xrayId("pendingChat.header")
    }

    // MARK: - Empty State

    private var suggestions: AgentSuggestions.SuggestionSet {
        if let group {
            return AgentSuggestions.groupSuggestions(for: group)
        }
        if let agent {
            return AgentSuggestions.suggestions(for: agent)
        }
        return AgentSuggestions.freeformSuggestions
    }

    @ViewBuilder
    private var emptyStateContent: some View {
        VStack(spacing: 16) {
            if let group {
                groupHeader(group)
            } else if let agent {
                agentHeader(agent)
            }

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
                        .xrayId("pendingChat.starter.\(index)")
                    }
                }
                .frame(maxWidth: 440)
            }
            .xrayId("pendingChat.suggestions")
        }
        .padding(.top, 40)
        .padding(.bottom, 20)
        .xrayId("pendingChat.emptyState")
    }

    @ViewBuilder
    private func agentHeader(_ agent: Agent) -> some View {
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
        .xrayId("pendingChat.agentInfo")
    }

    @ViewBuilder
    private func groupHeader(_ group: AgentGroup) -> some View {
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
        .xrayId("pendingChat.groupInfo")
    }

    // MARK: - Chips

    @ViewBuilder
    private var chipsStrip: some View {
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
                    .xrayId("pendingChat.chip.\(chip.lowercased().replacingOccurrences(of: " ", with: "-"))")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .xrayId("pendingChat.chips")
    }

    // MARK: - Input Area

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder
    private var inputArea: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message...", text: $inputText)
                .textFieldStyle(.plain)
                .onSubmit { if canSend { materializeAndSend() } }
                .xrayId("pendingChat.messageInput")

            Button {
                materializeAndSend()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.borderless)
            .disabled(!canSend)
            .keyboardShortcut(.return, modifiers: .command)
            .xrayId("pendingChat.sendButton")
            .accessibilityLabel("Send message")
        }
        .padding(12)
        .background(.bar)
    }

    // MARK: - Materialize

    private func materializeAndSend() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""

        if let group {
            materializeGroupChat(text: text, group: group)
        } else if let agent {
            materializeAgentChat(text: text, agent: agent)
        }
    }

    private func materializeAgentChat(text: String, agent: Agent) {
        let conversation = Conversation(topic: agent.name)
        let userParticipant = Participant(type: .user, displayName: "You")
        userParticipant.conversation = conversation
        conversation.participants.append(userParticipant)

        let session = Session(agent: agent, mode: .interactive)
        session.workingDirectory = agent.defaultWorkingDirectory ?? ""
        session.conversations = [conversation]
        conversation.sessions.append(session)

        let agentParticipant = Participant(
            type: .agentSession(sessionId: session.id),
            displayName: agent.name
        )
        agentParticipant.conversation = conversation
        conversation.participants.append(agentParticipant)

        let message = ConversationMessage(
            senderParticipantId: userParticipant.id,
            text: text,
            type: .chat,
            conversation: conversation
        )
        conversation.messages.append(message)

        // Auto-name
        let truncated = text.count <= 50 ? text : String(text.prefix(50)) + "..."
        conversation.topic = "\(agent.name): \(truncated)"

        modelContext.insert(session)
        modelContext.insert(conversation)
        try? modelContext.save()

        appState.selectedConversationId = conversation.id
    }

    private func materializeGroupChat(text: String, group: AgentGroup) {
        // Use AppState's startGroupChat to create the full group conversation
        appState.startGroupChat(group: group, modelContext: modelContext)

        // Now find the conversation that was just created and add the user message
        guard let conversationId = appState.selectedConversationId else { return }
        let desc = FetchDescriptor<Conversation>(predicate: #Predicate { $0.id == conversationId })
        guard let conversation = try? modelContext.fetch(desc).first else { return }

        let userParticipant = conversation.participants.first { $0.type == .user }
        let message = ConversationMessage(
            senderParticipantId: userParticipant?.id,
            text: text,
            type: .chat,
            conversation: conversation
        )
        conversation.messages.append(message)

        let truncated = text.count <= 50 ? text : String(text.prefix(50)) + "..."
        conversation.topic = "\(group.name): \(truncated)"

        modelContext.insert(message)
        try? modelContext.save()
    }
}
