import SwiftUI
import SwiftData

struct AutonomousMissionSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState: WindowState

    let group: AgentGroup

    @State private var mission: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(.orange)
                Text("Autonomous Mission")
                    .font(.title2.bold())
                Spacer()
            }
            .padding()

            Form {
                Section("Group") {
                    HStack {
                        Text(group.icon)
                        Text(group.name)
                            .font(.headline)
                        Spacer()
                        Text("\(group.agentIds.count) agents")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let coordId = group.coordinatorAgentId {
                        let agents = (try? modelContext.fetch(FetchDescriptor<Agent>())) ?? []
                        if let coord = agents.first(where: { $0.id == coordId }) {
                            HStack {
                                Image(systemName: coord.icon)
                                    .foregroundStyle(Color.fromAgentColor(coord.color))
                                Text("Coordinator: \(coord.name)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Mission") {
                    TextEditor(text: $mission)
                        .font(.body)
                        .frame(minHeight: 120)
                        .stableXrayId("autonomousMission.missionField")
                    Text("Describe what the team should accomplish. The coordinator will break it down and delegate tasks.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
                    .stableXrayId("autonomousMission.cancelButton")
                Spacer()
                Button {
                    let trimmedMission = mission.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let convoId = appState.startAutonomousGroupChat(
                        group: group,
                        mission: trimmedMission,
                        projectDirectory: windowState.projectDirectory,
                        projectId: windowState.selectedProjectId,
                        modelContext: modelContext
                    ) {
                        windowState.selectedConversationId = convoId
                        windowState.autoSendText = trimmedMission
                    }
                    dismiss()
                } label: {
                    Label("Launch", systemImage: "bolt.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(mission.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return)
                .stableXrayId("autonomousMission.launchButton")
            }
            .padding()
        }
        .frame(minWidth: 450, minHeight: 350)
        .onAppear {
            mission = group.defaultMission ?? ""
        }
    }
}
