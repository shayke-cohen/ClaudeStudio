import SwiftUI
import SwiftData

struct AutoAssembleSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @Query(sort: \Agent.name) private var agents: [Agent]

    @State private var taskDescription = ""
    @State private var recommendation: GroupAssembler.AssemblyRecommendation?
    @State private var selectedAgentIds: Set<UUID> = []
    @State private var groupName = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "wand.and.stars")
                    .foregroundStyle(.purple)
                Text("Auto-Assemble Team")
                    .font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.escape)
            }
            .padding()

            if recommendation == nil {
                // Step 1: Task input
                Form {
                    Section("What do you need to accomplish?") {
                        TextEditor(text: $taskDescription)
                            .font(.body)
                            .frame(minHeight: 100)
                            .accessibilityIdentifier("autoAssemble.taskField")
                        Text("Describe the task and the system will recommend the best team.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .formStyle(.grouped)

                HStack {
                    Spacer()
                    Button {
                        let result = GroupAssembler.assembleGroup(task: taskDescription, availableAgents: agents)
                        recommendation = result
                        selectedAgentIds = Set(result.agentIds)
                        groupName = result.suggestedName
                    } label: {
                        Label("Assemble", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .disabled(taskDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("autoAssemble.assembleButton")
                }
                .padding()
            } else if let rec = recommendation {
                // Step 2: Recommendation
                Form {
                    Section("Recommended Team") {
                        TextField("Group Name", text: $groupName)
                            .font(.headline)
                            .accessibilityIdentifier("autoAssemble.nameField")
                    }

                    Section("Agents") {
                        ForEach(agents) { agent in
                            let isRecommended = rec.agentIds.contains(agent.id)
                            let isSelected = selectedAgentIds.contains(agent.id)
                            HStack {
                                Image(systemName: agent.icon)
                                    .foregroundStyle(Color.fromAgentColor(agent.color))
                                    .frame(width: 24)
                                Text(agent.name)
                                if isRecommended {
                                    Text("recommended")
                                        .font(.caption2)
                                        .foregroundStyle(.purple)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(.purple.opacity(0.1))
                                        .clipShape(Capsule())
                                }
                                Spacer()
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isSelected ? .blue : .secondary)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if isSelected { selectedAgentIds.remove(agent.id) }
                                else { selectedAgentIds.insert(agent.id) }
                            }
                        }
                    }

                    Section("Reasoning") {
                        Text(rec.reasoning)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .formStyle(.grouped)

                HStack {
                    Button("Back") { recommendation = nil }
                    Spacer()
                    Button {
                        createAndStart(rec)
                    } label: {
                        Label("Create & Start Chat", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedAgentIds.isEmpty)
                    .accessibilityIdentifier("autoAssemble.createButton")
                }
                .padding()
            }
        }
        .frame(minWidth: 500, minHeight: 450)
    }

    private func createAndStart(_ rec: GroupAssembler.AssemblyRecommendation) {
        let group = AgentGroup(
            name: groupName.isEmpty ? rec.suggestedName : groupName,
            groupDescription: "Auto-assembled for: \(taskDescription.prefix(100))",
            icon: "🤖",
            color: "purple",
            groupInstruction: rec.suggestedInstruction,
            defaultMission: taskDescription,
            agentIds: Array(selectedAgentIds)
        )
        modelContext.insert(group)
        try? modelContext.save()
        appState.startGroupChat(group: group, modelContext: modelContext)
        dismiss()
    }
}
