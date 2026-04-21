import SwiftUI
import SwiftData

struct GroupEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Query(sort: \Agent.name) private var allAgents: [Agent]
    @AppStorage(FeatureFlags.showAdvancedKey, store: AppSettings.store) private var masterFlag = false
    @AppStorage(FeatureFlags.workflowsKey, store: AppSettings.store) private var workflowsFlag = false

    let group: AgentGroup?

    // MARK: Mode
    @State private var mode: CreationMode

    // MARK: From-Prompt state
    @State private var promptText: String = ""
    @State private var isGenerating: Bool = false
    @State private var generateError: String? = nil

    // MARK: Manual fields
    @State private var name: String = ""
    @State private var icon: String = "👥"
    @State private var color: String = "blue"
    @State private var groupDescription: String = ""
    @State private var groupInstruction: String = ""
    @State private var defaultMission: String = ""
    @State private var selectedAgentIds: [UUID] = []
    @State private var autoReplyEnabled: Bool = true
    @State private var autonomousCapable: Bool = false
    @State private var coordinatorAgentId: UUID?
    @State private var agentRoles: [UUID: String] = [:]
    @State private var hasWorkflow: Bool = false
    @State private var workflowSteps: [WorkflowStep] = []
    @State private var homeDirectory: String = ""
    @State private var hasCustomHomeDir: Bool = false

    init(group: AgentGroup?) {
        self.group = group
        _mode = State(initialValue: group != nil ? .manual : .fromPrompt)
    }

    private let availableColors = ["blue", "red", "green", "purple", "orange", "yellow", "pink", "teal", "indigo", "gray"]

    private var isEditing: Bool { group != nil }
    private var workflowsEnabled: Bool { FeatureFlags.isEnabled(FeatureFlags.workflowsKey) || (masterFlag && workflowsFlag) }

    private var selectedAgents: [Agent] {
        allAgents.filter { selectedAgentIds.contains($0.id) }
    }

    private var pastConversations: [Conversation] {
        guard let gid = group?.id else { return [] }
        let descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate { $0.sourceGroupId == gid },
            sortBy: [SortDescriptor(\Conversation.startedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isEditing ? "Edit Group" : "New Group")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("groupEditor.title")
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Close")
                .accessibilityIdentifier("groupEditor.closeButton")
                .accessibilityLabel("Close")
            }
            .padding()

            Divider()

            // Mode picker
            if !isEditing {
                Picker("Mode", selection: $mode) {
                    ForEach(CreationMode.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .disabled(isGenerating)
                .accessibilityIdentifier("groupEditor.modePicker")

                Divider()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch mode {
                    case .fromPrompt:
                        fromPromptSection
                    case .manual:
                        manualFieldsSection
                    }
                }
                .padding()
            }

            Divider()
            footerButtons
        }
        .frame(minWidth: 500, minHeight: 520)
        .onAppear { loadFromGroup() }
        .onChange(of: appState.isGeneratingGroup) { _, generating in
            isGenerating = generating
        }
        .onChange(of: appState.generateGroupError) { _, error in
            generateError = error
        }
        .onChange(of: appState.generatedGroupSpec) { _, spec in
            guard let spec else { return }
            applyGeneratedSpec(spec)
        }
    }

    // MARK: - From-Prompt Section

    @ViewBuilder
    private var fromPromptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Describe the group you want to create and Odyssey will generate a configuration for you.")
                .font(.callout)
                .foregroundStyle(.secondary)

            TextEditor(text: $promptText)
                .font(.body)
                .frame(minHeight: 100, maxHeight: 200)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .disabled(isGenerating)
                .opacity(isGenerating ? 0.6 : 1)
                .accessibilityIdentifier("groupEditor.promptEditor")

            if let error = generateError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("groupEditor.generateError")
            }

            if isGenerating {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Generating…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("groupEditor.generatingIndicator")
            }
        }
    }

    // MARK: - Manual Fields Section

    @ViewBuilder
    private var manualFieldsSection: some View {
        Form {
            // Identity
            Section("Identity") {
                    HStack {
                        TextField("Icon", text: $icon)
                            .frame(width: 50)
                            .stableXrayId("groupEditor.iconField")
                        TextField("Group Name", text: $name)
                            .stableXrayId("groupEditor.nameField")
                            .onChange(of: name) { _, newName in
                                if !hasCustomHomeDir {
                                    homeDirectory = AgentGroup.defaultHomePath(for: newName)
                                }
                            }
                    }

                    HStack {
                        TextField("Home Directory", text: $homeDirectory)
                            .stableXrayId("groupEditor.homeDirectoryField")
                            .onChange(of: homeDirectory) { _, newDir in
                                hasCustomHomeDir = newDir != AgentGroup.defaultHomePath(for: name)
                            }
                        Button("Browse…") {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = false
                            panel.canChooseDirectories = true
                            panel.allowsMultipleSelection = false
                            panel.prompt = "Select"
                            if panel.runModal() == .OK, let url = panel.url {
                                homeDirectory = url.path
                                hasCustomHomeDir = true
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .stableXrayId("groupEditor.homeDirectoryBrowseButton")
                    }

                    TextField("Description", text: $groupDescription)
                        .stableXrayId("groupEditor.descriptionField")

                    HStack(spacing: 6) {
                        Text("Color")
                            .foregroundStyle(.secondary)
                        ForEach(availableColors, id: \.self) { colorName in
                            Circle()
                                .fill(Color.fromAgentColor(colorName))
                                .frame(width: 20, height: 20)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary, lineWidth: color == colorName ? 2 : 0)
                                )
                                .onTapGesture { color = colorName }
                                .stableXrayId("groupEditor.color.\(colorName)")
                        }
                    }
                }

                // Group Instruction
                Section("Group Instruction") {
                    TextEditor(text: $groupInstruction)
                        .font(.body)
                        .frame(minHeight: 80)
                        .stableXrayId("groupEditor.instructionField")
                    Text("Injected as context at the start of each conversation.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                // Default Mission
                Section("Default Mission") {
                    TextField("Pre-filled mission (optional)", text: $defaultMission)
                        .stableXrayId("groupEditor.defaultMissionField")
                }

                // Behavior
                Section("Behavior") {
                    Toggle("Auto-Reply (agents react to each other)", isOn: $autoReplyEnabled)
                        .stableXrayId("groupEditor.autoReplyToggle")
                    Toggle("Autonomous Capable", isOn: $autonomousCapable)
                        .stableXrayId("groupEditor.autonomousToggle")

                    if autonomousCapable && !selectedAgents.isEmpty {
                        Picker("Coordinator", selection: $coordinatorAgentId) {
                            Text("None").tag(UUID?.none)
                            ForEach(selectedAgents) { agent in
                                HStack {
                                    Image(systemName: agent.icon)
                                        .foregroundStyle(Color.fromAgentColor(agent.color))
                                    Text(agent.name)
                                }
                                .tag(UUID?.some(agent.id))
                            }
                        }
                        .stableXrayId("groupEditor.coordinatorPicker")
                    }
                }

                // Workflow
                if workflowsEnabled {
                    Section("Workflow") {
                        Toggle("Enable Workflow (step-by-step pipeline)", isOn: $hasWorkflow)
                            .stableXrayId("groupEditor.workflowToggle")

                        if hasWorkflow {
                            WorkflowEditorView(
                                availableAgents: selectedAgents,
                                steps: $workflowSteps
                            )
                        }
                    }
                }

                // Agent Selection with Roles
                Section("Agents (\(selectedAgentIds.count))") {
                    ForEach(allAgents) { agent in
                        let isSelected = selectedAgentIds.contains(agent.id)
                        VStack(spacing: 0) {
                            HStack {
                                Image(systemName: agent.icon)
                                    .foregroundStyle(Color.fromAgentColor(agent.color))
                                    .frame(width: 24)
                                Text(agent.name)
                                Spacer()
                                if isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.blue)
                                } else {
                                    Image(systemName: "circle")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if isSelected {
                                    selectedAgentIds.removeAll { $0 == agent.id }
                                    agentRoles.removeValue(forKey: agent.id)
                                    if coordinatorAgentId == agent.id { coordinatorAgentId = nil }
                                } else {
                                    selectedAgentIds.append(agent.id)
                                }
                            }

                            if isSelected {
                                HStack {
                                    Spacer().frame(width: 28)
                                    Picker("Role", selection: Binding(
                                        get: { GroupRole(rawValue: agentRoles[agent.id] ?? "") ?? .participant },
                                        set: { agentRoles[agent.id] = $0.rawValue }
                                    )) {
                                        ForEach(GroupRole.allCases, id: \.self) { role in
                                            Text(role.displayName).tag(role)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                    .controlSize(.small)
                                    .stableXrayId("groupEditor.rolePicker.\(agent.id.uuidString)")
                                }
                                .padding(.top, 4)
                            }
                        }
                    }
                    .stableXrayId("groupEditor.agentPicker")
                }

                // Past Chats
                if isEditing && !pastConversations.isEmpty {
                    Section("Past Chats (\(pastConversations.count))") {
                        ForEach(pastConversations.prefix(20)) { conv in
                            HStack {
                                Text(conv.topic ?? "Untitled")
                                    .lineLimit(1)
                                Spacer()
                                Text(conv.startedAt, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }

    // MARK: - Footer

    @ViewBuilder
    private var footerButtons: some View {
        HStack {
            Spacer()
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .stableXrayId("groupEditor.cancelButton")

            if mode == .fromPrompt {
                Button {
                    Task { await generate() }
                } label: {
                    if isGenerating {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Text("Generate")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating)
                .accessibilityIdentifier("groupEditor.generateButton")
                .appXrayTapProxy(id: "groupEditor.generateButton") { Task { await generate() } }
            } else {
                Button(isEditing ? "Save" : "Create Group") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedAgentIds.isEmpty)
                    .keyboardShortcut(.defaultAction)
                    .stableXrayId("groupEditor.saveButton")
            }
        }
        .padding()
    }

    // MARK: - Actions

    @MainActor
    private func generate() async {
        guard !promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        generateError = nil

        let agentEntries = allAgents.map { agent in
            AgentCatalogEntry(
                id: agent.id.uuidString,
                name: agent.name,
                description: agent.agentDescription
            )
        }

        appState.requestGroupGeneration(
            prompt: promptText.trimmingCharacters(in: .whitespacesAndNewlines),
            agents: agentEntries
        )
    }

    @MainActor
    private func applyGeneratedSpec(_ spec: GeneratedGroupSpec) {
        name = spec.name
        groupDescription = spec.description
        icon = spec.icon
        color = spec.color
        groupInstruction = spec.groupInstruction
        defaultMission = spec.defaultMission ?? ""
        selectedAgentIds = spec.matchedAgentIds.compactMap { UUID(uuidString: $0) }
        homeDirectory = AgentGroup.defaultHomePath(for: spec.name)
        hasCustomHomeDir = false
        mode = .manual
    }

    private func loadFromGroup() {
        guard let group else { return }
        name = group.name
        icon = group.icon
        color = group.color
        groupDescription = group.groupDescription
        groupInstruction = group.groupInstruction
        defaultMission = group.defaultMission ?? ""
        selectedAgentIds = group.agentIds
        autoReplyEnabled = group.autoReplyEnabled
        autonomousCapable = group.autonomousCapable
        coordinatorAgentId = group.coordinatorAgentId
        agentRoles = group.agentRoles
        if let wf = group.workflow, !wf.isEmpty {
            hasWorkflow = true
            workflowSteps = wf
        }
        let existingHome = group.defaultWorkingDirectory ?? AgentGroup.defaultHomePath(for: group.name)
        homeDirectory = existingHome
        hasCustomHomeDir = existingHome != AgentGroup.defaultHomePath(for: group.name)
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !selectedAgentIds.isEmpty else { return }

        let resolvedHome = homeDirectory.isEmpty ? AgentGroup.defaultHomePath(for: trimmedName) : homeDirectory
        if let group {
            group.name = trimmedName
            group.icon = icon
            group.color = color
            group.groupDescription = groupDescription
            group.groupInstruction = groupInstruction
            group.defaultMission = defaultMission.isEmpty ? nil : defaultMission
            group.agentIds = selectedAgentIds
            group.autoReplyEnabled = autoReplyEnabled
            group.autonomousCapable = autonomousCapable
            group.coordinatorAgentId = coordinatorAgentId
            group.agentRoles = agentRoles
            group.workflow = hasWorkflow && !workflowSteps.isEmpty ? workflowSteps : nil
            group.defaultWorkingDirectory = resolvedHome
        } else {
            let newGroup = AgentGroup(
                name: trimmedName,
                groupDescription: groupDescription,
                icon: icon,
                color: color,
                groupInstruction: groupInstruction,
                defaultMission: defaultMission.isEmpty ? nil : defaultMission,
                agentIds: selectedAgentIds
            )
            newGroup.autoReplyEnabled = autoReplyEnabled
            newGroup.autonomousCapable = autonomousCapable
            newGroup.coordinatorAgentId = coordinatorAgentId
            newGroup.agentRoles = agentRoles
            newGroup.workflow = hasWorkflow && !workflowSteps.isEmpty ? workflowSteps : nil
            newGroup.defaultWorkingDirectory = resolvedHome
            modelContext.insert(newGroup)
        }

        try? modelContext.save()
        dismiss()
    }
}
