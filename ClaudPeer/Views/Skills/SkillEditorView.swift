import SwiftUI
import SwiftData

struct SkillEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \MCPServer.name) private var allMCPs: [MCPServer]

    let skill: Skill?
    let onSave: (Skill) -> Void

    @State private var name: String
    @State private var skillDescription: String
    @State private var category: String
    @State private var version: String
    @State private var triggersText: String
    @State private var content: String
    @State private var selectedMCPIds: Set<UUID>

    private static let categories = [
        "General",
        "Development",
        "Testing & QA",
        "DevOps & CI/CD",
        "Frontend",
        "Backend",
        "Mobile",
        "Security",
        "Data",
        "Project & Process",
        "Documentation",
        "ClaudPeer Collaboration",
        "Specialized",
    ]

    init(skill: Skill?, onSave: @escaping (Skill) -> Void) {
        self.skill = skill
        self.onSave = onSave
        _name = State(initialValue: skill?.name ?? "")
        _skillDescription = State(initialValue: skill?.skillDescription ?? "")
        _category = State(initialValue: skill?.category ?? "General")
        _version = State(initialValue: skill?.version ?? "1.0")
        _triggersText = State(initialValue: skill?.triggers.joined(separator: ", ") ?? "")
        _content = State(initialValue: skill?.content ?? "")
        _selectedMCPIds = State(initialValue: Set(skill?.mcpServerIds ?? []))
    }

    private var categoriesForPicker: [String] {
        var c = Self.categories
        if !c.contains(category) {
            c.append(category)
        }
        return c
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(skill == nil ? "Create Skill" : "Edit Skill")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Close")
            }
            .padding()

            Form {
                Section("Basic Info") {
                    TextField("Name", text: $name)
                    TextField("Description", text: $skillDescription, axis: .vertical)
                        .lineLimit(3...8)
                    Picker("Category", selection: $category) {
                        ForEach(categoriesForPicker, id: \.self) { c in
                            Text(c).tag(c)
                        }
                    }
                    TextField("Version", text: $version)
                }

                Section {
                    TextField("Triggers (comma-separated)", text: $triggersText)
                } header: {
                    Text("Triggers")
                } footer: {
                    Text("Separate multiple triggers with commas. They are used for matching and discovery.")
                        .font(.caption)
                }

                Section("Required MCPs") {
                    mcpPickerColumns
                        .frame(minHeight: 220)
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Content")
                                .font(.caption)
                                .fontWeight(.medium)
                            Spacer()
                            Text("\(content.count) chars")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        TextEditor(text: $content)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 160)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Save") {
                    saveSkill()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
    }

    @ViewBuilder
    private var mcpPickerColumns: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading) {
                Text("Selected (\(selectedMCPIds.count))")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal)
                List {
                    ForEach(allMCPs.filter { selectedMCPIds.contains($0.id) }) { mcp in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(mcp.name).font(.callout)
                                Text(mcp.serverDescription).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                selectedMCPIds.remove(mcp.id)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                            .help("Remove MCP server")
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)

            Divider()

            VStack(alignment: .leading) {
                Text("Available")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal)
                List {
                    ForEach(allMCPs.filter { !selectedMCPIds.contains($0.id) }) { mcp in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(mcp.name).font(.callout)
                                Text(mcp.serverDescription).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                selectedMCPIds.insert(mcp.id)
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(.green)
                            }
                            .buttonStyle(.borderless)
                            .help("Add MCP server")
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func saveSkill() {
        let parsedTriggers = triggersText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let target: Skill
        if let existing = skill {
            target = existing
        } else {
            let new = Skill(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                skillDescription: skillDescription,
                category: category,
                content: content
            )
            new.sourceKind = "custom"
            new.sourceValue = nil
            new.catalogId = nil
            modelContext.insert(new)
            target = new
        }

        target.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        target.skillDescription = skillDescription
        target.category = category
        target.version = version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "1.0" : version.trimmingCharacters(in: .whitespacesAndNewlines)
        target.triggers = parsedTriggers
        target.content = content
        target.mcpServerIds = Array(selectedMCPIds)
        target.updatedAt = Date()

        try? modelContext.save()
        onSave(target)
        dismiss()
    }
}
