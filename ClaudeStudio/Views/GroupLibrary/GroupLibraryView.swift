import SwiftUI
import SwiftData

struct GroupLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @Environment(WindowState.self) private var windowState: WindowState
    @Query(sort: \AgentGroup.sortOrder) private var groups: [AgentGroup]
    @Query(sort: \Agent.name) private var agents: [Agent]
    @State private var searchText = ""
    @State private var filterOrigin: OriginFilter = .all
    @State private var editingGroup: AgentGroup?
    @State private var showingNewGroup = false

    enum OriginFilter: String, CaseIterable {
        case all = "All"
        case mine = "Mine"
        case builtin = "Built-in"
        case imported = "Imported"
    }

    private var filteredGroups: [AgentGroup] {
        groups.filter { group in
            let matchesSearch = searchText.isEmpty ||
                group.name.localizedCaseInsensitiveContains(searchText) ||
                group.groupDescription.localizedCaseInsensitiveContains(searchText)
            let matchesFilter: Bool = {
                switch filterOrigin {
                case .all: return true
                case .mine: return group.originKind == "local"
                case .builtin: return group.originKind == "builtin"
                case .imported: return group.originKind == "imported"
                }
            }()
            return matchesSearch && matchesFilter
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Agent Groups")
                    .font(.title2.bold())
                Spacer()
                Button {
                    showingNewGroup = true
                } label: {
                    Label("New Group", systemImage: "plus")
                }
                .xrayId("groupLibrary.newGroupButton")

                Button("Done") { dismiss() }
                    .keyboardShortcut(.escape)
                    .xrayId("groupLibrary.doneButton")
            }
            .padding()

            // Search + Filter
            HStack {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search groups...", text: $searchText)
                        .textFieldStyle(.plain)
                        .xrayId("groupLibrary.searchField")
                }
                .padding(6)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Picker("Filter", selection: $filterOrigin) {
                    ForEach(OriginFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)
                .xrayId("groupLibrary.filterPicker")
            }
            .padding(.horizontal)

            // Grid
            if filteredGroups.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "person.3")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("No groups found")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    if filterOrigin != .all || !searchText.isEmpty {
                        Text("Try changing the filter or search term")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Button("Create Group") { showingNewGroup = true }
                        .buttonStyle(.borderedProminent)
                        .xrayId("groupLibrary.createGroupButton")
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 220, maximum: 300))],
                        spacing: 12
                    ) {
                        ForEach(filteredGroups) { group in
                            GroupCardView(
                                group: group,
                                agents: agents,
                                onStart: {
                                    if let convoId = appState.startGroupChat(group: group, projectDirectory: windowState.projectDirectory, modelContext: modelContext) {
                                        windowState.selectedConversationId = convoId
                                    }
                                    dismiss()
                                },
                                onEdit: {
                                    editingGroup = group
                                }
                            )
                            .contextMenu {
                                Button("Edit") { editingGroup = group }
                                    .xrayId("groupLibrary.context.edit.\(group.id.uuidString)")
                                Button("Duplicate") { duplicateGroup(group) }
                                    .xrayId("groupLibrary.context.duplicate.\(group.id.uuidString)")
                                Divider()
                                Button("Delete", role: .destructive) { deleteGroup(group) }
                                    .xrayId("groupLibrary.context.delete.\(group.id.uuidString)")
                            }
                        }
                    }
                    .padding()
                }
                .xrayId("groupLibrary.list")
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .sheet(item: $editingGroup) { group in
            GroupEditorView(group: group)
        }
        .sheet(isPresented: $showingNewGroup) {
            GroupEditorView(group: nil)
        }
    }

    private func duplicateGroup(_ group: AgentGroup) {
        let copy = AgentGroup(
            name: "\(group.name) Copy",
            groupDescription: group.groupDescription,
            icon: group.icon,
            color: group.color,
            groupInstruction: group.groupInstruction,
            defaultMission: group.defaultMission,
            agentIds: group.agentIds,
            sortOrder: groups.count
        )
        modelContext.insert(copy)
        try? modelContext.save()
    }

    private func deleteGroup(_ group: AgentGroup) {
        modelContext.delete(group)
        try? modelContext.save()
    }
}
