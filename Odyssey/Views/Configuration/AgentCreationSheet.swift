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
    }

    // MARK: - Header

    @ViewBuilder
    private var sheetHeader: some View {
        HStack {
            Text("New Agent")
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
                Button("Create Agent") {
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

    /// Stub: AI generation will be implemented in a later task.
    @MainActor
    private func generate() async {
        isGenerating = true
        generateError = nil
        // TODO: Integrate AI generation in a later task.
        isGenerating = false
    }

    /// Save the manually-configured agent.
    private func save() {
        performAgentSave(
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
    }
}

// MARK: - performAgentSave (free function for testability)

/// Creates a new `Agent` in SwiftData and writes its config file.
/// Extracted as a free function so unit tests can call it without a live view.
func performAgentSave(
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
) {
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
    try? ConfigFileManager.writeBack(agentSlug: slug, config: dto, prompt: systemPrompt)

    // Insert into SwiftData
    let agent = Agent(
        name: name,
        agentDescription: agentDescription,
        systemPrompt: systemPrompt,
        provider: provider,
        model: model,
        icon: icon.isEmpty ? "cpu" : icon,
        color: color.isEmpty ? "blue" : color
    )
    agent.configSlug = slug
    agent.maxTurns = maxTurns
    agent.maxBudget = maxBudget
    agent.instancePolicy = instancePolicy
    agent.updatedAt = Date()
    modelContext.insert(agent)
    try? modelContext.save()

    onSave(agent)
    dismiss()
}
