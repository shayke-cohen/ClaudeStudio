import SwiftUI

struct SlashCommandDropdown: View {
    let groupedSuggestions: [(group: SlashCommandGroup, commands: [SlashCommandInfo])]
    let selectedIndex: Int
    let onSelect: (SlashCommandInfo) -> Void
    let onDismiss: () -> Void

    // Flat list for index-based keyboard navigation
    private var flatCommands: [SlashCommandInfo] {
        groupedSuggestions.flatMap(\.commands)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(groupedSuggestions.enumerated()), id: \.offset) { gIdx, entry in
                if gIdx > 0 {
                    Divider().padding(.horizontal, 8)
                }
                groupHeader(entry.group)
                ForEach(entry.commands) { cmd in
                    commandRow(cmd)
                }
            }
            Divider()
            hintBar
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.separator, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 4)
        .frame(maxWidth: .infinity)
    }

    private func groupHeader(_ group: SlashCommandGroup) -> some View {
        Text(group.rawValue.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }

    private func commandRow(_ cmd: SlashCommandInfo) -> some View {
        let isSelected = flatCommands.firstIndex(where: { $0.id == cmd.id }) == selectedIndex
        return Button {
            onSelect(cmd)
        } label: {
            HStack(spacing: 8) {
                Text("/\(cmd.name)")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .frame(minWidth: 100, alignment: .leading)
                Text(cmd.description)
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
                    .lineLimit(1)
                Spacer()
                if cmd.hasSubPicker {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                        .foregroundStyle(isSelected ? .white.opacity(0.7) : .tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityIdentifier("slashDropdown.command.\(cmd.id)")
    }

    private var hintBar: some View {
        HStack(spacing: 12) {
            Label("navigate", systemImage: "arrow.up.arrow.down")
            Label("select", systemImage: "return")
            Label("dismiss", systemImage: "escape")
        }
        .font(.system(size: 10))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }
}

// MARK: - Sub-picker for commands that need a second step

struct SlashSubPickerView: View {
    let command: SlashCommandInfo
    let items: [SlashSubPickerItem]
    let selectedIndex: Int
    let onSelect: (SlashSubPickerItem) -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Back header
            Button(action: onBack) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text("/\(command.name)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.accent)
                    Text(subPickerTitle(for: command))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            Divider()
            ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                subPickerRow(item, isSelected: idx == selectedIndex)
            }
            Divider()
            HStack(spacing: 12) {
                Label("navigate", systemImage: "arrow.up.arrow.down")
                Label("select", systemImage: "return")
                Label("back", systemImage: "escape")
            }
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 4)
    }

    private func subPickerRow(_ item: SlashSubPickerItem, isSelected: Bool) -> some View {
        Button { onSelect(item) } label: {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isSelected ? .white : .primary)
                    if let detail = item.detail {
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                    }
                }
                Spacer()
                if item.isCurrent {
                    Text("current")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.green, in: Capsule())
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSelected ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("slashSubPicker.\(item.id)")
    }

    private func subPickerTitle(for cmd: SlashCommandInfo) -> String {
        switch cmd.id {
        case "model":    return "Choose model"
        case "effort":   return "Set effort level"
        case "mode":     return "Set agent mode"
        case "export":   return "Choose format"
        case "resume":   return "Choose session"
        case "branch":   return "Branch action"
        case "loop":     return "Set interval"
        default:         return "Choose option"
        }
    }
}

struct SlashSubPickerItem: Identifiable {
    let id: String
    let label: String
    let detail: String?
    let isCurrent: Bool

    init(id: String, label: String, detail: String? = nil, isCurrent: Bool = false) {
        self.id = id
        self.label = label
        self.detail = detail
        self.isCurrent = isCurrent
    }
}
