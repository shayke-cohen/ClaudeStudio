import SwiftUI
import SwiftData

struct AgentEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Skill.name) private var allSkills: [Skill]
    @Query(sort: \MCPServer.name) private var allMCPs: [MCPServer]
    @Query(sort: \PermissionSet.name) private var allPermissions: [PermissionSet]

    let agent: Agent?
    let onSave: (Agent) -> Void

    @State private var currentStep = 0
    @State private var name: String
    @State private var agentDescription: String
    @State private var icon: String
    @State private var color: String
    @State private var model: String
    @State private var maxTurns: String
    @State private var maxBudget: String
    @State private var instancePolicyType: Int
    @State private var poolMax: String
    @State private var workingDirectory: String
    @State private var githubRepo: String
    @State private var githubBranch: String
    @State private var selectedSkillIds: Set<UUID>
    @State private var selectedMCPIds: Set<UUID>
    @State private var selectedPermissionId: UUID?
    @State private var systemPrompt: String
    @State private var showSkillLibrary = false
    @State private var showMCPLibrary = false
    @State private var skillsExpanded = true
    @State private var mcpsExpanded = true
    @State private var permissionsExpanded = false

    init(agent: Agent?, onSave: @escaping (Agent) -> Void) {
        self.agent = agent
        self.onSave = onSave
        _name = State(initialValue: agent?.name ?? "")
        _agentDescription = State(initialValue: agent?.agentDescription ?? "")
        _icon = State(initialValue: agent?.icon ?? "cpu")
        _color = State(initialValue: agent?.color ?? "blue")
        _model = State(initialValue: agent?.model ?? "sonnet")
        _maxTurns = State(initialValue: agent?.maxTurns.map(String.init) ?? "")
        _maxBudget = State(initialValue: agent?.maxBudget.map { String(format: "%.2f", $0) } ?? "")
        _workingDirectory = State(initialValue: agent?.defaultWorkingDirectory ?? "")
        _githubRepo = State(initialValue: agent?.githubRepo ?? "")
        _githubBranch = State(initialValue: agent?.githubDefaultBranch ?? "main")
        _selectedSkillIds = State(initialValue: Set(agent?.skillIds ?? []))
        _selectedMCPIds = State(initialValue: Set(agent?.extraMCPServerIds ?? []))
        _selectedPermissionId = State(initialValue: agent?.permissionSetId)
        _systemPrompt = State(initialValue: agent?.systemPrompt ?? "")

        let policyType: Int
        if let policy = agent?.instancePolicy {
            switch policy {
            case .spawn: policyType = 0
            case .singleton: policyType = 1
            case .pool: policyType = 2
            }
        } else {
            policyType = 0
        }
        _instancePolicyType = State(initialValue: policyType)

        if case .pool(let max) = agent?.instancePolicy {
            _poolMax = State(initialValue: String(max))
        } else {
            _poolMax = State(initialValue: "3")
        }
    }

    private let steps = ["Identity", "Capabilities", "System Prompt"]

    var body: some View {
        VStack(spacing: 0) {
            editorHeader
            Divider()
            stepIndicator
            Divider()

            Group {
                switch currentStep {
                case 0: identityStep
                case 1: capabilitiesStep
                case 2: systemPromptStep
                default: EmptyView()
                }
            }
            .frame(maxHeight: .infinity)

            Divider()
            navigationButtons
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var editorHeader: some View {
        HStack {
            Text(agent == nil ? "Create Agent" : "Edit Agent")
                .font(.title3)
                .fontWeight(.semibold)
                .accessibilityIdentifier("agentEditor.title")
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Close")
            .accessibilityIdentifier("agentEditor.closeButton")
            .accessibilityLabel("Close")
        }
        .padding()
    }

    // MARK: - Step Indicator

    @ViewBuilder
    private var stepIndicator: some View {
        HStack(spacing: 0) {
            ForEach(0..<steps.count, id: \.self) { index in
                Button {
                    currentStep = index
                } label: {
                    Text(steps[index])
                        .font(.caption)
                        .fontWeight(currentStep == index ? .semibold : .regular)
                        .foregroundStyle(currentStep == index ? .primary : .secondary)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(currentStep == index ? Color.accentColor.opacity(0.1) : Color.clear)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("agentEditor.step.\(steps[index].lowercased().replacingOccurrences(of: " ", with: ""))")
                if index < steps.count - 1 {
                    Divider().frame(height: 20)
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Step 1: Identity

    @ViewBuilder
    private var identityStep: some View {
        Form {
            Section("Basic Info") {
                TextField("Name", text: $name)
                    .accessibilityIdentifier("agentEditor.nameField")
                TextField("Description", text: $agentDescription, axis: .vertical)
                    .lineLimit(2...4)
                    .accessibilityIdentifier("agentEditor.descriptionField")
                HStack {
                    TextField("Icon (SF Symbol)", text: $icon)
                        .accessibilityIdentifier("agentEditor.iconField")
                    Image(systemName: icon)
                        .foregroundStyle(.blue)
                }
                Picker("Color", selection: $color) {
                    ForEach(["blue", "red", "green", "purple", "orange", "teal", "pink", "indigo", "gray"], id: \.self) { c in
                        Text(c.capitalized).tag(c)
                    }
                }
                .accessibilityIdentifier("agentEditor.colorPicker")
                Picker("Model", selection: $model) {
                    Text("Sonnet").tag("sonnet")
                    Text("Opus").tag("opus")
                    Text("Haiku").tag("haiku")
                }
                .accessibilityIdentifier("agentEditor.modelPicker")
                TextField("Max Turns", text: $maxTurns)
                    .accessibilityIdentifier("agentEditor.maxTurnsField")
                TextField("Max Budget ($)", text: $maxBudget)
                    .accessibilityIdentifier("agentEditor.maxBudgetField")
            }

            Section("Instance Policy") {
                Picker("Policy", selection: $instancePolicyType) {
                    Text("Spawn (fresh per task)").tag(0)
                    Text("Singleton (one instance)").tag(1)
                    Text("Pool (multiple instances)").tag(2)
                }
                .accessibilityIdentifier("agentEditor.instancePolicyPicker")
                if instancePolicyType == 2 {
                    TextField("Max Instances", text: $poolMax)
                        .accessibilityIdentifier("agentEditor.poolMaxField")
                }
            }

            Section("Workspace") {
                TextField("Working Directory", text: $workingDirectory)
                    .accessibilityIdentifier("agentEditor.workingDirectoryField")
                TextField("GitHub Repo URL", text: $githubRepo)
                    .accessibilityIdentifier("agentEditor.githubRepoField")
                TextField("Branch", text: $githubBranch)
                    .accessibilityIdentifier("agentEditor.githubBranchField")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Step 2: Capabilities (Skills + MCPs + Permissions)

    private var inheritedMCPIds: Set<UUID> {
        let selectedSkills = allSkills.filter { selectedSkillIds.contains($0.id) }
        return Set(selectedSkills.flatMap(\.mcpServerIds))
    }

    @ViewBuilder
    private var capabilitiesStep: some View {
        ScrollView {
            VStack(spacing: 0) {
                skillsSection
                Divider().padding(.horizontal)
                mcpsSection
                Divider().padding(.horizontal)
                permissionsSection
            }
        }
        .sheet(isPresented: $showSkillLibrary) {
            SkillLibraryView()
                .frame(minWidth: 560, minHeight: 420)
        }
        .sheet(isPresented: $showMCPLibrary) {
            MCPLibraryView()
                .frame(minWidth: 560, minHeight: 420)
        }
    }

    @ViewBuilder
    private var skillsSection: some View {
        DisclosureGroup(isExpanded: $skillsExpanded) {
            HStack(spacing: 0) {
                VStack(alignment: .leading) {
                    Text("Selected (\(selectedSkillIds.count))")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal)
                    List {
                        ForEach(allSkills.filter { selectedSkillIds.contains($0.id) }) { skill in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(skill.name).font(.callout)
                                    Text(skill.category).font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    selectedSkillIds.remove(skill.id)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.borderless)
                                .help("Remove skill")
                                .accessibilityIdentifier("agentEditor.skills.removeButton.\(skill.id.uuidString)")
                                .accessibilityLabel("Remove \(skill.name)")
                            }
                        }
                    }
                    .accessibilityIdentifier("agentEditor.skills.selectedList")
                    .frame(minHeight: 120)
                }
                .frame(maxWidth: .infinity)

                Divider()

                VStack(alignment: .leading) {
                    Text("Available")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal)
                    List {
                        ForEach(allSkills.filter { !selectedSkillIds.contains($0.id) }) { skill in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(skill.name).font(.callout)
                                    Text(skill.category).font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    selectedSkillIds.insert(skill.id)
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(.green)
                                }
                                .buttonStyle(.borderless)
                                .help("Add skill")
                                .accessibilityIdentifier("agentEditor.skills.addButton.\(skill.id.uuidString)")
                                .accessibilityLabel("Add \(skill.name)")
                            }
                        }
                    }
                    .accessibilityIdentifier("agentEditor.skills.availableList")
                    .frame(minHeight: 120)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(height: 180)

            HStack {
                Spacer()
                Button {
                    showSkillLibrary = true
                } label: {
                    Label("Manage Skills...", systemImage: "book.fill")
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("agentEditor.manageSkills")
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
        } label: {
            Label("Skills (\(selectedSkillIds.count) selected)", systemImage: "book")
                .font(.headline)
        }
        .padding()
        .accessibilityIdentifier("agentEditor.skillsDisclosure")
    }

    @ViewBuilder
    private var mcpsSection: some View {
        DisclosureGroup(isExpanded: $mcpsExpanded) {
            if !inheritedMCPIds.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Inherited from Skills")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                    ForEach(allMCPs.filter { inheritedMCPIds.contains($0.id) }) { mcp in
                        HStack {
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(mcp.name)
                                .font(.callout)
                            Spacer()
                            let fromSkills = allSkills
                                .filter { selectedSkillIds.contains($0.id) && $0.mcpServerIds.contains(mcp.id) }
                                .map(\.name)
                                .joined(separator: ", ")
                            Text("from: \(fromSkills)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.bottom, 8)
            }

            HStack(spacing: 0) {
                VStack(alignment: .leading) {
                    Text("Extra MCPs (\(selectedMCPIds.count))")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal)
                    List {
                        ForEach(allMCPs.filter { selectedMCPIds.contains($0.id) }) { mcp in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(mcp.name).font(.callout)
                                    Text(mcp.serverDescription).font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                StatusBadge(status: mcp.status.rawValue.capitalized,
                                           color: mcp.status == .connected ? .green : .gray)
                                Button {
                                    selectedMCPIds.remove(mcp.id)
                                } label: {
                                    Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                                }
                                .buttonStyle(.borderless)
                                .help("Remove MCP server")
                                .accessibilityIdentifier("agentEditor.mcps.removeButton.\(mcp.id.uuidString)")
                                .accessibilityLabel("Remove \(mcp.name)")
                            }
                        }
                    }
                    .accessibilityIdentifier("agentEditor.mcps.selectedList")
                    .frame(minHeight: 80)
                }
                .frame(maxWidth: .infinity)

                Divider()

                VStack(alignment: .leading) {
                    Text("Available")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal)
                    List {
                        ForEach(allMCPs.filter { !selectedMCPIds.contains($0.id) && !inheritedMCPIds.contains($0.id) }) { mcp in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(mcp.name).font(.callout)
                                    Text(mcp.serverDescription).font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    selectedMCPIds.insert(mcp.id)
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(.green)
                                }
                                .buttonStyle(.borderless)
                                .help("Add MCP server")
                                .accessibilityIdentifier("agentEditor.mcps.addButton.\(mcp.id.uuidString)")
                                .accessibilityLabel("Add \(mcp.name)")
                            }
                        }
                    }
                    .accessibilityIdentifier("agentEditor.mcps.availableList")
                    .frame(minHeight: 80)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(height: 140)

            HStack {
                Spacer()
                Button {
                    showMCPLibrary = true
                } label: {
                    Label("Manage MCPs...", systemImage: "server.rack")
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("agentEditor.manageMCPs")
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
        } label: {
            let totalMCPs = selectedMCPIds.count + inheritedMCPIds.count
            Label("MCP Servers (\(totalMCPs) active)", systemImage: "server.rack")
                .font(.headline)
        }
        .padding()
        .accessibilityIdentifier("agentEditor.mcpsDisclosure")
    }

    @ViewBuilder
    private var permissionsSection: some View {
        DisclosureGroup(isExpanded: $permissionsExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Preset", selection: $selectedPermissionId) {
                    Text("None").tag(Optional<UUID>.none)
                    ForEach(allPermissions) { perm in
                        Text(perm.name).tag(Optional(perm.id))
                    }
                }
                .accessibilityIdentifier("agentEditor.permissionPresetPicker")

                if let permId = selectedPermissionId,
                   let perm = allPermissions.first(where: { $0.id == permId }) {
                    if !perm.allowRules.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Allow Rules")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(perm.allowRules, id: \.self) { rule in
                                Text(rule)
                                    .font(.system(.caption, design: .monospaced))
                                    .padding(.leading, 8)
                            }
                        }
                    }
                    if !perm.denyRules.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Deny Rules")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(perm.denyRules, id: \.self) { rule in
                                Text(rule)
                                    .font(.system(.caption, design: .monospaced))
                                    .padding(.leading, 8)
                            }
                        }
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            Label("Permissions", systemImage: "lock.shield")
                .font(.headline)
        }
        .padding()
        .accessibilityIdentifier("agentEditor.permissionsDisclosure")
    }

    // MARK: - Step 3: System Prompt

    @ViewBuilder
    private var systemPromptStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("System Prompt")
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                Text("\(systemPrompt.count) chars")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("agentEditor.systemPromptCharCount")
            }
            .padding(.horizontal)

            TextEditor(text: $systemPrompt)
                .font(.system(.body, design: .monospaced))
                .padding(4)
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.quaternary, lineWidth: 1)
                )
                .padding(.horizontal)
                .accessibilityIdentifier("agentEditor.systemPromptEditor")
        }
        .padding(.vertical)
    }

    // MARK: - Navigation

    @ViewBuilder
    private var navigationButtons: some View {
        HStack {
            if currentStep > 0 {
                Button("Back") {
                    currentStep -= 1
                }
                .accessibilityIdentifier("agentEditor.backButton")
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .accessibilityIdentifier("agentEditor.cancelButton")
            if currentStep < steps.count - 1 {
                Button("Next") {
                    currentStep += 1
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("agentEditor.nextButton")
            } else {
                Button("Save") {
                    saveAgent()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
                .accessibilityIdentifier("agentEditor.saveButton")
            }
        }
        .padding()
    }

    // MARK: - Save

    private func saveAgent() {
        let target: Agent
        if let existing = agent {
            target = existing
        } else {
            target = Agent(name: name)
            modelContext.insert(target)
        }

        target.name = name
        target.agentDescription = agentDescription
        target.icon = icon
        target.color = color
        target.model = model
        target.maxTurns = Int(maxTurns)
        target.maxBudget = Double(maxBudget)
        target.skillIds = Array(selectedSkillIds)
        target.extraMCPServerIds = Array(selectedMCPIds)
        target.permissionSetId = selectedPermissionId
        target.systemPrompt = systemPrompt
        target.defaultWorkingDirectory = workingDirectory.isEmpty ? nil : workingDirectory
        target.githubRepo = githubRepo.isEmpty ? nil : githubRepo
        target.githubDefaultBranch = githubBranch.isEmpty ? nil : githubBranch
        target.updatedAt = Date()

        switch instancePolicyType {
        case 1: target.instancePolicy = .singleton
        case 2: target.instancePolicy = .pool(max: Int(poolMax) ?? 3)
        default: target.instancePolicy = .spawn
        }

        try? modelContext.save()
        onSave(target)
        dismiss()
    }
}
