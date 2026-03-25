import Foundation
import SwiftData

/// Removes git worktrees when sessions end and prunes orphans on startup.
@MainActor
enum WorktreeCleanup {
    /// Remove the worktree associated with a completed or failed session.
    static func cleanupIfNeeded(session: Session) async {
        guard case .worktree(let repoUrl, _) = session.workspaceType,
              let worktreePath = session.worktreePath else { return }

        let baseClonePath = WorkspaceResolver.cloneDestinationPath(repoInput: repoUrl)
        await GitHubIntegration.removeWorktree(baseClonePath: baseClonePath, worktreePath: worktreePath)
    }

    /// Scan for worktree directories that don't belong to any active session and remove them.
    static func pruneOrphaned(activeSessions: [Session]) async {
        let worktreeBase = "\(NSHomeDirectory())/.claudpeer/worktrees"
        let fm = FileManager.default
        guard fm.fileExists(atPath: worktreeBase) else { return }

        let activeWorktreePaths = Set(activeSessions.compactMap(\.worktreePath))

        guard let repoDirs = try? fm.contentsOfDirectory(atPath: worktreeBase) else { return }
        for repoDir in repoDirs {
            let repoPath = (worktreeBase as NSString).appendingPathComponent(repoDir)
            guard let branchDirs = try? fm.contentsOfDirectory(atPath: repoPath) else { continue }
            for branchDir in branchDirs {
                let worktreePath = (repoPath as NSString).appendingPathComponent(branchDir)
                if !activeWorktreePaths.contains(worktreePath) {
                    // Find the base clone to prune from
                    let baseClonePath = "\(NSHomeDirectory())/.claudpeer/repos/\(repoDir)"
                    await GitHubIntegration.removeWorktree(baseClonePath: baseClonePath, worktreePath: worktreePath)
                }
            }
            // Remove repo dir if empty
            if let remaining = try? fm.contentsOfDirectory(atPath: repoPath), remaining.isEmpty {
                try? fm.removeItem(atPath: repoPath)
            }
        }
    }
}
