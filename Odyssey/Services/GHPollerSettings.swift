import Foundation

/// Persists GitHub poller configuration in UserDefaults.
/// Not a SwiftData model — poller config is machine-global, not per-project.
@Observable
final class GHPollerSettings {
    static let shared = GHPollerSettings()

    // MARK: - UserDefaults keys

    private static let inboxRepoKey         = "gh.inboxRepo"
    private static let pollIntervalKey      = "gh.pollIntervalSeconds"
    private static let trustedUsersKey      = "gh.trustedUsers"
    private static let daemonPlistPath      = ("~/Library/LaunchAgents/com.odyssey.sidecar.plist" as NSString).expandingTildeInPath

    // MARK: - Published properties

    var inboxRepo: String {
        didSet { UserDefaults.standard.set(inboxRepo, forKey: Self.inboxRepoKey) }
    }

    var pollIntervalSeconds: Int {
        didSet { UserDefaults.standard.set(pollIntervalSeconds, forKey: Self.pollIntervalKey) }
    }

    var trustedGitHubUsers: [String] {
        didSet {
            if let data = try? JSONEncoder().encode(trustedGitHubUsers) {
                UserDefaults.standard.set(data, forKey: Self.trustedUsersKey)
            }
        }
    }

    /// Read-only: true when ~/Library/LaunchAgents/com.odyssey.sidecar.plist exists.
    var daemonInstalled: Bool {
        FileManager.default.fileExists(atPath: Self.daemonPlistPath)
    }

    // MARK: - Init

    private init() {
        inboxRepo = UserDefaults.standard.string(forKey: Self.inboxRepoKey) ?? ""
        let storedInterval = UserDefaults.standard.integer(forKey: Self.pollIntervalKey)
        pollIntervalSeconds = storedInterval > 0 ? storedInterval : 120

        if let data = UserDefaults.standard.data(forKey: Self.trustedUsersKey),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            trustedGitHubUsers = decoded
        } else {
            trustedGitHubUsers = []
        }
    }

    // MARK: - Persistence
    // Note: All properties persist automatically via didSet; save() is kept for convenience but not required.
}
