import SwiftUI
import SwiftData

struct GroupEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Agent.name) private var allAgents: [Agent]

    let group: AgentGroup?

    @State private var name: String = ""
    @State private var icon: String = "👥"
    @State private var color: String = "blue"
    @State private var groupDescription: String = ""
    @State private var groupInstruction: String = ""
    @State private var defaultMission: String = ""
    @State private var selectedAgentIds: [UUID] = []

    private let availableColors = ["blue", "red", "green", "purple", "orange", "yellow", "pink", "teal", "indigo", "gray"]

    private var isEditing: Bool { group != nil }

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
                            .accessibilityIdentifier("groupEditor.iconField")
                        TextField("Group Name", text: $name)
                            .accessibilityIdentifier("groupEditor.nameField")
                    }

                    TextField("Description", text: $groupDescription)
                        .accessibilityIdentifier("groupEditor.descriptionField")

                    // Color swatches
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
                                .accessibilityIdentifier("groupEditor.color.\(colorName)")
                        }
                    }
                }

                // Group Instruction
                Section("Group Instruction") {
                    TextEditor(text: $groupInstruction)
                        .font(.body)
                        .frame(minHeight: 80)
                        .accessibilityIdentifier("groupEditor.instructionField")
                    Text("Injected as context at the start of each conversation.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                // Default Mission
                Section("Default Mission") {
                    TextField("Pre-filled mission (optional)", text: $defaultMission)
                        .accessibilityIdentifier("groupEditor.defaultMissionField")
                }

                // Agent Selection
                Section("Agents (\(selectedAgentIds.count))") {
                    ForEach(allAgents) { agent in
                        let isSelected = selectedAgentIds.contains(agent.id)
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
                            } else {
                                selectedAgentIds.append(agent.id)
                            }
                        }
                    }
                    .accessibilityIdentifier("groupEditor.agentPicker")
                }

                // Past Chats (read-only, only for existing groups)
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
                    .accessibilityIdentifier("groupEditor.cancelButton")
                Spacer()
                Button(isEditing ? "Save" : "Create") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedAgentIds.isEmpty)
                    .keyboardShortcut(.return)
                    .accessibilityIdentifier("groupEditor.saveButton")
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
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !selectedAgentIds.isEmpty else { return }

        if let group {
            group.name = trimmedName
            group.icon = icon
            group.color = color
            group.groupDescription = groupDescription
            group.groupInstruction = groupInstruction
            group.defaultMission = defaultMission.isEmpty ? nil : defaultMission
            group.agentIds = selectedAgentIds
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
            modelContext.insert(newGroup)
        }

        try? modelContext.save()
        dismiss()
    }
}
