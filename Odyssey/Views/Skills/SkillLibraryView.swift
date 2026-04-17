import SwiftUI
import SwiftData

struct SkillLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Skill.name) private var allSkills: [Skill]
    @Query(sort: \MCPServer.name) private var allMCPs: [MCPServer]

    @State private var searchText = ""
    @State private var showingNewSkill = false
    @State private var editingSkill: Skill?
    @State private var showCatalog = false
    @State private var skillToDelete: Skill?
    let showsDismissButton: Bool

    init(showsDismissButton: Bool = true) {
        self.showsDismissButton = showsDismissButton
    }

    private var filteredSkills: [Skill] {
        guard !searchText.isEmpty else { return allSkills }
        return allSkills.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.skillDescription.localizedCaseInsensitiveContains(searchText)
                || $0.category.localizedCaseInsensitiveContains(searchText)
        }
    }

    private let gridColumns = [
        GridItem(.adaptive(minimum: 220, maximum: 300), spacing: 16),
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if allSkills.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 16) {
                        ForEach(filteredSkills) { skill in
                            skillCard(skill)
                                .xrayId("skillLibrary.skillCard.\(skill.id.uuidString)")
                                .contextMenu {
                                    Button("Edit") {
                                        editingSkill = skill
                                    }
                                    .xrayId("skillLibrary.contextMenu.edit.\(skill.id.uuidString)")
                                    Button("Duplicate") {
                                        duplicateSkill(skill)
                                    }
                                    .xrayId("skillLibrary.contextMenu.duplicate.\(skill.id.uuidString)")
                                    Divider()
                                    Button("Delete", role: .destructive) {
                                        skillToDelete = skill
                                    }
                                    .xrayId("skillLibrary.contextMenu.delete.\(skill.id.uuidString)")
                                }
                        }
                    }
                    .padding()
                }
                .xrayId("skillLibrary.skillGrid")
            }
        }
        .sheet(item: $editingSkill) { skill in
            SkillCreationSheet(existingSkill: skill) { _ in
                editingSkill = nil
            }
        }
        .sheet(isPresented: $showingNewSkill) {
            SkillCreationSheet { _ in
                showingNewSkill = false
            }
        }
        .sheet(isPresented: $showCatalog) {
            CatalogBrowserView()
                .frame(minWidth: 520, minHeight: 440)
        }
        .confirmationDialog(
            "Delete this skill permanently?",
            isPresented: Binding(
                get: { skillToDelete != nil },
                set: { if !$0 { skillToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let skill = skillToDelete {
                    modelContext.delete(skill)
                    try? modelContext.save()
                }
                skillToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                skillToDelete = nil
            }
        } message: {
            if let skill = skillToDelete {
                Text(skill.name)
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack {
            Text("Installed Skills")
                .font(.title2)
                .fontWeight(.semibold)
            Spacer()
            TextField("Search...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .xrayId("skillLibrary.searchField")
            Button {
                showingNewSkill = true
            } label: {
                Label("New", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .xrayId("skillLibrary.newButton")
            Button {
                showCatalog = true
            } label: {
                Label("Catalog", systemImage: "square.grid.2x2")
            }
            .xrayId("skillLibrary.catalogButton")
            if showsDismissButton {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Close")
                .xrayId("skillLibrary.closeButton")
                .accessibilityLabel("Close")
            }
        }
        .padding()
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 24)
            Image(systemName: "book.closed")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No skills installed")
                .font(.title3)
                .foregroundStyle(.secondary)
            Button {
                showCatalog = true
            } label: {
                Text("Browse Catalog")
            }
            .buttonStyle(.borderedProminent)
            .xrayId("skillLibrary.emptyState.browseButton")
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func skillCard(_ skill: Skill) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "book.fill")
                    .font(.title2)
                    .foregroundStyle(Color.fromAgentColor("indigo"))
                    .frame(width: 36, height: 36)
                    .background(Color.fromAgentColor("indigo").opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(skill.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(sourceBadgeText(for: skill))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Text(skill.category)
                .font(.caption)
                .foregroundStyle(.tertiary)

            if !skill.skillDescription.isEmpty {
                Text(skill.skillDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            Divider()

            HStack(alignment: .top, spacing: 8) {
                Text("v\(skill.version)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("MCPs: \(mcpNamesLine(for: skill))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.quaternary, lineWidth: 1)
        )
    }

    private func sourceBadgeText(for skill: Skill) -> String {
        let isCatalog = skill.sourceKind == "catalog"
            || (skill.catalogId.map { !$0.isEmpty } ?? false)
        return isCatalog ? "Catalog" : "Custom"
    }

    private func mcpNamesLine(for skill: Skill) -> String {
        let names = skill.mcpServerIds.compactMap { id in
            allMCPs.first { $0.id == id }?.name
        }
        if names.isEmpty { return "—" }
        return names.joined(separator: ", ")
    }

    private func duplicateSkill(_ skill: Skill) {
        let copy = Skill(
            name: "\(skill.name) Copy",
            skillDescription: skill.skillDescription,
            category: skill.category,
            content: skill.content
        )
        copy.triggers = skill.triggers
        copy.version = skill.version
        copy.mcpServerIds = skill.mcpServerIds
        copy.sourceKind = "custom"
        copy.sourceValue = nil
        copy.catalogId = nil
        copy.updatedAt = Date()
        modelContext.insert(copy)
        try? modelContext.save()
    }
}
