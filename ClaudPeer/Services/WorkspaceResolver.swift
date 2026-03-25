import Foundation

/// Shared logic for GitHub clone paths and workspace resolution (used by `AgentProvisioner`, `GroupWorkingDirectory`, and UI).
enum WorkspaceResolver {
    /// Normalizes a user-entered repo string into a `git clone` URL.
    static func cloneURL(from repoInput: String) -> String {
        let trimmed = repoInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        if trimmed.hasPrefix("git@") || trimmed.hasPrefix("https://") || trimmed.hasPrefix("http://") || trimmed.hasPrefix("ssh://") {
            return trimmed
        }
        // org/repo shorthand
        let parts = trimmed.split(separator: "/").map(String.init)
        if parts.count == 2, !parts[0].contains(".") {
            return "https://github.com/\(parts[0])/\(parts[1])"
        }
        return trimmed
    }

    /// Stable directory name under `~/.claudpeer/repos/` (matches historical `AgentProvisioner` behavior).
    static func repositoryDirectoryName(repoInput: String) -> String {
        let trimmed = repoInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "unknown" }
        var slug = trimmed
        if slug.hasSuffix(".git") {
            slug = String(slug.dropLast(4))
        }
        if let range = slug.range(of: "://") {
            slug = String(slug[range.upperBound...])
        }
        if slug.hasPrefix("git@") {
            slug = slug.replacingOccurrences(of: ":", with: "/")
            slug = slug.replacingOccurrences(of: "git@", with: "")
        }
        let components = slug.split { $0 == "/" }.map(String.init)
        let tail = components.suffix(2)
        if tail.count == 2 {
            return tail.joined(separator: "-")
        }
        return components.last ?? "repo"
    }

    static func cloneDestinationPath(repoInput: String) -> String {
        let name = repositoryDirectoryName(repoInput: repoInput)
        return "\(NSHomeDirectory())/.claudpeer/repos/\(name)"
    }

    /// Path for a git worktree: `~/.claudpeer/worktrees/{repo-name}/{sanitized-branch}`
    static func worktreeDestinationPath(repoInput: String, branch: String) -> String {
        let repoName = repositoryDirectoryName(repoInput: repoInput)
        let safeBranch = branch
            .replacingOccurrences(of: "refs/heads/", with: "")
            .replacingOccurrences(of: "/", with: "-")
        return "\(NSHomeDirectory())/.claudpeer/worktrees/\(repoName)/\(safeBranch)"
    }

    /// Whether `session` should use automatic GitHub clone for `agent` (no unrelated explicit directory override).
    static func shouldManageGitHubClone(agent: Agent, sessionWorkingDirectory: String) -> Bool {
        guard let repo = agent.githubRepo?.trimmingCharacters(in: .whitespacesAndNewlines), !repo.isEmpty else {
            return false
        }
        let expected = cloneDestinationPath(repoInput: repo)
        let wd = sessionWorkingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        if wd.isEmpty { return true }
        if wd == expected { return true }
        let def = agent.defaultWorkingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !def.isEmpty, wd == def { return false }
        return false
    }
}
