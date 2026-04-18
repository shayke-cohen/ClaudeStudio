import SwiftUI
import SwiftData

// MARK: - Export Picker

struct SlashExportPickerSheet: View {
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader("Export Transcript")
            Divider()
            VStack(spacing: 8) {
                formatRow(id: "md",   label: "Markdown", detail: ".md — best for readability")
                formatRow(id: "html", label: "HTML",     detail: ".html — rich formatting")
                formatRow(id: "json", label: "JSON",     detail: ".json — raw data")
            }
            .padding()
        }
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func formatRow(id: String, label: String, detail: String) -> some View {
        Button { onSelect(id) } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.body.weight(.medium))
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("slashExport.\(id)")
    }
}

// MARK: - Model Picker

struct SlashModelPickerSheet: View {
    let currentModel: String
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    private let models: [(id: String, label: String, detail: String)] = [
        ("claude-opus-4-7",   "claude-opus-4-7",   "Most capable"),
        ("claude-sonnet-4-6", "claude-sonnet-4-6", "Fast · balanced"),
        ("claude-haiku-4-5",  "claude-haiku-4-5",  "Fastest"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader("Switch Model")
            Divider()
            VStack(spacing: 8) {
                ForEach(models, id: \.id) { m in
                    Button { onSelect(m.id) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.label).font(.system(.body, design: .monospaced).weight(.medium))
                                Text(m.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if currentModel.contains(m.id.split(separator: "-").dropFirst(2).joined(separator: "-")) {
                                Text("current")
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(.green, in: Capsule())
                                    .foregroundStyle(.white)
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("slashModel.\(m.id)")
                }
            }
            .padding()
        }
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Effort Picker

struct SlashEffortPickerSheet: View {
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    private let levels: [(id: String, label: String, detail: String)] = [
        ("low",    "low",    "Minimal thinking"),
        ("medium", "medium", "Balanced"),
        ("high",   "high",   "Thorough — recommended"),
        ("max",    "max",    "Maximum quality"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader("Set Effort Level")
            Divider()
            VStack(spacing: 8) {
                ForEach(levels, id: \.id) { l in
                    Button { onSelect(l.id) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(l.label).font(.body.weight(.medium))
                                Text(l.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("slashEffort.\(l.id)")
                }
            }
            .padding()
        }
        .frame(width: 300)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Mode Picker

struct SlashModePicker: View {
    let currentMode: SessionMode
    let onSelect: (SessionMode) -> Void
    @Environment(\.dismiss) private var dismiss

    private let modes: [(mode: SessionMode, label: String, detail: String)] = [
        (.interactive,  "interactive",  "Confirm before acting"),
        (.autonomous,   "autonomous",   "Act independently"),
        (.worker,       "worker",       "Headless task execution"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader("Set Agent Mode")
            Divider()
            VStack(spacing: 8) {
                ForEach(modes, id: \.mode) { m in
                    Button { onSelect(m.mode) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.label).font(.body.weight(.medium))
                                Text(m.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if currentMode == m.mode {
                                Text("current")
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(.green, in: Capsule())
                                    .foregroundStyle(.white)
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("slashMode.\(m.mode.rawValue)")
                }
            }
            .padding()
        }
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Branch Picker

struct SlashBranchPickerSheet: View {
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader("Git Branch")
            Divider()
            VStack(spacing: 8) {
                actionRow(id: "create", label: "Create branch", detail: "git checkout -b <name>")
                actionRow(id: "switch", label: "Switch branch",  detail: "git checkout <branch>")
                actionRow(id: "list",   label: "List branches",  detail: "git branch -a")
            }
            .padding()
        }
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func actionRow(id: String, label: String, detail: String) -> some View {
        Button { onSelect(id) } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.body.weight(.medium))
                    Text(detail).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("slashBranch.\(id)")
    }
}

// MARK: - Skills Sheet

struct SlashSkillsSheet: View {
    let session: Session?
    @Environment(AppState.self) var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var skills: [Skill]

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader("Skills")
            Divider()
            List(skills) { skill in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(skill.name).font(.body.weight(.medium))
                        if !skill.skillDescription.isEmpty {
                            Text(skill.skillDescription).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { skill.isEnabled },
                        set: { val in
                            skill.isEnabled = val
                            try? modelContext.save()
                        }
                    ))
                    .labelsHidden()
                    .accessibilityIdentifier("slashSkills.toggle.\(skill.id.uuidString)")
                }
            }
            .frame(minHeight: 200)
        }
        .frame(width: 380, height: 400)
    }
}

// MARK: - MCP Sheet

struct SlashMCPSheet: View {
    let session: Session?
    @Environment(AppState.self) var appState
    @Environment(\.dismiss) private var dismiss
    @Query private var mcpServers: [MCPServer]

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader("MCP Servers")
            Divider()
            if mcpServers.isEmpty {
                Text("No MCP servers configured.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(mcpServers) { server in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(server.name).font(.body.weight(.medium))
                            Text(server.transportCommand ?? server.transportUrl ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "circle.fill")
                            .foregroundStyle(server.isEnabled ? .green : .secondary)
                            .font(.caption)
                    }
                }
                .frame(minHeight: 200)
            }
        }
        .frame(width: 380, height: 360)
    }
}

// MARK: - Permissions Sheet

struct SlashPermissionsSheet: View {
    let session: Session?
    @Environment(\.dismiss) private var dismiss
    @Query private var permSets: [PermissionSet]

    private var activePermSet: PermissionSet? {
        guard let id = session?.agent?.permissionSetId else { return nil }
        return permSets.first { $0.id == id }
    }

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader("Active Permissions")
            Divider()
            if let perms = activePermSet {
                List {
                    if !perms.allowRules.isEmpty {
                        Section("Allow Rules") {
                            ForEach(perms.allowRules, id: \.self) { rule in
                                Text(rule).font(.system(.caption, design: .monospaced))
                            }
                        }
                    }
                    if !perms.denyRules.isEmpty {
                        Section("Deny Rules") {
                            ForEach(perms.denyRules, id: \.self) { rule in
                                Text(rule).font(.system(.caption, design: .monospaced))
                            }
                        }
                    }
                    if !perms.additionalDirectories.isEmpty {
                        Section("Additional Directories") {
                            ForEach(perms.additionalDirectories, id: \.self) { dir in
                                Text(dir).font(.system(.caption, design: .monospaced))
                            }
                        }
                    }
                }
                .frame(minHeight: 200)
            } else {
                Text("No permission rules for this agent.")
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .frame(width: 380, height: 360)
    }
}

// MARK: - Shared header helper

private func sheetHeader(_ title: String) -> some View {
    HStack {
        Text(title).font(.headline)
        Spacer()
    }
    .padding()
}
