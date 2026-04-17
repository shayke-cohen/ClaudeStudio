import SwiftUI

struct MemoryEditorSheet: View {
    let agent: Agent?
    @Environment(\.dismiss) private var dismiss

    @State private var content = ""
    @State private var isLoading = true
    @State private var saveError: String? = nil

    private var memoryFileURL: URL? {
        guard let slug = agent?.configSlug ?? agent?.name.lowercased().replacingOccurrences(of: " ", with: "-") else { return nil }
        let base = ConfigFileManager.configDirectory
        let dir = base.appendingPathComponent("agents/\(slug)", isDirectory: true)
        return dir.appendingPathComponent("memory.md")
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Agent Memory")
                        .font(.headline)
                    if let name = agent?.name {
                        Text(name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Done") { saveAndDismiss() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .accessibilityIdentifier("memoryEditor.doneButton")
            }
            .padding()

            Divider()

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TextEditor(text: $content)
                    .font(.system(size: 13, design: .monospaced))
                    .padding(8)
                    .accessibilityIdentifier("memoryEditor.textEditor")
            }

            if let err = saveError {
                Divider()
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.vertical, 6)
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .onAppear { loadFile() }
    }

    private func loadFile() {
        guard let url = memoryFileURL else {
            content = ""
            isLoading = false
            return
        }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }
        isLoading = false
    }

    private func saveAndDismiss() {
        guard let url = memoryFileURL else { dismiss(); return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
            dismiss()
        } catch {
            saveError = "Save failed: \(error.localizedDescription)"
        }
    }
}
