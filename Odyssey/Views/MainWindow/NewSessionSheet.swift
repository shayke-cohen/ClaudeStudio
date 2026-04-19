import SwiftUI
import SwiftData

enum CreateThreadStartKind: String, CaseIterable, Identifiable {
    case blank
    case agents
    case groups

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blank: "Blank"
        case .agents: "Agents"
        case .groups: "Groups"
        }
    }

    var icon: String {
        switch self {
        case .blank: "bubble.left.and.bubble.right"
        case .agents: "cpu"
        case .groups: "person.3.fill"
        }
    }
}

private enum CreateThreadPickerStyle: String, CaseIterable, Identifiable {
    case list
    case cards

    var id: String { rawValue }

    var title: String {
        switch self {
        case .list: "List"
        case .cards: "Cards"
        }
    }
}

struct NewSessionSheet: View {
    private let initialStartKind: CreateThreadStartKind

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState: WindowState

    @Query(sort: \Agent.name) private var agents: [Agent]
    @Query(sort: \Session.startedAt, order: .reverse) private var recentSessions: [Session]
    @Query(sort: \AgentGroup.sortOrder) private var groups: [AgentGroup]
    @Query(sort: \Conversation.startedAt, order: .reverse) private var recentConversations: [Conversation]
    @Query(sort: \Skill.name) private var allSkills: [Skill]
    @Query(sort: \MCPServer.name) private var allMCPs: [MCPServer]

    @State private var selectedStartKind: CreateThreadStartKind
    @State private var selectedAgentIds: Set<UUID> = []
    @State private var selectedGroupId: UUID?
    @State private var blankProviderOverride = AgentDefaults.inheritMarker
    @State private var blankModelOverride = AgentDefaults.inheritMarker
    @State private var providerOverridesByAgentId: [UUID: String] = [:]
    @State private var modelOverridesByAgentId: [UUID: String] = [:]
    @State private var sessionMode: SessionMode = .interactive
    @State private var mission = ""
    @State private var showCreateFromPrompt = false
    @State private var createFromPromptText = ""
    @State private var agentSearchText = ""
    @State private var groupSearchText = ""
    @State private var showCatalog = false
    @State private var agentPickerStyle: CreateThreadPickerStyle = .list
    @State private var groupPickerStyle: CreateThreadPickerStyle = .list
    @State private var didRefreshOllama = false
    @State private var ollamaRefreshTick = 0

    init(initialStartKind: CreateThreadStartKind = .agents) {
        self.initialStartKind = initialStartKind
        _selectedStartKind = State(initialValue: initialStartKind)
    }

    private var enabledAgents: [Agent] {
        agents.filter(\.isEnabled)
    }

    private var enabledGroups: [AgentGroup] {
        groups.filter(\.isEnabled)
    }

    private var recentAgents: [Agent] {
        var seen = Set<UUID>()
        var result: [Agent] = []
        for session in recentSessions {
            guard let agent = session.agent, agent.isEnabled, !seen.contains(agent.id) else { continue }
            seen.insert(agent.id)
            result.append(agent)
            if result.count >= 4 { break }
        }
        return result
    }

    private var recentGroups: [AgentGroup] {
        var seen = Set<UUID>()
        var result: [AgentGroup] = []
        for conversation in recentConversations {
            guard let groupId = conversation.sourceGroupId,
                  let group = enabledGroups.first(where: { $0.id == groupId }),
                  !seen.contains(groupId) else { continue }
            seen.insert(groupId)
            result.append(group)
            if result.count >= 4 { break }
        }
        return result
    }

    private var filteredAgents: [Agent] {
        let query = agentSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return enabledAgents }
        return enabledAgents.filter { agent in
            agent.name.localizedCaseInsensitiveContains(query)
            || agent.systemPrompt.localizedCaseInsensitiveContains(query)
            || AgentDefaults.label(for: agent.model).localizedCaseInsensitiveContains(query)
        }
    }

    private var filteredGroups: [AgentGroup] {
        let query = groupSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return enabledGroups }
        return enabledGroups.filter { group in
            group.name.localizedCaseInsensitiveContains(query)
            || group.groupDescription.localizedCaseInsensitiveContains(query)
            || (group.defaultMission ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    private var orderedSelectedAgents: [Agent] {
        agents.filter { selectedAgentIds.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }


    private var selectedGroup: AgentGroup? {
        guard let selectedGroupId else { return nil }
        return enabledGroups.first(where: { $0.id == selectedGroupId })
    }

    private var agentById: [UUID: Agent] {
        Dictionary(uniqueKeysWithValues: enabledAgents.map { ($0.id, $0) })
    }

    private var canStartSelectedGroup: Bool {
        guard let selectedGroup else { return false }
        if sessionMode == .interactive { return true }
        return selectedGroup.coordinatorAgentId != nil || selectedGroup.autonomousCapable
    }

    private var canStartSession: Bool {
        switch selectedStartKind {
        case .blank:
            return true
        case .agents:
            return !selectedAgentIds.isEmpty
        case .groups:
            return canStartSelectedGroup
        }
    }

    private var blankEffectiveProvider: String {
        AgentDefaults.resolveEffectiveProvider(sessionOverride: blankProviderOverride)
    }

    private var blankProviderDefaultLabel: String {
        "Default (\(AgentDefaults.displayName(forProvider: AgentDefaults.defaultProvider())))"
    }

    private var blankModelDefaultLabel: String {
        AgentDefaults.defaultModelChoiceLabel(for: blankEffectiveProvider)
    }

    private func providerOverrideSelection(for agent: Agent) -> String {
        AgentDefaults.normalizedProviderSelection(providerOverridesByAgentId[agent.id]).rawValue
    }

    private func modelOverrideSelection(for agent: Agent) -> String {
        AgentDefaults.normalizedModelSelection(modelOverridesByAgentId[agent.id])
    }

    private func effectiveProviderForOverrides(agent: Agent) -> String {
        resolvedProviderForSession(agent: agent)
    }

    private func providerDefaultLabel(for agent: Agent) -> String {
        "Default (\(AgentDefaults.displayName(forProvider: derivedProviderForAgent(agent))))"
    }

    private func modelDefaultLabel(for agent: Agent) -> String {
        let model = AgentDefaults.resolveEffectiveModel(
            agentSelection: agent.model,
            provider: effectiveProviderForOverrides(agent: agent)
        )
        return "Default (\(AgentDefaults.label(for: model)))"
    }

    private func resolvedProviderForSession(agent: Agent?) -> String {
        guard let agent else { return AgentDefaults.defaultProvider() }
        let overrideSelection = AgentDefaults.normalizedProviderSelection(providerOverridesByAgentId[agent.id])
        if let concreteProvider = overrideSelection.concreteProvider {
            return concreteProvider
        }
        return derivedProviderForAgent(agent)
    }

    private func derivedProviderForAgent(_ agent: Agent?) -> String {
        guard let agent else { return AgentDefaults.defaultProvider() }
        if let explicitProvider = AgentDefaults.normalizedProviderSelection(agent.provider).concreteProvider {
            return explicitProvider
        }
        if let inferredProvider = inferredProvider(fromModel: agent.model) {
            return inferredProvider
        }
        return AgentDefaults.defaultProvider()
    }

    private func inferredProvider(fromModel model: String?) -> String? {
        let normalizedModel = AgentDefaults.normalizedModelSelection(model)
        guard normalizedModel != AgentDefaults.inheritMarker else { return nil }

        if CodexModel.allCases.contains(where: { $0.rawValue == normalizedModel }) {
            return ProviderSelection.codex.rawValue
        }
        if FoundationModel.allCases.contains(where: { $0.rawValue == normalizedModel }) {
            return ProviderSelection.foundation.rawValue
        }
        if ClaudeModel.allCases.contains(where: { $0.rawValue == normalizedModel })
            || AgentDefaults.isOllamaBackedClaudeModel(normalizedModel) {
            return ProviderSelection.claude.rawValue
        }
        if AgentDefaults.isLikelyMLXModelSelection(normalizedModel) {
            return ProviderSelection.mlx.rawValue
        }

        return nil
    }

    private func providerSelectionBinding(for agent: Agent) -> Binding<String> {
        Binding(
            get: { providerOverrideSelection(for: agent) },
            set: { newValue in
                let normalizedProvider = AgentDefaults.normalizedProviderSelection(newValue)
                if normalizedProvider == .system {
                    providerOverridesByAgentId.removeValue(forKey: agent.id)
                } else {
                    providerOverridesByAgentId[agent.id] = normalizedProvider.rawValue
                }

                let normalizedModel = modelOverrideSelection(for: agent)
                let availableModels = AgentDefaults.availableThreadModelChoices(
                    for: effectiveProviderForOverrides(agent: agent),
                    inheritLabel: "Inherit from Agent",
                    preserving: normalizedModel
                )

                if availableModels.contains(where: { $0.id == normalizedModel }) {
                    if normalizedModel == AgentDefaults.inheritMarker {
                        modelOverridesByAgentId.removeValue(forKey: agent.id)
                    } else {
                        modelOverridesByAgentId[agent.id] = normalizedModel
                    }
                } else {
                    modelOverridesByAgentId.removeValue(forKey: agent.id)
                }
            }
        )
    }

    private func modelSelectionBinding(for agent: Agent) -> Binding<String> {
        Binding(
            get: { modelOverrideSelection(for: agent) },
            set: { newValue in
                let normalizedModel = AgentDefaults.normalizedModelSelection(newValue)
                if normalizedModel == AgentDefaults.inheritMarker {
                    modelOverridesByAgentId.removeValue(forKey: agent.id)
                } else {
                    modelOverridesByAgentId[agent.id] = normalizedModel
                }
            }
        )
    }

    private var modePromptLabel: String {
        switch (selectedStartKind, sessionMode) {
        case (.groups, .interactive):
            return "Shared context for the team"
        case (.groups, .autonomous):
            return "Used as the first group job right away"
        case (.groups, .worker):
            return "Defines the first group job and worker focus"
        case (_, .interactive):
            return selectedStartKind == .blank ? "Optional context for the thread" : "Context for the selected starter"
        case (_, .autonomous):
            return "Required if you want it to start right away"
        case (_, .worker):
            return "Defines the first job and worker focus"
        }
    }

    private var goalPlaceholder: String {
        switch (selectedStartKind, sessionMode) {
        case (.blank, .interactive):
            return "Describe what this thread is for, or leave it blank and start chatting..."
        case (.blank, .autonomous):
            return "What should this blank thread do immediately?"
        case (.blank, .worker):
            return "What should this worker handle now and be ready to handle again later?"
        case (.agents, .interactive):
            return "What should this agent thread help with?"
        case (.agents, .autonomous):
            return "What should this agent start doing immediately?"
        case (.agents, .worker):
            return "What should this worker handle now and be ready to handle again later?"
        case (.groups, .interactive):
            return "What is this team thread for?"
        case (.groups, .autonomous):
            return "What should this team start doing immediately?"
        case (.groups, .worker):
            return "What should this team handle now and be ready to handle again later?"
        }
    }

    private var goalHelpText: String {
        switch (selectedStartKind, sessionMode) {
        case (.groups, .interactive):
            return "Starts with the group default when available, but you can adjust it before opening the thread."
        case (.groups, .autonomous):
            return "The goal is posted into the transcript and sent immediately to the team coordinator."
        case (.groups, .worker):
            return "The goal launches the first coordinator-led run now, then the same thread returns to standby."
        case (.blank, .interactive):
            return "This becomes shared context in the thread header and initial instructions, but the thread still waits for your first message."
        case (.blank, .autonomous), (.agents, .autonomous):
            return "The goal is posted into the transcript and sent immediately so the run can begin without another click."
        case (.blank, .worker), (.agents, .worker):
            return "The goal launches the first run now. After it finishes, the same thread returns to standby for the next job."
        case (.agents, .interactive):
            return "This becomes shared context for the selected agent or ad hoc team and still waits for your first message."
        }
    }

    private var modeConstraintText: String? {
        guard selectedStartKind == .groups,
              sessionMode != .interactive,
              let selectedGroup,
              selectedGroup.coordinatorAgentId == nil,
              !selectedGroup.autonomousCapable else {
            return nil
        }
        return "This team needs a coordinator or autonomous-capable fallback before autonomous or worker mode can start."
    }

    private var startActionSummary: String {
        switch selectedStartKind {
        case .blank:
            switch sessionMode {
            case .interactive:
                return "Blank thread will wait for your first message."
            case .autonomous:
                return "Blank thread will launch the goal as soon as it opens."
            case .worker:
                return "Blank worker thread will run the first job, then stay ready in the same thread."
            }
        case .agents:
            let selectionSummary: String
            if orderedSelectedAgents.isEmpty {
                selectionSummary = "Agent thread"
            } else if orderedSelectedAgents.count == 1, let agent = orderedSelectedAgents.first {
                selectionSummary = agent.name
            } else {
                selectionSummary = "\(orderedSelectedAgents.count)-agent thread"
            }

            switch sessionMode {
            case .interactive:
                return "\(selectionSummary) will wait for your first message."
            case .autonomous:
                return "\(selectionSummary) will launch the goal as soon as the thread opens."
            case .worker:
                return "\(selectionSummary) will run the first job, then stay ready in the same thread."
            }
        case .groups:
            let teamName = selectedGroup?.name ?? "Group thread"
            switch sessionMode {
            case .interactive:
                return "\(teamName) will wait for your first message."
            case .autonomous:
                return "\(teamName) will launch the kickoff goal through the coordinator immediately."
            case .worker:
                return "\(teamName) will run the first job, then stay ready in the same thread."
            }
        }
    }

    private var primaryActionTitle: String {
        switch (selectedStartKind, sessionMode) {
        case (.blank, .interactive):
            return "Start Blank Thread"
        case (.blank, .autonomous):
            return "Launch Autonomous Thread"
        case (.blank, .worker):
            return "Start Worker Thread"
        case (.agents, .interactive):
            return "Start Thread"
        case (.agents, .autonomous):
            return "Launch Autonomous Thread"
        case (.agents, .worker):
            return "Start Worker Thread"
        case (.groups, .interactive):
            return "Start Group Thread"
        case (.groups, .autonomous):
            return "Launch Autonomous Group"
        case (.groups, .worker):
            return "Start Group Worker"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    projectInfoRow
                    startKindTabs
                    starterSelectionSection
                    optionsSection
                }
                .padding(24)
            }
            Divider()
            footer
        }
        .frame(width: 860, height: 720)
        .onAppear {
            selectedStartKind = initialStartKind
            ensureSelectionDefaults(for: initialStartKind)
        }
        .onChange(of: selectedStartKind) { _, newValue in
            ensureSelectionDefaults(for: newValue)
        }
        .onChange(of: selectedGroupId) { _, _ in
            guard selectedStartKind == .groups else { return }
            // Mission stays as the user left it; prompt templates replace the old
            // `defaultMission` auto-prefill.
        }
        .onChange(of: blankProviderOverride) { _, _ in
            let normalizedModel = AgentDefaults.normalizedModelSelection(blankModelOverride)
            let availableModels = AgentDefaults.availableThreadModelChoices(
                for: blankEffectiveProvider,
                inheritLabel: "Use Provider Default",
                preserving: normalizedModel
            )
            blankModelOverride = availableModels.contains(where: { $0.id == normalizedModel })
                ? normalizedModel
                : AgentDefaults.inheritMarker
        }
        .task {
            guard !didRefreshOllama else { return }
            didRefreshOllama = true
            await refreshOllamaCatalogIfNeeded()
        }
        .sheet(isPresented: $showCatalog) {
            CatalogBrowserView()
                .frame(minWidth: 700, minHeight: 550)
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Create Thread")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .xrayId("newSession.title")
                Text("Start blank, with an agent, or with a saved team.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .xrayId("newSession.subtitle")
            }
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

    private func refreshOllamaCatalogIfNeeded() async {
        guard OllamaCatalogService.modelsEnabled() else { return }
        _ = await OllamaCatalogService.refresh()
        ollamaRefreshTick += 1
    }

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

    @ViewBuilder
    private var startKindTabs: some View {
        HStack(spacing: 10) {
            ForEach(CreateThreadStartKind.allCases) { kind in
                Button {
                    selectedStartKind = kind
                } label: {
                    Label(kind.title, systemImage: kind.icon)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity)
                        .background(startKindTint(for: kind).opacity(selectedStartKind == kind ? 0.14 : 0.0))
                        .foregroundStyle(selectedStartKind == kind ? startKindTint(for: kind) : .secondary)
                        .clipShape(Capsule())
                        .overlay {
                            Capsule()
                                .stroke(selectedStartKind == kind ? startKindTint(for: kind) : .secondary.opacity(0.16), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .xrayId("newSession.startKind.\(kind.rawValue)")
                .accessibilityLabel(kind.title)
            }
        }
    }

    @ViewBuilder
    private var starterSelectionSection: some View {
        switch selectedStartKind {
        case .blank:
            blankStarterCard
        case .agents:
            agentStarterSection
        case .groups:
            groupStarterSection
        }
    }

    @ViewBuilder
    private var blankStarterCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Blank Thread", systemImage: CreateThreadStartKind.blank.icon)
                .font(.headline)
                .foregroundStyle(.primary)

            Text("Start with an empty thread and decide the rest in conversation. This is the lightest path when you do not want to choose an agent or saved team upfront.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Launch Defaults")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack(alignment: .top, spacing: 10) {
                        overridePickerColumn(
                            title: "Provider",
                            selection: $blankProviderOverride,
                            options: [
                                ModelChoice(id: AgentDefaults.inheritMarker, label: blankProviderDefaultLabel),
                                ModelChoice(id: ProviderSelection.claude.rawValue, label: ProviderSelection.claude.label),
                                ModelChoice(id: ProviderSelection.codex.rawValue, label: ProviderSelection.codex.label),
                                ModelChoice(id: ProviderSelection.foundation.rawValue, label: ProviderSelection.foundation.label),
                                ModelChoice(id: ProviderSelection.mlx.rawValue, label: ProviderSelection.mlx.label)
                            ],
                            xrayId: "newSession.blankProviderPicker"
                        )
                        overridePickerColumn(
                            title: "Model",
                            selection: $blankModelOverride,
                            options: AgentDefaults.availableThreadModelChoices(
                                for: blankEffectiveProvider,
                                inheritLabel: blankModelDefaultLabel,
                                preserving: blankModelOverride
                            ),
                            xrayId: "newSession.blankModelPicker"
                        )
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 10) {
                    Button("Quick Chat") {
                        createQuickChat()
                    }
                    .xrayId("newSession.quickChatButton")

                    Text("Use this when you want the calmest possible start.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        }
        .xrayId("newSession.blankStateCard")
    }

    @ViewBuilder
    private var agentStarterSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            createFromPromptSection

            if !recentAgents.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent Agents")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(recentAgents) { agent in
                                Button {
                                    selectedAgentIds = [agent.id]
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
                                    .background(selectedAgentIds == [agent.id]
                                        ? Color.fromAgentColor(agent.color).opacity(0.12)
                                        : Color.clear
                                    )
                                    .clipShape(Capsule())
                                    .overlay {
                                        Capsule()
                                            .strokeBorder(
                                                selectedAgentIds == [agent.id]
                                                    ? Color.fromAgentColor(agent.color)
                                                    : .secondary.opacity(0.3),
                                                lineWidth: selectedAgentIds == [agent.id] ? 2 : 1
                                            )
                                    }
                                }
                                .buttonStyle(.plain)
                                .xrayId("newSession.recentAgent.\(agent.id.uuidString)")
                            }
                        }
                    }
                }
            }

            assetPickerHeader(
                title: "All Agents",
                searchText: $agentSearchText,
                pickerStyle: $agentPickerStyle,
                tint: .blue,
                searchPrompt: "Search agents by name, role, or specialty...",
                searchId: "newSession.agentSearchField",
                listToggleId: "newSession.agentPickerStyle.list",
                cardsToggleId: "newSession.agentPickerStyle.cards"
            )

            if enabledAgents.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.2.badge.plus")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("No agents yet")
                        .font(.headline)
                    Text("Open the Catalog to install your first agent.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Open Catalog") {
                        showCatalog = true
                    }
                    .buttonStyle(.borderedProminent)
                    .xrayId("newSession.openCatalogCTA")
                }
                .padding(40)
                .frame(maxWidth: .infinity)
                .xrayId("newSession.agentPickerEmptyState")
            } else if filteredAgents.isEmpty {
                ContentUnavailableView(
                    "No agents match your search",
                    systemImage: "cpu",
                    description: Text("Try a broader search or create one from prompt above.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .xrayId("newSession.agentPickerEmptyState")
            } else {
                if agentPickerStyle == .list {
                    VStack(spacing: 10) {
                        ForEach(filteredAgents) { agent in
                            agentListRow(agent)
                        }
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 210, maximum: 320), spacing: 12)], spacing: 12) {
                        ForEach(filteredAgents) { agent in
                            agentCard(agent)
                        }
                    }
                }
            }

            if !orderedSelectedAgents.isEmpty {
                Text("Selected: \(orderedSelectedAgents.map(\.name).joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .xrayId("newSession.selectedAgentsSummary")
            }
        }
    }

    @ViewBuilder
    private var groupStarterSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !recentGroups.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent Groups")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(recentGroups) { group in
                                Button {
                                    selectGroup(group)
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "bubble.left.and.bubble.right.fill")
                                            .foregroundStyle(Color.fromAgentColor(group.color))
                                        Text(group.name)
                                            .font(.callout)
                                            .lineLimit(1)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(selectedGroupId == group.id
                                        ? Color.fromAgentColor(group.color).opacity(0.12)
                                        : Color.clear
                                    )
                                    .clipShape(Capsule())
                                    .overlay {
                                        Capsule()
                                            .strokeBorder(
                                                selectedGroupId == group.id
                                                    ? Color.fromAgentColor(group.color)
                                                    : .secondary.opacity(0.3),
                                                lineWidth: selectedGroupId == group.id ? 2 : 1
                                            )
                                    }
                                }
                                .buttonStyle(.plain)
                                .xrayId("newSession.recentGroup.\(group.id.uuidString)")
                            }
                        }
                    }
                }
            }

            assetPickerHeader(
                title: "All Groups",
                searchText: $groupSearchText,
                pickerStyle: $groupPickerStyle,
                tint: .green,
                searchPrompt: "Search groups by team name, mission, or member composition...",
                searchId: "newSession.groupSearchField",
                listToggleId: "newSession.groupPickerStyle.list",
                cardsToggleId: "newSession.groupPickerStyle.cards"
            )

            if filteredGroups.isEmpty {
                ContentUnavailableView(
                    "No groups match your search",
                    systemImage: "person.3.fill",
                    description: Text("Try a broader search or switch back to agents or blank.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .xrayId("newSession.groupPickerEmptyState")
            } else {
                if groupPickerStyle == .list {
                    VStack(spacing: 10) {
                        ForEach(filteredGroups) { group in
                            groupListRow(group)
                        }
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 12)], spacing: 12) {
                        ForEach(filteredGroups) { group in
                            groupCard(group)
                        }
                    }
                }
            }

            if let modeConstraintText {
                Label(modeConstraintText, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .xrayId("newSession.groupModeConstraint")
            }
        }
    }

    @ViewBuilder
    private func assetPickerHeader(
        title: String,
        searchText: Binding<String>,
        pickerStyle: Binding<CreateThreadPickerStyle>,
        tint: Color,
        searchPrompt: String,
        searchId: String,
        listToggleId: String,
        cardsToggleId: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Text(title)
                    .font(.headline)
                Spacer()
                HStack(spacing: 4) {
                    togglePill(
                        title: "List",
                        isSelected: pickerStyle.wrappedValue == .list,
                        tint: tint,
                        xrayId: listToggleId
                    ) {
                        pickerStyle.wrappedValue = .list
                    }
                    togglePill(
                        title: "Cards",
                        isSelected: pickerStyle.wrappedValue == .cards,
                        tint: tint,
                        xrayId: cardsToggleId
                    ) {
                        pickerStyle.wrappedValue = .cards
                    }
                }
            }

            TextField(searchPrompt, text: searchText)
                .textFieldStyle(.roundedBorder)
                .xrayId(searchId)
        }
    }

    private func togglePill(title: String, isSelected: Bool, tint: Color, xrayId: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(isSelected ? tint : .secondary)
                .background(isSelected ? tint.opacity(0.12) : Color.secondary.opacity(0.08))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .xrayId(xrayId)
    }

    @ViewBuilder
    private func agentListRow(_ agent: Agent) -> some View {
        let isSelected = selectedAgentIds.contains(agent.id)
        let showInlineOverrides = isSelected

        HStack(alignment: .top, spacing: showInlineOverrides ? 14 : 0) {
            Button {
                toggleAgent(agent)
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: agent.icon)
                        .font(.headline)
                        .foregroundStyle(Color.fromAgentColor(agent.color))
                        .frame(width: 32, height: 32)
                        .background(Color.fromAgentColor(agent.color).opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(agent.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(AgentDefaults.label(for: agent.model))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        let description = agent.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                        Text(description.isEmpty ? "No description yet" : description)
                            .font(.caption)
                            .foregroundStyle(description.isEmpty ? .tertiary : .secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showInlineOverrides {
                selectedAgentOverridesPanel(for: agent, compact: false)
                    .frame(width: 280)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.fromAgentColor(agent.color).opacity(0.10) : Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(isSelected ? Color.fromAgentColor(agent.color) : Color.secondary.opacity(0.15), lineWidth: isSelected ? 2 : 1)
        }
        .animation(.easeInOut(duration: 0.18), value: showInlineOverrides)
        .xrayId("newSession.agentRow.\(agent.id.uuidString)")
        .accessibilityLabel(agent.name)
    }

    @ViewBuilder
    private func agentCard(_ agent: Agent) -> some View {
        let isSelected = selectedAgentIds.contains(agent.id)
        let showInlineOverrides = isSelected

        VStack(alignment: .leading, spacing: 12) {
            Button {
                toggleAgent(agent)
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: agent.icon)
                            .font(.title3)
                            .foregroundStyle(Color.fromAgentColor(agent.color))
                            .frame(width: 32, height: 32)
                            .background(Color.fromAgentColor(agent.color).opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(agent.name)
                                .font(.headline)
                                .lineLimit(1)
                            Text(AgentDefaults.label(for: agent.model))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    let description = agent.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                    Text(description.isEmpty ? "No description yet" : description)
                        .font(.caption)
                        .foregroundStyle(description.isEmpty ? .tertiary : .secondary)
                        .lineLimit(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showInlineOverrides {
                selectedAgentOverridesPanel(for: agent, compact: true)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.fromAgentColor(agent.color).opacity(0.10) : Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.fromAgentColor(agent.color) : Color.secondary.opacity(0.15), lineWidth: isSelected ? 2 : 1)
        }
        .animation(.easeInOut(duration: 0.18), value: showInlineOverrides)
        .xrayId("newSession.agentCard.\(agent.id.uuidString)")
        .accessibilityLabel(agent.name)
    }

    @ViewBuilder
    private func groupListRow(_ group: AgentGroup) -> some View {
        let isSelected = selectedGroupId == group.id
        VStack(alignment: .leading, spacing: 0) {
            Button {
                selectGroup(group)
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.headline)
                        .foregroundStyle(Color.fromAgentColor(group.color))
                        .frame(width: 32, height: 32)
                        .background(Color.fromAgentColor(group.color).opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(group.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text("\(group.agentIds.count) agents")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Image(systemName: isSelected ? "chevron.up" : "chevron.down")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }

                        let description = groupSummaryText(group)
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(description == "No description yet" ? .tertiary : .secondary)
                            .lineLimit(isSelected ? 3 : 2)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isSelected ? Color.fromAgentColor(group.color).opacity(0.10) : Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isSelected ? Color.fromAgentColor(group.color) : Color.secondary.opacity(0.15), lineWidth: isSelected ? 2 : 1)
                }
            }
            .buttonStyle(.plain)

            if isSelected {
                groupMembersSection(group, compact: false)
                    .padding(.top, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .xrayId("newSession.groupRow.\(group.id.uuidString)")
        .accessibilityLabel(group.name)
    }

    @ViewBuilder
    private func groupCard(_ group: AgentGroup) -> some View {
        let isSelected = selectedGroupId == group.id
        Button {
            selectGroup(group)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.title3)
                        .foregroundStyle(Color.fromAgentColor(group.color))
                        .frame(width: 32, height: 32)
                        .background(Color.fromAgentColor(group.color).opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.name)
                            .font(.headline)
                            .lineLimit(1)
                        Text("\(group.agentIds.count) agents")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: isSelected ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }

                Text(groupSummaryText(group))
                    .font(.caption)
                    .foregroundStyle(groupSummaryText(group) == "No description yet" ? .tertiary : .secondary)
                    .lineLimit(3)

                if isSelected {
                    groupMembersSection(group, compact: true)
                        .padding(.top, 4)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.fromAgentColor(group.color).opacity(0.08) : Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.fromAgentColor(group.color) : Color.secondary.opacity(0.15), lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .xrayId("newSession.groupCard.\(group.id.uuidString)")
        .accessibilityLabel(group.name)
    }

    @ViewBuilder
    private func groupMembersSection(_ group: AgentGroup, compact: Bool) -> some View {
        let resolvedAgents = resolvedAgents(for: group)

        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            HStack(spacing: 8) {
                Text("Agents")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if let coordinator = resolvedAgents.first(where: { $0.id == group.coordinatorAgentId }) {
                    Text("Coordinator: \(coordinator.name)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else if group.autonomousCapable {
                    Text("Autonomous-ready")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if compact {
                FlowLayout(spacing: 6) {
                    ForEach(resolvedAgents) { agent in
                        groupMemberPill(agent: agent, group: group)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(resolvedAgents) { agent in
                        groupMemberRow(agent: agent, group: group)
                    }
                }
            }
        }
        .padding(compact ? 10 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.fromAgentColor(group.color).opacity(compact ? 0.08 : 0.06))
        .clipShape(RoundedRectangle(cornerRadius: compact ? 10 : 12))
        .xrayId("newSession.groupMembers.\(group.id.uuidString)")
    }

    @ViewBuilder
    private func groupMemberRow(agent: Agent, group: AgentGroup) -> some View {
        let role = group.roleFor(agentId: agent.id)

        HStack(spacing: 10) {
            Image(systemName: agent.icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.fromAgentColor(agent.color))
                .frame(width: 24, height: 24)
                .background(Color.fromAgentColor(agent.color).opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 2) {
                Text(agent.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                let description = agent.agentDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                if !description.isEmpty {
                    Text(description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if role != .participant {
                Text(role.displayName)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(groupRoleColor(role).opacity(0.14))
                    .foregroundStyle(groupRoleColor(role))
                    .clipShape(Capsule())
            }
        }
        .xrayId("newSession.groupMember.\(group.id.uuidString).\(agent.id.uuidString)")
    }

    @ViewBuilder
    private func groupMemberPill(agent: Agent, group: AgentGroup) -> some View {
        let role = group.roleFor(agentId: agent.id)

        HStack(spacing: 6) {
            Image(systemName: agent.icon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.fromAgentColor(agent.color))
            Text(agent.name)
                .font(.caption)
                .foregroundStyle(.primary)
            if role != .participant {
                Text(role.displayName)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(groupRoleColor(role))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .xrayId("newSession.groupMember.\(group.id.uuidString).\(agent.id.uuidString)")
    }

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
                        .help(createFromPromptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Describe the agent you want to create." : "Generate a new agent from your description.")
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
                            selectedStartKind = .agents
                            selectedAgentIds = [agent.id]
                            appState.generatedAgentSpec = nil
                            appState.generateAgentError = nil
                        },
                        onSaveAndStart: { agent in
                            modelContext.insert(agent)
                            try? modelContext.save()
                            selectedStartKind = .agents
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

    @ViewBuilder
    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Thread Setup")
                    .font(.headline)
                    .xrayId("newSession.optionsTitle")
                Text("Pick how this thread should behave, then give it a clear goal.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .xrayId("newSession.optionsSubtitle")
            }

            modeCards

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(selectedStartKind == .groups ? "Kickoff Goal" : "Goal")
                        .font(.subheadline.weight(.semibold))
                        .xrayId("newSession.goalTitle")
                    Text(modePromptLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .xrayId("newSession.goalCaption")
                }

                TextField(goalPlaceholder, text: $mission, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)
                    .xrayId("newSession.missionField")

                Text(goalHelpText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .xrayId("newSession.goalHelp")
            }

        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        }
        .xrayId("newSession.optionsDisclosure")
    }

    @ViewBuilder
    private var modeCards: some View {
        HStack(spacing: 12) {
            modeCard(
                mode: .interactive,
                title: "Interactive",
                subtitle: "Waits for you",
                detail: "Opens the thread and lets you steer each turn.",
                icon: "hand.tap.fill",
                accent: .blue
            )
            modeCard(
                mode: .autonomous,
                title: "Autonomous",
                subtitle: "Runs once",
                detail: "Starts immediately, works hands-off, then stops when done.",
                icon: "sparkles.rectangle.stack",
                accent: .orange
            )
            modeCard(
                mode: .worker,
                title: "Worker",
                subtitle: "Stays on call",
                detail: "Starts now, finishes the first job, then waits in the same thread.",
                icon: "shippingbox.fill",
                accent: .green
            )
        }
    }

    private func modeCard(
        mode: SessionMode,
        title: String,
        subtitle: String,
        detail: String,
        icon: String,
        accent: Color
    ) -> some View {
        let isSelected = sessionMode == mode
        return Button {
            sessionMode = mode
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Image(systemName: icon)
                        .font(.headline)
                        .foregroundStyle(isSelected ? accent : .secondary)
                        .frame(width: 30, height: 30)
                        .background(
                            Circle()
                                .fill(isSelected ? accent.opacity(0.14) : Color.secondary.opacity(0.08))
                        )

                    Spacer(minLength: 0)

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.headline)
                        .foregroundStyle(isSelected ? accent : .secondary.opacity(0.5))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(isSelected ? accent : .secondary)
                }

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
            .padding(14)
            .background(isSelected ? accent.opacity(0.10) : Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? accent.opacity(0.9) : Color.secondary.opacity(0.15), lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .xrayId("newSession.modeCard.\(mode.rawValue)")
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private func selectedAgentOverridesPanel(for agent: Agent, compact: Bool) -> some View {
        let providerXrayId = "newSession.providerPicker.\(agent.id.uuidString)"
        let modelXrayId = "newSession.modelPicker.\(agent.id.uuidString)"

        VStack(alignment: .leading, spacing: compact ? 10 : 12) {
            Text("Launch Defaults")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if compact {
                VStack(alignment: .leading, spacing: 10) {
                    overridePickerColumn(
                        title: "Provider",
                        selection: providerSelectionBinding(for: agent),
                        options: [
                            ModelChoice(id: AgentDefaults.inheritMarker, label: providerDefaultLabel(for: agent)),
                            ModelChoice(id: ProviderSelection.claude.rawValue, label: ProviderSelection.claude.label),
                            ModelChoice(id: ProviderSelection.codex.rawValue, label: ProviderSelection.codex.label),
                            ModelChoice(id: ProviderSelection.foundation.rawValue, label: ProviderSelection.foundation.label),
                            ModelChoice(id: ProviderSelection.mlx.rawValue, label: ProviderSelection.mlx.label)
                        ],
                        xrayId: providerXrayId
                    )
                    overridePickerColumn(
                        title: "Model",
                        selection: modelSelectionBinding(for: agent),
                        options: AgentDefaults.availableThreadModelChoices(
                            for: effectiveProviderForOverrides(agent: agent),
                            inheritLabel: modelDefaultLabel(for: agent),
                            preserving: modelOverrideSelection(for: agent)
                        ),
                        xrayId: modelXrayId
                    )
                }
            } else {
                HStack(alignment: .top, spacing: 10) {
                    overridePickerColumn(
                        title: "Provider",
                        selection: providerSelectionBinding(for: agent),
                        options: [
                            ModelChoice(id: AgentDefaults.inheritMarker, label: providerDefaultLabel(for: agent)),
                            ModelChoice(id: ProviderSelection.claude.rawValue, label: ProviderSelection.claude.label),
                            ModelChoice(id: ProviderSelection.codex.rawValue, label: ProviderSelection.codex.label),
                            ModelChoice(id: ProviderSelection.foundation.rawValue, label: ProviderSelection.foundation.label),
                            ModelChoice(id: ProviderSelection.mlx.rawValue, label: ProviderSelection.mlx.label)
                        ],
                        xrayId: providerXrayId
                    )
                    overridePickerColumn(
                        title: "Model",
                        selection: modelSelectionBinding(for: agent),
                        options: AgentDefaults.availableThreadModelChoices(
                            for: effectiveProviderForOverrides(agent: agent),
                            inheritLabel: modelDefaultLabel(for: agent),
                            preserving: modelOverrideSelection(for: agent)
                        ),
                        xrayId: modelXrayId
                    )
                }
            }
        }
        .padding(compact ? 12 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.fromAgentColor(agent.color).opacity(compact ? 0.08 : 0.06))
        .clipShape(RoundedRectangle(cornerRadius: compact ? 10 : 12))
    }

    private func overridePickerColumn(
        title: String,
        selection: Binding<String>,
        options: [ModelChoice],
        xrayId: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Picker(title, selection: selection) {
                ForEach(options) { option in
                    Text(option.label).tag(option.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .xrayId(xrayId)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(startActionSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .xrayId("newSession.footerSummary")
                Text("⌘N open  ·  ⌘⇧N quick chat")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button("Quick Chat") {
                createQuickChat()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .xrayId("newSession.quickChatButton")
            Button(primaryActionTitle) {
                Task { await createSessionAsync() }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return)
            .disabled(!canStartSession)
            .help(canStartSession ? "Start the session" : "Select at least one agent to start a session.")
            .xrayId("newSession.startSessionButton")
        }
        .padding(16)
    }

    private func startKindTint(for kind: CreateThreadStartKind) -> Color {
        switch kind {
        case .blank: .orange
        case .agents: .blue
        case .groups: .green
        }
    }

    private func ensureSelectionDefaults(for startKind: CreateThreadStartKind) {
        if startKind == .groups, selectedGroupId == nil {
            if let defaultGroup = recentGroups.first ?? enabledGroups.first {
                selectGroup(defaultGroup)
            }
        }
    }

    private func toggleAgent(_ agent: Agent) {
        if selectedAgentIds.contains(agent.id) {
            selectedAgentIds.remove(agent.id)
        } else {
            selectedAgentIds.insert(agent.id)
        }
    }

    private func selectGroup(_ group: AgentGroup) {
        withAnimation(.easeInOut(duration: 0.18)) {
            selectedGroupId = group.id
        }
    }

    private func resolvedAgents(for group: AgentGroup) -> [Agent] {
        group.agentIds.compactMap { agentById[$0] }
    }

    private func groupSummaryText(_ group: AgentGroup) -> String {
        let description = group.groupDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !description.isEmpty { return description }
        let defaultMission = (group.defaultMission ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !defaultMission.isEmpty { return defaultMission }
        return "No description yet"
    }

    private func groupRoleColor(_ role: GroupRole) -> Color {
        switch role {
        case .coordinator: .orange
        case .scribe: .purple
        case .observer: .gray
        case .participant: .secondary
        }
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

    private func createSessionAsync() async {
        switch selectedStartKind {
        case .blank:
            createBlankThread()
        case .agents:
            createAgentThread()
        case .groups:
            startGroupThread()
        }
    }

    private func createBlankThread() {
        let missionText = mission.trimmingCharacters(in: .whitespacesAndNewlines)
        let projectDir = windowState.projectDirectory
        let executionMode = mappedExecutionMode

        let conversation = Conversation(
            topic: "New Thread",
            projectId: windowState.selectedProjectId,
            threadKind: .freeform
        )
        conversation.executionMode = executionMode
        conversation.goal = missionText.isEmpty ? nil : missionText

        let userParticipant = Participant(type: .user, displayName: "You")
        userParticipant.conversation = conversation
        conversation.participants = (conversation.participants ?? []) + [userParticipant]

        let session = Session(
            agent: nil,
            mission: missionText.isEmpty ? nil : missionText,
            mode: sessionMode,
            workingDirectory: projectDir
        )
        session.provider = AgentDefaults.resolveEffectiveProvider(sessionOverride: blankProviderOverride)
        session.model = AgentDefaults.resolveEffectiveModel(
            sessionOverride: blankModelOverride,
            provider: session.provider
        )
        session.conversations = [conversation]
        conversation.sessions = (conversation.sessions ?? []) + [session]

        let agentParticipant = Participant(
            type: .agentSession(sessionId: session.id),
            displayName: AgentDefaults.displayName(forProvider: session.provider)
        )
        agentParticipant.conversation = conversation
        conversation.participants = (conversation.participants ?? []) + [agentParticipant]

        modelContext.insert(session)
        modelContext.insert(conversation)
        try? modelContext.save()
        windowState.selectedConversationId = conversation.id
        if executionMode != .interactive, !missionText.isEmpty {
            windowState.autoSendText = missionText
        }
        dismiss()
    }

    private func createAgentThread() {
        let missionText = mission.trimmingCharacters(in: .whitespacesAndNewlines)
        let projectDir = windowState.projectDirectory
        let executionMode = mappedExecutionMode
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
            projectId: nil,
            threadKind: selectedList.count > 1 ? .group : .direct
        )
        conversation.executionMode = executionMode
        conversation.goal = missionText.isEmpty ? nil : missionText
        if selectedList.count > 1 {
            conversation.routingMode = .mentionAware
        }

        let userParticipant = Participant(type: .user, displayName: "You")
        userParticipant.conversation = conversation
        conversation.participants = (conversation.participants ?? []) + [userParticipant]

        for agent in selectedList {
            // Agent home always wins when set; fall back to project dir for non-resident agents
            let agentWD = agent.defaultWorkingDirectory.flatMap { $0.isEmpty ? nil : $0 }
            let effectiveWD = agentWD.map { NSString(string: $0).expandingTildeInPath as String }
                ?? (projectDir.isEmpty ? "" : projectDir)
            let session = Session(
                agent: agent,
                mission: missionText.isEmpty ? nil : missionText,
                mode: sessionMode,
                workingDirectory: effectiveWD
            )

            session.provider = resolvedProviderForSession(agent: agent)
            session.model = AgentDefaults.resolveEffectiveModel(
                sessionOverride: modelOverrideSelection(for: agent),
                agentSelection: agent.model,
                provider: session.provider
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

        modelContext.insert(conversation)
        try? modelContext.save()
        windowState.selectedConversationId = conversation.id
        if executionMode != .interactive, !missionText.isEmpty {
            windowState.autoSendText = missionText
        }
        dismiss()
    }

    private func startGroupThread() {
        guard let selectedGroup else { return }
        let missionText = mission.trimmingCharacters(in: .whitespacesAndNewlines)
        if let conversationId = appState.startGroupChat(
            group: selectedGroup,
            projectDirectory: "",
            projectId: nil,
            modelContext: modelContext,
            missionOverride: missionText,
            executionMode: mappedExecutionMode
        ) {
            windowState.selectedConversationId = conversationId
            if mappedExecutionMode != .interactive, !missionText.isEmpty {
                windowState.autoSendText = missionText
            }
        }
        dismiss()
    }

    private var mappedExecutionMode: ConversationExecutionMode {
        switch sessionMode {
        case .interactive: .interactive
        case .autonomous: .autonomous
        case .worker: .worker
        }
    }

    private func createQuickChat() {
        let projectDir = windowState.projectDirectory
        let conversation = Conversation(
            topic: "New Thread",
            projectId: windowState.selectedProjectId,
            threadKind: .freeform
        )
        conversation.executionMode = .interactive

        let userParticipant = Participant(type: .user, displayName: "You")
        userParticipant.conversation = conversation
        conversation.participants = (conversation.participants ?? []) + [userParticipant]

        let session = Session(
            agent: nil,
            mission: nil,
            mode: .interactive,
            workingDirectory: projectDir
        )
        session.provider = AgentDefaults.resolveEffectiveProvider(sessionOverride: blankProviderOverride)
        session.model = AgentDefaults.resolveEffectiveModel(
            sessionOverride: blankModelOverride,
            provider: session.provider
        )
        session.conversations = [conversation]
        conversation.sessions = (conversation.sessions ?? []) + [session]

        let agentParticipant = Participant(
            type: .agentSession(sessionId: session.id),
            displayName: AgentDefaults.displayName(forProvider: session.provider)
        )
        agentParticipant.conversation = conversation
        conversation.participants = (conversation.participants ?? []) + [agentParticipant]

        modelContext.insert(session)
        modelContext.insert(conversation)
        try? modelContext.save()
        windowState.selectedConversationId = conversation.id
        dismiss()
    }
}
