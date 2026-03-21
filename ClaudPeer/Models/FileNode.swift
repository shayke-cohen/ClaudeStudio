import Foundation

@MainActor
final class FileNode: Identifiable, ObservableObject {
    let id: String
    let name: String
    let url: URL
    let isDirectory: Bool
    let size: Int64
    let modifiedDate: Date?
    @Published var gitStatus: GitFileStatus?

    @Published var children: [FileNode]?
    @Published var isExpanded: Bool = false

    var hasChanges: Bool {
        if gitStatus != nil { return true }
        return children?.contains(where: { $0.hasChanges }) ?? false
    }

    var fileExtension: String {
        url.pathExtension
    }

    var relativePath: String {
        url.lastPathComponent
    }

    nonisolated init(
        name: String,
        url: URL,
        isDirectory: Bool,
        size: Int64 = 0,
        modifiedDate: Date? = nil
    ) {
        self.id = url.path
        self.name = name
        self.url = url
        self.isDirectory = isDirectory
        self.size = size
        self.modifiedDate = modifiedDate
    }

    func loadChildren(showHidden: Bool = false) {
        guard isDirectory, children == nil else { return }
        children = FileSystemService.listDirectory(at: url, showHidden: showHidden)
    }

    func reloadChildren(showHidden: Bool = false) {
        guard isDirectory else { return }
        children = FileSystemService.listDirectory(at: url, showHidden: showHidden)
    }

    func applyGitStatus(_ statusMap: [String: GitFileStatus], rootPath: String) {
        let myRelative = String(url.path.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        if !isDirectory {
            gitStatus = statusMap[myRelative]
        }

        children?.forEach { child in
            child.applyGitStatus(statusMap, rootPath: rootPath)
        }
    }
}
