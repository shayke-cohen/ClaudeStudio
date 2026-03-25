import Foundation
import SwiftData

/// Ensures a GitHub-linked clone or worktree exists before the sidecar runs tools in that directory.
@MainActor
enum GitWorkspacePreparer {
    static func prepareIfNeeded(session: Session, modelContext: ModelContext) async throws {
        // Handle worktree workspace type
        if case .worktree(let repoUrl, let branch) = session.workspaceType {
            let baseClonePath = WorkspaceResolver.cloneDestinationPath(repoInput: repoUrl)
            let worktreePath = WorkspaceResolver.worktreeDestinationPath(repoInput: repoUrl, branch: branch)
            try await GitHubIntegration.ensureWorktree(
                repoInput: repoUrl,
                branch: branch,
                baseClonePath: baseClonePath,
                worktreePath: worktreePath
            )
            session.workingDirectory = worktreePath
            session.worktreePath = worktreePath
            try? modelContext.save()
        } else if let agent = session.agent,
                  WorkspaceResolver.shouldManageGitHubClone(agent: agent, sessionWorkingDirectory: session.workingDirectory),
                  let repo = agent.githubRepo?.trimmingCharacters(in: .whitespacesAndNewlines), !repo.isEmpty {
            // Handle GitHub clone workspace type
            let path = WorkspaceResolver.cloneDestinationPath(repoInput: repo)
            let branchRaw = agent.githubDefaultBranch?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let branch = branchRaw.isEmpty ? "main" : branchRaw

            try await GitHubIntegration.ensureClone(repoInput: repo, branch: branch, destinationPath: path)

            if session.workingDirectory != path {
                session.workingDirectory = path
            }
            session.workspaceType = .githubClone(repoUrl: repo)
            try? modelContext.save()
        }

        // Ensure every working directory has git initialized.
        // Worktree and GitHub clone dirs already have git (no-op).
        // Ephemeral sandboxes, agent defaults, and explicit paths get git init + initial commit.
        ensureGitRepo(session: session)
    }

    /// Ensures the working directory has git initialized.
    /// Worktree and GitHub clone paths return early above, so this covers
    /// ephemeral sandboxes, agent defaults, and explicit user paths.
    static func ensureGitRepo(session: Session) {
        let dirURL = URL(fileURLWithPath: session.workingDirectory)
        guard FileManager.default.fileExists(atPath: dirURL.path),
              !GitService.isGitRepo(at: dirURL) else { return }
        GitService.initializeRepo(at: dirURL)
    }
}
