import SwiftUI

@MainActor
struct QuickActionsSettingsView: View {
    @ObservedObject private var store = QuickActionStore.shared
    @State private var editingConfig: QuickActionConfig? = nil
    @State private var showAddSheet = false
    @State private var showResetConfirmation = false

    var body: some View {
        Form {
            Section {
                ForEach(store.configs) { config in
                    HStack(spacing: 10) {
                        Image(systemName: "line.3.horizontal")
                            .frame(width: 16)
                            .foregroundStyle(.tertiary)
                            .accessibilityLabel("Drag to reorder \(config.name)")
                            .accessibilityIdentifier("settings.quickActions.dragHandle.\(config.id.uuidString)")

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
                    .accessibilityIdentifier("settings.quickActions.row.\(config.id.uuidString)")
                    .draggable(config.id.uuidString)
                    .dropDestination(for: String.self) { items, _ in
                        MainActor.assumeIsolated {
                            guard let draggedIdString = items.first,
                                  let draggedId = UUID(uuidString: draggedIdString),
                                  draggedId != config.id,
                                  let fromIndex = store.configs.firstIndex(where: { $0.id == draggedId }),
                                  let toIndex = store.configs.firstIndex(where: { $0.id == config.id })
                            else { return false }
                            store.move(
                                fromOffsets: IndexSet(integer: fromIndex),
                                toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
                            )
                            return true
                        }
                    }
                }

                Button {
                    showAddSheet = true
                } label: {
                    Label("Add chip", systemImage: "plus.circle.fill")
                }
                .accessibilityIdentifier("settings.quickActions.addButton")
            } header: {
                HStack {
                    Text("Chips")
                    Spacer()
                    Button("Reset to Defaults") { showResetConfirmation = true }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .accessibilityIdentifier("settings.quickActions.resetButton")
                }
            } footer: {
                Text("Drag to reorder. Changes appear immediately in the chat bar.")
                    .foregroundStyle(.secondary)
            }

            Section("Ordering") {
                Toggle("Order by usage", isOn: Binding(
                    get: { store.usageOrderEnabled },
                    set: { store.setUsageOrderEnabled($0) }
                ))
                .help("Reorders chips by how often you use them after \(QuickActionConfig.usageThreshold) total uses.")
                .accessibilityIdentifier("settings.quickActions.usageOrderToggle")
            }
        }
        .formStyle(.grouped)
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
}
