import SwiftUI

/// A horizontal chip row that surfaces a small list of prompt templates above
/// the mission field in chat-start sheets. Clicking a chip replaces the
/// mission text via the supplied binding. If `templates` is empty the row
/// renders nothing, so callers can place it unconditionally.
struct TemplatePickerRow: View {
    let templates: [PromptTemplate]
    @Binding var mission: String
    let ownerLabel: String
    let onManage: (() -> Void)?

    private let visibleChipLimit = 3

    var body: some View {
        if templates.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Templates")
                        .font(.subheadline.weight(.semibold))
                    Text(ownerLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let onManage {
                        Button("Manage\u{2026}", action: onManage)
                            .buttonStyle(.borderless)
                            .font(.caption)
                            .xrayId("newSession.templatePicker.manageLink")
                            .accessibilityLabel("Manage templates")
                    }
                }

                HStack(spacing: 8) {
                    ForEach(sortedTemplates.prefix(visibleChipLimit)) { template in
                        chip(for: template)
                    }
                    if sortedTemplates.count > visibleChipLimit {
                        overflowMenu
                    }
                }
            }
            .xrayId("newSession.templatePicker.row")
        }
    }

    private var sortedTemplates: [PromptTemplate] {
        templates.sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            return lhs.name < rhs.name
        }
    }

    private func chip(for template: PromptTemplate) -> some View {
        Button {
            mission = template.prompt
        } label: {
            Text(template.name)
                .font(.callout)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.12), in: Capsule())
                .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .help(template.prompt)
        .xrayId("newSession.templatePicker.chip.\(template.id.uuidString)")
        .accessibilityLabel(template.name)
    }

    private var overflowMenu: some View {
        Menu {
            ForEach(sortedTemplates.dropFirst(visibleChipLimit)) { template in
                Button(template.name) { mission = template.prompt }
            }
        } label: {
            Label("More", systemImage: "ellipsis")
                .labelStyle(.titleAndIcon)
                .font(.callout)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.12), in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .xrayId("newSession.templatePicker.moreMenu")
    }
}
