import Foundation

enum GitHubIntegrationError: LocalizedError, Equatable {
    case emptyRepository
    case gitNotFound
    case ghNotFound
    case workDirMissing
    case commandFailed(command: String, message: String)

    var errorDescription: String? {
        switch self {
        case .emptyRepository:
            return "No GitHub repository configured."
        case .gitNotFound:
            return "git was not found. Install Xcode Command Line Tools or add git to your PATH."
        case .ghNotFound:
            return "gh CLI was not found. Install it via `brew install gh`."
        case .workDirMissing:
            return "Working directory does not exist."
        case .commandFailed(_, let message):
            return message
        }
    }
}

/// Runs `git` to clone or update a repository used as an agent workspace.
enum GitHubIntegration {
    private static func gitExecutablePath() -> String {
        let candidates = ["/usr/bin/git", "/opt/homebrew/bin/git", "/usr/local/bin/git"]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return "/usr/bin/git"
    }

    /// Ensures `destinationPath` contains the repo on `branch`, cloning if needed.
    static func ensureClone(repoInput: String, branch: String, destinationPath: String) async throws {
        let trimmedRepo = repoInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRepo.isEmpty else { throw GitHubIntegrationError.emptyRepository }

        let url = WorkspaceResolver.cloneURL(from: trimmedRepo)
        let git = gitExecutablePath()
        guard FileManager.default.isExecutableFile(atPath: git) else {
            throw GitHubIntegrationError.gitNotFound
        }

        let fm = FileManager.default
        let branchName = branch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "main" : branch

        let gitDir = (destinationPath as NSString).appendingPathComponent(".git")
        if fm.fileExists(atPath: gitDir) {
            try await runGit(
                git: git,
                arguments: ["-C", destinationPath, "fetch", "--quiet", "origin"],
                description: "git fetch"
            )
            do {
                try await runGit(
                    git: git,
                    arguments: ["-C", destinationPath, "checkout", "-q", branchName],
                    description: "git checkout"
                )
            } catch {
                try await runGit(
                    git: git,
                    arguments: ["-C", destinationPath, "checkout", "-q", "-B", branchName, "origin/\(branchName)"],
                    description: "git checkout tracking branch"
                )
            }
            return
        }

        let parent = (destinationPath as NSString).deletingLastPathComponent
        try fm.createDirectory(atPath: parent, withIntermediateDirectories: true)
        if fm.fileExists(atPath: destinationPath) {
            try fm.removeItem(atPath: destinationPath)
        }

        do {
            try await runGit(
                git: git,
                arguments: ["clone", "--depth", "1", "--branch", branchName, url, destinationPath],
                description: "git clone"
            )
        } catch {
            try await runGit(
                git: git,
                arguments: ["clone", "--depth", "1", url, destinationPath],
                description: "git clone default branch"
            )
            try await runGit(
                git: git,
                arguments: ["-C", destinationPath, "checkout", "-q", branchName],
                description: "git checkout branch"
            )
        }
    }

    // MARK: - GitHub CLI (gh)

    private static func ghExecutablePath() -> String? {
        let candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    /// Returns true if `gh auth status` succeeds.
    static func isGhAuthenticated() async -> Bool {
        guard let gh = ghExecutablePath() else { return false }
        do {
            _ = try await runGitOutput(git: gh, arguments: ["auth", "status"], description: "gh auth status")
            return true
        } catch {
            return false
        }
    }

    /// Runs a `gh` command and returns stdout.
    static func ghOutput(arguments: [String], workingDirectory: String? = nil) async throws -> String {
        guard let gh = ghExecutablePath() else { throw GitHubIntegrationError.ghNotFound }
        var args = arguments
        if let wd = workingDirectory {
            args = ["-C", wd] + args
        }
        return try await runGitOutput(git: gh, arguments: args, description: "gh \(arguments.first ?? "")")
    }

    /// Fetches a GitHub issue's title, body, and labels as JSON.
    static func fetchIssue(repoInput: String, issueNumber: Int) async throws -> (title: String, body: String, labels: [String]) {
        let repo = WorkspaceResolver.cloneURL(from: repoInput)
            .replacingOccurrences(of: "https://github.com/", with: "")
            .replacingOccurrences(of: ".git", with: "")
        let json = try await ghOutput(arguments: [
            "issue", "view", "\(issueNumber)",
            "--repo", repo,
            "--json", "title,body,labels"
        ])
        guard let data = json.data(using: .utf8) else {
            throw GitHubIntegrationError.commandFailed(command: "gh issue view", message: "Invalid JSON output")
        }
        struct IssueJSON: Codable {
            let title: String
            let body: String
            struct Label: Codable { let name: String }
            let labels: [Label]
        }
        let issue = try JSONDecoder().decode(IssueJSON.self, from: data)
        return (title: issue.title, body: issue.body, labels: issue.labels.map(\.name))
    }

    /// Creates a branch named `issue-{number}-{slug}` from the issue title, returns the branch name.
    static func createBranchFromIssue(repoInput: String, issueNumber: Int, baseClonePath: String) async throws -> (branch: String, title: String, body: String) {
        let issue = try await fetchIssue(repoInput: repoInput, issueNumber: issueNumber)
        let slug = issue.title.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            .prefix(40)
        let branchName = "issue-\(issueNumber)-\(slug)"

        let git = gitExecutablePath()
        try await runGit(git: git, arguments: ["-C", baseClonePath, "checkout", "-b", branchName], description: "git checkout -b")

        return (branch: branchName, title: issue.title, body: issue.body)
    }

    // MARK: - Worktree operations

    /// Creates a git worktree at `worktreePath` for `branch`, ensuring the base clone exists and is unshallowed.
    static func ensureWorktree(repoInput: String, branch: String, baseClonePath: String, worktreePath: String) async throws {
        let trimmedRepo = repoInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRepo.isEmpty else { throw GitHubIntegrationError.emptyRepository }

        // 1. Ensure the base clone exists
        try await ensureClone(repoInput: trimmedRepo, branch: "main", destinationPath: baseClonePath)

        let git = gitExecutablePath()

        // 2. Unshallow if needed — worktrees require full history
        let isShallow = try await runGitOutput(
            git: git,
            arguments: ["-C", baseClonePath, "rev-parse", "--is-shallow-repository"],
            description: "check shallow"
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        if isShallow == "true" {
            try await runGit(
                git: git,
                arguments: ["-C", baseClonePath, "fetch", "--unshallow"],
                description: "git fetch --unshallow"
            )
        }

        // 3. Fetch latest refs
        try await runGit(
            git: git,
            arguments: ["-C", baseClonePath, "fetch", "--quiet", "origin"],
            description: "git fetch origin"
        )

        let fm = FileManager.default
        let gitFile = (worktreePath as NSString).appendingPathComponent(".git")

        if fm.fileExists(atPath: gitFile) {
            // 4a. Worktree already exists — update it
            try await runGit(
                git: git,
                arguments: ["-C", worktreePath, "checkout", "-q", branch],
                description: "git checkout in worktree"
            )
        } else {
            // 4b. Create new worktree
            let parent = (worktreePath as NSString).deletingLastPathComponent
            try fm.createDirectory(atPath: parent, withIntermediateDirectories: true)

            do {
                // Try checking out existing branch
                try await runGit(
                    git: git,
                    arguments: ["-C", baseClonePath, "worktree", "add", worktreePath, branch],
                    description: "git worktree add"
                )
            } catch {
                // Branch doesn't exist remotely — create it
                try await runGit(
                    git: git,
                    arguments: ["-C", baseClonePath, "worktree", "add", "-b", branch, worktreePath],
                    description: "git worktree add -b"
                )
            }
        }
    }

    /// Removes a git worktree and prunes stale references.
    static func removeWorktree(baseClonePath: String, worktreePath: String) async {
        let git = gitExecutablePath()
        do {
            try await runGit(
                git: git,
                arguments: ["-C", baseClonePath, "worktree", "remove", worktreePath, "--force"],
                description: "git worktree remove"
            )
        } catch {
            // Fallback: prune stale worktree refs and clean up directory
            try? await runGit(
                git: git,
                arguments: ["-C", baseClonePath, "worktree", "prune"],
                description: "git worktree prune"
            )
            try? FileManager.default.removeItem(atPath: worktreePath)
        }
    }

    // MARK: - Private helpers

    private static func runGit(git: String, arguments: [String], description: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: git)
                process.arguments = arguments
                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe
                do {
                    try process.run()
                    process.waitUntilExit()
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    let errText = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    guard process.terminationStatus == 0 else {
                        let msg = errText.isEmpty ? "\(description) failed (exit \(process.terminationStatus))." : errText
                        continuation.resume(throwing: GitHubIntegrationError.commandFailed(command: description, message: msg))
                        return
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: GitHubIntegrationError.commandFailed(
                        command: description,
                        message: error.localizedDescription
                    ))
                }
            }
        }
    }

    private static func runGitOutput(git: String, arguments: [String], description: String) async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: git)
                process.arguments = arguments
                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe
                do {
                    try process.run()
                    process.waitUntilExit()
                    let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                    let outText = String(data: outData, encoding: .utf8) ?? ""
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    let errText = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    guard process.terminationStatus == 0 else {
                        let msg = errText.isEmpty ? "\(description) failed (exit \(process.terminationStatus))." : errText
                        continuation.resume(throwing: GitHubIntegrationError.commandFailed(command: description, message: msg))
                        return
                    }
                    continuation.resume(returning: outText)
                } catch {
                    continuation.resume(throwing: GitHubIntegrationError.commandFailed(
                        command: description,
                        message: error.localizedDescription
                    ))
                }
            }
        }
    }
}
