import SwiftUI

struct AgentQuestionBubble: View {
    let question: AppState.AgentQuestion
    let agentName: String
    var agentColor: Color?
    let onAnswer: (String, [String]?) -> Void

    @State private var freeTextInput = ""
    @State private var selectedOptions: Set<String> = []

    private var tintColor: Color { agentColor ?? .purple }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 4) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(tintColor)
                Text(agentName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("is asking you")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if question.isPrivate {
                    Label("Private", systemImage: "eye.slash")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }

            // Question text
            Text(question.question)
                .font(.body)
                .textSelection(.enabled)

            // Options (if provided)
            if let options = question.options, !options.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                        optionButton(option: option, index: index)
                    }
                }
            }

            // Multi-select submit button
            if question.multiSelect, !selectedOptions.isEmpty {
                Button("Submit \(selectedOptions.count) selection\(selectedOptions.count == 1 ? "" : "s")") {
                    let answer = selectedOptions.sorted().joined(separator: ", ")
                    onAnswer(answer, Array(selectedOptions))
                }
                .buttonStyle(.borderedProminent)
                .tint(tintColor)
                .xrayId("chat.agentQuestion.submitSelections")
            }

            // Free-text input (always available)
            HStack(spacing: 8) {
                TextField(
                    question.options != nil ? "Or type your own answer\u{2026}" : "Type your answer\u{2026}",
                    text: $freeTextInput
                )
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    submitFreeText()
                }
                .xrayId("chat.agentQuestion.textInput")

                Button("Send") {
                    submitFreeText()
                }
                .buttonStyle(.borderedProminent)
                .tint(tintColor)
                .disabled(freeTextInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .xrayId("chat.agentQuestion.sendButton")
            }
        }
        .padding(12)
        .background(tintColor.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(tintColor.opacity(0.3), lineWidth: 1)
        )
        .xrayId("chat.agentQuestion.\(question.id)")
    }

    @ViewBuilder
    private func optionButton(option: QuestionOption, index: Int) -> some View {
        Button {
            if question.multiSelect {
                toggleSelection(option.label)
            } else {
                onAnswer(option.label, [option.label])
            }
        } label: {
            HStack(spacing: 8) {
                if question.multiSelect {
                    Image(systemName: selectedOptions.contains(option.label) ? "checkmark.square.fill" : "square")
                        .foregroundStyle(selectedOptions.contains(option.label) ? tintColor : .secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
                        .font(.callout)
                        .fontWeight(.medium)
                    if let desc = option.description {
                        Text(desc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(tintColor.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        selectedOptions.contains(option.label) ? tintColor.opacity(0.5) : tintColor.opacity(0.15),
                        lineWidth: selectedOptions.contains(option.label) ? 1.5 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .xrayId("chat.agentQuestionOption.\(index)")
    }

    private func toggleSelection(_ label: String) {
        if selectedOptions.contains(label) {
            selectedOptions.remove(label)
        } else {
            selectedOptions.insert(label)
        }
    }

    private func submitFreeText() {
        let text = freeTextInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if question.multiSelect, !selectedOptions.isEmpty {
            onAnswer(text, Array(selectedOptions))
        } else {
            onAnswer(text, nil)
        }
    }
}
