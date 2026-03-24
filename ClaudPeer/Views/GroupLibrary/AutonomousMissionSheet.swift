import SwiftUI
import SwiftData

struct AutonomousMissionSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

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
                        .accessibilityIdentifier("autonomousMission.missionField")
                    Text("Describe what the team should accomplish. The coordinator will break it down and delegate tasks.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
                    .accessibilityIdentifier("autonomousMission.cancelButton")
                Spacer()
                Button {
                    appState.startAutonomousGroupChat(group: group, mission: mission, modelContext: modelContext)
                    dismiss()
                } label: {
                    Label("Launch", systemImage: "bolt.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(mission.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return)
                .accessibilityIdentifier("autonomousMission.launchButton")
            }
            .padding()
        }
        .frame(minWidth: 450, minHeight: 350)
        .onAppear {
            mission = group.defaultMission ?? ""
        }
    }
}
