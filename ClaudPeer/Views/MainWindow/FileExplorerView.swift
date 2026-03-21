import SwiftUI

struct FileExplorerView: View {
    let workingDirectory: String
    let refreshTrigger: Int

    @State private var selectedFile: FileNode?
    @State private var changesOnly = false
    @State private var showHidden = false
    @State private var localRefresh = 0

    private var rootURL: URL {
        URL(fileURLWithPath: workingDirectory)
    }

    private var abbreviatedPath: String {
        let home = NSHomeDirectory()
        if workingDirectory.hasPrefix(home) {
            return "~" + workingDirectory.dropFirst(home.count)
        }
        return workingDirectory
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if selectedFile != nil {
                contentView
            } else {
                treeView
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 6) {
            Text(abbreviatedPath)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
                .help(workingDirectory)
                .accessibilityIdentifier("inspector.fileTree.pathLabel")

            Spacer()

            Button {
                localRefresh += 1
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Refresh file tree")
            .accessibilityIdentifier("inspector.fileTree.refreshButton")
            .accessibilityLabel("Refresh file tree")

            Menu {
                Toggle("Show Hidden Files", isOn: $showHidden)
                    .accessibilityIdentifier("inspector.fileTree.showHiddenToggle")
                Toggle("Changes Only", isOn: $changesOnly)
                    .accessibilityIdentifier("inspector.fileTree.changesOnlyMenuToggle")
                Divider()
                Button("Reveal in Finder") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: workingDirectory)
                }
                .accessibilityIdentifier("inspector.fileTree.revealInFinderButton")
                Button("Open in Terminal") {
                    openInTerminal(workingDirectory)
                }
                .accessibilityIdentifier("inspector.fileTree.openInTerminalButton")
            } label: {
                Image(systemName: "gearshape")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 20)
            .help("File explorer settings")
            .accessibilityIdentifier("inspector.fileTree.settingsButton")
            .accessibilityLabel("File explorer settings")

            Button {
                changesOnly.toggle()
            } label: {
                Image(systemName: changesOnly ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .font(.caption)
                    .foregroundStyle(changesOnly ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)
            .help(changesOnly ? "Show all files" : "Show changes only")
            .accessibilityIdentifier("inspector.fileTree.changesOnlyToggle")
            .accessibilityLabel(changesOnly ? "Show all files" : "Show changes only")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: - Tree

    private var treeView: some View {
        FileTreeView(
            rootURL: rootURL,
            onSelectFile: { node in
                selectedFile = node
            },
            changesOnly: changesOnly,
            showHidden: showHidden,
            refreshTrigger: refreshTrigger + localRefresh
        )
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        if let file = selectedFile {
            FileContentView(
                node: file,
                rootURL: rootURL,
                onBack: { selectedFile = nil }
            )
        }
    }

    // MARK: - Helpers

    private func openInTerminal(_ path: String) {
        let script = "tell application \"Terminal\" to do script \"cd \(path.replacingOccurrences(of: "\"", with: "\\\""))\""
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }
}
