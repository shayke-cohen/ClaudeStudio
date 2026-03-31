import SwiftUI
import SwiftData

struct NewSessionSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @Environment(WindowState.self) private var windowState: WindowState
    @Query(sort: \Agent.name) private var agents: [Agent]
    @Query(sort: \Session.startedAt, order: .reverse) private var recentSessions: [Session]

    /// Agents selected for this conversation (one or more = group-capable).
    @State private var selectedAgentIds: Set<UUID> = []
    @State private var isFreeformChat = false
    @State private var providerOverride = AgentDefaults.inheritMarker
    @State private var modelOverride = AgentDefaults.inheritMarker
    @State private var sessionMode: SessionMode = .interactive
    @State private var mission = ""
    @State private var showOptions = false

    @State private var showCreateFromPrompt = false
    @State private var createFromPromptText = ""
    @Query(sort: \Skill.name) private var allSkills: [Skill]
    @Query(sort: \MCPServer.name) private var allMCPs: [MCPServer]

    private var enabledAgents: [Agent] {
        agents.filter { $0.isEnabled }
    }

    private var recentAgents: [Agent] {
        var seen = Set<UUID>()
        var result: [Agent] = []
        for session in recentSessions {
            guard let agent = session.agent, agent.isEnabled, !seen.contains(agent.id) else { continue }
            seen.insert(agent.id)
            result.append(agent)
            if result.count >= 3 { break }
        }
        return result
    }

    private var orderedSelectedAgents: [Agent] {
        agents.filter { selectedAgentIds.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var canStartSession: Bool {
        isFreeformChat || !selectedAgentIds.isEmpty
    }

    private var selectedSingleAgent: Agent? {
        orderedSelectedAgents.count == 1 ? orderedSelectedAgents.first : nil
    }

    private var allowsSessionOverrides: Bool {
        !isFreeformChat && selectedSingleAgent != nil
    }

    private var effectiveProviderForOverrides: String {
        AgentDefaults.resolveEffectiveProvider(
            sessionOverride: providerOverride,
            agentSelection: selectedSingleAgent?.provider
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    createFromPromptSection
                    if !recentAgents.isEmpty {
                        recentAgentsRow
                    }
                    agentPicker
                    if !orderedSelectedAgents.isEmpty {
                        Text("Selected: \(orderedSelectedAgents.map(\.name).joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .xrayId("newSession.selectedAgentsSummary")
                    }
                    projectInfoRow
                    optionsSection
                }
                .padding(24)
            }
            Divider()
            footer
        }
        .frame(width: 620, height: 620)
        .onChange(of: providerOverride) { _, _ in
            modelOverride = AgentDefaults.availableThreadModelChoices(
                for: effectiveProviderForOverrides,
                inheritLabel: "Inherit from Agent"
            ).contains(where: { $0.id == AgentDefaults.normalizedModelSelection(modelOverride) })
                ? AgentDefaults.normalizedModelSelection(modelOverride)
                : AgentDefaults.inheritMarker
        }
    }

    // MARK: - Project Info

    @ViewBuilder
    private var projectInfoRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .foregroundStyle(.secondary)
            Text("Project:")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(windowState.projectName)
                .font(.subheadline)
                .fontWeight(.medium)
            Spacer()
        }
        .padding(.vertical, 4)
        .xrayId("newSession.projectInfo")
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack {
            Text("New Thread")
                .font(.title2)
                .fontWeight(.semibold)
                .xrayId("newSession.title")
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .help("Close")
            .xrayId("newSession.closeButton")
            .accessibilityLabel("Close")
        }
        .padding(16)
    }

    // MARK: - Create from Prompt

    @ViewBuilder
    private var createFromPromptSection: some View {
        DisclosureGroup("Create agent from prompt", isExpanded: $showCreateFromPrompt) {
            VStack(alignment: .leading, spacing: 10) {
                if appState.generatedAgentSpec == nil && !appState.isGeneratingAgent {
                    HStack(spacing: 8) {
                        TextField("Describe an agent to create...", text: $createFromPromptText)
                            .textFieldStyle(.roundedBorder)
                            .xrayId("newSession.fromPrompt.textField")
                        Button {
                            generateAgentFromPrompt()
                        } label: {
                            Label("Generate", systemImage: "wand.and.stars")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(createFromPromptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .xrayId("newSession.fromPrompt.generateButton")
                    }
                    Text("e.g. \"A code reviewer focused on security\"")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if appState.isGeneratingAgent {
                    HStack {
                        ProgressView().scaleEffect(0.7)
                        Text("Generating...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .xrayId("newSession.fromPrompt.loading")
                }

                if let error = appState.generateAgentError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                        Button("Retry") { generateAgentFromPrompt() }
                            .controlSize(.small)
                            .xrayId("newSession.fromPrompt.retryButton")
                    }
                }

                if let spec = appState.generatedAgentSpec {
                    AgentPreviewCard(
                        spec: spec,
                        onSave: { agent in
                            modelContext.insert(agent)
                            try? modelContext.save()
                            isFreeformChat = false
                            selectedAgentIds = [agent.id]
                            appState.generatedAgentSpec = nil
                            appState.generateAgentError = nil
                        },
                        onSaveAndStart: { agent in
                            modelContext.insert(agent)
                            try? modelContext.save()
                            isFreeformChat = false
                            selectedAgentIds = [agent.id]
                            appState.generatedAgentSpec = nil
                            appState.generateAgentError = nil
                            Task { await createSessionAsync() }
                        },
                        onCancel: {
                            appState.generatedAgentSpec = nil
                            appState.generateAgentError = nil
                        }
                    )
                }
            }
            .padding(.top, 8)
        }
        .font(.headline)
        .xrayId("newSession.fromPrompt.disclosure")
    }

    private func generateAgentFromPrompt() {
        let skillEntries = allSkills.map { skill in
            SkillCatalogEntry(
                id: skill.id.uuidString,
                name: skill.name,
                description: skill.skillDescription,
                category: skill.category
            )
        }
        let mcpEntries = allMCPs.map { mcp in
            MCPCatalogEntry(
                id: mcp.id.uuidString,
                name: mcp.name,
                description: mcp.serverDescription
            )
        }
        appState.requestAgentGeneration(
            prompt: createFromPromptText.trimmingCharacters(in: .whitespacesAndNewlines),
            skills: skillEntries,
            mcps: mcpEntries
        )
    }

    // MARK: - Recent Agents

    @ViewBuilder
    private var recentAgentsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                ForEach(recentAgents) { agent in
                    Button {
                        isFreeformChat = false
                        selectedAgentIds = [agent.id]
                        providerOverride = AgentDefaults.inheritMarker
                        modelOverride = AgentDefaults.inheritMarker
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: agent.icon)
                                .foregroundStyle(Color.fromAgentColor(agent.color))
                            Text(agent.name)
                                .font(.callout)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selectedAgentIds == [agent.id] && !isFreeformChat
                            ? Color.fromAgentColor(agent.color).opacity(0.12)
                            : Color.clear
                        )
                        .clipShape(Capsule())
                        .overlay {
                            Capsule()
                                .strokeBorder(
                                    selectedAgentIds == [agent.id] && !isFreeformChat
                                        ? Color.fromAgentColor(agent.color)
                                        : .secondary.opacity(0.3),
                                    lineWidth: selectedAgentIds == [agent.id] && !isFreeformChat ? 2 : 1
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .xrayId("newSession.recentAgent.\(agent.id.uuidString)")
                }
                Spacer()
            }
        }
    }

    // MARK: - Agent Picker

    @ViewBuilder
    private var agentPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("All Agents (select one or more)")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 10)
            ], spacing: 10) {
                agentPickerCard(
                    icon: "bubble.left.and.bubble.right",
                    name: "Freeform",
                    detail: "No agent",
                    color: .secondary,
                    isSelected: isFreeformChat && selectedAgentIds.isEmpty,
                    identifier: "newSession.agentCard.freeform"
                ) {
                    isFreeformChat = true
                    selectedAgentIds.removeAll()
                    providerOverride = AgentDefaults.inheritMarker
                    modelOverride = AgentDefaults.inheritMarker
                }

                ForEach(enabledAgents) { agent in
                    agentPickerCard(
                        icon: agent.icon,
                        name: agent.name,
                        detail: AgentDefaults.label(for: agent.model),
                        color: Color.fromAgentColor(agent.color),
                        isSelected: selectedAgentIds.contains(agent.id),
                        identifier: "newSession.agentCard.\(agent.id.uuidString)"
                    ) {
                        isFreeformChat = false
                        if selectedAgentIds.contains(agent.id) {
                            selectedAgentIds.remove(agent.id)
                        } else {
                            selectedAgentIds.insert(agent.id)
                            providerOverride = AgentDefaults.inheritMarker
                            modelOverride = AgentDefaults.inheritMarker
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
        .xrayId(identifier)
    }

    // MARK: - Options

    @ViewBuilder
    private var optionsSection: some View {
        DisclosureGroup("Session Options", isExpanded: $showOptions) {
            VStack(alignment: .leading, spacing: 14) {
                if allowsSessionOverrides {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Provider")
                            .frame(width: 80, alignment: .trailing)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Picker("", selection: $providerOverride) {
                            Text("Inherit from Agent").tag(AgentDefaults.inheritMarker)
                            Text("Claude").tag(ProviderSelection.claude.rawValue)
                            Text("Codex").tag(ProviderSelection.codex.rawValue)
                        }
                        .labelsHidden()
                        .frame(width: 220)
                        .xrayId("newSession.providerPicker")
                    }

                    HStack(alignment: .firstTextBaseline) {
                        Text("Model")
                            .frame(width: 80, alignment: .trailing)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Picker("", selection: $modelOverride) {
                            ForEach(
                                AgentDefaults.availableThreadModelChoices(
                                    for: effectiveProviderForOverrides,
                                    inheritLabel: "Inherit from Agent"
                                )
                            ) { choice in
                                Text(choice.label).tag(choice.id)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 220)
                        .xrayId("newSession.modelPicker")
                    }
                }

                HStack(alignment: .firstTextBaseline) {
                    Text("Mode")
                        .frame(width: 80, alignment: .trailing)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $sessionMode) {
                        Text("Interactive").tag(SessionMode.interactive)
                            .help("You guide the agent step by step")
                        Text("Autonomous").tag(SessionMode.autonomous)
                            .help("Agent works independently toward a goal")
                        Text("Worker").tag(SessionMode.worker)
                            .help("Background task with no interaction")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 280)
                    .labelsHidden()
                    .xrayId("newSession.modePicker")
                }

                modeDescription

                HStack(alignment: .top) {
                    Text("Mission")
                        .frame(width: 80, alignment: .trailing)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                    TextField("Describe the goal for this session...", text: $mission, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                        .xrayId("newSession.missionField")
                }
            }
            .padding(.top, 8)
        }
        .xrayId("newSession.optionsDisclosure")
    }

    @ViewBuilder
    private var modeDescription: some View {
        HStack {
            Spacer().frame(width: 84)
            Group {
                switch sessionMode {
                case .interactive:
                    Text("You guide the agent step by step, reviewing each action.")
                case .autonomous:
                    Text("The agent works independently toward a goal you define.")
                case .worker:
                    Text("Background task that runs without interaction.")
                }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
            .xrayId("newSession.modeDescription")
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
            .xrayId("newSession.quickChatButton")
                Button("Start Thread") {
                    Task { await createSessionAsync() }
                }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return)
            .disabled(!canStartSession)
            .xrayId("newSession.startSessionButton")
        }
        .padding(16)
    }

    // MARK: - Actions

    private func createSessionAsync() async {
        let missionText = mission.trimmingCharacters(in: .whitespacesAndNewlines)
        let projectDir = windowState.projectDirectory

        // Freeform chat
        if isFreeformChat || selectedAgentIds.isEmpty {
            let conversation = Conversation(
                topic: "New Thread",
                projectId: windowState.selectedProjectId,
                threadKind: .freeform
            )
            let userParticipant = Participant(type: .user, displayName: "You")
            userParticipant.conversation = conversation
            conversation.participants.append(userParticipant)
            modelContext.insert(conversation)
            try? modelContext.save()
            windowState.selectedConversationId = conversation.id
            dismiss()
            return
        }

        let selectedList = orderedSelectedAgents
        guard !selectedList.isEmpty else {
            dismiss()
            return
        }

        let topic: String
        if selectedList.count == 1 {
            topic = selectedList[0].name
        } else {
            topic = selectedList.map(\.name).joined(separator: ", ")
        }

        let conversation = Conversation(
            topic: topic,
            projectId: windowState.selectedProjectId,
            threadKind: selectedList.count > 1 ? .group : .direct
        )
        if selectedList.count > 1 {
            conversation.selectiveRepliesEnabled = true
        }
        let userParticipant = Participant(type: .user, displayName: "You")
        userParticipant.conversation = conversation
        conversation.participants.append(userParticipant)

        for agent in selectedList {
            let session = Session(
                agent: agent,
                mission: missionText.isEmpty ? nil : missionText,
                mode: sessionMode,
                workingDirectory: projectDir
            )

            if selectedList.count == 1 {
                session.provider = AgentDefaults.resolveEffectiveProvider(
                    sessionOverride: providerOverride,
                    agentSelection: agent.provider
                )
                session.model = AgentDefaults.resolveEffectiveModel(
                    sessionOverride: modelOverride,
                    agentSelection: agent.model,
                    provider: session.provider
                )
            }

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
        windowState.selectedConversationId = conversation.id
        dismiss()
    }

    private func createQuickChat() {
        let conversation = Conversation(
            topic: "New Thread",
            projectId: windowState.selectedProjectId,
            threadKind: .freeform
        )
        let userParticipant = Participant(type: .user, displayName: "You")
        userParticipant.conversation = conversation
        conversation.participants.append(userParticipant)
        modelContext.insert(conversation)
        try? modelContext.save()
        windowState.selectedConversationId = conversation.id
        dismiss()
    }
}
