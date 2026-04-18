import SwiftUI

struct QuickActionEditSheet: View {
    enum Mode { case add, edit }

    let mode: Mode
    var onSave: (QuickActionConfig) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var prompt: String
    @State private var symbolName: String
    @State private var showSymbolPicker = false

    private let id: UUID

    init(mode: Mode, existing: QuickActionConfig? = nil, onSave: @escaping (QuickActionConfig) -> Void) {
        self.mode = mode
        self.onSave = onSave
        self.id = existing?.id ?? UUID()
        _name       = State(initialValue: existing?.name ?? "")
        _prompt     = State(initialValue: existing?.prompt ?? "")
        _symbolName = State(initialValue: existing?.symbolName ?? "star")
    }

    private var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !prompt.trimmingCharacters(in: .whitespaces).isEmpty }
    private var title: String { mode == .add ? "Add Chip" : "Edit Chip" }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)

            HStack(alignment: .top, spacing: 12) {
                Button {
                    showSymbolPicker = true
                } label: {
                    Image(systemName: symbolName)
                        .font(.system(size: 22))
                        .frame(width: 48, height: 48)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor.opacity(0.4), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Choose icon")
                .accessibilityIdentifier("chipEdit.iconButton")
                .popover(isPresented: $showSymbolPicker) {
                    SymbolPickerView(selectedSymbol: $symbolName)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Name").font(.caption).foregroundStyle(.secondary)
                    TextField("e.g. Fix It", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("chipEdit.nameField")
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Prompt").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $prompt)
                    .frame(minHeight: 80)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                    .accessibilityIdentifier("chipEdit.promptField")
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .accessibilityIdentifier("chipEdit.cancelButton")
                Spacer()
                Button(mode == .add ? "Add" : "Save") {
                    onSave(QuickActionConfig(id: id, name: name.trimmingCharacters(in: .whitespaces), prompt: prompt.trimmingCharacters(in: .whitespaces), symbolName: symbolName))
                    dismiss()
                }
                .disabled(!isValid)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("chipEdit.saveButton")
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
