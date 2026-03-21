import SwiftUI
import SwiftData

enum InspectorTab: String, CaseIterable, Identifiable {
    case info = "Info"
    case files = "Files"

    var id: String { rawValue }
}

struct InspectorView: View {
    let conversationId: UUID
    @Environment(\.modelContext) private var modelContext
    @Query private var allConversations: [Conversation]
    @EnvironmentObject private var appState: AppState
    @State private var now = Date()
    @State private var inspectorTab: InspectorTab = .info

    private let durationTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var conversation: Conversation? {
        allConversations.first { $0.id == conversationId }
    }

    private var session: Session? {
        conversation?.session
    }

    private var agent: Agent? {
        session?.agent
    }

    private var liveInfo: AppState.SessionInfo? {
        appState.activeSessions[conversationId]
    }

    private var hasWorkingDirectory: Bool {
        guard let session = session else { return false }
        return !session.workingDirectory.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            if hasWorkingDirectory {
                Picker("Inspector Tab", selection: $inspectorTab) {
                    ForEach(InspectorTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .accessibilityIdentifier("inspector.tabPicker")
            }

            switch inspectorTab {
            case .info:
                infoContent
            case .files:
                if let dir = session?.workingDirectory, !dir.isEmpty {
                    FileExplorerView(
                        workingDirectory: dir,
                        refreshTrigger: appState.fileTreeRefreshTrigger
                    )
                } else {
                    infoContent
                }
            }
        }
        .frame(minWidth: 220, idealWidth: 280)
        .onReceive(durationTimer) { _ in
            now = Date()
        }
    }

    // MARK: - Info Content

    private var infoContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if session != nil {
                    sessionSection
                    usageSection
                }
                if hasWorkingDirectory {
                    workspaceSection
                }
                if agent != nil {
                    agentSection
                }
                historySection
            }
            .padding()
        }
        .accessibilityIdentifier("inspector.scrollView")
    }

    // MARK: - Session Section

    @ViewBuilder
    private var sessionSection: some View {
        if let session = session {
            VStack(alignment: .leading, spacing: 8) {
                Label("Session", systemImage: "terminal")
                    .font(.headline)
                    .accessibilityIdentifier("inspector.sessionHeading")

                InfoRow(label: "Status", value: session.status.rawValue.capitalized)
                InfoRow(label: "Model", value: modelShortName(session.agent?.model ?? ""))
                InfoRow(label: "Mode", value: session.mode.rawValue.capitalized)

                if let convo = conversation {
                    InfoRow(label: "Duration", value: durationString(from: convo.startedAt))
                }
            }
        }
    }

    // MARK: - Usage Section

    @ViewBuilder
    private var usageSection: some View {
        if let session = session {
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Label("Usage", systemImage: "chart.bar")
                    .font(.headline)
                    .accessibilityIdentifier("inspector.usageHeading")

                let liveTokens = liveInfo?.tokenCount ?? session.tokenCount
                let liveCost = liveInfo?.cost ?? session.totalCost
                let maxTurns = agent?.maxTurns ?? 30
                let toolCalls = session.toolCallCount

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
                    .accessibilityIdentifier("inspector.turnsLabel")

                    ProgressView(value: min(Double(toolCalls), Double(maxTurns)), total: Double(maxTurns))
                        .tint(turnProgressColor(used: toolCalls, max: maxTurns))
                        .padding(.leading, 84)
                        .accessibilityIdentifier("inspector.turnsProgress")
                }
            }
        }
    }

    // MARK: - Workspace Section

    @ViewBuilder
    private var workspaceSection: some View {
        if let session = session, !session.workingDirectory.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Label("Workspace", systemImage: "folder")
                    .font(.headline)
                    .accessibilityIdentifier("inspector.workspaceHeading")

                Text(abbreviatePath(session.workingDirectory))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .accessibilityIdentifier("inspector.workspacePath")

                Button {
                    openInTerminal(session.workingDirectory)
                } label: {
                    Label("Open in Terminal", systemImage: "terminal")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Open working directory in Terminal")
                .accessibilityIdentifier("inspector.openTerminalButton")
            }
        }
    }

    // MARK: - Agent Section

    @ViewBuilder
    private var agentSection: some View {
        if let agent = agent {
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Label("Agent", systemImage: agent.icon)
                    .font(.headline)
                    .foregroundStyle(Color.fromAgentColor(agent.color))
                    .accessibilityIdentifier("inspector.agentHeading")

                Button {
                    appState.showAgentLibrary = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: agent.icon)
                            .foregroundStyle(Color.fromAgentColor(agent.color))
                        Text(agent.name)
                            .font(.callout)
                            .fontWeight(.medium)
                    }
                }
                .buttonStyle(.plain)
                .help("Open \(agent.name) in editor")
                .accessibilityIdentifier("inspector.agentNameButton")

                HStack(spacing: 12) {
                    Label("\(agent.skillIds.count) skills", systemImage: "book")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label("\(agent.extraMCPServerIds.count) MCPs", systemImage: "server.rack")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("inspector.agentCapabilities")

                InfoRow(label: "Policy", value: policyLabel(agent.instancePolicy))
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
                    .accessibilityIdentifier("inspector.historyHeading")

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

    // MARK: - Helpers

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
        if model.contains("haiku") { return "Haiku 4.6" }
        return model
    }

    private func policyLabel(_ policy: InstancePolicy) -> String {
        switch policy {
        case .spawn: return "Spawn"
        case .singleton: return "Singleton"
        case .pool(let max): return "Pool(\(max))"
        }
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
        .accessibilityIdentifier("infoRow.\(label.lowercased().replacingOccurrences(of: " ", with: ""))")
        .accessibilityLabel("\(label): \(value)")
    }
}
