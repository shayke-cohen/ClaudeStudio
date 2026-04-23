import SwiftUI
import SwiftData

// MARK: - GitHub Settings

struct GitHubSettingsView: View {
    @State private var settings = GHPollerSettings.shared
    @Query(sort: [SortDescriptor(\Project.name)]) private var projects: [Project]
    @Query(sort: [SortDescriptor(\Agent.name)]) private var agents: [Agent]

    @State private var newTrustedUser = ""
    @State private var isSettingUpInbox = false
    @State private var inboxSetupError: String? = nil
    @State private var inboxSetupSuccess = false
    @State private var isDaemonToggling = false
    @State private var daemonError: String? = nil

    var body: some View {
        Form {
            inboxSection
            daemonSection
            trustedUsersSection
            pollIntervalSection
            perProjectSection
        }
        .formStyle(.grouped)
        .settingsDetailLayout()
        .stableXrayId("settings.github.form")
    }

    // MARK: - Inbox Setup

    private var inboxSection: some View {
        Section {
            if settings.inboxRepo.isEmpty {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No inbox repo connected")
                            .font(.body)
                        Text("Create a private repo for filing issues from your phone")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        setupInboxRepo()
                    } label: {
                        if isSettingUpInbox {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Set Up Inbox Repo")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSettingUpInbox)
                    .stableXrayId("settings.github.inboxSetupButton")
                }
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(settings.inboxRepo)
                            .font(.body.monospaced())
                        Text("GitHub inbox repo")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open on GitHub") {
                        if let url = URL(string: "https://github.com/\(settings.inboxRepo)") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                    .stableXrayId("settings.github.inboxOpenButton")
                }
            }
            if let err = inboxSetupError {
                Text(err)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .stableXrayId("settings.github.inboxSetupError")
            }
        } header: {
            Text("Inbox Repository")
        } footer: {
            Text("File issues from the GitHub iPhone app with `odyssey:agent:{name}` labels — the agent works them on your Mac and posts results back as comments.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Daemon

    private var daemonSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Run sidecar in background")
                        .font(.body)
                    Text(settings.daemonInstalled ? "Active — polls even when app is closed" : "Disabled — only polls while app is open")
                        .font(.caption)
                        .foregroundStyle(settings.daemonInstalled ? Color.green : .secondary)
                        .stableXrayId("settings.github.daemonStatusLabel")
                }
                Spacer()
                if isDaemonToggling {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Toggle("", isOn: Binding(
                        get: { settings.daemonInstalled },
                        set: { enabled in toggleDaemon(enable: enabled) }
                    ))
                    .labelsHidden()
                    .stableXrayId("settings.github.daemonToggle")
                }
            }
            if let err = daemonError {
                Text(err)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .stableXrayId("settings.github.daemonError")
            }
        } header: {
            Text("Background Daemon")
        } footer: {
            Text("Installs a launchd agent that keeps the sidecar running in the background so GitHub issues are processed even when Odyssey is not open.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Trusted Users

    private var trustedUsersSection: some View {
        Section {
            if settings.trustedGitHubUsers.isEmpty {
                Text("No trusted users — only issues from repo owner will trigger agents.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                ForEach(settings.trustedGitHubUsers, id: \.self) { user in
                    HStack {
                        Image(systemName: "person.circle")
                            .foregroundStyle(.secondary)
                        Text(user)
                        Spacer()
                        Button {
                            settings.trustedGitHubUsers.removeAll { $0 == user }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .stableXrayId("settings.github.trustedUser.removeButton.\(user)")
                        .accessibilityLabel("Remove \(user)")
                    }
                }
            }
            HStack {
                TextField("GitHub username", text: $newTrustedUser)
                    .textFieldStyle(.plain)
                    .onSubmit { addTrustedUser() }
                    .stableXrayId("settings.github.trustedUserField")
                Button("Add") { addTrustedUser() }
                    .buttonStyle(.bordered)
                    .disabled(newTrustedUser.trimmingCharacters(in: .whitespaces).isEmpty)
                    .stableXrayId("settings.github.trustedUserAddButton")
            }
        } header: {
            Text("Trusted GitHub Users")
        } footer: {
            Text("Only issues filed by these GitHub usernames will trigger agents. Add yourself and any team members who should be able to start agent sessions remotely.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Poll Interval

    private var pollIntervalSection: some View {
        Section {
            Picker("Check for new issues every", selection: Binding(
                get: { settings.pollIntervalSeconds },
                set: { settings.pollIntervalSeconds = $0 }
            )) {
                Text("1 minute").tag(60)
                Text("2 minutes").tag(120)
                Text("5 minutes").tag(300)
                Text("10 minutes").tag(600)
            }
            .stableXrayId("settings.github.pollIntervalPicker")
        } header: {
            Text("Poll Interval")
        }
    }

    // MARK: - Per-Project Repos

    @ViewBuilder
    private var perProjectSection: some View {
        let projectsWithRepos = projects.filter { !($0.githubRepo ?? "").isEmpty }
        let projectsWithoutRepos = projects.filter { ($0.githubRepo ?? "").isEmpty }

        Section {
            if projects.isEmpty {
                Text("No projects yet — create a project to connect its GitHub repo.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                ForEach(projects) { project in
                    ProjectGitHubRow(project: project, agents: agents.filter(\.isEnabled))
                }
            }
        } header: {
            Text("Project Repos")
        } footer: {
            Text("Connect a project to its GitHub repo so issues tagged `odyssey` automatically start agent sessions. The default agent handles issues with no routing label.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func setupInboxRepo() {
        isSettingUpInbox = true
        inboxSetupError = nil
        Task {
            do {
                let username = try await getGitHubUsername()
                let repoName = "\(username)/odyssey-inbox"
                try await runGhCLI(["repo", "create", repoName, "--private", "--confirm"])
                try await seedInboxLabels(repo: repoName)
                await MainActor.run {
                    settings.inboxRepo = repoName
                    isSettingUpInbox = false
                    inboxSetupSuccess = true
                }
            } catch {
                await MainActor.run {
                    inboxSetupError = error.localizedDescription
                    isSettingUpInbox = false
                }
            }
        }
    }

    private func addTrustedUser() {
        let user = newTrustedUser.trimmingCharacters(in: .whitespaces)
        guard !user.isEmpty, !settings.trustedGitHubUsers.contains(user) else { return }
        settings.trustedGitHubUsers.append(user)
        newTrustedUser = ""
    }

    private func toggleDaemon(enable: Bool) {
        isDaemonToggling = true
        daemonError = nil
        Task {
            do {
                let scriptPath = Bundle.main.bundlePath + "/Contents/Resources/install-daemon.sh"
                let arg = enable ? "install" : "uninstall"
                try await runShellScript(scriptPath, args: [arg])
                await MainActor.run { isDaemonToggling = false }
            } catch {
                await MainActor.run {
                    daemonError = error.localizedDescription
                    isDaemonToggling = false
                }
            }
        }
    }

    // MARK: - Shell helpers

    private func getGitHubUsername() async throws -> String {
        let output = try await runGhCLI(["auth", "status", "--json", "user", "-q", ".user.login"])
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func seedInboxLabels(repo: String) async throws {
        let labels = [
            ("odyssey:queued", "0075ca"),
            ("odyssey:in-progress", "e4e669"),
            ("odyssey:done", "0e8a16"),
            ("odyssey:failed", "d93f0b"),
        ]
        for (name, color) in labels {
            _ = try? await runGhCLI(["label", "create", name, "--repo", repo, "--color", color, "--force"])
        }
    }

    @discardableResult
    private func runGhCLI(_ args: [String]) async throws -> String {
        let ghPaths = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
        let ghPath = ghPaths.first { FileManager.default.fileExists(atPath: $0) } ?? "gh"
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ghPath)
            process.arguments = args
            let pipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = pipe
            process.standardError = errPipe
            process.terminationHandler = { proc in
                let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                if proc.terminationStatus == 0 {
                    continuation.resume(returning: out.trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    continuation.resume(throwing: GitHubCLIError(message: err.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func runShellScript(_ path: String, args: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [path] + args
            let errPipe = Pipe()
            process.standardError = errPipe
            process.terminationHandler = { proc in
                if proc.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    continuation.resume(throwing: GitHubCLIError(message: err.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

// MARK: - Per-project row

private struct ProjectGitHubRow: View {
    @Bindable var project: Project
    let agents: [Agent]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(project.name)
                .font(.body.weight(.medium))
            HStack(spacing: 12) {
                TextField("owner/repo", text: Binding(
                    get: { project.githubRepo ?? "" },
                    set: { project.githubRepo = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.plain)
                .font(.callout.monospaced())
                .stableXrayId("settings.github.project.repoField.\(project.id.uuidString)")
            }
            Picker("Default agent", selection: Binding(
                get: { project.githubDefaultAgentId },
                set: { project.githubDefaultAgentId = $0 }
            )) {
                Text("None").tag(nil as UUID?)
                ForEach(agents) { agent in
                    Text(agent.name).tag(agent.id as UUID?)
                }
            }
            .stableXrayId("settings.github.project.defaultAgentPicker.\(project.id.uuidString)")
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Error type

private struct GitHubCLIError: LocalizedError {
    let message: String
    var errorDescription: String? { message.isEmpty ? "gh CLI error" : message }
}
