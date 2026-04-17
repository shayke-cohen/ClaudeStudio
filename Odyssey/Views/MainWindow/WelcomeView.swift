import SwiftUI
import SwiftData

struct WelcomeView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(WindowState.self) private var windowState: WindowState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Agent.name) private var allAgents: [Agent]
    @Query(sort: \AgentGroup.sortOrder) private var allGroups: [AgentGroup]
    @Query(sort: \Session.startedAt, order: .reverse) private var recentSessions: [Session]

    var onQuickChat: () -> Void
    var onStartAgent: (Agent) -> Void
    var onStartGroup: (AgentGroup) -> Void

    @State private var recentProjects: [String] = []
    @State private var showProjectPicker = false

    // MARK: - Computed

    private var enabledAgents: [Agent] {
        allAgents.filter(\.isEnabled)
    }

    private var recentAgents: [Agent] {
        var seen = Set<UUID>()
        var result: [Agent] = []
        for session in recentSessions {
            guard let agent = session.agent, agent.isEnabled, !seen.contains(agent.id) else { continue }
            seen.insert(agent.id)
            result.append(agent)
            if result.count >= 6 { break }
        }
        return result
    }

    private var enabledGroups: [AgentGroup] {
        allGroups.filter(\.isEnabled)
    }

    /// Recent projects excluding the current one.
    private var otherRecentProjects: [String] {
        recentProjects.filter { $0 != windowState.projectDirectory }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                heroSection
                projectSection
                quickActionsGrid
                if !recentAgents.isEmpty {
                    recentAgentsSection
                }
                if !enabledGroups.isEmpty {
                    agentGroupsSection
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .stableXrayId("welcome.scrollView")
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear { recentProjects = RecentDirectories.load() }
    }

    // MARK: - Hero

    @ViewBuilder
    private var heroSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
                .xrayId("welcome.heroIcon")
            Text("Welcome to Odyssey")
                .font(.largeTitle)
                .fontWeight(.bold)
                .xrayId("welcome.heading")
            Text("Pick a project, start a thread, and bring in the agents or teams you need.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
                .xrayId("welcome.subtitle")
        }
        .padding(.top, 40)
    }

    // MARK: - Project

    @ViewBuilder
    private var projectSection: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: isGitRepo(windowState.projectDirectory) ? "externaldrive.badge.checkmark" : "folder.fill")
                    .font(.title2)
                    .foregroundStyle(isGitRepo(windowState.projectDirectory) ? .green : .blue)
                    .frame(width: 40, height: 40)
                    .background((isGitRepo(windowState.projectDirectory) ? Color.green : Color.blue).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Working in")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(windowState.projectName)
                        .font(.headline)
                        .lineLimit(1)
                    Text(abbreviatePath(windowState.projectDirectory))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer()
                Button("Change\u{2026}") {
                    showProjectPicker = true
                }
                .buttonStyle(.bordered)
                .xrayId("welcome.changeProjectButton")
            }
            .padding(14)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.blue.opacity(0.3), lineWidth: 1))
            .xrayId("welcome.currentProject")

            Text("Threads in this project share the root folder, and active ones can spin up their own worktrees.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: 520)
            .sheet(isPresented: $showProjectPicker) {
                ChangeProjectSheet { path in
                    let project = ProjectRecords.upsertProject(at: path, in: modelContext)
                    showProjectPicker = false
                    windowState.selectProject(project)
                }
            }
    }

    // MARK: - Quick Actions

    @ViewBuilder
    private var quickActionsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            quickActionCard(
                title: "Quick Chat",
                subtitle: "Freeform, no agent",
                icon: "plus.message",
                shortcut: "\u{21E7}\u{2318}N",
                color: .blue,
                identifier: "welcome.quickAction.quickChat"
            ) {
                onQuickChat()
            }
            quickActionCard(
                title: "New Thread",
                subtitle: "Freeform chat, no agent",
                icon: "plus.bubble",
                shortcut: nil,
                color: .purple,
                identifier: "welcome.quickAction.newSession"
            ) {
                onQuickChat()
            }
            quickActionCard(
                title: "Browse Agents",
                subtitle: "\(enabledAgents.count) available",
                icon: "cpu",
                shortcut: nil,
                color: .orange,
                identifier: "welcome.quickAction.browseAgents"
            ) {
                windowState.openConfiguration(section: .agents)
            }
            quickActionCard(
                title: "Browse Groups",
                subtitle: "\(enabledGroups.count) teams",
                icon: "person.3",
                shortcut: nil,
                color: .teal,
                identifier: "welcome.quickAction.browseGroups"
            ) {
                windowState.openConfiguration(section: .groups)
            }
            quickActionCard(
                title: "Schedules",
                subtitle: "Recurring missions",
                icon: "clock.badge",
                shortcut: "\u{2318}\u{21E7}S",
                color: .green,
                identifier: "welcome.quickAction.schedules"
            ) {
                windowState.showScheduleLibrary = true
            }
        }
        .frame(maxWidth: 520)
    }

    private func quickActionCard(
        title: String,
        subtitle: String,
        icon: String,
        shortcut: String?,
        color: Color,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                    .frame(width: 40, height: 40)
                    .background(color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(12)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .appXrayTapProxy(id: identifier, action: action)
        .stableXrayId(identifier)
        .accessibilityLabel(title)
    }

    // MARK: - Recent Agents

    @ViewBuilder
    private var recentAgentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RECENT AGENTS")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.tertiary)
                .xrayId("welcome.recentAgents")

            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 12)
            ], spacing: 12) {
                ForEach(recentAgents) { agent in
                    recentAgentCard(agent)
                }
            }
        }
        .frame(maxWidth: 660)
    }

    private func recentAgentCard(_ agent: Agent) -> some View {
        Button {
            onStartAgent(agent)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: agent.icon)
                    .font(.title3)
                    .foregroundStyle(Color.fromAgentColor(agent.color))
                    .frame(width: 32, height: 32)
                    .background(Color.fromAgentColor(agent.color).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.name)
                        .font(.callout)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text(AgentDefaults.label(for: agent.model))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(10)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .xrayId("welcome.recentAgent.\(agent.id.uuidString)")
    }

    // MARK: - Agent Groups

    @ViewBuilder
    private var agentGroupsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AGENT GROUPS")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.tertiary)
                .xrayId("welcome.agentGroups")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(enabledGroups.prefix(6)) { group in
                    welcomeGroupCard(group)
                }
            }
        }
        .frame(maxWidth: 660)
    }

    private func welcomeGroupCard(_ group: AgentGroup) -> some View {
        Button {
            onStartGroup(group)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(group.icon)
                        .font(.title3)
                    Text(group.name)
                        .font(.callout)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Spacer()
                }
                Text(groupAgentNames(for: group))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(10)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .xrayId("welcome.groupCard.\(group.id.uuidString)")
    }

    private func groupAgentNames(for group: AgentGroup) -> String {
        let names = group.agentIds.compactMap { agentId in
            allAgents.first { $0.id == agentId }?.name
        }
        guard !names.isEmpty else { return "No agents" }
        return names.joined(separator: ", ")
    }

    // MARK: - Helpers

    private func isGitRepo(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: (path as NSString).appendingPathComponent(".git"))
    }

    private func abbreviatePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

// MARK: - Change Project Sheet

/// Modal sheet for switching/creating projects. Shown from WelcomeView and ProjectPickerView.
struct ChangeProjectSheet: View {
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var recentProjects: [String] = []
    @State private var cloneURL = ""
    @State private var showCloneField = false
    @State private var isCloning = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Choose Project")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Browse section
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            browseFolder()
                        } label: {
                            HStack {
                                Image(systemName: "folder")
                                    .frame(width: 20)
                                Text("Open Existing Folder\u{2026}")
                                Spacer()
                            }
                            .padding(10)
                            .background(.background)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .xrayId("changeProject.browseButton")
                    }

                    // Clone section
                    VStack(alignment: .leading, spacing: 8) {
                        if showCloneField {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.down.circle")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20)
                                TextField("GitHub URL or user/repo", text: $cloneURL)
                                    .textFieldStyle(.roundedBorder)
                                    .onSubmit { cloneRepo() }
                                    .xrayId("changeProject.cloneURLField")
                                Button("Clone") { cloneRepo() }
                                    .disabled(cloneURL.trimmingCharacters(in: .whitespaces).isEmpty || isCloning)
                                    .xrayId("changeProject.cloneButton")
                                Button {
                                    showCloneField = false
                                    cloneURL = ""
                                } label: {
                                    Image(systemName: "xmark")
                                }
                                .buttonStyle(.plain)
                                .xrayId("changeProject.cancelCloneButton")
                                .accessibilityLabel("Cancel clone")
                            }
                            .padding(10)
                            .background(.background)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary, lineWidth: 1))

                            if isCloning {
                                ProgressView("Cloning\u{2026}")
                                    .padding(.leading, 30)
                            }
                        } else {
                            Button {
                                showCloneField = true
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.down.circle")
                                        .frame(width: 20)
                                    Text("Clone from GitHub\u{2026}")
                                    Spacer()
                                }
                                .padding(10)
                                .background(.background)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .xrayId("changeProject.cloneRepoButton")
                        }
                    }

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    // Recent projects
                    if !recentProjects.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            Text("RECENT PROJECTS")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.tertiary)

                            ForEach(recentProjects.prefix(8), id: \.self) { path in
                                Button {
                                    RecentDirectories.add(path)
                                    onSelect(path)
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: isGitRepo(path) ? "externaldrive.badge.checkmark" : "folder")
                                            .font(.body)
                                            .foregroundStyle(isGitRepo(path) ? .green : .secondary)
                                            .frame(width: 20)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text((path as NSString).lastPathComponent)
                                                .font(.callout)
                                                .fontWeight(.medium)
                                                .lineLimit(1)
                                            Text(abbreviatePath(path))
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                    }
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 10)
                                    .background(.background)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                .xrayId("changeProject.recent.\(path.hashValue)")
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 400, minHeight: 300)
        .onAppear { recentProjects = RecentDirectories.load() }
    }

    // MARK: - Actions

    private func browseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        panel.message = "Choose a project folder (or create a new one)"
        if panel.runModal() == .OK, let url = panel.url {
            let path = url.path
            RecentDirectories.add(path)
            onSelect(path)
        }
    }

    private func cloneRepo() {
        let repoInput = cloneURL.trimmingCharacters(in: .whitespaces)
        guard !repoInput.isEmpty else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Clone Here"
        panel.message = "Choose where to clone the repository"
        guard panel.runModal() == .OK, let destURL = panel.url else { return }

        let repoName = repoInput.split(separator: "/").last.map(String.init) ?? "repo"
        let clonePath = destURL.appendingPathComponent(repoName).path

        isCloning = true
        errorMessage = nil
        Task {
            do {
                try await GitHubIntegration.ensureClone(
                    repoInput: repoInput,
                    branch: "main",
                    destinationPath: clonePath
                )
                await MainActor.run {
                    isCloning = false
                    RecentDirectories.add(clonePath)
                    onSelect(clonePath)
                }
            } catch {
                await MainActor.run {
                    isCloning = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func isGitRepo(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: (path as NSString).appendingPathComponent(".git"))
    }

    private func abbreviatePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
