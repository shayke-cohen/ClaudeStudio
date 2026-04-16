import SwiftUI
import SwiftData

struct NewGroupThreadSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @Environment(WindowState.self) private var windowState: WindowState

    @Query(sort: \AgentGroup.sortOrder) private var groups: [AgentGroup]
    @Query(sort: \Conversation.startedAt, order: .reverse) private var recentConversations: [Conversation]
    @Query(sort: [SortDescriptor(\PromptTemplate.sortOrder), SortDescriptor(\PromptTemplate.name)]) private var allPromptTemplates: [PromptTemplate]

    @State private var selectedGroupId: UUID?
    @State private var mission = ""
    @State private var executionMode: ConversationExecutionMode = .interactive

    private var availableTemplates: [PromptTemplate] {
        guard let groupId = selectedGroupId else { return [] }
        return allPromptTemplates.filter { $0.group?.id == groupId }
    }

    private var enabledGroups: [AgentGroup] {
        groups.filter(\.isEnabled)
    }

    private var selectedGroup: AgentGroup? {
        guard let selectedGroupId else { return nil }
        return enabledGroups.first(where: { $0.id == selectedGroupId })
    }

    private var recentGroups: [AgentGroup] {
        var seen = Set<UUID>()
        var result: [AgentGroup] = []
        for conversation in recentConversations {
            guard let groupId = conversation.sourceGroupId,
                  let group = enabledGroups.first(where: { $0.id == groupId }),
                  !seen.contains(groupId) else { continue }
            seen.insert(groupId)
            result.append(group)
            if result.count >= 4 { break }
        }
        return result
    }

    private var canStart: Bool {
        guard let selectedGroup else { return false }
        if executionMode == .interactive { return true }
        return selectedGroup.coordinatorAgentId != nil || selectedGroup.autonomousCapable
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    projectInfoRow
                    setupSection
                    if !recentGroups.isEmpty {
                        recentGroupsRow
                    }
                    groupPicker
                }
                .padding(24)
            }
            Divider()
            footer
        }
        .frame(width: 620, height: 560)
        .onAppear {
            if selectedGroupId == nil {
                selectedGroupId = recentGroups.first?.id ?? enabledGroups.first?.id
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack {
            Text("New Group Thread")
                .font(.title2)
                .fontWeight(.semibold)
                .xrayId("newGroupThread.title")
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .help("Close")
            .xrayId("newGroupThread.closeButton")
            .accessibilityLabel("Close")
        }
        .padding(16)
    }

    @ViewBuilder
    private var recentGroupsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                ForEach(recentGroups) { group in
                    Button {
                        selectedGroupId = group.id
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .foregroundStyle(Color.fromAgentColor(group.color))
                            Text(group.name)
                                .font(.callout)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selectedGroupId == group.id
                            ? Color.fromAgentColor(group.color).opacity(0.12)
                            : Color.clear
                        )
                        .clipShape(Capsule())
                        .overlay {
                            Capsule()
                                .strokeBorder(
                                    selectedGroupId == group.id
                                        ? Color.fromAgentColor(group.color)
                                        : Color.secondary.opacity(0.15),
                                    lineWidth: 1
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .xrayId("newGroupThread.recentGroup.\(group.id.uuidString)")
                }
            }
        }
    }

    @ViewBuilder
    private var groupPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose Group")
                .font(.headline)
                .xrayId("newGroupThread.groupPickerTitle")

            if enabledGroups.isEmpty {
                ContentUnavailableView(
                    "No groups available",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Open Library > Groups to create a reusable team first.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .xrayId("newGroupThread.emptyState")
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 12)], spacing: 12) {
                    ForEach(enabledGroups) { group in
                        groupCard(group)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func groupCard(_ group: AgentGroup) -> some View {
        let isSelected = selectedGroupId == group.id
        Button {
            selectedGroupId = group.id
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.title3)
                        .foregroundStyle(Color.fromAgentColor(group.color))
                        .frame(width: 32, height: 32)
                        .background(Color.fromAgentColor(group.color).opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.name)
                            .font(.headline)
                            .lineLimit(1)
                        Text("\(group.agentIds.count) agents")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                if !group.groupDescription.isEmpty {
                    Text(group.groupDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                } else if let mission = group.defaultMission, !mission.isEmpty {
                    Text(mission)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                } else {
                    Text("No description")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.15), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .xrayId("newGroupThread.groupCard.\(group.id.uuidString)")
        .accessibilityLabel(group.name)
    }

    @ViewBuilder
    private var projectInfoRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .foregroundStyle(.secondary)
            Text("Project:")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(windowState.projectName)
                .font(.subheadline)
                .fontWeight(.medium)
            Spacer()
        }
        .padding(.vertical, 4)
        .xrayId("newGroupThread.projectInfo")
    }

    @ViewBuilder
    private var setupSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Team Setup")
                    .font(.headline)
                    .xrayId("newGroupThread.setupTitle")
                Text("Choose how the team should work, then set the kickoff goal.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .xrayId("newGroupThread.setupSubtitle")
            }

            modeCards

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Kickoff Goal")
                        .font(.subheadline.weight(.semibold))
                        .xrayId("newGroupThread.missionTitle")
                    Text(goalPromptLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .xrayId("newGroupThread.goalCaption")
                }

                TemplatePickerRow(
                    templates: availableTemplates,
                    mission: $mission,
                    ownerLabel: selectedGroup?.name ?? "",
                    onManage: { windowState.openSettings() }
                )

                TextField(goalPlaceholder, text: $mission, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)
                    .xrayId("newGroupThread.missionField")

                Text(goalHelpText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .xrayId("newGroupThread.missionHelp")
            }

            if let modeConstraintText {
                Label(modeConstraintText, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .xrayId("newGroupThread.modeConstraint")
            }
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        }
        .xrayId("newGroupThread.setupSection")
    }

    @ViewBuilder
    private var modeCards: some View {
        HStack(spacing: 12) {
            modeCard(
                mode: .interactive,
                title: "Interactive",
                subtitle: "Whole team chats",
                detail: "Broadcast user turns across the team using the current routing rules.",
                icon: "person.3.fill",
                accent: .blue
            )
            modeCard(
                mode: .autonomous,
                title: "Autonomous",
                subtitle: "Coordinator runs once",
                detail: "Starts immediately and routes future user turns to the coordinator first.",
                icon: "sparkles.rectangle.stack",
                accent: .orange
            )
            modeCard(
                mode: .worker,
                title: "Worker",
                subtitle: "Coordinator stays ready",
                detail: "Runs the first job now, then keeps the same group thread ready for the next one.",
                icon: "shippingbox.fill",
                accent: .green
            )
        }
    }

    private func modeCard(
        mode: ConversationExecutionMode,
        title: String,
        subtitle: String,
        detail: String,
        icon: String,
        accent: Color
    ) -> some View {
        let isSelected = executionMode == mode
        return Button {
            executionMode = mode
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Image(systemName: icon)
                        .font(.headline)
                        .foregroundStyle(isSelected ? accent : .secondary)
                        .frame(width: 30, height: 30)
                        .background(
                            Circle()
                                .fill(isSelected ? accent.opacity(0.14) : Color.secondary.opacity(0.08))
                        )

                    Spacer(minLength: 0)

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.headline)
                        .foregroundStyle(isSelected ? accent : .secondary.opacity(0.5))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(isSelected ? accent : .secondary)
                }

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
            .padding(14)
            .background(isSelected ? accent.opacity(0.10) : Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? accent.opacity(0.9) : Color.secondary.opacity(0.15), lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .xrayId("newGroupThread.modeCard.\(mode.rawValue)")
        .accessibilityLabel(title)
    }

    private var modeDescription: String {
        switch executionMode {
        case .interactive:
            return "Broadcast user turns across the team using the current group routing rules."
        case .autonomous:
            return "Auto-start the mission and route future user turns to the coordinator first."
        case .worker:
            return "Auto-start the first job, then keep the same coordinator-led thread ready for future jobs."
        }
    }

    private var goalPromptLabel: String {
        switch executionMode {
        case .interactive:
            return "Shared context for the team"
        case .autonomous:
            return "Used as the first job right away"
        case .worker:
            return "Defines the first job and worker focus"
        }
    }

    private var goalPlaceholder: String {
        switch executionMode {
        case .interactive:
            return "What is this team thread for?"
        case .autonomous:
            return "What should this team start doing immediately?"
        case .worker:
            return "What should this team handle now and be ready to handle again later?"
        }
    }

    private var goalHelpText: String {
        let defaultHint = "Starts with the group default when available, but you can tweak it before opening the thread."
        switch executionMode {
        case .interactive:
            return "\(defaultHint) On the first real turn, the team will treat this as the saved group objective."
        case .autonomous:
            return "\(defaultHint) The goal is posted into the thread and sent immediately to the coordinator."
        case .worker:
            return "\(defaultHint) The goal launches the first coordinator-led run now, then the same thread returns to standby."
        }
    }

    private var modeConstraintText: String? {
        guard executionMode != .interactive,
              let selectedGroup,
              selectedGroup.coordinatorAgentId == nil,
              !selectedGroup.autonomousCapable else {
            return nil
        }
        return "This team needs a coordinator or autonomous-capable fallback before autonomous or worker mode can start."
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(startActionSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .xrayId("newGroupThread.footerSummary")
                Text("Choose a reusable team and start a project thread.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button(primaryActionTitle) {
                startGroupThread()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return)
            .disabled(!canStart)
            .xrayId("newGroupThread.startButton")
        }
        .padding(16)
    }

    private var startActionSummary: String {
        let teamName = selectedGroup?.name ?? "Team"
        switch executionMode {
        case .interactive:
            return "\(teamName) will wait for your first message."
        case .autonomous:
            return "\(teamName) will launch the kickoff goal through the coordinator immediately."
        case .worker:
            return "\(teamName) will run the first job, then stay ready in the same thread."
        }
    }

    private var primaryActionTitle: String {
        switch executionMode {
        case .interactive:
            return "Start Group Thread"
        case .autonomous:
            return "Launch Autonomous Group"
        case .worker:
            return "Start Group Worker"
        }
    }

    private func startGroupThread() {
        guard let selectedGroup else { return }
        if let conversationId = appState.startGroupChat(
            group: selectedGroup,
            projectDirectory: windowState.projectDirectory,
            projectId: windowState.selectedProjectId,
            modelContext: modelContext,
            missionOverride: mission,
            executionMode: executionMode
        ) {
            windowState.selectedConversationId = conversationId
            let trimmedMission = mission.trimmingCharacters(in: .whitespacesAndNewlines)
            if executionMode != .interactive, !trimmedMission.isEmpty {
                windowState.autoSendText = trimmedMission
            }
        }
        dismiss()
    }
}
