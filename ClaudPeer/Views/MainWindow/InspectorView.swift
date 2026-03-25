import SwiftUI
import SwiftData
import AppKit

enum InspectorTab: String, CaseIterable, Identifiable {
    case info = "Info"
    case files = "Files"
    case group = "Group"

    var id: String { rawValue }
}

struct InspectorView: View {
    let conversationId: UUID
    @Environment(\.modelContext) private var modelContext
    @Query private var allConversations: [Conversation]
    @Query(sort: \Session.startedAt) private var allSessions: [Session]
    @EnvironmentObject private var appState: AppState
    @Query private var allGroups: [AgentGroup]
    @Query private var allAgents: [Agent]
    @State private var now = Date()
    @State private var inspectorTab: InspectorTab = .info
    @State private var editingGroup: AgentGroup?
    @State private var instructionExpanded = false
    @State private var showAttachRepoSheet = false

    private let durationTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var conversation: Conversation? {
        allConversations.first { $0.id == conversationId }
    }

    private var sourceGroup: AgentGroup? {
        guard let gid = conversation?.sourceGroupId else { return nil }
        return allGroups.first { $0.id == gid }
    }

    private var isGroupConversation: Bool { sourceGroup != nil }

    private var availableTabs: [InspectorTab] {
        var tabs: [InspectorTab] = [.info]
        if hasWorkingDirectory { tabs.append(.files) }
        if isGroupConversation { tabs.append(.group) }
        return tabs
    }

    /// Sessions for this conversation — uses the relationship first, falls back to
    /// a manual query when the SwiftData many-to-many inverse returns empty.
    private var orderedSessions: [Session] {
        let relSessions = conversation?.sessions ?? []
        if !relSessions.isEmpty {
            return relSessions.sorted { $0.startedAt < $1.startedAt }
        }
        // Fallback: find sessions whose conversations include this one
        return allSessions.filter { session in
            session.conversations.contains { $0.id == conversationId }
        }
    }

    private var primarySession: Session? {
        orderedSessions.first
    }

    private func liveInfo(for session: Session) -> AppState.SessionInfo? {
        appState.activeSessions[session.id]
    }

    private var hasWorkingDirectory: Bool {
        guard let session = primarySession else { return false }
        return !session.workingDirectory.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            if availableTabs.count > 1 {
                Picker("Inspector Tab", selection: $inspectorTab) {
                    ForEach(availableTabs) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .xrayId("inspector.tabPicker")
            }

            switch inspectorTab {
            case .info:
                infoContent
            case .files:
                if let dir = primarySession?.workingDirectory, !dir.isEmpty {
                    FileExplorerView(
                        workingDirectory: dir,
                        refreshTrigger: appState.fileTreeRefreshTrigger
                    )
                } else {
                    infoContent
                }
            case .group:
                if let group = sourceGroup {
                    groupContent(group)
                } else {
                    infoContent
                }
            }
        }
        .frame(minWidth: 220, idealWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(durationTimer) { _ in
            now = Date()
        }
        .onChange(of: isGroupConversation) {
            if isGroupConversation {
                inspectorTab = .group
            } else if !availableTabs.contains(inspectorTab) {
                inspectorTab = .info
            }
        }
        .onAppear {
            if isGroupConversation {
                inspectorTab = .group
            }
        }
        .sheet(item: $editingGroup) { g in
            GroupEditorView(group: g)
        }
        .sheet(isPresented: $showAttachRepoSheet) {
            AttachRepoSheet(conversationId: conversationId)
                .environmentObject(appState)
                .environment(\.modelContext, modelContext)
        }
    }

    // MARK: - Info Content

    private var infoContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if orderedSessions.isEmpty {
                    if let convo = conversation {
                        InfoRow(label: "Topic", value: convo.topic ?? "Untitled")
                        InfoRow(label: "Started", value: convo.startedAt.formatted(.dateTime))
                    }
                } else if orderedSessions.count == 1, let session = orderedSessions.first {
                    sessionSection(session: session)
                    usageSection(session: session, agent: session.agent)
                    if let agent = session.agent {
                        agentSection(agent: agent)
                    }
                } else {
                    multiSessionsSection
                }
                if hasWorkingDirectory {
                    workspaceSection
                }
                if !orderedSessions.isEmpty {
                    Button { showAttachRepoSheet = true } label: {
                        Label("Attach GitHub Repo", systemImage: "arrow.triangle.branch")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Attach a GitHub repository to this conversation")
                    .xrayId("inspector.attachRepoButton")
                }
                historySection
            }
            .padding()
        }
        .xrayId("inspector.scrollView")
    }

    // MARK: - Session Section

    @ViewBuilder
    private func sessionSection(session: Session) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Session", systemImage: "terminal")
                .font(.headline)
                .xrayId("inspector.sessionHeading")

            InfoRow(label: "Status", value: appState.sessionActivity[session.id.uuidString]?.displayLabel ?? session.status.rawValue.capitalized)
            InfoRow(label: "Model", value: modelShortName(session.agent?.model ?? ""))
            InfoRow(label: "Mode", value: session.mode.rawValue.capitalized)

            if let convo = conversation {
                InfoRow(label: "Duration", value: durationString(from: convo.startedAt))
            }
        }
    }

    @ViewBuilder
    private var multiSessionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Sessions in this conversation", systemImage: "person.3")
                .font(.headline)
                .xrayId("inspector.sessionsListHeading")

            ForEach(orderedSessions, id: \.id) { session in
                multiSessionRow(session: session)
            }

            sessionTotalsRow
        }
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
            InfoRow(label: "Model", value: modelShortName(agent?.model ?? ""))
            InfoRow(label: "Tokens", value: formatNumber(liveTokens))
            InfoRow(label: "Cost", value: String(format: "$%.4f", liveCost))
            InfoRow(label: "Tool Calls", value: "\(live?.toolCallCount ?? session.toolCallCount)")
            if let agent {
                Button {
                    appState.showAgentLibrary = true
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
        Divider()
        VStack(alignment: .leading, spacing: 8) {
            Label("Usage", systemImage: "chart.bar")
                .font(.headline)
                .xrayId("inspector.usageHeading")

            let live = liveInfo(for: session)
            let liveTokens = live?.tokenCount ?? session.tokenCount
            let liveCost = live?.cost ?? session.totalCost
            let maxTurns = agent?.maxTurns ?? 30
            let toolCalls = live?.toolCallCount ?? session.toolCallCount

            InfoRow(label: "Tokens", value: formatNumber(liveTokens))
            InfoRow(label: "Cost", value: String(format: "$%.4f", liveCost))
            InfoRow(label: "Tool Calls", value: "\(toolCalls)")

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Turns")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .trailing)
                    Text("\(toolCalls) / \(maxTurns)")
                        .font(.caption)
                        .monospacedDigit()
                }
                .xrayId("inspector.turnsLabel")

                ProgressView(value: min(Double(toolCalls), Double(maxTurns)), total: Double(maxTurns))
                    .tint(turnProgressColor(used: toolCalls, max: maxTurns))
                    .padding(.leading, 84)
                    .xrayId("inspector.turnsProgress")
            }
        }
    }

    // MARK: - Workspace Section

    @ViewBuilder
    private var workspaceSection: some View {
        if let session = primarySession, !session.workingDirectory.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Label("Working directory", systemImage: "folder")
                    .font(.headline)
                    .xrayId("inspector.workspaceHeading")

                InfoRow(label: "Path", value: abbreviatePath(session.workingDirectory))

                HStack(spacing: 8) {
                    Button {
                        revealInFinder(session.workingDirectory)
                    } label: {
                        Label("Finder", systemImage: "arrow.up.right.square")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Reveal working directory in Finder")
                    .accessibilityLabel("Reveal in Finder")
                    .xrayId("inspector.openFinderButton")

                    Button {
                        openInTerminal(session.workingDirectory)
                    } label: {
                        Label("Open in Terminal", systemImage: "terminal")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Open working directory in Terminal")
                    .xrayId("inspector.openTerminalButton")

                    Button {
                        revealSandboxesRootInFinder()
                    } label: {
                        Label("Sandboxes", systemImage: "archivebox")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Open ~/.claudpeer/sandboxes in Finder")
                    .xrayId("inspector.openSandboxesFinderButton")
                }
            }
        }
    }

    // MARK: - Agent Section

    @ViewBuilder
    private func agentSection(agent: Agent) -> some View {
        Divider()
        VStack(alignment: .leading, spacing: 8) {
            Label("Agent", systemImage: agent.icon)
                .font(.headline)
                .foregroundStyle(Color.fromAgentColor(agent.color))
                .xrayId("inspector.agentHeading")

            Button {
                appState.showAgentLibrary = true
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
    }

    // MARK: - History Section

    @ViewBuilder
    private var historySection: some View {
        if let convo = conversation {
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Label("History", systemImage: "clock")
                    .font(.headline)
                    .xrayId("inspector.historyHeading")

                InfoRow(label: "Started", value: convo.startedAt.formatted(.relative(presentation: .named)))
                InfoRow(label: "Messages", value: "\(convo.messages.count)")

                if let parentId = convo.parentConversationId,
                   let parent = allConversations.first(where: { $0.id == parentId }) {
                    InfoRow(label: "Forked from", value: parent.topic ?? "Untitled")
                }

                if convo.isPinned {
                    InfoRow(label: "Pinned", value: "Yes")
                }
            }
        }
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
                        appState.startGroupChat(group: group, modelContext: modelContext)
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
        let currentStep = conversation?.workflowCurrentStep
        let completedSteps = conversation?.workflowCompletedSteps ?? []

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
        let convos = allConversations
            .filter { $0.sourceGroupId == group.id }
            .sorted { $0.startedAt > $1.startedAt }

        VStack(alignment: .leading, spacing: 6) {
            Label("Recent Chats", systemImage: "clock")
                .font(.headline)
                .xrayId("inspector.group.recentHeading")

            if convos.isEmpty {
                Text("No conversations yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(convos.prefix(5)) { conv in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(conv.id == conversationId ? Color.accentColor : Color.gray.opacity(0.4))
                            .frame(width: 6, height: 6)
                        Text(conv.topic ?? "Untitled")
                            .font(.caption)
                            .lineLimit(1)
                            .fontWeight(conv.id == conversationId ? .semibold : .regular)
                        Spacer()
                        Text(conv.startedAt, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        appState.selectedConversationId = conv.id
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

    // MARK: - Helpers

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
        if model.contains("sonnet") { return "Sonnet 4.6" }
        if model.contains("opus") { return "Opus 4.6" }
        if model.contains("haiku") { return "Haiku 4.5" }
        return model
    }

    private func formatNumber(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private func abbreviatePath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func revealInFinder(_ path: String) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
    }

    /// Opens `~/.claudpeer/sandboxes` (conversation sandboxes and other ephemeral dirs live here).
    private func revealSandboxesRootInFinder() {
        let path = "\(NSHomeDirectory())/.claudpeer/sandboxes"
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
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
            Text(value)
                .font(.caption)
                .lineLimit(2)
        }
        .xrayId("infoRow.\(label.lowercased().replacingOccurrences(of: " ", with: ""))")
        .accessibilityLabel("\(label): \(value)")
    }
}
