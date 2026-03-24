import SwiftUI

struct WorkflowEditorView: View {
    let availableAgents: [Agent]
    @Binding var steps: [WorkflowStep]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                workflowStepRow(index: index, step: step)
            }
            .onMove { from, to in
                steps.move(fromOffsets: from, toOffset: to)
            }

            Button {
                steps.append(WorkflowStep(
                    agentId: availableAgents.first?.id ?? UUID(),
                    instruction: "",
                    autoAdvance: true
                ))
            } label: {
                Label("Add Step", systemImage: "plus")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
            .accessibilityIdentifier("workflowEditor.addStepButton")
        }
    }

    @ViewBuilder
    private func workflowStepRow(index: Int, step: WorkflowStep) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Step \(index + 1)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Button(role: .destructive) {
                    steps.removeAll { $0.id == step.id }
                } label: {
                    Image(systemName: "trash")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }

            HStack(spacing: 8) {
                Picker("Agent", selection: Binding(
                    get: { step.agentId },
                    set: { newId in
                        if let idx = steps.firstIndex(where: { $0.id == step.id }) {
                            steps[idx].agentId = newId
                        }
                    }
                )) {
                    ForEach(availableAgents) { agent in
                        HStack {
                            Image(systemName: agent.icon)
                                .foregroundStyle(Color.fromAgentColor(agent.color))
                            Text(agent.name)
                        }
                        .tag(agent.id)
                    }
                }
                .frame(maxWidth: 160)
                .accessibilityIdentifier("workflowEditor.step.\(index).agentPicker")

                TextField("Label", text: Binding(
                    get: { step.stepLabel ?? "" },
                    set: { val in
                        if let idx = steps.firstIndex(where: { $0.id == step.id }) {
                            steps[idx].stepLabel = val.isEmpty ? nil : val
                        }
                    }
                ))
                .frame(maxWidth: 120)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("workflowEditor.step.\(index).labelField")
            }

            TextField("Instruction for this step", text: Binding(
                get: { step.instruction },
                set: { val in
                    if let idx = steps.firstIndex(where: { $0.id == step.id }) {
                        steps[idx].instruction = val
                    }
                }
            ))
            .textFieldStyle(.roundedBorder)
            .accessibilityIdentifier("workflowEditor.step.\(index).instructionField")

            HStack(spacing: 12) {
                Toggle("Auto-advance", isOn: Binding(
                    get: { step.autoAdvance },
                    set: { val in
                        if let idx = steps.firstIndex(where: { $0.id == step.id }) {
                            steps[idx].autoAdvance = val
                        }
                    }
                ))
                .controlSize(.small)

                TextField("Condition (optional)", text: Binding(
                    get: { step.condition ?? "" },
                    set: { val in
                        if let idx = steps.firstIndex(where: { $0.id == step.id }) {
                            steps[idx].condition = val.isEmpty ? nil : val
                        }
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)
                .accessibilityIdentifier("workflowEditor.step.\(index).conditionField")
            }

            Divider()
        }
        .padding(.vertical, 2)
    }
}
