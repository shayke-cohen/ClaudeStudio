import SwiftUI

struct FileTreeView: View {
    let rootURL: URL
    let onSelectFile: (FileNode) -> Void
    let changesOnly: Bool
    let showHidden: Bool
    let refreshTrigger: Int

    @State private var rootNodes: [FileNode] = []
    @State private var gitStatusMap: [String: GitFileStatus] = [:]
    @State private var isGitRepo = false
    @State private var isLoading = false

    var body: some View {
        Group {
            if isLoading && rootNodes.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("inspector.fileTree.loading")
            } else {
                List {
                    ForEach(filteredNodes) { node in
                        FileTreeRow(
                            node: node,
                            showHidden: showHidden,
                            changesOnly: changesOnly,
                            gitStatusMap: gitStatusMap,
                            rootPath: rootURL.path,
                            onSelectFile: onSelectFile
                        )
                    }
                }
                .listStyle(.sidebar)
                .accessibilityIdentifier("inspector.fileTree.list")
            }
        }
        .task { await loadTree() }
        .onChange(of: refreshTrigger) { _, _ in Task { await loadTree() } }
        .onChange(of: showHidden) { _, _ in Task { await loadTree() } }
    }

    private var filteredNodes: [FileNode] {
        guard changesOnly else { return rootNodes }
        return rootNodes.filter { $0.isDirectory ? $0.hasChanges : $0.gitStatus != nil }
    }

    private func loadTree() async {
        isLoading = true
        let url = rootURL

        let (isGit, statusMap) = await Task.detached {
            let isGit = GitService.isGitRepo(at: url)
            let statusMap = isGit ? GitService.status(in: url) : [String: GitFileStatus]()
            return (isGit, statusMap)
        }.value

        rootNodes = FileSystemService.listDirectory(at: rootURL, showHidden: showHidden)
        isGitRepo = isGit
        gitStatusMap = statusMap

        if isGit {
            for node in rootNodes {
                node.applyGitStatus(statusMap, rootPath: rootURL.path)
            }
        }
        isLoading = false
    }
}

// MARK: - Tree Row

private struct FileTreeRow: View {
    @ObservedObject var node: FileNode
    let showHidden: Bool
    let changesOnly: Bool
    let gitStatusMap: [String: GitFileStatus]
    let rootPath: String
    let onSelectFile: (FileNode) -> Void

    var body: some View {
        if node.isDirectory {
            directoryRow
        } else {
            fileRow
        }
    }

    @ViewBuilder
    private var directoryRow: some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { node.isExpanded },
                set: { expanded in
                    node.isExpanded = expanded
                    if expanded {
                        node.loadChildren(showHidden: showHidden)
                        node.children?.forEach { $0.applyGitStatus(gitStatusMap, rootPath: rootPath) }
                    }
                }
            )
        ) {
            if let children = node.children {
                let visible = changesOnly
                    ? children.filter { $0.isDirectory ? $0.hasChanges : $0.gitStatus != nil }
                    : children
                ForEach(visible) { child in
                    FileTreeRow(
                        node: child,
                        showHidden: showHidden,
                        changesOnly: changesOnly,
                        gitStatusMap: gitStatusMap,
                        rootPath: rootPath,
                        onSelectFile: onSelectFile
                    )
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: node.isExpanded ? "folder.fill" : "folder")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .frame(width: 16)
                Text(node.name)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if node.hasChanges {
                    Circle()
                        .fill(Color.secondary.opacity(0.4))
                        .frame(width: 6, height: 6)
                }
            }
        }
        .accessibilityIdentifier("inspector.fileTree.directoryRow.\(node.name)")
    }

    @ViewBuilder
    private var fileRow: some View {
        Button {
            onSelectFile(node)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: FileSystemService.fileIcon(for: node.fileExtension))
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .frame(width: 16)
                Text(node.name)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if let status = node.gitStatus {
                    gitStatusBadge(status)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("inspector.fileTree.fileRow.\(node.name)")
    }

    @ViewBuilder
    private func gitStatusBadge(_ status: GitFileStatus) -> some View {
        Circle()
            .fill(colorForStatus(status))
            .frame(width: 7, height: 7)
            .help(status.label)
    }

    private func colorForStatus(_ status: GitFileStatus) -> Color {
        switch status {
        case .modified:  return .orange
        case .added:     return .green
        case .deleted:   return .red
        case .renamed:   return .blue
        case .untracked: return .gray
        case .copied:    return .teal
        }
    }
}
