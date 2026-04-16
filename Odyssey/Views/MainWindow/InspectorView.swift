import SwiftUI
import SwiftData
import AppKit

private struct WorkspaceGitState {
    var isGitRepo = false
    var currentBranch: String?
    var changeCount = 0
    var localBranches: [GitBranchRef] = []
    var remoteBranches: [GitBranchRef] = []
}

struct InspectorView: View {
    let conversation: Conversation
    @Environment(\.modelContext) private var modelContext
    @Environment(WindowState.self) private var windowState: WindowState
    @Query(sort: \Session.startedAt) private var allSessions: [Session]
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var sharedRoomService: SharedRoomService
    @Query private var allGroups: [AgentGroup]
    @Query private var allAgents: [Agent]
    @AppStorage(FeatureFlags.showAdvancedKey, store: AppSettings.store) private var masterFlag = false
    @AppStorage(FeatureFlags.federationKey, store: AppSettings.store) private var federationFlag = false
    @State private var now = Date()
    @State private var editingGroup: AgentGroup?
    @State private var instructionExpanded = false
    @State private var parentConversationTitle: String?
    @State private var groupRecentConversations: [Conversation] = []
    @State private var workspaceGitState = WorkspaceGitState()
    @State private var workspaceGitError: String?
    @State private var isWorkspaceGitLoading = false
    @State private var isFetchingBranches = false
    @State private var switchingBranchName: String?
    // editingWorkingDirectory removed — project dir is per-window
    // workingDirectoryDraft removed — project dir is per-window, not editable per-session

    private let durationTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var federationEnabled: Bool { FeatureFlags.isEnabled(FeatureFlags.federationKey) || (masterFlag && federationFlag) }

    private var sourceGroup: AgentGroup? {
        guard let gid = conversation.sourceGroupId else { return nil }
        return allGroups.first { $0.id == gid }
    }

    private var isGroupConversation: Bool { sourceGroup != nil }

    private var availableTabs: [WindowInspectorTab] {
        var tabs: [WindowInspectorTab] = [.info, .blackboard]
        if hasWorkingDirectory { tabs.append(.files) }
        if isGroupConversation { tabs.append(.group) }
        return tabs
    }

    /// Sessions for this conversation — uses the relationship first, falls back to
    /// a manual query when the SwiftData many-to-many inverse returns empty.
    private var orderedSessions: [Session] {
        let relSessions = conversation.sessions
        if !relSessions.isEmpty {
            return relSessions.sorted { $0.startedAt < $1.startedAt }
        }
        // Fallback: find sessions whose conversations include this one
        return allSessions.filter { session in
            session.conversations.contains { $0.id == conversation.id }
        }
    }

    private var primarySession: Session? {
        orderedSessions.first
    }

    private var relevantBlackboardKeys: Set<String> {
        Set(conversation.messages.compactMap { message in
            guard message.type == .blackboardUpdate else { return nil }
            return message.toolName
        })
    }

    private var relevantBlackboardWriters: Set<String> {
        let persistedWriters: [String] = conversation.messages.compactMap { message -> String? in
            guard message.type == .blackboardUpdate else { return nil }
            return message.toolInput?.lowercased()
        }
        let sessionWriters: [String] = orderedSessions.compactMap { session -> String? in
            session.agent?.name.lowercased()
        }
        return Set(persistedWriters + sessionWriters)
    }

    private func liveInfo(for session: Session) -> AppState.SessionInfo? {
        appState.activeSessions[session.id]
    }

    private var hasWorkingDirectory: Bool {
        !windowState.projectDirectory.isEmpty
    }

    private var workspaceDirectoryPath: String {
        conversation.worktreePath ?? windowState.projectDirectory
    }

    private var fileExplorerDirectoryPath: String {
        if let worktreePath = conversation.worktreePath,
           WorktreeManager.isUsableWorktree(at: worktreePath) {
            return worktreePath
        }
        return windowState.projectDirectory
    }

    private var workspaceDirectoryURL: URL? {
        let trimmed = workspaceDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(fileURLWithPath: trimmed)
    }

    var body: some View {
        @Bindable var windowState = windowState
        VStack(spacing: 0) {
            if availableTabs.count > 1 {
                InspectorTabBar(
                    tabs: availableTabs,
                    selection: $windowState.selectedInspectorTab
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .xrayId("inspector.tabPicker")

                Divider()
            }

            switch windowState.selectedInspectorTab {
            case .info:
                infoContent
            case .blackboard:
                BlackboardInspectorPanel(
                    conversation: conversation,
                    relevantKeys: relevantBlackboardKeys,
                    relevantWriters: relevantBlackboardWriters
                )
            case .files:
                FileExplorerView(
                    workingDirectory: fileExplorerDirectoryPath,
                    refreshTrigger: appState.fileTreeRefreshTrigger,
                    selectionRequest: windowState.inspectorFileSelectionRequest,
                    onConsumeSelectionRequest: { requestId in
                        windowState.consumeInspectorFileSelectionRequest(id: requestId)
                    }
                )
                .id(fileExplorerDirectoryPath)
            case .group:
                if let group = sourceGroup {
                    groupContent(group)
                } else {
                    infoContent
                }
            }
        }
        .frame(minWidth: 240, idealWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(durationTimer) { _ in
            now = Date()
        }
        .onChange(of: isGroupConversation) {
            normalizeSelectedTab()
        }
        .onAppear {
            normalizeSelectedTab()
            refreshDerivedInspectorState()
        }
        .onChange(of: conversation.id) { _, _ in
            normalizeSelectedTab()
            refreshDerivedInspectorState()
        }
        .onChange(of: conversation.parentConversationId) { _, _ in
            refreshDerivedInspectorState()
        }
        .onChange(of: conversation.sourceGroupId) { _, _ in
            refreshDerivedInspectorState()
        }
        .onChange(of: conversation.worktreePath) { _, _ in
            Task { await refreshWorkspaceGitInfo() }
        }
        .onChange(of: windowState.projectDirectory) { _, _ in
            Task { await refreshWorkspaceGitInfo() }
        }
        .onChange(of: appState.fileTreeRefreshTrigger) { _, _ in
            Task { await refreshWorkspaceGitInfo() }
        }
        .task(id: workspaceDirectoryPath) {
            await repairInvalidWorktreeIfNeeded()
            await refreshWorkspaceGitInfo()
        }
        .sheet(item: $editingGroup) { g in
            GroupEditorView(group: g)
        }
    }

    // MARK: - Info Content

    private var infoContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if orderedSessions.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        sectionLabel("Conversation", systemImage: "bubble.left.and.text.bubble.right")
                        InfoRow(label: "Topic", value: conversation.topic ?? "Untitled")
                        InfoRow(label: "Started", value: conversation.startedAt.formatted(.dateTime))
                    }
                    .inspectorSectionCard()
                } else if orderedSessions.count == 1, let session = orderedSessions.first {
                    sessionSection(session: session)
                    usageSection(session: session, agent: session.agent)
                    if let agent = session.agent {
                        agentSection(agent: agent)
                    }
                } else {
                    multiSessionsSection
                }
                if conversation.isSharedRoom && federationEnabled {
                    sharedRoomSection
                }
                if hasWorkingDirectory {
                    workspaceSection
                }
                historySection
            }
            .padding(12)
        }
        .xrayId("inspector.scrollView")
    }

    // MARK: - Session Section

    @ViewBuilder
    private var sharedRoomSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Shared Room", systemImage: "person.3.sequence")
            InfoRow(label: "Room ID", value: conversation.roomId ?? "Pending")
            InfoRow(label: "Role", value: conversation.roomRole?.rawValue.capitalized ?? "Unknown")
            InfoRow(label: "Status", value: conversation.roomStatus.rawValue.capitalized)
            InfoRow(label: "Sync", value: conversation.roomHistorySyncState.rawValue.capitalized)
            if let owner = conversation.roomOwnerUserId, !owner.isEmpty {
                InfoRow(label: "Owner", value: owner)
            }
            HStack {
                Button("Invite People") {
                    windowState.sharedRoomInviteConversationId = conversation.id
                    windowState.showSharedRoomInviteSheet = true
                }
                .buttonStyle(.bordered)
                .xrayId("inspector.sharedRoom.inviteButton")

                Button("Refresh Room") {
                    Task { try? await sharedRoomService.refreshConversation(conversation) }
                }
                .buttonStyle(.bordered)
                .xrayId("inspector.sharedRoom.refreshButton")
            }
        }
        .inspectorSectionCard()
    }

    @ViewBuilder
    private func sessionSection(session: Session) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Session", systemImage: "terminal")
                .xrayId("inspector.sessionHeading")

            InfoRow(label: "Status", value: appState.sessionActivity[session.id.uuidString]?.displayLabel ?? session.status.rawValue.capitalized)
            InfoRow(label: "Model", value: modelShortName(session.model ?? session.agent?.model ?? ""))
            InfoRow(label: "Mode", value: session.mode.rawValue.capitalized)
            InfoRow(label: "Duration", value: durationString(from: conversation.startedAt))
        }
        .inspectorSectionCard()
    }

    @ViewBuilder
    private var multiSessionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Sessions", systemImage: "person.3")
                .xrayId("inspector.sessionsListHeading")

            ForEach(orderedSessions, id: \.id) { session in
                multiSessionRow(session: session)
            }

            sessionTotalsRow
        }
        .inspectorSectionCard()
    }

    @ViewBuilder
    private var sessionTotalsRow: some View {
        let totalTokens = orderedSessions.reduce(0) { sum, s in
            sum + (liveInfo(for: s)?.tokenCount ?? s.tokenCount)
        }
        let totalCost = orderedSessions.reduce(0.0) { sum, s in
            sum + (liveInfo(for: s)?.cost ?? s.totalCost)
        }
        let totalToolCalls = orderedSessions.reduce(0) { sum, s in
            sum + (liveInfo(for: s)?.toolCallCount ?? s.toolCallCount)
        }

        Divider()

        VStack(alignment: .leading, spacing: 6) {
            Text("Totals")
                .font(.subheadline)
                .fontWeight(.semibold)
            InfoRow(label: "Sessions", value: "\(orderedSessions.count)")
            InfoRow(label: "Tokens", value: formatNumber(totalTokens))
            InfoRow(label: "Cost", value: String(format: "$%.4f", totalCost))
            InfoRow(label: "Tool Calls", value: "\(totalToolCalls)")
        }
        .xrayId("inspector.sessionTotals")
    }

    @ViewBuilder
    private func multiSessionRow(session: Session) -> some View {
        let live = liveInfo(for: session)
        let agent = session.agent
        let liveTokens = live?.tokenCount ?? session.tokenCount
        let liveCost = live?.cost ?? session.totalCost
        let activityState = appState.sessionActivity[session.id.uuidString]
        let statusText = activityState?.displayLabel ?? session.status.rawValue.capitalized

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(agent?.name ?? "Agent")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                if let state = activityState, state.isActive {
                    ActivityDot(state: state)
                        .frame(width: 6, height: 6)
                }
            }
            InfoRow(label: "Status", value: statusText)
            InfoRow(label: "Model", value: modelShortName(session.model ?? agent?.model ?? ""))
            InfoRow(label: "Tokens", value: formatNumber(liveTokens))
            InfoRow(label: "Cost", value: String(format: "$%.4f", liveCost))
            InfoRow(label: "Tool Calls", value: "\(live?.toolCallCount ?? session.toolCallCount)")
            if let agent {
                Button {
                    windowState.openLibrary(.build, buildSection: .agents)
                } label: {
                    Text("Open \(agent.name) in editor")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .xrayId("inspector.sessionRow.agentLink.\(session.id.uuidString)")
            }
        }
        .padding(.vertical, 4)
        .xrayId("inspector.sessionRow.\(session.id.uuidString)")
    }

    // MARK: - Usage Section

    @ViewBuilder
    private func usageSection(session: Session, agent: Agent?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Usage", systemImage: "chart.bar")
                .xrayId("inspector.usageHeading")

            let live = liveInfo(for: session)
            let liveTokens = live?.tokenCount ?? session.tokenCount
            let liveCost = live?.cost ?? session.totalCost
            let maxTurns = agent?.maxTurns ?? 30
            let toolCalls = live?.toolCallCount ?? session.toolCallCount

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                ],
                alignment: .leading,
                spacing: 8
            ) {
                InspectorMetricTile(title: "Tokens", value: formatNumber(liveTokens))
                InspectorMetricTile(title: "Cost", value: String(format: "$%.4f", liveCost))
                InspectorMetricTile(title: "Tool Calls", value: "\(toolCalls)")
                InspectorMetricTile(title: "Turns", value: "\(toolCalls) / \(maxTurns)")
                    .xrayId("inspector.turnsLabel")
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Turn budget")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(max(0, maxTurns - toolCalls)) remaining")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                ProgressView(value: min(Double(toolCalls), Double(maxTurns)), total: Double(maxTurns))
                    .tint(turnProgressColor(used: toolCalls, max: maxTurns))
                    .xrayId("inspector.turnsProgress")
            }
        }
        .inspectorSectionCard()
    }

    // MARK: - Workspace Section

    @ViewBuilder
    private var workspaceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Project", systemImage: "folder")
                .xrayId("inspector.workspaceHeading")

            VStack(alignment: .leading, spacing: 4) {
                Text("Directory")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(abbreviatePath(workspaceDirectoryPath))
                    .font(.callout)
                    .fontWeight(.medium)
                    .textSelection(.enabled)
                    .lineLimit(3)
            }

            if workspaceGitState.isGitRepo {
                InfoRow(label: "Branch", value: workspaceGitState.currentBranch ?? "Unknown")
                InfoRow(label: "Repo State", value: repoStateLabel)
            } else {
                InfoRow(label: "Git", value: "Not a repository")
            }

            if let message = workspaceGitError, !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .xrayId("inspector.workspaceError")
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                ],
                alignment: .leading,
                spacing: 8
            ) {
                workspaceBranchMenu

                Button {
                    Task { await fetchBranches() }
                } label: {
                    Label(isFetchingBranches ? "Fetching…" : "Fetch", systemImage: "arrow.trianglehead.2.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!workspaceGitState.isGitRepo || isFetchingBranches || switchingBranchName != nil)
                .help("Fetch latest branches from origin")
                .xrayId("inspector.fetchBranchesButton")

                Button {
                    revealInFinder(workspaceDirectoryPath)
                } label: {
                    Label("Finder", systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Reveal workspace in Finder")
                .accessibilityLabel("Reveal in Finder")
                .xrayId("inspector.openFinderButton")

                Button {
                    openInTerminal(workspaceDirectoryPath)
                } label: {
                    Label("Terminal", systemImage: "terminal")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Open workspace in Terminal")
                .xrayId("inspector.openTerminalButton")
            }
        }
        .inspectorSectionCard()
    }

    @ViewBuilder
    private var workspaceBranchMenu: some View {
        Menu {
            if isWorkspaceGitLoading {
                Text("Loading branches…")
            } else if !workspaceGitState.isGitRepo {
                Text("No git repository found")
            } else {
                if !workspaceGitState.localBranches.isEmpty {
                    Section("Local") {
                        ForEach(workspaceGitState.localBranches) { branch in
                            branchMenuButton(branch: branch)
                        }
                    }
                }

                let remoteOnlyBranches = workspaceGitState.remoteBranches.filter { remote in
                    !workspaceGitState.localBranches.contains(where: { $0.name == remote.name })
                }
                if !remoteOnlyBranches.isEmpty {
                    Section("Origin") {
                        ForEach(remoteOnlyBranches) { branch in
                            branchMenuButton(branch: branch)
                        }
                    }
                }
            }
        } label: {
            Label(switchingBranchName != nil ? "Switching…" : "Branch", systemImage: "arrow.triangle.swap")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .disabled(!workspaceGitState.isGitRepo || isWorkspaceGitLoading || switchingBranchName != nil)
        .help("Switch the current workspace to a different branch")
        .xrayId("inspector.switchBranchMenu")
    }

    @ViewBuilder
    private func branchMenuButton(branch: GitBranchRef) -> some View {
        let isCurrent = branch.name == workspaceGitState.currentBranch
        Button {
            Task { await switchToBranch(branch.name) }
        } label: {
            if isCurrent {
                Label(branch.name, systemImage: "checkmark")
            } else if branch.isRemote {
                Label(branch.name, systemImage: "icloud")
            } else {
                Text(branch.name)
            }
        }
        .disabled(isCurrent || switchingBranchName != nil || isFetchingBranches)
    }

    // MARK: - Agent Section

    @ViewBuilder
    private func agentSection(agent: Agent) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Agent", systemImage: agent.icon)
                .foregroundStyle(Color.fromAgentColor(agent.color))
                .xrayId("inspector.agentHeading")

            Button {
                windowState.openLibrary(.build, buildSection: .agents)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: agent.icon)
                        .font(.title3)
                        .frame(width: 32, height: 32)
                        .foregroundStyle(Color.fromAgentColor(agent.color))
                        .background(Color.fromAgentColor(agent.color).opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(agent.name)
                            .font(.callout)
                            .fontWeight(.medium)
                        Text(agentOriginLabel(agent))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)
            .help("Open \(agent.name) in editor")
            .xrayId("inspector.agentNameButton")

            if !agent.agentDescription.isEmpty {
                Text(agent.agentDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .xrayId("inspector.agentDescription")
            }

            HStack(spacing: 12) {
                Label("\(agent.skillIds.count) skills", systemImage: "book")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label("\(agent.extraMCPServerIds.count) MCPs", systemImage: "server.rack")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .xrayId("inspector.agentCapabilities")

            if let maxTurns = agent.maxTurns {
                InfoRow(label: "Max Turns", value: "\(maxTurns)")
            }
            if let maxBudget = agent.maxBudget {
                InfoRow(label: "Budget", value: String(format: "$%.2f", maxBudget))
            }
        }
        .inspectorSectionCard()
    }

    // MARK: - History Section

    @ViewBuilder
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("History", systemImage: "clock")
                .xrayId("inspector.historyHeading")

            InfoRow(label: "Started", value: conversation.startedAt.formatted(.relative(presentation: .named)))
            InfoRow(label: "Messages", value: "\(conversation.messages.count)")

            if conversation.parentConversationId != nil {
                InfoRow(label: "Forked from", value: parentConversationTitle ?? "Loading…")
            }

            if conversation.isPinned {
                InfoRow(label: "Pinned", value: "Yes")
            }
        }
        .inspectorSectionCard()
    }

    // MARK: - Group Content (Drawer — Option C)

    @ViewBuilder
    private func groupContent(_ group: AgentGroup) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(spacing: 8) {
                    Text(group.icon)
                        .font(.title)
                        .frame(width: 48, height: 48)
                        .background(Color.fromAgentColor(group.color).opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    Text(group.name)
                        .font(.headline)
                        .xrayId("inspector.group.name")

                    HStack(spacing: 4) {
                        if group.autoReplyEnabled {
                            groupMiniPill("Auto-Reply", color: .green)
                        }
                        if group.autonomousCapable {
                            groupMiniPill("Autonomous", color: .orange)
                        }
                        if group.workflow != nil {
                            groupMiniPill("Workflow", color: .teal)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .xrayId("inspector.group.header")

                // Actions
                HStack(spacing: 6) {
                    Button {
                        if let convoId = appState.startGroupChat(
                            group: group,
                            projectDirectory: windowState.projectDirectory,
                            projectId: windowState.selectedProjectId,
                            modelContext: modelContext
                        ) {
                            windowState.selectedConversationId = convoId
                        }
                    } label: {
                        Label("New Chat", systemImage: "play.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .xrayId("inspector.group.newChatButton")

                    Button {
                        editingGroup = group
                    } label: {
                        Label("Edit", systemImage: "pencil")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .xrayId("inspector.group.editButton")
                }
                .frame(maxWidth: .infinity)

                // Workflow progress
                if let steps = group.workflow, !steps.isEmpty {
                    Divider()
                    groupWorkflowSection(steps, group: group)
                }

                // Team
                Divider()
                groupTeamSection(group)

                // Instruction
                if !group.groupInstruction.isEmpty {
                    Divider()
                    groupInstructionSection(group.groupInstruction)
                }

                // Recent chats from this group
                Divider()
                groupRecentSection(group)
            }
            .padding()
        }
        .xrayId("inspector.group.scrollView")
    }

    @ViewBuilder
    private func groupWorkflowSection(_ steps: [WorkflowStep], group: AgentGroup) -> some View {
        let agentById = Dictionary(uniqueKeysWithValues: allAgents.map { ($0.id, $0) })
        let currentStep = conversation.workflowCurrentStep
        let completedSteps = conversation.workflowCompletedSteps ?? []

        VStack(alignment: .leading, spacing: 8) {
            Label("Workflow Progress", systemImage: "arrow.triangle.branch")
                .font(.headline)
                .xrayId("inspector.group.workflowHeading")

            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(stepColor(index: index, current: currentStep, completed: completedSteps))
                            .frame(width: 22, height: 22)
                        if completedSteps.contains(index) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                        } else {
                            Text("\(index + 1)")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(index == currentStep ? .white : .secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(step.stepLabel ?? "Step \(index + 1)")
                            .font(.caption)
                            .fontWeight(index == currentStep ? .semibold : .regular)
                            .foregroundStyle(index == currentStep ? .primary : .secondary)
                        if let agent = agentById[step.agentId] {
                            Text(agent.name)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                }
                .xrayId("inspector.group.workflowStep.\(index)")
            }
        }
    }

    @ViewBuilder
    private func groupTeamSection(_ group: AgentGroup) -> some View {
        let agentById = Dictionary(uniqueKeysWithValues: allAgents.map { ($0.id, $0) })
        let resolved = group.agentIds.compactMap { agentById[$0] }

        VStack(alignment: .leading, spacing: 8) {
            Label("Team", systemImage: "person.3")
                .font(.headline)
                .xrayId("inspector.group.teamHeading")

            ForEach(resolved) { agent in
                HStack(spacing: 8) {
                    Image(systemName: agent.icon)
                        .font(.caption2)
                        .frame(width: 22, height: 22)
                        .foregroundStyle(Color.fromAgentColor(agent.color))
                        .background(Color.fromAgentColor(agent.color).opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 5))

                    Text(agent.name)
                        .font(.caption)

                    Spacer()

                    let role = group.roleFor(agentId: agent.id)
                    if role != .participant {
                        Text(role.displayName)
                            .font(.system(size: 9))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(groupRoleColor(role).opacity(0.12))
                            .foregroundStyle(groupRoleColor(role))
                            .clipShape(Capsule())
                    }
                }
                .xrayId("inspector.group.agentRow.\(agent.id.uuidString)")
            }
        }
    }

    @ViewBuilder
    private func groupInstructionSection(_ instruction: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Instruction", systemImage: "text.quote")
                .font(.headline)
                .xrayId("inspector.group.instructionHeading")

            Text(instruction)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(instructionExpanded ? nil : 4)
                .xrayId("inspector.group.instructionText")

            if instruction.count > 120 {
                Button(instructionExpanded ? "Show Less" : "Show More") {
                    withAnimation { instructionExpanded.toggle() }
                }
                .font(.caption2)
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
        }
    }

    @ViewBuilder
    private func groupRecentSection(_ group: AgentGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Recent Chats", systemImage: "clock")
                .font(.headline)
                .xrayId("inspector.group.recentHeading")

            if groupRecentConversations.isEmpty {
                Text("No conversations yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(groupRecentConversations.prefix(5)) { conv in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(conv.id == conversation.id ? Color.accentColor : Color.gray.opacity(0.4))
                            .frame(width: 6, height: 6)
                        Text(conv.topic ?? "Untitled")
                            .font(.caption)
                            .lineLimit(1)
                            .fontWeight(conv.id == conversation.id ? .semibold : .regular)
                        Spacer()
                        Text(conv.startedAt, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        windowState.selectedConversationId = conv.id
                    }
                    .xrayId("inspector.group.recentRow.\(conv.id.uuidString)")
                }
            }
        }
    }

    // MARK: - Group Helpers

    private func stepColor(index: Int, current: Int?, completed: [Int]) -> Color {
        if completed.contains(index) { return .green }
        if index == current { return .accentColor }
        return Color.gray.opacity(0.3)
    }

    private func groupRoleColor(_ role: GroupRole) -> Color {
        switch role {
        case .coordinator: .orange
        case .scribe: .purple
        case .observer: .gray
        case .participant: .secondary
        }
    }

    @ViewBuilder
    private func groupMiniPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9))
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func sectionLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
    }

    // MARK: - Helpers

    private func refreshDerivedInspectorState() {
        parentConversationTitle = loadParentConversationTitle()
        groupRecentConversations = loadRecentGroupConversations()
    }

    @MainActor
    private func refreshWorkspaceGitInfo() async {
        guard let directoryURL = workspaceDirectoryURL else {
            workspaceGitState = WorkspaceGitState()
            workspaceGitError = nil
            return
        }

        isWorkspaceGitLoading = true
        let updatedState = await Task.detached(priority: .userInitiated) {
            var state = WorkspaceGitState()
            state.isGitRepo = GitService.isGitRepo(at: directoryURL)
            guard state.isGitRepo else { return state }

            state.currentBranch = GitService.currentBranch(in: directoryURL)
            state.changeCount = GitService.status(in: directoryURL).count
            state.localBranches = GitService.localBranches(in: directoryURL)
            state.remoteBranches = GitService.remoteBranches(in: directoryURL)
            return state
        }.value

        workspaceGitState = updatedState
        isWorkspaceGitLoading = false

        if conversation.worktreePath != nil, conversation.worktreeBranch != updatedState.currentBranch {
            conversation.worktreeBranch = updatedState.currentBranch
            try? modelContext.save()
        }
    }

    @MainActor
    private func repairInvalidWorktreeIfNeeded() async {
        guard let worktreePath = conversation.worktreePath,
              !WorktreeManager.isUsableWorktree(at: worktreePath) else {
            return
        }

        _ = await WorktreeManager.ensureWorktree(
            for: conversation,
            projectDirectory: windowState.projectDirectory,
            modelContext: modelContext
        )
        appState.fileTreeRefreshTrigger += 1
    }

    @MainActor
    private func fetchBranches() async {
        guard let directoryURL = workspaceDirectoryURL else { return }
        workspaceGitError = nil
        isFetchingBranches = true
        defer { isFetchingBranches = false }

        do {
            try await GitService.fetch(in: directoryURL)
            await refreshWorkspaceGitInfo()
        } catch {
            workspaceGitError = gitErrorMessage(error)
        }
    }

    @MainActor
    private func switchToBranch(_ branch: String) async {
        guard let directoryURL = workspaceDirectoryURL else { return }
        workspaceGitError = nil
        switchingBranchName = branch
        defer { switchingBranchName = nil }

        do {
            try await GitService.switchBranch(named: branch, in: directoryURL)
            appState.fileTreeRefreshTrigger += 1
            await refreshWorkspaceGitInfo()
        } catch {
            workspaceGitError = gitErrorMessage(error)
        }
    }

    private func loadParentConversationTitle() -> String? {
        guard let parentId = conversation.parentConversationId else { return nil }
        let descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate<Conversation> { convo in
                convo.id == parentId
            }
        )
        return try? modelContext.fetch(descriptor).first?.topic ?? "Untitled"
    }

    private func loadRecentGroupConversations() -> [Conversation] {
        guard let groupId = conversation.sourceGroupId else { return [] }
        var descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate<Conversation> { convo in
                convo.sourceGroupId == groupId
            }
        )
        descriptor.sortBy = [SortDescriptor(\Conversation.startedAt, order: .reverse)]
        descriptor.fetchLimit = 5
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func agentOriginLabel(_ agent: Agent) -> String {
        switch agent.origin {
        case .local: "Local"
        case .peer: "Shared"
        case .imported: "Imported"
        case .builtin: "Built-in"
        }
    }

    private func durationString(from start: Date) -> String {
        let interval = now.timeIntervalSince(start)
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60
        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        }
        return String(format: "%dm %02ds", minutes, seconds)
    }

    private func turnProgressColor(used: Int, max: Int) -> Color {
        let ratio = Double(used) / Double(max)
        if ratio >= 0.9 { return .red }
        if ratio >= 0.7 { return .orange }
        return .accentColor
    }

    private func modelShortName(_ model: String) -> String {
        AgentDefaults.label(for: model)
    }

    private func formatNumber(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private var repoStateLabel: String {
        switch workspaceGitState.changeCount {
        case 0:
            return "Clean"
        case 1:
            return "Dirty (1 change)"
        default:
            return "Dirty (\(workspaceGitState.changeCount) changes)"
        }
    }

    private func abbreviatePath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func gitErrorMessage(_ error: Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription {
            return localized
        }
        return error.localizedDescription
    }

    private func revealInFinder(_ path: String) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
    }

    /// Opens `~/.odyssey/sandboxes` (conversation sandboxes and other ephemeral dirs live here).
    private func revealSandboxesRootInFinder() {
        let path = "\(NSHomeDirectory())/.odyssey/sandboxes"
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
    }

    private func openInTerminal(_ path: String) {
        let script = "tell application \"Terminal\" to do script \"cd \(path.replacingOccurrences(of: "\"", with: "\\\""))\""
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }

    private func normalizeSelectedTab() {
        if isGroupConversation, windowState.selectedInspectorTab == .info {
            windowState.selectedInspectorTab = .group
            return
        }
        if !availableTabs.contains(windowState.selectedInspectorTab) {
            windowState.selectedInspectorTab = isGroupConversation ? .group : .info
        }
    }
}

private struct BlackboardInspectorPanel: View {
    let conversation: Conversation
    let relevantKeys: Set<String>
    let relevantWriters: Set<String>

    @EnvironmentObject private var appState: AppState
    @State private var entries: [BlackboardSnapshotEntry] = []
    @State private var scope: BlackboardInspectorScope = .relevant
    @State private var searchText = ""
    @State private var expandedKeys: Set<String> = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var blackboardEventCount: Int {
        appState.commsEvents.reduce(into: 0) { partial, event in
            if case .blackboardUpdate = event.kind {
                partial += 1
            }
        }
    }

    private var filteredEntries: [BlackboardSnapshotEntry] {
        BlackboardSnapshotFilter.filteredEntries(
            entries,
            scope: scope,
            searchText: searchText,
            relevantKeys: relevantKeys,
            relevantWriters: relevantWriters
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            controls

            if isLoading && entries.isEmpty {
                stateContainer(loadingState)
            } else if let errorMessage, entries.isEmpty {
                stateContainer(errorState(message: errorMessage))
            } else if filteredEntries.isEmpty {
                stateContainer(emptyState)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(filteredEntries) { entry in
                            BlackboardEntryCard(
                                entry: entry,
                                isExpanded: expandedKeys.contains(entry.key),
                                onToggle: { toggle(entry.key) }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
                .xrayId("inspector.blackboard.entryList")
            }
        }
        .padding()
        .task {
            await loadEntries()
        }
        .onChange(of: conversation.id) { _, _ in
            expandedKeys.removeAll()
        }
        .onChange(of: blackboardEventCount) { _, _ in
            Task { await loadEntries() }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Search keys or values", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .xrayId("inspector.blackboard.searchField")

                Button {
                    Task { await loadEntries() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh blackboard")
                .xrayId("inspector.blackboard.refreshButton")
                .accessibilityLabel("Refresh blackboard")
                .disabled(isLoading)
            }

            Picker("Blackboard Scope", selection: $scope) {
                ForEach(BlackboardInspectorScope.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .xrayId("inspector.blackboard.filterPicker")
        }
    }

    private var loadingState: some View {
        InspectorEmptyState(
            title: "Loading blackboard",
            message: "Fetching the latest shared state from the sidecar.",
            systemImage: "square.grid.2x2"
        )
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: 12) {
            InspectorEmptyState(
                title: "Blackboard unavailable",
                message: message,
                systemImage: "exclamationmark.triangle"
            )

            Button("Retry") {
                Task { await loadEntries() }
            }
        }
    }

    private var emptyState: some View {
        InspectorEmptyState(
            title: "No blackboard entries",
            message: scope == .relevant
                ? "No entries match this conversation yet."
                : "The blackboard does not have any entries yet.",
            systemImage: "square.grid.2x2"
        )
    }

    @ViewBuilder
    private func stateContainer<Content: View>(_ content: Content) -> some View {
        VStack {
            Spacer(minLength: 24)
            content
            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadEntries() async {
        guard let client = BlackboardSnapshotClient.live(port: appState.allocatedHttpPort) else {
            errorMessage = "Connect the sidecar to inspect the blackboard."
            entries = []
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let freshEntries = try await client.fetchAllEntries()
            entries = freshEntries
            errorMessage = nil
            expandedKeys = expandedKeys.intersection(Set(freshEntries.map(\.key)))
        } catch {
            if let clientError = error as? BlackboardSnapshotClientError {
                errorMessage = clientError.errorDescription
            } else {
                errorMessage = error.localizedDescription
            }
            if entries.isEmpty {
                expandedKeys.removeAll()
            }
        }
    }

    private func toggle(_ key: String) {
        if expandedKeys.contains(key) {
            expandedKeys.remove(key)
        } else {
            expandedKeys.insert(key)
        }
    }
}

private struct BlackboardEntryCard: View {
    let entry: BlackboardSnapshotEntry
    let isExpanded: Bool
    let onToggle: () -> Void

    private var accessibilitySlug: String {
        let lowered = entry.key.lowercased()
        let slug = lowered.replacingOccurrences(
            of: "[^a-z0-9]+",
            with: "-",
            options: .regularExpression
        )
        return slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private var formattedValue: String {
        guard let data = entry.value.data(using: .utf8) else { return entry.value }
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return entry.value }
        guard JSONSerialization.isValidJSONObject(object),
              let prettyData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]),
              let prettyString = String(data: prettyData, encoding: .utf8) else {
            return entry.value
        }
        return prettyString
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                onToggle()
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.key)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)

                        HStack(spacing: 6) {
                            Text(entry.writtenBy)
                            Text("•")
                            Text(entry.updatedAt, style: .relative)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    if let workspaceId = entry.workspaceId, !workspaceId.isEmpty {
                        InfoRow(label: "Scope", value: workspaceId)
                    }

                    ScrollView(.horizontal, showsIndicators: true) {
                        Text(formattedValue)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(8)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

                    HStack(spacing: 8) {
                        Button("Copy Key") {
                            copy(entry.key)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .xrayId("inspector.blackboard.copyKey.\(accessibilitySlug)")

                        Button("Copy Value") {
                            copy(entry.value)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .xrayId("inspector.blackboard.copyValue.\(accessibilitySlug)")

                        Spacer()
                    }
                }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.quaternary, lineWidth: 0.8)
        )
        .xrayId("inspector.blackboard.entryRow.\(accessibilitySlug)")
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(value)
                    .font(.callout)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(3)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout)
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .xrayId("infoRow.\(label.lowercased().replacingOccurrences(of: " ", with: ""))")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

private struct InspectorTabBar: View {
    let tabs: [WindowInspectorTab]
    @Binding var selection: WindowInspectorTab

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tabs) { tab in
                    Button {
                        selection = tab
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab.symbolName)
                                .font(.caption)
                            Text(tab.shortTitle)
                                .font(.subheadline)
                                .fontWeight(selection == tab ? .semibold : .medium)
                        }
                        .foregroundStyle(selection == tab ? Color.primary : Color.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule(style: .continuous)
                                .fill(selection == tab ? Color(nsColor: .controlBackgroundColor) : .clear)
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(selection == tab ? Color.primary.opacity(0.08) : .clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .stableXrayId("inspector.tab.\(tab.id.lowercased())")
                }
            }
            .padding(4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
        }
        .accessibilityElement(children: .contain)
    }
}

private struct InspectorMetricTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .monospacedDigit()
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct InspectorEmptyState: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 220)
    }
}

private extension WindowInspectorTab {
    var shortTitle: String {
        switch self {
        case .info:
            return "Info"
        case .files:
            return "Files"
        case .blackboard:
            return "Board"
        case .group:
            return "Group"
        }
    }

    var symbolName: String {
        switch self {
        case .info:
            return "info.circle"
        case .files:
            return "folder"
        case .blackboard:
            return "square.grid.2x2"
        case .group:
            return "person.3"
        }
    }
}

private extension View {
    func inspectorSectionCard() -> some View {
        self
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}
