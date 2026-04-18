import SwiftUI

@MainActor
struct QuickActionsSettingsView: View {
    @ObservedObject private var store = QuickActionStore.shared
    @State private var editingConfig: QuickActionConfig? = nil
    @State private var showAddSheet = false
    @State private var showResetConfirmation = false
    @State private var draggingId: UUID? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                chipsSection
                orderingSection
            }
            .padding(20)
        }
        .sheet(item: $editingConfig) { config in
            QuickActionEditSheet(mode: .edit, existing: config) { updated in
                store.update(updated)
            }
        }
        .sheet(isPresented: $showAddSheet) {
            QuickActionEditSheet(mode: .add) { newConfig in
                store.add(newConfig)
            }
        }
        .confirmationDialog("Reset all chips to defaults?", isPresented: $showResetConfirmation, titleVisibility: .visible) {
            Button("Reset to Defaults", role: .destructive) { store.resetToDefaults() }
            Button("Cancel", role: .cancel) {}
        }
        .navigationTitle("Quick Actions")
    }

    // MARK: - Sections

    private var chipsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Chips")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reset to Defaults") { showResetConfirmation = true }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .accessibilityIdentifier("settings.quickActions.resetButton")
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(store.configs) { config in
                    rowView(config: config)
                    if store.configs.last?.id != config.id {
                        Divider().padding(.leading, 46)
                    }
                }

                Divider().padding(.leading, 46)

                Button {
                    showAddSheet = true
                } label: {
                    Label("Add chip", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .accessibilityIdentifier("settings.quickActions.addButton")
            }
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Text("Drag the handle to reorder. Changes appear immediately in the chat bar.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    private var orderingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ordering")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            Toggle("Order by usage", isOn: Binding(
                get: { store.usageOrderEnabled },
                set: { store.setUsageOrderEnabled($0) }
            ))
            .toggleStyle(.switch)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .help("Reorders chips by how often you use them after \(QuickActionConfig.usageThreshold) total uses.")
            .accessibilityIdentifier("settings.quickActions.usageOrderToggle")
        }
    }

    // MARK: - Row

    private func rowView(config: QuickActionConfig) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .frame(width: 16)
                .foregroundStyle(.tertiary)
                .accessibilityLabel("Drag to reorder \(config.name)")
                .accessibilityIdentifier("settings.quickActions.dragHandle.\(config.id.uuidString)")
                .gesture(
                    DragGesture(minimumDistance: 5, coordinateSpace: .global)
                        .onChanged { _ in
                            if draggingId == nil { draggingId = config.id }
                        }
                        .onEnded { value in
                            defer {
                                draggingId = nil
                            }
                            guard draggingId == config.id,
                                  let fromIndex = store.configs.firstIndex(where: { $0.id == config.id })
                            else { return }
                            let rowHeight: CGFloat = 44
                            let delta = Int((value.translation.height / rowHeight).rounded())
                            let toIndex = max(0, min(store.configs.count - 1, fromIndex + delta))
                            guard fromIndex != toIndex else { return }
                            store.move(
                                fromOffsets: IndexSet(integer: fromIndex),
                                toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
                            )
                        }
                )

            Image(systemName: config.symbolName)
                .frame(width: 20)
                .foregroundStyle(.secondary)

            Text(config.name)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("Edit") { editingConfig = config }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .accessibilityIdentifier("settings.quickActions.editButton.\(config.id.uuidString)")

            Button {
                store.delete(id: config.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete \(config.name)")
            .accessibilityIdentifier("settings.quickActions.deleteButton.\(config.id.uuidString)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .opacity(draggingId == config.id ? 0.5 : 1.0)
        .accessibilityIdentifier("settings.quickActions.row.\(config.id.uuidString)")
    }
}
