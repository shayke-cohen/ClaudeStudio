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
        _selectedMCPIds = State(initialValue: Set(agent?.mcpServerIds ?? []))
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

    private let steps = ["Identity", "Skills", "MCPs", "Permissions", "System Prompt"]

    var body: some View {
        VStack(spacing: 0) {
            editorHeader
            Divider()
            stepIndicator
            Divider()

            Group {
                switch currentStep {
                case 0: identityStep
                case 1: skillsStep
                case 2: mcpsStep
                case 3: permissionsStep
                case 4: systemPromptStep
                default: EmptyView()
                }
            }
            .frame(maxHeight: .infinity)

            Divider()
            navigationButtons
        }
    }

    @ViewBuilder
    private var editorHeader: some View {
        HStack {
            Text(agent == nil ? "Create Agent" : "Edit Agent")
                .font(.title3)
                .fontWeight(.semibold)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding()
    }

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
                if index < steps.count - 1 {
                    Divider().frame(height: 20)
                }
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var identityStep: some View {
        Form {
            Section("Basic Info") {
                TextField("Name", text: $name)
                TextField("Description", text: $agentDescription, axis: .vertical)
                    .lineLimit(2...4)
                HStack {
                    TextField("Icon (SF Symbol)", text: $icon)
                    Image(systemName: icon)
                        .foregroundStyle(.blue)
                }
                Picker("Color", selection: $color) {
                    ForEach(["blue", "red", "green", "purple", "orange", "teal", "pink"], id: \.self) { c in
                        Text(c.capitalized).tag(c)
                    }
                }
                Picker("Model", selection: $model) {
                    Text("Sonnet").tag("sonnet")
                    Text("Opus").tag("opus")
                    Text("Haiku").tag("haiku")
                }
                TextField("Max Turns", text: $maxTurns)
                TextField("Max Budget ($)", text: $maxBudget)
            }

            Section("Instance Policy") {
                Picker("Policy", selection: $instancePolicyType) {
                    Text("Spawn (fresh per task)").tag(0)
                    Text("Singleton (one instance)").tag(1)
                    Text("Pool (multiple instances)").tag(2)
                }
                if instancePolicyType == 2 {
                    TextField("Max Instances", text: $poolMax)
                }
            }

            Section("Workspace") {
                TextField("Working Directory", text: $workingDirectory)
                TextField("GitHub Repo URL", text: $githubRepo)
                TextField("Branch", text: $githubBranch)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var skillsStep: some View {
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
                        }
                    }
                }
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
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var mcpsStep: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading) {
                Text("Selected (\(selectedMCPIds.count))")
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
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)

            Divider()

            VStack(alignment: .leading) {
                Text("Available")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal)
                List {
                    ForEach(allMCPs.filter { !selectedMCPIds.contains($0.id) }) { mcp in
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
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var permissionsStep: some View {
        Form {
            Section("Permission Preset") {
                Picker("Preset", selection: $selectedPermissionId) {
                    Text("None").tag(Optional<UUID>.none)
                    ForEach(allPermissions) { perm in
                        Text(perm.name).tag(Optional(perm.id))
                    }
                }
            }

            if let permId = selectedPermissionId,
               let perm = allPermissions.first(where: { $0.id == permId }) {
                Section("Allow Rules") {
                    ForEach(perm.allowRules, id: \.self) { rule in
                        Text(rule).font(.system(.caption, design: .monospaced))
                    }
                }
                Section("Deny Rules") {
                    ForEach(perm.denyRules, id: \.self) { rule in
                        Text(rule).font(.system(.caption, design: .monospaced))
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

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
        }
        .padding(.vertical)
    }

    @ViewBuilder
    private var navigationButtons: some View {
        HStack {
            if currentStep > 0 {
                Button("Back") {
                    currentStep -= 1
                }
            }
            Spacer()
            Button("Cancel") { dismiss() }
            if currentStep < steps.count - 1 {
                Button("Next") {
                    currentStep += 1
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Save") {
                    saveAgent()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
            }
        }
        .padding()
    }

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
        target.mcpServerIds = Array(selectedMCPIds)
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
