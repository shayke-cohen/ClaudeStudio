import SwiftUI

struct AgentQuestionBubble: View {
    let question: AppState.AgentQuestion
    let agentName: String
    var agentColor: Color?
    let onAnswer: (String, [String]?) -> Void

    @State private var freeTextInput = ""
    @State private var selectedOptions: Set<String> = []
    @State private var ratingValue: Int = 0
    @State private var sliderValue: Double = 0
    @State private var formValues: [String: String] = [:]
    @State private var formToggles: [String: Bool] = [:]

    private var tintColor: Color { agentColor ?? .purple }
    private var inputType: String { question.inputType ?? "options" }

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

            // Input area based on type
            switch inputType {
            case "rating":
                ratingInput
            case "slider":
                sliderInput
            case "toggle":
                toggleInput
            case "dropdown":
                dropdownInput
            case "form":
                formInput
            case "text":
                freeTextOnlyInput
            default:
                optionsInput
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

    // MARK: - Options Input (default)

    @ViewBuilder
    private var optionsInput: some View {
        if let options = question.options, !options.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                    optionButton(option: option, index: index)
                }
            }
        }

        if question.multiSelect, !selectedOptions.isEmpty {
            Button("Submit \(selectedOptions.count) selection\(selectedOptions.count == 1 ? "" : "s")") {
                let answer = selectedOptions.sorted().joined(separator: ", ")
                onAnswer(answer, Array(selectedOptions))
            }
            .buttonStyle(.borderedProminent)
            .tint(tintColor)
            .xrayId("chat.agentQuestion.submitSelections")
        }

        freeTextRow
    }

    // MARK: - Free Text Only

    @ViewBuilder
    private var freeTextOnlyInput: some View {
        freeTextRow
    }

    @ViewBuilder
    private var freeTextRow: some View {
        HStack(spacing: 8) {
            TextField(
                question.options != nil ? "Or type your own answer\u{2026}" : "Type your answer\u{2026}",
                text: $freeTextInput
            )
            .textFieldStyle(.roundedBorder)
            .onSubmit { submitFreeText() }
            .xrayId("chat.agentQuestion.textInput")

            Button("Send") { submitFreeText() }
                .buttonStyle(.borderedProminent)
                .tint(tintColor)
                .disabled(freeTextInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .xrayId("chat.agentQuestion.sendButton")
        }
    }

    // MARK: - Rating Input

    @ViewBuilder
    private var ratingInput: some View {
        let maxStars = question.inputConfig?.maxRating ?? 5
        let labels = question.inputConfig?.ratingLabels

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(1...maxStars, id: \.self) { star in
                    Button {
                        ratingValue = star
                    } label: {
                        Image(systemName: star <= ratingValue ? "star.fill" : "star")
                            .font(.title2)
                            .foregroundStyle(star <= ratingValue ? .yellow : .secondary.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .xrayId("chat.agentQuestion.star.\(star)")
                }
            }

            if let labels, ratingValue > 0, ratingValue <= labels.count {
                Text(labels[ratingValue - 1])
                    .font(.caption)
                    .foregroundStyle(tintColor)
            }

            if ratingValue > 0 {
                Button("Submit rating: \(ratingValue)/\(maxStars)") {
                    let label = (labels != nil && ratingValue <= labels!.count) ? labels![ratingValue - 1] : "\(ratingValue)"
                    onAnswer("\(ratingValue)", [label])
                }
                .buttonStyle(.borderedProminent)
                .tint(tintColor)
                .xrayId("chat.agentQuestion.submitRating")
            }
        }
    }

    // MARK: - Slider Input

    @ViewBuilder
    private var sliderInput: some View {
        let minVal = question.inputConfig?.min ?? 0
        let maxVal = question.inputConfig?.max ?? 100
        let stepVal = question.inputConfig?.step ?? 1
        let unit = question.inputConfig?.unit ?? ""

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(String(format: stepVal == 1 ? "%.0f" : "%.1f", sliderValue))
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(tintColor)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Slider(value: $sliderValue, in: minVal...maxVal, step: stepVal)
                .tint(tintColor)
                .xrayId("chat.agentQuestion.slider")

            HStack {
                Text(String(format: stepVal == 1 ? "%.0f" : "%.1f", minVal))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(String(format: stepVal == 1 ? "%.0f" : "%.1f", maxVal))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Button("Submit") {
                let formatted = stepVal == 1 ? String(format: "%.0f", sliderValue) : String(format: "%.1f", sliderValue)
                onAnswer("\(formatted)\(unit)", nil)
            }
            .buttonStyle(.borderedProminent)
            .tint(tintColor)
            .xrayId("chat.agentQuestion.submitSlider")
        }
        .onAppear { sliderValue = minVal }
    }

    // MARK: - Toggle Input

    @ViewBuilder
    private var toggleInput: some View {
        HStack(spacing: 12) {
            Button {
                onAnswer("Yes", ["yes"])
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Yes")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .xrayId("chat.agentQuestion.toggleYes")

            Button {
                onAnswer("No", ["no"])
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill")
                    Text("No")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red.opacity(0.8))
            .xrayId("chat.agentQuestion.toggleNo")
        }
    }

    // MARK: - Dropdown Input

    @ViewBuilder
    private var dropdownInput: some View {
        if let options = question.options, !options.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Picker("Select", selection: Binding(
                    get: { selectedOptions.first ?? "" },
                    set: { selectedOptions = [$0] }
                )) {
                    Text("Choose...").tag("")
                    ForEach(options) { option in
                        Text(option.label).tag(option.label)
                    }
                }
                .labelsHidden()
                .xrayId("chat.agentQuestion.dropdown")

                if let selected = selectedOptions.first, !selected.isEmpty {
                    Button("Submit") {
                        onAnswer(selected, [selected])
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(tintColor)
                    .xrayId("chat.agentQuestion.submitDropdown")
                }
            }
        }
        freeTextRow
    }

    // MARK: - Form Input

    @ViewBuilder
    private var formInput: some View {
        if let fields = question.inputConfig?.fields, !fields.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(fields) { field in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 2) {
                            Text(field.label)
                                .font(.caption)
                                .fontWeight(.medium)
                            if field.required == true {
                                Text("*")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }

                        switch field.type {
                        case "toggle":
                            Toggle("", isOn: Binding(
                                get: { formToggles[field.name] ?? false },
                                set: { formToggles[field.name] = $0 }
                            ))
                            .labelsHidden()
                            .xrayId("chat.agentQuestion.form.\(field.name)")
                        case "number":
                            TextField(field.placeholder ?? "", text: Binding(
                                get: { formValues[field.name] ?? "" },
                                set: { formValues[field.name] = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .xrayId("chat.agentQuestion.form.\(field.name)")
                        default:
                            TextField(field.placeholder ?? "", text: Binding(
                                get: { formValues[field.name] ?? "" },
                                set: { formValues[field.name] = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .xrayId("chat.agentQuestion.form.\(field.name)")
                        }
                    }
                }

                Button("Submit") {
                    submitForm()
                }
                .buttonStyle(.borderedProminent)
                .tint(tintColor)
                .disabled(!formIsValid)
                .xrayId("chat.agentQuestion.submitForm")
            }
        }
    }

    // MARK: - Option Button

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

    private var formIsValid: Bool {
        guard let fields = question.inputConfig?.fields else { return false }
        return fields.allSatisfy { field in
            if field.required != true { return true }
            if field.type == "toggle" { return true }
            let val = formValues[field.name] ?? ""
            return !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func submitForm() {
        guard let fields = question.inputConfig?.fields else { return }
        var result: [String: String] = [:]
        for field in fields {
            if field.type == "toggle" {
                result[field.name] = (formToggles[field.name] ?? false) ? "true" : "false"
            } else {
                result[field.name] = formValues[field.name] ?? ""
            }
        }
        if let data = try? JSONSerialization.data(withJSONObject: result),
           let json = String(data: data, encoding: .utf8) {
            onAnswer(json, nil)
        }
    }
}

// MARK: - Answered Question (read-only, persisted)

struct AnsweredQuestionBubble: View {
    let message: ConversationMessage
    var agentAppearance: AgentAppearance?

    private var agentName: String { message.toolName ?? "Agent" }
    private var questionText: String { message.text }
    private var answerText: String { message.toolInput ?? "" }
    private var tintColor: Color { agentAppearance?.color ?? .purple }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                Text(agentName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(tintColor)
                Text("asked you")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Question text
            Text(questionText)
                .font(.body)
                .textSelection(.enabled)

            // Answer
            HStack(spacing: 6) {
                Text("\u{25B8}")
                    .foregroundStyle(tintColor)
                Text(answerText)
                    .font(.callout)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tintColor.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(12)
        .background(tintColor.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(tintColor.opacity(0.2), lineWidth: 0.5)
        )
        .xrayId("chat.answeredQuestion.\(message.id.uuidString)")
    }
}
