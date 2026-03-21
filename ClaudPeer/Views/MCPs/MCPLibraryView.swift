import SwiftUI
import SwiftData

struct MCPLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \MCPServer.name) private var allMCPs: [MCPServer]
    @Query(sort: \Skill.name) private var allSkills: [Skill]

    @State private var searchText = ""
    @State private var showingNewMCP = false
    @State private var editingMCP: MCPServer?
    @State private var showCatalog = false
    @State private var mcpPendingDelete: MCPServer?
    @State private var showDeleteConfirmation = false

    private var filteredMCPs: [MCPServer] {
        allMCPs.filter { mcp in
            searchText.isEmpty
                || mcp.name.localizedCaseInsensitiveContains(searchText)
                || mcp.serverDescription.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if filteredMCPs.isEmpty {
                ContentUnavailableView(
                    "No MCP Servers",
                    systemImage: "server.rack",
                    description: Text(searchText.isEmpty ? "Add a server or install from the catalog." : "No matches for your search.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredMCPs) { mcp in
                    mcpRow(mcp)
                        .contextMenu {
                            Button("Edit") { editingMCP = mcp }
                            Button("Duplicate") { duplicateMCP(mcp) }
                            Divider()
                            Button("Delete", role: .destructive) {
                                if skillsUsing(mcp).isEmpty {
                                    deleteMCP(mcp)
                                } else {
                                    mcpPendingDelete = mcp
                                    showDeleteConfirmation = true
                                }
                            }
                        }
                }
                .listStyle(.inset)
            }
        }
        .sheet(item: $editingMCP) { mcp in
            MCPEditorView(mcp: mcp) { _ in
                editingMCP = nil
            }
            .frame(minWidth: 520, minHeight: 480)
        }
        .sheet(isPresented: $showingNewMCP) {
            MCPEditorView(mcp: nil) { _ in
                showingNewMCP = false
            }
            .frame(minWidth: 520, minHeight: 480)
        }
        .sheet(isPresented: $showCatalog) {
            MCPCatalogSheet()
                .frame(minWidth: 480, minHeight: 400)
        }
        .confirmationDialog(
            "Delete MCP server?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let m = mcpPendingDelete {
                    deleteMCP(m)
                }
                mcpPendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                mcpPendingDelete = nil
            }
        } message: {
            if let m = mcpPendingDelete {
                let names = skillsUsing(m).map(\.name).joined(separator: ", ")
                Text("Skills still reference this server: \(names)")
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Installed MCPs")
                .font(.title2)
                .fontWeight(.semibold)
            Spacer()
            TextField("Search...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
            Button {
                showingNewMCP = true
            } label: {
                Label("New", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            Button {
                showCatalog = true
            } label: {
                Label("Catalog", systemImage: "square.grid.2x2")
            }
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
    }

    @ViewBuilder
    private func mcpRow(_ mcp: MCPServer) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "server.rack")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(mcp.name)
                        .font(.headline)
                    if mcp.catalogId != nil {
                        Text("Catalog")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary.opacity(0.6))
                            .clipShape(Capsule())
                    }
                }
                if !mcp.serverDescription.isEmpty {
                    Text(mcp.serverDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                let users = skillsUsing(mcp).map(\.name)
                if users.isEmpty {
                    Text("Used by: —")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    Text("Used by: \(users.joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                Text(mcp.transportKind == "stdio" ? "stdio" : "http")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary.opacity(0.5))
                    .clipShape(Capsule())
                statusDot(for: mcp.status)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func statusDot(for status: MCPStatus) -> some View {
        let color: Color = switch status {
        case .connected: .green
        case .available: .gray
        case .error: .red
        }
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
            .accessibilityLabel(String(describing: status))
    }

    private func skillsUsing(_ mcp: MCPServer) -> [Skill] {
        allSkills.filter { $0.mcpServerIds.contains(mcp.id) }
    }

    private func duplicateMCP(_ mcp: MCPServer) {
        let copy = MCPServer(
            name: "\(mcp.name) Copy",
            serverDescription: mcp.serverDescription,
            transport: mcp.transport
        )
        copy.catalogId = nil
        copy.toolSchemas = mcp.toolSchemas
        copy.resourceSchemas = mcp.resourceSchemas
        copy.status = .available
        modelContext.insert(copy)
        try? modelContext.save()
    }

    private func deleteMCP(_ mcp: MCPServer) {
        modelContext.delete(mcp)
        try? modelContext.save()
    }
}

private struct MCPCatalogSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""

    private var entries: [CatalogMCP] {
        let all = CatalogService.shared.allMCPs()
        guard !searchText.isEmpty else { return all }
        return all.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.description.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List(entries) { entry in
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.name)
                            .font(.headline)
                        Text(entry.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(entry.category)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 8)
                    Button("Install") {
                        CatalogService.shared.installMCP(entry.catalogId, into: modelContext)
                        try? modelContext.save()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 2)
                .contextMenu {
                    Button("Install") {
                        CatalogService.shared.installMCP(entry.catalogId, into: modelContext)
                        try? modelContext.save()
                    }
                }
            }
            .navigationTitle("MCP Catalog")
            .searchable(text: $searchText, prompt: "Search catalog")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
