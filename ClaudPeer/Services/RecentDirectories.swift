import Foundation

/// Manages a global list of recently-used working directories, persisted to
/// `~/.claudpeer/recent-directories.json` so all instances share the same history.
enum RecentDirectories {
    private static let maxCount = 10

    private static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claudpeer/recent-directories.json")
    }

    static func load() -> [String] {
        guard let data = try? Data(contentsOf: fileURL),
              let paths = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return paths.filter { FileManager.default.fileExists(atPath: $0) }
    }

    /// Adds `path` to the front of the list, deduplicating and capping at `maxCount`.
    static func add(_ path: String) {
        var dirs = load()
        dirs.removeAll { $0 == path }
        dirs.insert(path, at: 0)
        if dirs.count > maxCount {
            dirs = Array(dirs.prefix(maxCount))
        }
        save(dirs)
    }

    private static func save(_ dirs: [String]) {
        let parentDir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(dirs) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
