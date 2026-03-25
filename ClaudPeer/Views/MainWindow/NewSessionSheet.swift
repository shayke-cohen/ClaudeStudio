import SwiftUI
import SwiftData

struct NewSessionSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @Query(sort: \Agent.name) private var agents: [Agent]
    @Query(sort: \Session.startedAt, order: .reverse) private var recentSessions: [Session]

    /// Agents selected for this conversation (one or more = group-capable).
    @State private var selectedAgentIds: Set<UUID> = []
    @State private var isFreeformChat = false
    @State private var modelOverride = ""
    @State private var sessionMode: SessionMode = .interactive
    @State private var mission = ""
    @State private var workingDirectory = ""
    @State private var showOptions = false
    @State private var didSetInitialDir = false

    private enum WorkspaceTab: Int, Hashable {
        case localDirectory = 0
        case githubRepo = 1
    }

    private enum GitHubWorkspaceMode: Int, Hashable {
        case clone = 0
        case worktree = 1
    }

    @State private var workspaceTab: WorkspaceTab = .localDirectory
    @State private var githubRepoInput = ""
    @State private var githubBranch = ""
    @State private var githubMode: GitHubWorkspaceMode = .clone
    @State private var worktreeBranch = ""
    @State private var githubIssueNumber = ""
    @State private var fetchedIssueTitle: String?
    @State private var isWorkspacePreparing = false
    @State private var workspacePrepError: String?
    @State private var showCreateFromPrompt = false
    @State private var createFromPromptText = ""
    @State private var recentDirs: [String] = []
    @State private var recentRepos: [String] = []
    @Query(sort: \Skill.name) private var allSkills: [Skill]
    @Query(sort: \MCPServer.name) private var allMCPs: [MCPServer]

    private var enabledAgents: [Agent] {
        agents.filter { $0.isEnabled }
    }

    private var recentAgents: [Agent] {
        var seen = Set<UUID>()
        var result: [Agent] = []
        for session in recentSessions {
            guard let agent = session.agent, agent.isEnabled, !seen.contains(agent.id) else { continue }
            seen.insert(agent.id)
            result.append(agent)
            if result.count >= 3 { break }
        }
        return result
    }

    private var orderedSelectedAgents: [Agent] {
        agents.filter { selectedAgentIds.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var canStartSession: Bool {
        (isFreeformChat || !selectedAgentIds.isEmpty) && !isWorkspacePreparing
    }

    private var isGithubRepoInputValid: Bool {
        let trimmed = githubRepoInput.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && (trimmed.contains("/") || trimmed.hasPrefix("https://") || trimmed.hasPrefix("git@"))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    createFromPromptSection
                    if !recentAgents.isEmpty {
                        recentAgentsRow
                    }
                    agentPicker
                    if !orderedSelectedAgents.isEmpty {
                        Text("Selected: \(orderedSelectedAgents.map(\.name).joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .xrayId("newSession.selectedAgentsSummary")
                    }
                    workspaceSection
                    optionsSection
                }
                .padding(24)
            }
            Divider()
            footer
        }
        .frame(width: 620, height: 620)
        .onAppear {
            recentDirs = RecentDirectories.load()
            recentRepos = RecentRepos.load()
            if !didSetInitialDir, workingDirectory.isEmpty,
               let instanceDir = appState.instanceWorkingDirectory {
                workingDirectory = instanceDir
                didSetInitialDir = true
            }
        }
        .onChange(of: selectedAgentIds) { _, newIds in
            if newIds.count == 1, let agentId = newIds.first,
               let agent = agents.first(where: { $0.id == agentId }) {
                if let repo = agent.githubRepo?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !repo.isEmpty, githubRepoInput.isEmpty {
                    githubRepoInput = repo
                    githubBranch = agent.githubDefaultBranch?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "main"
                    workspaceTab = .githubRepo
                }
                if let dir = agent.defaultWorkingDirectory, !dir.isEmpty, workingDirectory.isEmpty {
                    workingDirectory = dir
                }
            }
            workspacePrepError = nil
        }
    }

    // MARK: - Workspace

    @ViewBuilder
    private var workspaceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Workspace")
                .font(.headline)

            Picker("", selection: $workspaceTab) {
                Text("Local Directory").tag(WorkspaceTab.localDirectory)
                Text("GitHub Repo").tag(WorkspaceTab.githubRepo)
            }
            .pickerStyle(.segmented)
            .xrayId("newSession.workspaceTabPicker")

            switch workspaceTab {
            case .localDirectory:
                localDirectoryTab
            case .githubRepo:
                githubRepoTab
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var localDirectoryTab: some View {
        if !recentDirs.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(recentDirs.prefix(6).enumerated()), id: \.offset) { index, dir in
                        let displayName = (dir as NSString).lastPathComponent
                        Button {
                            workingDirectory = dir
                        } label: {
                            Text(displayName)
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(workingDirectory == dir ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
                                .clipShape(Capsule())
                                .overlay {
                                    Capsule()
                                        .strokeBorder(workingDirectory == dir ? Color.accentColor : .clear, lineWidth: 1.5)
                                }
                        }
                        .buttonStyle(.plain)
                        .help(dir)
                        .xrayId("newSession.recentDirChip.\(index)")
                        .accessibilityLabel("Select recent directory: \(displayName) at \(dir)")
                    }
                }
            }
        }

        HStack(alignment: .firstTextBaseline) {
            TextField("~/projects/my-app", text: $workingDirectory)
                .textFieldStyle(.roundedBorder)
                .xrayId("newSession.workingDirectoryField")
            Button {
                pickDirectory()
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Browse for directory")
            .xrayId("newSession.browseDirectoryButton")
            .accessibilityLabel("Browse for directory")
        }
    }

    @ViewBuilder
    private var githubRepoTab: some View {
        if !recentRepos.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(recentRepos.prefix(6).enumerated()), id: \.offset) { index, repo in
                        Button {
                            githubRepoInput = repo
                            githubBranch = "main"
                        } label: {
                            Text(repo)
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(githubRepoInput == repo ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
                                .clipShape(Capsule())
                                .overlay {
                                    Capsule()
                                        .strokeBorder(githubRepoInput == repo ? Color.accentColor : .clear, lineWidth: 1.5)
                                }
                        }
                        .buttonStyle(.plain)
                        .help(repo)
                        .xrayId("newSession.recentRepoChip.\(index)")
                        .accessibilityLabel("Select recent repository: \(repo)")
                    }
                }
            }
        }

        HStack(alignment: .firstTextBaseline) {
            Text("Repo")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)
            TextField("org/repo or URL", text: $githubRepoInput)
                .textFieldStyle(.roundedBorder)
                .xrayId("newSession.githubRepoField")
        }

        HStack(alignment: .firstTextBaseline) {
            Text("Branch")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)
            TextField("main", text: $githubBranch)
                .textFieldStyle(.roundedBorder)
                .xrayId("newSession.githubBranchField")
        }

        HStack(alignment: .firstTextBaseline) {
            Text("Mode")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)
            Picker("", selection: $githubMode) {
                Text("Clone").tag(GitHubWorkspaceMode.clone)
                Text("Worktree").tag(GitHubWorkspaceMode.worktree)
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
            .labelsHidden()
            .xrayId("newSession.githubModePicker")
        }

        if githubMode == .worktree {
            HStack(alignment: .firstTextBaseline) {
                Text("WT Branch")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .trailing)
                TextField("feature/my-branch", text: $worktreeBranch)
                    .textFieldStyle(.roundedBorder)
                    .xrayId("newSession.worktreeBranchField")
            }
        }

        if isGithubRepoInputValid {
            let repo = githubRepoInput.trimmingCharacters(in: .whitespacesAndNewlines)
            if githubMode == .clone {
                Text("Path: \(WorkspaceResolver.cloneDestinationPath(repoInput: repo))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            } else {
                let branch = worktreeBranch.trimmingCharacters(in: .whitespacesAndNewlines)
                Text("Path: \(WorkspaceResolver.worktreeDestinationPath(repoInput: repo, branch: branch.isEmpty ? "branch" : branch))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
        }

        if let workspacePrepError {
            Text(workspacePrepError)
                .font(.caption)
                .foregroundStyle(.red)
                .xrayId("newSession.githubWorkspaceError")
        }

        HStack {
            if isWorkspacePreparing {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Preparing…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Validate / Clone") {
                Task { await prepareGithubClone() }
            }
            .disabled(!isGithubRepoInputValid || isWorkspacePreparing)
            .xrayId("newSession.githubValidateButton")
        }

        // GitHub issue (optional)
        Divider()
        HStack {
            Text("Issue:")
                .font(.caption)
            TextField("#123", text: $githubIssueNumber)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
                .xrayId("newSession.githubIssueField")
            if let title = fetchedIssueTitle {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("Fetch") {
                Task { await fetchIssue() }
            }
            .disabled(githubIssueNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !isGithubRepoInputValid)
            .xrayId("newSession.githubIssueFetchButton")
        }
        Text("Optional — fetches issue context into the agent's system prompt")
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }

    private func fetchIssue() async {
        let numberStr = githubIssueNumber.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        let repo = githubRepoInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let number = Int(numberStr), !repo.isEmpty else {
            workspacePrepError = "Enter a valid issue number"
            return
        }
        do {
            let issue = try await GitHubIntegration.fetchIssue(repoInput: repo, issueNumber: number)
            fetchedIssueTitle = issue.title
            if mission.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                mission = issue.body
            }
        } catch {
            workspacePrepError = error.localizedDescription
        }
    }

    private func prepareGithubClone() async {
        let repo = githubRepoInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repo.isEmpty else { return }
        isWorkspacePreparing = true
        workspacePrepError = nil
        defer { isWorkspacePreparing = false }
        let branch = {
            let b = githubBranch.trimmingCharacters(in: .whitespacesAndNewlines)
            return b.isEmpty ? "main" : b
        }()
        do {
            if githubMode == .clone {
                let path = WorkspaceResolver.cloneDestinationPath(repoInput: repo)
                try await GitHubIntegration.ensureClone(repoInput: repo, branch: branch, destinationPath: path)
            } else {
                let wtBranch = worktreeBranch.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !wtBranch.isEmpty else {
                    workspacePrepError = "Branch name is required for worktree mode."
                    return
                }
                let basePath = WorkspaceResolver.cloneDestinationPath(repoInput: repo)
                let wtPath = WorkspaceResolver.worktreeDestinationPath(repoInput: repo, branch: wtBranch)
                try await GitHubIntegration.ensureWorktree(
                    repoInput: repo, branch: wtBranch,
                    baseClonePath: basePath, worktreePath: wtPath
                )
            }
        } catch {
            workspacePrepError = error.localizedDescription
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack {
            Text("New Session")
                .font(.title2)
                .fontWeight(.semibold)
                .xrayId("newSession.title")
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .help("Close")
            .xrayId("newSession.closeButton")
            .accessibilityLabel("Close")
        }
        .padding(16)
    }

    // MARK: - Create from Prompt

    @ViewBuilder
    private var createFromPromptSection: some View {
        DisclosureGroup("Create agent from prompt", isExpanded: $showCreateFromPrompt) {
            VStack(alignment: .leading, spacing: 10) {
                if appState.generatedAgentSpec == nil && !appState.isGeneratingAgent {
                    HStack(spacing: 8) {
                        TextField("Describe an agent to create...", text: $createFromPromptText)
                            .textFieldStyle(.roundedBorder)
                            .xrayId("newSession.fromPrompt.textField")
                        Button {
                            generateAgentFromPrompt()
                        } label: {
                            Label("Generate", systemImage: "wand.and.stars")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(createFromPromptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .xrayId("newSession.fromPrompt.generateButton")
                    }
                    Text("e.g. \"A code reviewer focused on security\"")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if appState.isGeneratingAgent {
                    HStack {
                        ProgressView().scaleEffect(0.7)
                        Text("Generating...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .xrayId("newSession.fromPrompt.loading")
                }

                if let error = appState.generateAgentError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                        Button("Retry") { generateAgentFromPrompt() }
                            .controlSize(.small)
                            .xrayId("newSession.fromPrompt.retryButton")
                    }
                }

                if let spec = appState.generatedAgentSpec {
                    AgentPreviewCard(
                        spec: spec,
                        onSave: { agent in
                            modelContext.insert(agent)
                            try? modelContext.save()
                            isFreeformChat = false
                            selectedAgentIds = [agent.id]
                            appState.generatedAgentSpec = nil
                            appState.generateAgentError = nil
                        },
                        onSaveAndStart: { agent in
                            modelContext.insert(agent)
                            try? modelContext.save()
                            isFreeformChat = false
                            selectedAgentIds = [agent.id]
                            appState.generatedAgentSpec = nil
                            appState.generateAgentError = nil
                            Task { await createSessionAsync() }
                        },
                        onCancel: {
                            appState.generatedAgentSpec = nil
                            appState.generateAgentError = nil
                        }
                    )
                }
            }
            .padding(.top, 8)
        }
        .font(.headline)
        .xrayId("newSession.fromPrompt.disclosure")
    }

    private func generateAgentFromPrompt() {
        let skillEntries = allSkills.map { skill in
            SkillCatalogEntry(
                id: skill.id.uuidString,
                name: skill.name,
                description: skill.skillDescription,
                category: skill.category
            )
        }
        let mcpEntries = allMCPs.map { mcp in
            MCPCatalogEntry(
                id: mcp.id.uuidString,
                name: mcp.name,
                description: mcp.serverDescription
            )
        }
        appState.requestAgentGeneration(
            prompt: createFromPromptText.trimmingCharacters(in: .whitespacesAndNewlines),
            skills: skillEntries,
            mcps: mcpEntries
        )
    }

    // MARK: - Recent Agents

    @ViewBuilder
    private var recentAgentsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                ForEach(recentAgents) { agent in
                    Button {
                        isFreeformChat = false
                        selectedAgentIds = [agent.id]
                        modelOverride = ""
                        if let dir = agent.defaultWorkingDirectory, !dir.isEmpty {
                            workingDirectory = dir
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: agent.icon)
                                .foregroundStyle(Color.fromAgentColor(agent.color))
                            Text(agent.name)
                                .font(.callout)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selectedAgentIds == [agent.id] && !isFreeformChat
                            ? Color.fromAgentColor(agent.color).opacity(0.12)
                            : Color.clear
                        )
                        .clipShape(Capsule())
                        .overlay {
                            Capsule()
                                .strokeBorder(
                                    selectedAgentIds == [agent.id] && !isFreeformChat
                                        ? Color.fromAgentColor(agent.color)
                                        : .secondary.opacity(0.3),
                                    lineWidth: selectedAgentIds == [agent.id] && !isFreeformChat ? 2 : 1
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .xrayId("newSession.recentAgent.\(agent.id.uuidString)")
                }
                Spacer()
            }
        }
    }

    // MARK: - Agent Picker

    @ViewBuilder
    private var agentPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("All Agents (select one or more)")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 10)
            ], spacing: 10) {
                agentPickerCard(
                    icon: "bubble.left.and.bubble.right",
                    name: "Freeform",
                    detail: "No agent",
                    color: .secondary,
                    isSelected: isFreeformChat && selectedAgentIds.isEmpty,
                    identifier: "newSession.agentCard.freeform"
                ) {
                    isFreeformChat = true
                    selectedAgentIds.removeAll()
                    modelOverride = "claude-sonnet-4-6"
                }

                ForEach(enabledAgents) { agent in
                    agentPickerCard(
                        icon: agent.icon,
                        name: agent.name,
                        detail: agent.model,
                        color: Color.fromAgentColor(agent.color),
                        isSelected: selectedAgentIds.contains(agent.id),
                        identifier: "newSession.agentCard.\(agent.id.uuidString)"
                    ) {
                        isFreeformChat = false
                        if selectedAgentIds.contains(agent.id) {
                            selectedAgentIds.remove(agent.id)
                        } else {
                            selectedAgentIds.insert(agent.id)
                            modelOverride = ""
                            if let dir = agent.defaultWorkingDirectory, !dir.isEmpty {
                                workingDirectory = dir
                            }
                        }
                    }
                }
            }
        }
    }

    private func agentPickerCard(icon: String, name: String, detail: String, color: Color, isSelected: Bool, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                    .frame(width: 32, height: 32)
                Text(name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
            .background(isSelected ? color.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? color.opacity(1.0) : color.opacity(0.0), lineWidth: 2)
            }
            .overlay {
                if !isSelected {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.secondary.opacity(0.2), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .help(name)
        .xrayId(identifier)
    }

    // MARK: - Options

    @ViewBuilder
    private var optionsSection: some View {
        DisclosureGroup("Session Options", isExpanded: $showOptions) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Model")
                        .frame(width: 80, alignment: .trailing)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $modelOverride) {
                        if selectedAgentIds.count <= 1 {
                            Text("Inherit from Agent").tag("")
                        }
                        Text("Sonnet 4.6").tag("claude-sonnet-4-6")
                        Text("Opus 4.6").tag("claude-opus-4-6")
                        Text("Haiku 4.5").tag("claude-haiku-4-5-20251001")
                    }
                    .labelsHidden()
                    .frame(width: 220)
                    .xrayId("newSession.modelPicker")
                }

                HStack(alignment: .firstTextBaseline) {
                    Text("Mode")
                        .frame(width: 80, alignment: .trailing)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $sessionMode) {
                        Text("Interactive").tag(SessionMode.interactive)
                            .help("You guide the agent step by step")
                        Text("Autonomous").tag(SessionMode.autonomous)
                            .help("Agent works independently toward a goal")
                        Text("Worker").tag(SessionMode.worker)
                            .help("Background task with no interaction")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 280)
                    .labelsHidden()
                    .xrayId("newSession.modePicker")
                }

                modeDescription

                HStack(alignment: .top) {
                    Text("Mission")
                        .frame(width: 80, alignment: .trailing)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                    TextField("Describe the goal for this session...", text: $mission, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                        .xrayId("newSession.missionField")
                }
            }
            .padding(.top, 8)
        }
        .xrayId("newSession.optionsDisclosure")
    }

    @ViewBuilder
    private var modeDescription: some View {
        HStack {
            Spacer().frame(width: 84)
            Group {
                switch sessionMode {
                case .interactive:
                    Text("You guide the agent step by step, reviewing each action.")
                case .autonomous:
                    Text("The agent works independently toward a goal you define.")
                case .worker:
                    Text("Background task that runs without interaction.")
                }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
            .xrayId("newSession.modeDescription")
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        HStack {
            Text("⌘N this sheet  ·  ⌘⇧N quick chat")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Quick Chat") {
                createQuickChat()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .xrayId("newSession.quickChatButton")
            Button("Start Session") {
                Task { await createSessionAsync() }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return)
            .disabled(!canStartSession)
            .xrayId("newSession.startSessionButton")
        }
        .padding(16)
    }

    // MARK: - Actions

    private func createSessionAsync() async {
        let missionText = mission.trimmingCharacters(in: .whitespacesAndNewlines)
        let dirText = workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)

        // Resolve workspace based on active tab
        var resolvedWd = ""
        var resolvedWsType: WorkspaceType?
        var resolvedWorktreePath: String?

        switch workspaceTab {
        case .localDirectory:
            resolvedWd = dirText
            if !dirText.isEmpty {
                resolvedWsType = .explicit(path: dirText)
                RecentDirectories.add(dirText)
            }

        case .githubRepo:
            let repo = githubRepoInput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !repo.isEmpty else { break }
            let branch = {
                let b = githubBranch.trimmingCharacters(in: .whitespacesAndNewlines)
                return b.isEmpty ? "main" : b
            }()

            if githubMode == .clone {
                isWorkspacePreparing = true
                workspacePrepError = nil
                defer { isWorkspacePreparing = false }
                let path = WorkspaceResolver.cloneDestinationPath(repoInput: repo)
                do {
                    try await GitHubIntegration.ensureClone(repoInput: repo, branch: branch, destinationPath: path)
                } catch {
                    workspacePrepError = error.localizedDescription
                    return
                }
                resolvedWd = path
                resolvedWsType = .githubClone(repoUrl: repo)
                RecentRepos.add(repo)
            } else {
                let wtBranch = worktreeBranch.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !wtBranch.isEmpty else {
                    workspacePrepError = "Branch name is required for worktree mode."
                    return
                }
                isWorkspacePreparing = true
                workspacePrepError = nil
                defer { isWorkspacePreparing = false }
                let basePath = WorkspaceResolver.cloneDestinationPath(repoInput: repo)
                let wtPath = WorkspaceResolver.worktreeDestinationPath(repoInput: repo, branch: wtBranch)
                do {
                    try await GitHubIntegration.ensureWorktree(
                        repoInput: repo, branch: wtBranch,
                        baseClonePath: basePath, worktreePath: wtPath
                    )
                } catch {
                    workspacePrepError = error.localizedDescription
                    return
                }
                resolvedWd = wtPath
                resolvedWsType = .worktree(repoUrl: repo, branch: wtBranch)
                resolvedWorktreePath = wtPath
                RecentRepos.add(repo)
            }
        }

        // Freeform chat
        if isFreeformChat || selectedAgentIds.isEmpty {
            let conversation = Conversation(topic: "New Chat")
            let userParticipant = Participant(type: .user, displayName: "You")
            userParticipant.conversation = conversation
            conversation.participants.append(userParticipant)
            modelContext.insert(conversation)
            try? modelContext.save()
            appState.selectedConversationId = conversation.id
            dismiss()
            return
        }

        let selectedList = orderedSelectedAgents
        guard !selectedList.isEmpty else {
            dismiss()
            return
        }

        let topic: String
        if selectedList.count == 1 {
            topic = selectedList[0].name
        } else {
            topic = selectedList.map(\.name).joined(separator: ", ")
        }

        let conversation = Conversation(topic: topic)
        let userParticipant = Participant(type: .user, displayName: "You")
        userParticipant.conversation = conversation
        conversation.participants.append(userParticipant)

        // Issue context for system prompt
        let issueContext: String? = {
            if let title = fetchedIssueTitle, !title.isEmpty {
                let num = githubIssueNumber.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
                return "GitHub Issue #\(num): \(title)"
            }
            return nil
        }()

        for agent in selectedList {
            let wd: String
            if !resolvedWd.isEmpty {
                wd = resolvedWd
            } else if selectedList.count > 1 {
                wd = ""
            } else {
                wd = agent.defaultWorkingDirectory ?? appState.instanceWorkingDirectory ?? ""
            }

            let session = Session(
                agent: agent,
                mission: missionText.isEmpty ? nil : missionText,
                mode: sessionMode,
                workingDirectory: wd
            )

            if let wsType = resolvedWsType {
                session.workspaceType = wsType
                if let wtPath = resolvedWorktreePath {
                    session.worktreePath = wtPath
                }
            } else if !wd.isEmpty {
                session.workspaceType = .explicit(path: wd)
            }

            if let issue = issueContext {
                session.githubIssue = issue
            }

            session.conversations = [conversation]
            conversation.sessions.append(session)

            let agentParticipant = Participant(
                type: .agentSession(sessionId: session.id),
                displayName: agent.name
            )
            agentParticipant.conversation = conversation
            conversation.participants.append(agentParticipant)

            modelContext.insert(session)
        }

        modelContext.insert(conversation)
        if selectedList.count > 1, resolvedWd.isEmpty {
            GroupWorkingDirectory.ensureShared(
                for: conversation,
                instanceDefault: appState.instanceWorkingDirectory,
                modelContext: modelContext
            )
        }
        try? modelContext.save()
        appState.selectedConversationId = conversation.id
        dismiss()
    }

    private func createQuickChat() {
        let conversation = Conversation(topic: "New Chat")
        let userParticipant = Participant(type: .user, displayName: "You")
        userParticipant.conversation = conversation
        conversation.participants.append(userParticipant)
        modelContext.insert(conversation)
        try? modelContext.save()
        appState.selectedConversationId = conversation.id
        dismiss()
    }

    private func pickDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            workingDirectory = url.path(percentEncoded: false)
        }
    }
}
