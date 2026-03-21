import SwiftUI
import SwiftData

struct NewSessionSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @Query(sort: \Agent.name) private var agents: [Agent]

    @State private var selectedAgent: Agent?
    @State private var modelOverride = ""
    @State private var sessionMode: SessionMode = .interactive
    @State private var mission = ""
    @State private var workingDirectory = ""

    private let availableModels = [
        "claude-sonnet-4-6",
        "claude-opus-4",
        "claude-haiku-3-5",
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    agentPicker
                    optionsSection
                }
                .padding(24)
            }
            Divider()
            footer
        }
        .frame(width: 620, height: 520)
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack {
            Text("New Session")
                .font(.title2)
                .fontWeight(.semibold)
                .accessibilityIdentifier("newSession.title")
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .help("Close")
            .accessibilityIdentifier("newSession.closeButton")
            .accessibilityLabel("Close")
        }
        .padding(16)
    }

    // MARK: - Agent Picker

    @ViewBuilder
    private var agentPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose an Agent")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 10)
            ], spacing: 10) {
                agentPickerCard(
                    icon: "bubble.left.and.bubble.right",
                    name: "Freeform",
                    detail: "No agent",
                    color: .secondary,
                    isSelected: selectedAgent == nil,
                    identifier: "newSession.agentCard.freeform"
                ) {
                    selectedAgent = nil
                    modelOverride = "claude-sonnet-4-6"
                }

                ForEach(agents) { agent in
                    agentPickerCard(
                        icon: agent.icon,
                        name: agent.name,
                        detail: agent.model,
                        color: agentColor(agent.color),
                        isSelected: selectedAgent?.id == agent.id,
                        identifier: "newSession.agentCard.\(agent.id.uuidString)"
                    ) {
                        selectedAgent = agent
                        modelOverride = agent.model
                        if let dir = agent.defaultWorkingDirectory, !dir.isEmpty {
                            workingDirectory = dir
                        }
                    }
                }
            }
        }
    }

    private func agentPickerCard(icon: String, name: String, detail: String, color: Color, isSelected: Bool, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                    .frame(width: 32, height: 32)
                Text(name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
            .background(isSelected ? color.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? color.opacity(1.0) : color.opacity(0.0), lineWidth: 2)
            }
            .overlay {
                if !isSelected {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.secondary.opacity(0.2), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityIdentifier(identifier)
    }

    // MARK: - Options

    @ViewBuilder
    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Options")
                .font(.headline)

            HStack(alignment: .firstTextBaseline) {
                Text("Model")
                    .frame(width: 80, alignment: .trailing)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Picker("", selection: $modelOverride) {
                    ForEach(availableModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .labelsHidden()
                .frame(width: 220)
                .accessibilityIdentifier("newSession.modelPicker")
            }

            HStack(alignment: .firstTextBaseline) {
                Text("Mode")
                    .frame(width: 80, alignment: .trailing)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Picker("", selection: $sessionMode) {
                    Text("Interactive").tag(SessionMode.interactive)
                    Text("Autonomous").tag(SessionMode.autonomous)
                    Text("Worker").tag(SessionMode.worker)
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
                .labelsHidden()
                .accessibilityIdentifier("newSession.modePicker")
            }

            HStack(alignment: .top) {
                Text("Mission")
                    .frame(width: 80, alignment: .trailing)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                TextField("Optional goal for this session...", text: $mission, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                    .accessibilityIdentifier("newSession.missionField")
            }

            HStack(alignment: .firstTextBaseline) {
                Text("Directory")
                    .frame(width: 80, alignment: .trailing)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                TextField("~/projects/my-app", text: $workingDirectory)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("newSession.workingDirectoryField")
                Button {
                    pickDirectory()
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help("Browse for directory")
                .accessibilityIdentifier("newSession.browseDirectoryButton")
                .accessibilityLabel("Browse for directory")
            }
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        HStack {
            Text("⌘N this sheet  ·  ⌘⇧N quick chat")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Quick Chat") {
                createQuickChat()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .accessibilityIdentifier("newSession.quickChatButton")
            Button("Start Session") {
                createSession()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return)
            .accessibilityIdentifier("newSession.startSessionButton")
        }
        .padding(16)
    }

    // MARK: - Actions

    private func createSession() {
        let agent = selectedAgent
        let missionText = mission.trimmingCharacters(in: .whitespacesAndNewlines)
        let dirText = workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)

        if let agent {
            let session = Session(
                agent: agent,
                mission: missionText.isEmpty ? nil : missionText,
                mode: sessionMode,
                workingDirectory: dirText.isEmpty ? (agent.defaultWorkingDirectory ?? "") : dirText
            )
            let conversation = Conversation(topic: agent.name, session: session)
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
            appState.selectedConversationId = conversation.id
        } else {
            let conversation = Conversation(topic: "New Chat")
            let userParticipant = Participant(type: .user, displayName: "You")
            userParticipant.conversation = conversation
            conversation.participants.append(userParticipant)
            modelContext.insert(conversation)
            try? modelContext.save()
            appState.selectedConversationId = conversation.id
        }

        dismiss()
    }

    private func createQuickChat() {
        let conversation = Conversation(topic: "New Chat")
        let userParticipant = Participant(type: .user, displayName: "You")
        userParticipant.conversation = conversation
        conversation.participants.append(userParticipant)
        modelContext.insert(conversation)
        try? modelContext.save()
        appState.selectedConversationId = conversation.id
        dismiss()
    }

    private func pickDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            workingDirectory = url.path(percentEncoded: false)
        }
    }

    private func agentColor(_ color: String) -> Color {
        switch color {
        case "blue": return .blue
        case "red": return .red
        case "green": return .green
        case "purple": return .purple
        case "orange": return .orange
        case "yellow": return .yellow
        case "pink": return .pink
        case "teal": return .teal
        default: return .accentColor
        }
    }
}
