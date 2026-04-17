import SwiftUI
import SwiftData

// MARK: - SkillCreationSheet

struct SkillCreationSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @Query(sort: \MCPServer.name) private var allMCPs: [MCPServer]

    var existingSkill: Skill? = nil
    let onSave: (Skill) -> Void

    @State private var showMCPPicker: Bool = false

    // MARK: Mode

    @State private var mode: CreationMode = .fromPrompt

    // MARK: From-Prompt state

    @State private var promptText: String = ""
    @State private var isGenerating: Bool = false
    @State private var generateError: String? = nil

    // MARK: Starter chip selection

    private let starterChips: [String] = [
        "Security patterns",
        "Code review style",
        "Architecture principles",
        "Testing strategy"
    ]

    // MARK: Manual fields

    @State private var name: String = ""
    @State private var skillDescription: String = ""
    @State private var category: String = "General"
    @State private var triggers: [String] = []
    @State private var newTrigger: String = ""
    @State private var mcpServerIds: [UUID] = []
    @State private var content: String = ""
    @State private var version: String = "1.0"

    private let categories = ["General", "Security", "Code Review", "Architecture", "Testing", "DevOps"]

    // MARK: - Init (pre-fill for edit use-case)

    init(existingSkill: Skill? = nil, onSave: @escaping (Skill) -> Void) {
        self.existingSkill = existingSkill
        self.onSave = onSave
        if let s = existingSkill {
            _name = State(initialValue: s.name)
            _skillDescription = State(initialValue: s.skillDescription)
            _category = State(initialValue: s.category.isEmpty ? "General" : s.category)
            _triggers = State(initialValue: s.triggers)
            _mcpServerIds = State(initialValue: s.mcpServerIds)
            _content = State(initialValue: s.content)
            _version = State(initialValue: s.version.isEmpty ? "1.0" : s.version)
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
        .onChange(of: appState.isGeneratingSkill) { _, generating in
            isGenerating = generating
        }
        .onChange(of: appState.generateSkillError) { _, error in
            generateError = error
        }
        .onChange(of: appState.generatedSkillSpec) { _, spec in
            guard let spec else { return }
            applyGeneratedSpec(spec)
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var sheetHeader: some View {
        HStack {
            Text(existingSkill != nil ? "Edit Skill" : "New Skill")
                .font(.title3)
                .fontWeight(.semibold)
                .accessibilityIdentifier("skillCreation.title")
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Close")
            .accessibilityIdentifier("skillCreation.closeButton")
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
        .accessibilityIdentifier("skillCreation.modePicker")
    }

    // MARK: - From-Prompt Section

    @ViewBuilder
    private var fromPromptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Describe the skill you want to create and Odyssey will generate a configuration for you.")
                .font(.callout)
                .foregroundStyle(.secondary)

            // Starter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(starterChips, id: \.self) { chip in
                        Button {
                            promptText = chip
                        } label: {
                            Text(chip)
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    promptText == chip
                                        ? Color.accentColor.opacity(0.2)
                                        : Color.secondary.opacity(0.1)
                                )
                                .foregroundStyle(promptText == chip ? Color.accentColor : Color.primary)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("skillCreation.starterChip.\(chip)")
                    }
                }
            }

            TextEditor(text: $promptText)
                .font(.body)
                .frame(minHeight: 100, maxHeight: 200)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .accessibilityIdentifier("skillCreation.promptEditor")

            if let error = generateError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("skillCreation.generateError")
            }

            if isGenerating {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Generating…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("skillCreation.generatingIndicator")
            }
        }
    }

    // MARK: - Manual Fields Section

    @ViewBuilder
    private var manualFieldsSection: some View {
        Form {
            Section("Identity") {
                TextField("Name", text: $name)
                    .accessibilityIdentifier("skillCreation.nameField")

                TextField("Description", text: $skillDescription, axis: .vertical)
                    .lineLimit(2...4)
                    .accessibilityIdentifier("skillCreation.descriptionField")

                Picker("Category", selection: $category) {
                    ForEach(categories, id: \.self) { cat in
                        Text(cat).tag(cat)
                    }
                }
                .accessibilityIdentifier("skillCreation.categoryPicker")

                TextField("Version", text: $version)
                    .accessibilityIdentifier("skillCreation.versionField")
            }

            Section("Triggers") {
                triggersSection
            }

            Section("Required MCPs") {
                mcpsSection
            }

            Section("Content (Markdown)") {
                TextEditor(text: $content)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 120)
                    .accessibilityIdentifier("skillCreation.contentEditor")

                if !name.isEmpty {
                    let slug = ConfigFileManager.slugify(name)
                    Text("→ ~/.odyssey/config/skills/\(slug).md")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("skillCreation.filePathHint")
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - MCPs Section

    @ViewBuilder
    private var mcpsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Agents using this skill receive these MCPs automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !mcpServerIds.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(allMCPs.filter { mcpServerIds.contains($0.id) }) { mcp in
                            HStack(spacing: 3) {
                                Image(systemName: "server.rack").font(.caption2)
                                Text(mcp.name).font(.caption2)
                                Button {
                                    mcpServerIds.removeAll { $0 == mcp.id }
                                } label: {
                                    Image(systemName: "xmark").font(.caption2)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove MCP \(mcp.name)")
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.15))
                            .cornerRadius(4)
                        }
                    }
                }
                .accessibilityIdentifier("skillCreation.selectedMCPsList")
            }

            Button("Add MCP…") { showMCPPicker.toggle() }
                .font(.caption)
                .buttonStyle(.borderless)
                .foregroundStyle(Color.accentColor)
                .accessibilityIdentifier("skillCreation.addMCPButton")
                .popover(isPresented: $showMCPPicker, arrowEdge: .trailing) {
                    mcpPickerPopover
                }
        }
    }

    private var mcpPickerPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("MCPs")
                .font(.headline)
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 8)
            Divider()
            if allMCPs.isEmpty {
                Text("No MCPs available")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(14)
            } else {
                List(allMCPs) { mcp in
                    let isSelected = mcpServerIds.contains(mcp.id)
                    Button {
                        if isSelected {
                            mcpServerIds.removeAll { $0 == mcp.id }
                        } else {
                            mcpServerIds.append(mcp.id)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(mcp.name).font(.callout)
                                if !mcp.serverDescription.isEmpty {
                                    Text(mcp.serverDescription)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
                .frame(width: 280, height: min(CGFloat(allMCPs.count) * 44 + 8, 240))
            }
        }
    }

    // MARK: - Triggers UI

    @ViewBuilder
    private var triggersSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !triggers.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(triggers, id: \.self) { t in
                            HStack(spacing: 3) {
                                Text(t).font(.caption2)
                                Button {
                                    triggers.removeAll { $0 == t }
                                } label: {
                                    Image(systemName: "xmark").font(.caption2)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove trigger \(t)")
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.15))
                            .cornerRadius(4)
                        }
                    }
                }
                .accessibilityIdentifier("skillCreation.triggersList")
            }
            HStack(spacing: 6) {
                TextField("Add trigger…", text: $newTrigger)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .onSubmit { addTrigger() }
                    .accessibilityIdentifier("skillCreation.newTriggerField")
                Button("Add") { addTrigger() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(newTrigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("skillCreation.addTriggerButton")
            }
        }
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
            .accessibilityIdentifier("skillCreation.cancelButton")

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
                .accessibilityIdentifier("skillCreation.generateButton")
            } else {
                Button(existingSkill != nil ? "Save" : "Create Skill") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("skillCreation.createButton")
            }
        }
        .padding()
    }

    // MARK: - Actions

    /// Trigger AI skill generation via the sidecar.
    @MainActor
    private func generate() async {
        guard !promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        generateError = nil

        let mcpEntries = allMCPs.map { mcp in
            MCPCatalogEntry(
                id: mcp.id.uuidString,
                name: mcp.name,
                description: mcp.serverDescription
            )
        }

        appState.requestSkillGeneration(
            prompt: promptText.trimmingCharacters(in: .whitespacesAndNewlines),
            categories: categories,
            mcps: mcpEntries
        )
    }

    /// Apply a generated spec to the manual fields and switch to manual mode.
    @MainActor
    private func applyGeneratedSpec(_ spec: GeneratedSkillSpec) {
        name = spec.name
        skillDescription = spec.description
        category = spec.category
        triggers = spec.triggers
        content = spec.content
        // Resolve matched MCP IDs from UUIDs
        mcpServerIds = spec.matchedMCPIds.compactMap { UUID(uuidString: $0) }
        // Switch to manual mode so the user can review and edit the result
        mode = .manual
    }

    /// Add current newTrigger text to the triggers list.
    private func addTrigger() {
        let trimmed = newTrigger.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !triggers.contains(trimmed) else { return }
        triggers.append(trimmed)
        newTrigger = ""
    }

    /// Save the manually-configured skill.
    private func save() {
        do {
            try performSkillSave(
                existingSkill: existingSkill,
                name: name,
                skillDescription: skillDescription,
                category: category,
                triggers: triggers,
                mcpServerIds: mcpServerIds,
                content: content,
                version: version,
                context: modelContext
            )
            dismiss()
        } catch {
            generateError = error.localizedDescription
        }
    }
}

// MARK: - performSkillSave (free function for testability)

/// Creates or updates a `Skill` in SwiftData and writes its markdown file to disk.
/// Extracted as a free function so unit tests can call it without a live view.
@discardableResult
func performSkillSave(
    existingSkill: Skill?,
    name: String,
    skillDescription: String,
    category: String,
    triggers: [String],
    mcpServerIds: [UUID],
    content: String,
    version: String,
    context: ModelContext
) throws -> String {
    let slug = ConfigFileManager.slugify(name)

    // Build the on-disk DTO
    let dto = SkillFileDTO(
        name: name,
        category: category.isEmpty ? nil : category,
        triggers: triggers.isEmpty ? nil : triggers
    )

    // Write to disk — ConfigSyncService will pick it up via file-watching
    try ConfigFileManager.writeBack(skillSlug: slug, dto: dto, content: content)

    // Insert or update SwiftData
    let skill: Skill
    if let existing = existingSkill {
        skill = existing
    } else {
        skill = Skill(name: name, skillDescription: skillDescription, category: category, content: content)
        context.insert(skill)
    }

    skill.name = name
    skill.skillDescription = skillDescription
    skill.category = category.isEmpty ? "General" : category
    skill.triggers = triggers
    skill.mcpServerIds = mcpServerIds
    skill.content = content
    skill.version = version
    skill.configSlug = slug
    skill.sourceKind = "filesystem"
    skill.sourceValue = ConfigFileManager.skillsDirectory.appendingPathComponent("\(slug).md").path
    skill.updatedAt = Date()

    try context.save()

    return slug
}
