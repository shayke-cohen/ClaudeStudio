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

enum GitServiceError: LocalizedError, Equatable {
    case notGitRepository
    case dirtyWorkingTree(changeCount: Int)
    case branchNotFound(String)
    case commandFailed(command: String, message: String)

    var errorDescription: String? {
        switch self {
        case .notGitRepository:
            return "This directory is not a git repository."
        case .dirtyWorkingTree(let changeCount):
            return changeCount == 1
                ? "Switching branches is disabled while 1 file has uncommitted changes."
                : "Switching branches is disabled while \(changeCount) files have uncommitted changes."
        case .branchNotFound(let branch):
            return "Branch \"\(branch)\" was not found locally or on origin."
        case .commandFailed(_, let message):
            return message
        }
    }
}

struct GitBranchRef: Identifiable, Hashable, Sendable {
    let name: String
    let isRemote: Bool

    var id: String {
        "\(isRemote ? "remote" : "local"):\(name)"
    }
}

enum GitService {

    static func isGitRepo(at directory: URL) -> Bool {
        let gitDir = directory.appendingPathComponent(".git")
        // .git can be a directory (normal repo) or a file (worktree with gitdir: pointer)
        return FileManager.default.fileExists(atPath: gitDir.path)
    }

    /// Runs `git init` in the given directory if it is not already a git repository.
    /// Safe to call multiple times — no-op when a repo already exists.
    @discardableResult
    static func initIfNeeded(at directory: URL) -> Bool {
        guard !isGitRepo(at: directory) else { return false }
        guard FileManager.default.fileExists(atPath: directory.path) else { return false }
        return runGit(["init", "-b", "main"], in: directory) != nil
    }

    static func currentBranch(in directory: URL) -> String? {
        guard isGitRepo(at: directory) else { return nil }

        let branch = runGit(["branch", "--show-current"], in: directory)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let branch, !branch.isEmpty {
            return branch
        }

        let detachedHead = runGit(["rev-parse", "--short", "HEAD"], in: directory)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let detachedHead, !detachedHead.isEmpty {
            return "Detached (\(detachedHead))"
        }

        return nil
    }

    static func localBranches(in directory: URL) -> [GitBranchRef] {
        branchRefs(arguments: ["branch", "--format=%(refname:short)"], in: directory, isRemote: false)
    }

    static func remoteBranches(in directory: URL) -> [GitBranchRef] {
        branchRefs(arguments: ["branch", "-r", "--format=%(refname:short)"], in: directory, isRemote: true)
    }

    static func fetch(in directory: URL) async throws {
        guard isGitRepo(at: directory) else { throw GitServiceError.notGitRepository }
        try await runGitThrowing(["fetch", "--prune", "origin"], in: directory)
    }

    static func switchBranch(named branch: String, in directory: URL) async throws {
        guard isGitRepo(at: directory) else { throw GitServiceError.notGitRepository }

        let changeCount = status(in: directory).count
        guard changeCount == 0 else {
            throw GitServiceError.dirtyWorkingTree(changeCount: changeCount)
        }

        let localBranchNames = Set(localBranches(in: directory).map(\.name))
        if localBranchNames.contains(branch) {
            try await runGitThrowing(["checkout", "-q", branch], in: directory)
            return
        }

        let remoteBranchNames = Set(remoteBranches(in: directory).map(\.name))
        if remoteBranchNames.contains(branch) {
            try await runGitThrowing(["checkout", "-q", "--track", "origin/\(branch)"], in: directory)
            return
        }

        throw GitServiceError.branchNotFound(branch)
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

    private static func branchRefs(arguments: [String], in directory: URL, isRemote: Bool) -> [GitBranchRef] {
        guard isGitRepo(at: directory),
              let output = runGit(arguments, in: directory) else {
            return []
        }

        let current = currentBranch(in: directory)

        return output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .compactMap { rawName -> GitBranchRef? in
                if isRemote {
                    guard rawName.hasPrefix("origin/"), rawName != "origin/HEAD" else { return nil }
                    let shortName = String(rawName.dropFirst("origin/".count))
                    guard shortName != "HEAD", !shortName.isEmpty else { return nil }
                    return GitBranchRef(name: shortName, isRemote: true)
                }
                return GitBranchRef(name: rawName, isRemote: false)
            }
            .sorted { lhs, rhs in
                if lhs.name == current { return true }
                if rhs.name == current { return false }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private static func runGitThrowing(_ arguments: [String], in directory: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: resolvedGitPath)
                process.arguments = arguments
                process.currentDirectoryURL = directory
                process.environment = ProcessInfo.processInfo.environment

                let outputPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = outputPipe

                do {
                    try process.run()
                    let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()

                    guard process.terminationStatus == 0 else {
                        let message = String(data: data, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        continuation.resume(throwing: GitServiceError.commandFailed(
                            command: "git \(arguments.joined(separator: " "))",
                            message: message?.isEmpty == false ? message! : "Git command failed."
                        ))
                        return
                    }

                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
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
