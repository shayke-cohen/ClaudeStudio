import SwiftUI
import SwiftData

// MARK: - CreationMode
// Shared enum for all hybrid creation sheets (AI-assisted vs manual).

enum CreationMode: String, CaseIterable {
    case fromPrompt = "From Prompt"
    case manual = "Manual"
}

// MARK: - AgentCreationSheet

struct AgentCreationSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @Query(sort: \Skill.name) private var allSkills: [Skill]
    @Query(sort: \MCPServer.name) private var allMCPs: [MCPServer]

    var existingAgent: Agent? = nil
    let onSave: (Agent) -> Void

    // MARK: Mode

    @State private var mode: CreationMode = .fromPrompt

    // MARK: From-Prompt state

    @State private var promptText: String = ""
    @State private var isGenerating: Bool = false
    @State private var generateError: String? = nil

    // MARK: Manual fields

    @State private var name: String = ""
    @State private var agentDescription: String = ""
    @State private var icon: String = "cpu"
    @State private var color: String = "blue"
    @State private var provider: String = ProviderSelection.system.rawValue
    @State private var model: String = AgentDefaults.inheritMarker
    @State private var systemPrompt: String = ""
    @State private var maxTurns: String = ""
    @State private var maxBudget: String = ""
    @State private var instancePolicy: AgentInstancePolicy = .agentDefault

    // Skill / MCP / permission pickers — full picker logic is a TODO in later tasks
    // @State private var selectedSkillIds: Set<UUID> = []
    // @State private var selectedMCPIds: Set<UUID> = []
    // @State private var selectedPermissionId: UUID? = nil

    // MARK: - Init (pre-fill for edit use-case)

    init(existingAgent: Agent? = nil, onSave: @escaping (Agent) -> Void) {
        self.existingAgent = existingAgent
        self.onSave = onSave
        if let a = existingAgent {
            _name = State(initialValue: a.name)
            _agentDescription = State(initialValue: a.agentDescription)
            _icon = State(initialValue: a.icon)
            _color = State(initialValue: a.color)
            _provider = State(initialValue: AgentDefaults.normalizedProviderSelection(a.provider).rawValue)
            _model = State(initialValue: a.model.isEmpty ? AgentDefaults.inheritMarker : a.model)
            _systemPrompt = State(initialValue: a.systemPrompt)
            _maxTurns = State(initialValue: a.maxTurns.map { String($0) } ?? "")
            _maxBudget = State(initialValue: a.maxBudget.map { String($0) } ?? "")
            _instancePolicy = State(initialValue: a.instancePolicy)
            _mode = State(initialValue: .manual)
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            Divider()
            modeSegment
            Divider()

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
        .frame(minWidth: 480, minHeight: 520)
        .onChange(of: appState.isGeneratingAgent) { _, generating in
            isGenerating = generating
        }
        .onChange(of: appState.generateAgentError) { _, error in
            generateError = error
        }
        .onChange(of: appState.generatedAgentSpec) { _, spec in
            guard let spec else { return }
            applyGeneratedSpec(spec)
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var sheetHeader: some View {
        HStack {
            Text(existingAgent != nil ? "Edit Agent" : "New Agent")
                .font(.title3)
                .fontWeight(.semibold)
                .accessibilityIdentifier("agentCreation.title")
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Close")
            .accessibilityIdentifier("agentCreation.closeButton")
            .accessibilityLabel("Close")
        }
        .padding()
    }

    // MARK: - Mode Segment

    @ViewBuilder
    private var modeSegment: some View {
        Picker("Mode", selection: $mode) {
            ForEach(CreationMode.allCases, id: \.self) { m in
                Text(m.rawValue).tag(m)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .accessibilityIdentifier("agentCreation.modePicker")
    }

    // MARK: - From-Prompt Section

    @ViewBuilder
    private var fromPromptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Describe the agent you want to create and Odyssey will generate a configuration for you.")
                .font(.callout)
                .foregroundStyle(.secondary)

            TextEditor(text: $promptText)
                .font(.body)
                .frame(minHeight: 100, maxHeight: 200)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .accessibilityIdentifier("agentCreation.promptEditor")

            if let error = generateError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("agentCreation.generateError")
            }

            if isGenerating {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Generating…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("agentCreation.generatingIndicator")
            }
        }
    }

    // MARK: - Manual Fields Section

    @ViewBuilder
    private var manualFieldsSection: some View {
        Form {
            Section("Identity") {
                TextField("Name", text: $name)
                    .accessibilityIdentifier("agentCreation.nameField")

                TextField("Description", text: $agentDescription, axis: .vertical)
                    .lineLimit(2...4)
                    .accessibilityIdentifier("agentCreation.descriptionField")

                HStack {
                    TextField("Icon (SF Symbol)", text: $icon)
                        .accessibilityIdentifier("agentCreation.iconField")
                    Image(systemName: icon.isEmpty ? "questionmark" : icon)
                        .foregroundStyle(Color.accentColor)
                }

                Picker("Color", selection: $color) {
                    ForEach(["blue", "red", "green", "purple", "orange", "teal", "pink", "indigo", "gray"], id: \.self) { c in
                        Text(c.capitalized).tag(c)
                    }
                }
                .accessibilityIdentifier("agentCreation.colorPicker")
            }

            Section("Model") {
                Picker("Provider", selection: $provider) {
                    ForEach(ProviderSelection.allCases) { choice in
                        Text(choice.label).tag(choice.rawValue)
                    }
                }
                .accessibilityIdentifier("agentCreation.providerPicker")

                Picker("Instance Policy", selection: $instancePolicy) {
                    ForEach(AgentInstancePolicy.allCases, id: \.self) { policy in
                        Text(policy.displayName).tag(policy)
                    }
                }
                .accessibilityIdentifier("agentCreation.instancePolicyPicker")
            }

            Section("System Prompt") {
                TextEditor(text: $systemPrompt)
                    .font(.body)
                    .frame(minHeight: 80)
                    .accessibilityIdentifier("agentCreation.systemPromptEditor")
            }

            Section("Capabilities") {
                // TODO: Skill picker — implement in a later task
                Text("Skills: (picker coming soon)")
                    .foregroundStyle(Color.secondary.opacity(0.6))
                    .font(.callout)

                // TODO: MCP picker — implement in a later task
                Text("MCPs: (picker coming soon)")
                    .foregroundStyle(Color.secondary.opacity(0.6))
                    .font(.callout)
            }

            Section("Limits (optional)") {
                TextField("Max Turns", text: $maxTurns)
                    .accessibilityIdentifier("agentCreation.maxTurnsField")

                TextField("Max Budget ($)", text: $maxBudget)
                    .accessibilityIdentifier("agentCreation.maxBudgetField")
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
            .accessibilityIdentifier("agentCreation.cancelButton")

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
                .accessibilityIdentifier("agentCreation.generateButton")
            } else {
                Button(existingAgent != nil ? "Save" : "Create Agent") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("agentCreation.createButton")
            }
        }
        .padding()
    }

    // MARK: - Actions

    /// Trigger AI agent generation via the sidecar.
    @MainActor
    private func generate() async {
        guard !promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        generateError = nil

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
            prompt: promptText.trimmingCharacters(in: .whitespacesAndNewlines),
            skills: skillEntries,
            mcps: mcpEntries
        )
    }

    /// Apply a generated spec to the manual fields and switch to manual mode.
    @MainActor
    private func applyGeneratedSpec(_ spec: GeneratedAgentSpec) {
        name = spec.name
        agentDescription = spec.description
        icon = spec.icon
        color = spec.color
        model = spec.model
        systemPrompt = spec.systemPrompt
        maxTurns = spec.maxTurns.map { String($0) } ?? ""
        maxBudget = spec.maxBudget.map { String($0) } ?? ""
        // Switch to manual mode so the user can review and edit the result
        mode = .manual
    }

    /// Save the manually-configured agent.
    private func save() {
        do {
            try performAgentSave(
                existingAgent: existingAgent,
                name: name,
                agentDescription: agentDescription,
                icon: icon.isEmpty ? "cpu" : icon,
                color: color.isEmpty ? "blue" : color,
                provider: provider,
                model: model,
                systemPrompt: systemPrompt,
                maxTurns: Int(maxTurns),
                maxBudget: Double(maxBudget),
                instancePolicy: instancePolicy,
                modelContext: modelContext,
                onSave: onSave,
                dismiss: { dismiss() }
            )
        } catch {
            generateError = error.localizedDescription
        }
    }
}

// MARK: - performAgentSave (free function for testability)

/// Creates or updates an `Agent` in SwiftData and writes its config file.
/// Extracted as a free function so unit tests can call it without a live view.
func performAgentSave(
    existingAgent: Agent? = nil,
    name: String,
    agentDescription: String,
    icon: String,
    color: String,
    provider: String,
    model: String,
    systemPrompt: String,
    maxTurns: Int?,
    maxBudget: Double?,
    instancePolicy: AgentInstancePolicy,
    modelContext: ModelContext,
    onSave: (Agent) -> Void,
    dismiss: () -> Void
) throws {
    let slug = ConfigFileManager.slugify(name)

    // Build the on-disk DTO
    let dto = AgentConfigFileDTO(
        name: name,
        description: agentDescription.isEmpty ? nil : agentDescription,
        model: model,
        provider: provider == ProviderSelection.system.rawValue ? nil : provider,
        resident: nil,
        icon: icon.isEmpty ? nil : icon,
        color: color.isEmpty ? nil : color,
        skills: [],
        mcps: [],
        permissions: nil,
        maxTurns: maxTurns,
        maxBudget: maxBudget,
        maxThinkingTokens: nil,
        instancePolicy: instancePolicy == .agentDefault ? nil : instancePolicy.rawValue,
        instancePolicyPoolMax: nil,
        defaultWorkingDirectory: Agent.defaultHomePath(for: name),
        isShared: nil
    )

    // Write to disk — ConfigSyncService will pick it up via file-watching
    try ConfigFileManager.writeBack(agentSlug: slug, config: dto, prompt: systemPrompt)

    // Insert or update SwiftData
    let agent: Agent
    if let existing = existingAgent {
        agent = existing
    } else {
        agent = Agent(
            name: name,
            agentDescription: agentDescription,
            systemPrompt: systemPrompt,
            provider: provider,
            model: model,
            icon: icon.isEmpty ? "cpu" : icon,
            color: color.isEmpty ? "blue" : color
        )
        modelContext.insert(agent)
    }
    agent.name = name
    agent.agentDescription = agentDescription
    agent.systemPrompt = systemPrompt
    agent.provider = provider
    agent.model = model
    agent.icon = icon.isEmpty ? "cpu" : icon
    agent.color = color.isEmpty ? "blue" : color
    agent.configSlug = slug
    agent.maxTurns = maxTurns
    agent.maxBudget = maxBudget
    agent.instancePolicy = instancePolicy
    agent.updatedAt = Date()
    try? modelContext.save()

    onSave(agent)
    dismiss()
}
