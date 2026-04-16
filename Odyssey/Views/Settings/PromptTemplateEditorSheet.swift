import SwiftUI

/// Modal sheet for creating or editing a single prompt template. Contents are
/// captured via `onSave` — the caller owns persistence (SwiftData insert/update
/// and write-back to disk).
struct PromptTemplateEditorSheet: View {
    enum Mode {
        case create(ownerLabel: String)
        case edit(PromptTemplate)
    }

    let mode: Mode
    let onSave: (_ name: String, _ prompt: String) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var prompt: String

    init(
        mode: Mode,
        onSave: @escaping (_ name: String, _ prompt: String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.mode = mode
        self.onSave = onSave
        self.onCancel = onCancel
        switch mode {
        case .create:
            _name = State(initialValue: "")
            _prompt = State(initialValue: "")
        case .edit(let template):
            _name = State(initialValue: template.name)
            _prompt = State(initialValue: template.prompt)
        }
    }

    private var title: String {
        switch mode {
        case .create(let label): "New template for \(label)"
        case .edit(let template): "Edit \(template.name)"
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                TextField("e.g. Review PR", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .xrayId("settings.templates.editor.nameField")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Prompt")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                TextEditor(text: $prompt)
                    .font(.system(.body, design: .default))
                    .padding(6)
                    .frame(minHeight: 180)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                    .xrayId("settings.templates.editor.promptEditor")

                Text("Tip: include phrasing like \u{201C}before starting, ask me for X\u{201D} to have the agent collect missing parameters.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .xrayId("settings.templates.editor.cancelButton")
                Button("Save Template") {
                    onSave(name.trimmingCharacters(in: .whitespaces),
                           prompt.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
                .xrayId("settings.templates.editor.saveButton")
            }
        }
        .padding(24)
        .frame(width: 540, height: 420)
        .xrayId("settings.templates.editor.root")
    }
}
