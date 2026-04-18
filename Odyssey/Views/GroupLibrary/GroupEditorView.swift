import SwiftUI
import SwiftData

struct GroupEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Agent.name) private var allAgents: [Agent]
    @AppStorage(FeatureFlags.showAdvancedKey, store: AppSettings.store) private var masterFlag = false
    @AppStorage(FeatureFlags.workflowsKey, store: AppSettings.store) private var workflowsFlag = false

    let group: AgentGroup?

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
            HStack {
                Text(isEditing ? "Edit Group" : "New Group")
                    .font(.title2.bold())
                Spacer()
            }
            .padding()

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

            // Footer
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
                    .stableXrayId("groupEditor.cancelButton")
                Spacer()
                Button(isEditing ? "Save" : "Create") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedAgentIds.isEmpty)
                    .keyboardShortcut(.return)
                    .stableXrayId("groupEditor.saveButton")
            }
            .padding()
        }
        .frame(minWidth: 500, minHeight: 500)
        .onAppear { loadFromGroup() }
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
