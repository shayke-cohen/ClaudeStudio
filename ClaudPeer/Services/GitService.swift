import Foundation

enum GitFileStatus: String, Sendable {
    case modified = "M"
    case added = "A"
    case deleted = "D"
    case renamed = "R"
    case untracked = "?"
    case copied = "C"

    var label: String {
        switch self {
        case .modified:  return "Modified"
        case .added:     return "Added"
        case .deleted:   return "Deleted"
        case .renamed:   return "Renamed"
        case .untracked: return "Untracked"
        case .copied:    return "Copied"
        }
    }
}

enum GitService {

    static func isGitRepo(at directory: URL) -> Bool {
        let gitDir = directory.appendingPathComponent(".git")
        // .git can be a directory (normal repo) or a file (worktree with gitdir: pointer)
        return FileManager.default.fileExists(atPath: gitDir.path)
    }

    static func status(in directory: URL) -> [String: GitFileStatus] {
        guard let output = runGit(["status", "--porcelain", "-u"], in: directory) else {
            return [:]
        }

        var result: [String: GitFileStatus] = [:]
        for line in output.components(separatedBy: "\n") where line.count >= 4 {
            let indexStatus = line[line.index(line.startIndex, offsetBy: 0)]
            let workTreeStatus = line[line.index(line.startIndex, offsetBy: 1)]
            let path = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)

            if path.isEmpty { continue }

            let cleanPath = path.hasPrefix("\"") ? unquoteGitPath(path) : path

            if cleanPath.contains(" -> ") {
                let parts = cleanPath.components(separatedBy: " -> ")
                if parts.count == 2 {
                    result[parts[1]] = .renamed
                }
                continue
            }

            let status: GitFileStatus
            if indexStatus == "?" && workTreeStatus == "?" {
                status = .untracked
            } else if indexStatus == "A" || workTreeStatus == "A" {
                status = .added
            } else if indexStatus == "D" || workTreeStatus == "D" {
                status = .deleted
            } else if indexStatus == "R" {
                status = .renamed
            } else if indexStatus == "C" {
                status = .copied
            } else {
                status = .modified
            }

            result[cleanPath] = status
        }

        return result
    }

    static func diff(file: String, in directory: URL) -> String? {
        runGit(["diff", "--", file], in: directory)
    }

    static func diffCached(file: String, in directory: URL) -> String? {
        runGit(["diff", "--cached", "--", file], in: directory)
    }

    static func diffSummary(file: String, in directory: URL) -> (added: Int, removed: Int) {
        guard let output = runGit(["diff", "--numstat", "--", file], in: directory) else {
            return (0, 0)
        }
        let parts = output.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\t")
        guard parts.count >= 2 else { return (0, 0) }
        return (added: Int(parts[0]) ?? 0, removed: Int(parts[1]) ?? 0)
    }

    static func fullDiff(file: String, in directory: URL) -> String? {
        if let workTree = diff(file: file, in: directory), !workTree.isEmpty {
            return workTree
        }
        return diffCached(file: file, in: directory)
    }

    /// Initializes a new git repo with an initial commit. Returns true on success.
    @discardableResult
    static func initializeRepo(at directory: URL) -> Bool {
        guard runGit(["init"], in: directory) != nil else { return false }
        _ = runGit(["add", "-A"], in: directory)
        _ = runGit(["commit", "-m", "Initial commit", "--allow-empty"], in: directory)
        return true
    }

    // MARK: - Private

    static let resolvedGitPath: String = {
        let candidates = [
            "/usr/bin/git",
            "/opt/homebrew/bin/git",
            "/usr/local/bin/git"
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return "/usr/bin/git"
    }()

    private static func runGit(_ arguments: [String], in directory: URL) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: resolvedGitPath)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = ProcessInfo.processInfo.environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        // Read output BEFORE waitUntilExit to avoid pipe buffer deadlock.
        // If git output exceeds the 64KB pipe buffer and nobody is reading,
        // git blocks on write and waitUntilExit() blocks forever.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func unquoteGitPath(_ path: String) -> String {
        var result = path
        if result.hasPrefix("\"") { result.removeFirst() }
        if result.hasSuffix("\"") { result.removeLast() }
        result = result.replacingOccurrences(of: "\\\\", with: "\\")
        result = result.replacingOccurrences(of: "\\\"", with: "\"")
        result = result.replacingOccurrences(of: "\\t", with: "\t")
        result = result.replacingOccurrences(of: "\\n", with: "\n")
        return result
    }
}
