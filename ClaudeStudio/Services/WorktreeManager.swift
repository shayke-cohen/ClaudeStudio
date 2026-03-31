import Foundation
import SwiftData
import OSLog

/// Manages git worktrees for conversations.
/// Each conversation gets its own worktree branched from the project directory,
/// so multiple chats can work in parallel without conflicts.
@MainActor
enum WorktreeManager {

    /// Ensures a worktree exists for the given conversation.
    /// Called lazily on first message, not on conversation creation.
    /// Returns the worktree path (or the project directory if git is unavailable).
    static func ensureWorktree(
        for conversation: Conversation,
        projectDirectory: String,
        modelContext: ModelContext
    ) async -> String {
        // Already has a worktree — return it
        if let existing = conversation.worktreePath,
           FileManager.default.fileExists(atPath: existing) {
            if isUsableWorktree(at: existing) {
                return existing
            }

            Log.general.warning("WorktreeManager: repairing invalid worktree at \(existing, privacy: .public)")
            await removeInvalidWorktree(at: existing, projectDirectory: projectDirectory)
            conversation.worktreePath = nil
            conversation.worktreeBranch = nil
            try? modelContext.save()
        }

        // Check if project is a git repo
        let gitDir = (projectDirectory as NSString).appendingPathComponent(".git")
        guard FileManager.default.fileExists(atPath: gitDir) else {
            // Not a git repo — just use the project directory directly
            Log.general.info("WorktreeManager: project is not a git repo, using directly")
            return projectDirectory
        }

        let shortId = conversation.id.uuidString.prefix(8).lowercased()
        let topicSlug = slugify(conversation.topic ?? "chat")
        let branchName = "claude/\(topicSlug)-\(shortId)"
        let worktreesDir = (projectDirectory as NSString).appendingPathComponent(".claudestudio/worktrees")
        let worktreePath = (worktreesDir as NSString).appendingPathComponent(String(shortId))

        do {
            // Ensure .claudestudio/worktrees/ exists
            try FileManager.default.createDirectory(atPath: worktreesDir, withIntermediateDirectories: true)

            // Add .claudestudio to .gitignore if not already there
            ensureGitignore(projectDirectory: projectDirectory)

            let git = gitExecutablePath()

            // Check if worktree already exists on disk
            let gitFile = (worktreePath as NSString).appendingPathComponent(".git")
            if FileManager.default.fileExists(atPath: gitFile) {
                // Reuse existing worktree
                Log.general.info("WorktreeManager: reusing existing worktree at \(worktreePath, privacy: .public)")
            } else {
                // Create new worktree with new branch
                do {
                    try await runGit(git: git, arguments: [
                        "-C", projectDirectory,
                        "worktree", "add", "-b", branchName, worktreePath
                    ])
                } catch {
                    // Branch might already exist — try without -b
                    try await runGit(git: git, arguments: [
                        "-C", projectDirectory,
                        "worktree", "add", worktreePath, branchName
                    ])
                }
                Log.general.info("WorktreeManager: created worktree at \(worktreePath, privacy: .public) branch=\(branchName, privacy: .public)")
            }

            // Store on conversation
            conversation.worktreePath = worktreePath
            conversation.worktreeBranch = branchName
            try? modelContext.save()

            return worktreePath

        } catch {
            Log.general.error("WorktreeManager: failed to create worktree: \(error.localizedDescription, privacy: .public)")
            // Fallback: use project directory directly
            return projectDirectory
        }
    }

    static func isUsableWorktree(at path: String) -> Bool {
        let gitFile = (path as NSString).appendingPathComponent(".git")
        guard FileManager.default.fileExists(atPath: gitFile) else { return false }

        let contents = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
        if contents.contains(where: { $0 != ".git" }) {
            return true
        }

        let git = gitExecutablePath()
        return runGitSync(git: git, arguments: ["-C", path, "rev-parse", "--verify", "HEAD"])
    }

    /// Removes the worktree for a conversation (on archive/delete).
    static func removeWorktree(for conversation: Conversation, projectDirectory: String) async {
        guard let worktreePath = conversation.worktreePath else { return }

        let git = gitExecutablePath()
        do {
            try await runGit(git: git, arguments: [
                "-C", projectDirectory,
                "worktree", "remove", worktreePath, "--force"
            ])
        } catch {
            // Fallback: prune + manual delete
            try? await runGit(git: git, arguments: [
                "-C", projectDirectory,
                "worktree", "prune"
            ])
            try? FileManager.default.removeItem(atPath: worktreePath)
        }
        Log.general.info("WorktreeManager: removed worktree at \(worktreePath, privacy: .public)")
    }

    // MARK: - Private

    private static func slugify(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            .prefix(30)
            .description
    }

    private static func gitExecutablePath() -> String {
        let candidates = ["/usr/bin/git", "/opt/homebrew/bin/git", "/usr/local/bin/git"]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return "/usr/bin/git"
    }

    private static func ensureGitignore(projectDirectory: String) {
        let gitignorePath = (projectDirectory as NSString).appendingPathComponent(".gitignore")
        let entry = ".claudestudio/"

        if FileManager.default.fileExists(atPath: gitignorePath) {
            guard let content = try? String(contentsOfFile: gitignorePath, encoding: .utf8) else { return }
            if content.contains(entry) { return }
            let updated = content.hasSuffix("\n") ? content + entry + "\n" : content + "\n" + entry + "\n"
            try? updated.write(toFile: gitignorePath, atomically: true, encoding: .utf8)
        } else {
            try? (entry + "\n").write(toFile: gitignorePath, atomically: true, encoding: .utf8)
        }
    }

    private static func removeInvalidWorktree(at worktreePath: String, projectDirectory: String) async {
        let git = gitExecutablePath()
        _ = await runGitBestEffort(git: git, arguments: [
            "-C", projectDirectory,
            "worktree", "remove", worktreePath, "--force"
        ])
        _ = await runGitBestEffort(git: git, arguments: [
            "-C", projectDirectory,
            "worktree", "prune"
        ])
        try? FileManager.default.removeItem(atPath: worktreePath)
    }

    private static func runGit(git: String, arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: git)
                process.arguments = arguments
                let errPipe = Pipe()
                process.standardOutput = FileHandle.nullDevice
                process.standardError = errPipe
                do {
                    try process.run()
                    process.waitUntilExit()
                    guard process.terminationStatus == 0 else {
                        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                        let errText = String(data: errData, encoding: .utf8) ?? ""
                        continuation.resume(throwing: GitHubIntegrationError.commandFailed(
                            command: "git \(arguments.joined(separator: " "))",
                            message: errText
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

    private static func runGitBestEffort(git: String, arguments: [String]) async -> Bool {
        do {
            try await runGit(git: git, arguments: arguments)
            return true
        } catch {
            return false
        }
    }

    private static func runGitSync(git: String, arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: git)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
