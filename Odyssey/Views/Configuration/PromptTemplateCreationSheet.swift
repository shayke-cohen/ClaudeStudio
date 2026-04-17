import SwiftUI
import SwiftData

// MARK: - PromptTemplateCreationSheet

/// Hybrid creation sheet for prompt templates.
/// - "From Prompt" mode: user describes the task intent; Odyssey generates name + prompt.
/// - "Manual" mode: user types name and prompt directly.
///
/// The sheet is always opened in the context of an owner (Agent or AgentGroup). The caller
/// passes `ownerAgent` or `ownerGroup` (exactly one non-nil). On save, a file is written to
/// `~/.odyssey/config/prompt-templates/<ownerKind>/<ownerSlug>/<templateSlug>.md` and a
/// `PromptTemplate` SwiftData record is inserted.
struct PromptTemplateCreationSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    var ownerAgent: Agent? = nil
    var ownerGroup: AgentGroup? = nil
    var existingTemplate: PromptTemplate? = nil
    var onSave: ((PromptTemplate) -> Void)? = nil

    // MARK: Mode

    @State private var mode: CreationMode = .fromPrompt

    // MARK: From-Prompt state

    @State private var intentText: String = ""
    @State private var isGenerating: Bool = false
    @State private var generateError: String? = nil

    // MARK: Manual fields

    @State private var name: String = ""
    @State private var prompt: String = ""

    // MARK: - Init (pre-fill for edit use-case)

    init(
        ownerAgent: Agent? = nil,
        ownerGroup: AgentGroup? = nil,
        existingTemplate: PromptTemplate? = nil,
        onSave: ((PromptTemplate) -> Void)? = nil
    ) {
        self.ownerAgent = ownerAgent
        self.ownerGroup = ownerGroup
        self.existingTemplate = existingTemplate
        self.onSave = onSave

        if let t = existingTemplate {
            _name = State(initialValue: t.name)
            _prompt = State(initialValue: t.prompt)
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
        .frame(minWidth: 480, minHeight: 460)
        .onChange(of: appState.isGeneratingTemplate) { _, generating in
            isGenerating = generating
        }
        .onChange(of: appState.generateTemplateError) { _, error in
            generateError = error
        }
        .onChange(of: appState.generatedTemplateSpec) { _, spec in
            guard let spec else { return }
            applyGeneratedSpec(spec)
        }
    }

    // MARK: - Header

    private var sheetHeader: some View {
        HStack {
            Text(existingTemplate != nil ? "Edit Template" : "New Template")
                .font(.title3)
                .fontWeight(.semibold)
                .accessibilityIdentifier("templateCreation.title")
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Close")
            .accessibilityIdentifier("templateCreation.closeButton")
            .accessibilityLabel("Close")
        }
        .padding()
    }

    // MARK: - Mode Segment

    private var modeSegment: some View {
        Picker("Mode", selection: $mode) {
            ForEach(CreationMode.allCases, id: \.self) { m in
                Text(m.rawValue).tag(m)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .accessibilityIdentifier("templateCreation.modePicker")
    }

    // MARK: - From-Prompt Section

    private var fromPromptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Describe the task this template should help with and Odyssey will generate the prompt for you.")
                .font(.callout)
                .foregroundStyle(.secondary)

            TextEditor(text: $intentText)
                .font(.body)
                .frame(minHeight: 120, maxHeight: 240)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .accessibilityIdentifier("templateCreation.intentEditor")

            if let error = generateError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("templateCreation.generateError")
            }

            if isGenerating {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Generating…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("templateCreation.generatingIndicator")
            }
        }
    }

    // MARK: - Manual Fields Section

    private var manualFieldsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                TextField("e.g. Review PR", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("templateCreation.nameField")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Prompt")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                TextEditor(text: $prompt)
                    .font(.system(.body, design: .default))
                    .padding(6)
                    .frame(minHeight: 180)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                    .accessibilityIdentifier("templateCreation.promptEditor")
                Text("Tip: include phrasing like \u{201C}before starting, ask me for X\u{201D} to have the agent collect missing parameters.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Footer

    private var footerButtons: some View {
        HStack {
            Spacer()
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier("templateCreation.cancelButton")

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
                .disabled(intentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating)
                .accessibilityIdentifier("templateCreation.generateButton")
            } else {
                Button(existingTemplate != nil ? "Save Template" : "Create Template") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("templateCreation.createButton")
            }
        }
        .padding()
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Actions

    @MainActor
    private func generate() async {
        guard !intentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        generateError = nil

        appState.requestTemplateGeneration(
            intent: intentText.trimmingCharacters(in: .whitespacesAndNewlines),
            agentName: ownerAgent?.name ?? ownerGroup?.name ?? "",
            agentSystemPrompt: ownerAgent?.systemPrompt ?? ""
        )
    }

    @MainActor
    private func applyGeneratedSpec(_ spec: GeneratedTemplateSpec) {
        name = spec.name
        prompt = spec.prompt
        mode = .manual
    }

    private func save() {
        let sortOrder: Int
        if let existing = existingTemplate {
            sortOrder = existing.sortOrder
        } else {
            sortOrder = 0
        }

        do {
            let saved = try performTemplateSave(
                existingTemplate: existingTemplate,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
                ownerAgent: ownerAgent,
                ownerGroup: ownerGroup,
                sortOrder: sortOrder,
                context: modelContext
            )
            onSave?(saved)
        } catch {
            // Surface write errors via generateError so the user sees feedback
            generateError = error.localizedDescription
            return
        }
        dismiss()
    }
}

// MARK: - performTemplateSave (free function for testability)

/// Creates or updates a `PromptTemplate` in SwiftData and writes its `.md` file to disk.
/// Extracted as a free function so unit tests can call it without a live view.
@discardableResult
func performTemplateSave(
    existingTemplate: PromptTemplate?,
    name: String,
    prompt: String,
    ownerAgent: Agent?,
    ownerGroup: AgentGroup?,
    sortOrder: Int,
    context: ModelContext
) throws -> PromptTemplate {
    let ownerKind: PromptTemplateOwnerKindOnDisk = ownerAgent != nil ? .agents : .groups
    let ownerSlug: String = ownerAgent?.configSlug
        ?? ownerGroup?.configSlug
        ?? ConfigFileManager.slugify(ownerAgent?.name ?? ownerGroup?.name ?? "unknown")

    let templateSlug: String
    if let existing = existingTemplate, let slug = existing.templateSlugComponent {
        templateSlug = slug
    } else {
        templateSlug = ConfigFileManager.uniquePromptTemplateSlug(
            baseName: name,
            ownerKind: ownerKind,
            ownerSlug: ownerSlug
        )
    }

    let configSlug = "\(ownerKind.rawValue)/\(ownerSlug)/\(templateSlug)"

    let dto = PromptTemplateFileDTO(
        name: name,
        sortOrder: sortOrder,
        prompt: prompt
    )
    try ConfigFileManager.writePromptTemplate(
        ownerKind: ownerKind,
        ownerSlug: ownerSlug,
        templateSlug: templateSlug,
        dto: dto
    )

    if let existing = existingTemplate {
        existing.name = name
        existing.prompt = prompt
        existing.sortOrder = sortOrder
        existing.configSlug = configSlug
        existing.updatedAt = Date()
        try context.save()
        return existing
    } else {
        let template = PromptTemplate(
            name: name,
            prompt: prompt,
            sortOrder: sortOrder,
            isBuiltin: false,
            agent: ownerAgent,
            group: ownerGroup,
            configSlug: configSlug
        )
        context.insert(template)
        try context.save()
        return template
    }
}
