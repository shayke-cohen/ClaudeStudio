import SwiftUI
import SwiftData

struct GroupDetailView: View {
    let groupId: UUID
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState: WindowState
    @Environment(\.modelContext) private var modelContext
    @Query private var allGroups: [AgentGroup]
    @Query private var allAgents: [Agent]
    @Query private var allConversations: [Conversation]
    @AppStorage(FeatureFlags.showAdvancedKey, store: AppSettings.store) private var masterFlag = false
    @AppStorage(FeatureFlags.autonomousMissionsKey, store: AppSettings.store) private var autonomousMissionsFlag = false
    @State private var editingGroup: AgentGroup?
    @State private var showDeleteConfirm = false
    @State private var autonomousGroup: AgentGroup?
    @State private var instructionExpanded = false
    @State private var showingScheduleEditor = false
    @State private var scheduleDraft = ScheduledMissionDraft()

    private var autonomousMissionsEnabled: Bool { FeatureFlags.isEnabled(FeatureFlags.autonomousMissionsKey) || (masterFlag && autonomousMissionsFlag) }

    private var group: AgentGroup? { allGroups.first { $0.id == groupId } }

    private var resolvedAgents: [Agent] {
        guard let group else { return [] }
        let byId = Dictionary(uniqueKeysWithValues: allAgents.map { ($0.id, $0) })
        return group.agentIds.compactMap { byId[$0] }
    }

    private var groupConversations: [Conversation] {
        allConversations
            .filter { $0.sourceGroupId == groupId }
            .sorted { $0.startedAt > $1.startedAt }
    }

    var body: some View {
        if let group {
            ScrollView {
                VStack(spacing: 0) {
                    heroHeader(group)
                    bodyGrid(group)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor))
            .xrayId("groupDetail.scrollView")
            .sheet(item: $editingGroup) { g in
                GroupEditorView(group: g)
            }
            .sheet(item: $autonomousGroup) { g in
                AutonomousMissionSheet(group: g)
            }
            .sheet(isPresented: $showingScheduleEditor) {
                ScheduleEditorView(schedule: nil, draft: scheduleDraft)
                    .environment(appState)
                    .environment(\.modelContext, modelContext)
            }
            .alert("Delete Group?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) { deleteGroup(group) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete \"\(group.name)\". Existing conversations will be kept.")
            }
        } else {
            ContentUnavailableView("Group Not Found", systemImage: "exclamationmark.triangle")
                .xrayId("groupDetail.notFound")
        }
    }

    // MARK: - Hero Header

    @ViewBuilder
    private func heroHeader(_ group: AgentGroup) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 16) {
                    Text(group.icon)
                        .font(.system(size: 40))
                        .frame(width: 64, height: 64)
                        .background(Color.fromAgentColor(group.color).opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .xrayId("groupDetail.icon")

                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.name)
                            .font(.title2)
                            .fontWeight(.bold)
                            .lineLimit(1)
                            .xrayId("groupDetail.name")

                        if !group.groupDescription.isEmpty {
                            Text(group.groupDescription)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .xrayId("groupDetail.description")
                        }

                        HStack(spacing: 6) {
                            badgePill(originLabel(group), color: .secondary)
                            if group.autoReplyEnabled {
                                badgePill("Auto-Reply", color: .green)
                            }
                            if group.autonomousCapable {
                                badgePill("Autonomous", color: .orange)
                            }
                            if group.workflow != nil {
                                badgePill("\(group.workflow!.count)-Step Workflow", color: .teal)
                            }
                        }
                        .xrayId("groupDetail.badges")
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    Button {
                        if let convoId = appState.startGroupChat(
                            group: group,
                            projectDirectory: "",
                            projectId: nil,
                            modelContext: modelContext
                        ) {
                            windowState.selectedConversationId = convoId
                        }
                    } label: {
                        Label("Start Chat", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .xrayId("groupDetail.startChatButton")

                    if autonomousMissionsEnabled && group.autonomousCapable {
                        Button {
                            autonomousGroup = group
                        } label: {
                            Label("Autonomous", systemImage: "bolt.fill")
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                        .controlSize(.regular)
                        .xrayId("groupDetail.autonomousButton")
                    }

                    Button {
                        editingGroup = group
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .xrayId("groupDetail.editButton")

                    Button {
                        scheduleDraft = ScheduledMissionDraft(
                            name: "\(group.name) schedule",
                            targetKind: .group,
                            projectDirectory: windowState.projectDirectory,
                            promptTemplate: group.defaultMission ?? ""
                        )
                        scheduleDraft.targetGroupId = group.id
                        scheduleDraft.targetConversationId = groupConversations.first?.id
                        scheduleDraft.sourceConversationId = groupConversations.first?.id
                        scheduleDraft.usesAutonomousMode = group.autonomousCapable
                        showingScheduleEditor = true
                    } label: {
                        Label("Schedule", systemImage: "clock.badge")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .xrayId("groupDetail.scheduleButton")
                    .accessibilityLabel("Schedule")

                    Menu {
                        Button("Duplicate") { duplicateGroup(group) }
                        Divider()
                        Button("Delete", role: .destructive) { showDeleteConfirm = true }
                    } label: {
                        Label("More", systemImage: "ellipsis")
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 30)
                    .xrayId("groupDetail.moreMenu")
                }
            }
            .padding(24)

            Divider()
        }
    }

    // MARK: - Body Grid

    @ViewBuilder
    private func bodyGrid(_ group: AgentGroup) -> some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                teamCard(group)
                activityCard
            }

            if let steps = group.workflow, !steps.isEmpty {
                workflowCard(steps, group: group)
            }

            if !group.groupInstruction.isEmpty {
                instructionCard(group.groupInstruction)
            }

            conversationsCard
        }
        .padding(24)
    }

    // MARK: - Team Card

    @ViewBuilder
    private func teamCard(_ group: AgentGroup) -> some View {
        card(title: "Team (\(resolvedAgents.count) agents)") {
            VStack(spacing: 0) {
                ForEach(resolvedAgents) { agent in
                    HStack(spacing: 10) {
                        Image(systemName: agent.icon)
                            .font(.caption)
                            .frame(width: 28, height: 28)
                            .foregroundStyle(Color.fromAgentColor(agent.color))
                            .background(Color.fromAgentColor(agent.color).opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 7))

                        Text(agent.name)
                            .font(.callout)

                        Spacer()

                        let role = group.roleFor(agentId: agent.id)
                        Text(role.displayName)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(roleColor(role).opacity(0.15))
                            .foregroundStyle(roleColor(role))
                            .clipShape(Capsule())
                    }
                    .padding(.vertical, 6)
                    .xrayId("groupDetail.agentRow.\(agent.id.uuidString)")

                    if agent.id != resolvedAgents.last?.id {
                        Divider()
                    }
                }
            }
        }
        .xrayId("groupDetail.teamCard")
    }

    // MARK: - Activity Card

    @ViewBuilder
    private var activityCard: some View {
        let convos = groupConversations
        let totalMessages = convos.reduce(0) { $0 + ($1.messages ?? []).count }

        card(title: "Activity") {
            VStack(spacing: 12) {
                HStack(spacing: 24) {
                    statBlock(value: "\(convos.count)", label: "Conversations")
                    statBlock(value: "\(totalMessages)", label: "Messages")
                }

                if let latest = convos.first {
                    HStack {
                        Text("Last active")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Text(latest.startedAt, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .xrayId("groupDetail.activityCard")
    }

    // MARK: - Workflow Card

    @ViewBuilder
    private func workflowCard(_ steps: [WorkflowStep], group: AgentGroup) -> some View {
        let agentById = Dictionary(uniqueKeysWithValues: allAgents.map { ($0.id, $0) })
        card(title: "Workflow Pipeline") {
            VStack(spacing: 8) {
                HStack(spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        VStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(Color.accentColor.opacity(0.15))
                                    .frame(width: 36, height: 36)
                                Text("\(index + 1)")
                                    .font(.callout)
                                    .fontWeight(.bold)
                                    .foregroundStyle(Color.accentColor)
                            }
                            Text(step.stepLabel ?? "Step \(index + 1)")
                                .font(.caption)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            if let agent = agentById[step.agentId] {
                                Text(agent.name)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .xrayId("groupDetail.workflowStep.\(index)")

                        if index < steps.count - 1 {
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.quaternary)
                                .frame(width: 20)
                        }
                    }
                }

                HStack(spacing: 12) {
                    let autoCount = steps.filter(\.autoAdvance).count
                    Text("\(autoCount)/\(steps.count) auto-advance")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if steps.contains(where: { $0.condition != nil }) {
                        Text("Has conditions")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .xrayId("groupDetail.workflowCard")
    }

    // MARK: - Instruction Card

    @ViewBuilder
    private func instructionCard(_ instruction: String) -> some View {
        card(title: "Group Instruction") {
            VStack(alignment: .leading, spacing: 8) {
                Text(instruction)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(instructionExpanded ? nil : 3)
                    .xrayId("groupDetail.instructionText")

                if instruction.count > 150 {
                    Button(instructionExpanded ? "Show Less" : "Show More") {
                        withAnimation { instructionExpanded.toggle() }
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .xrayId("groupDetail.instructionToggle")
                }
            }
        }
        .xrayId("groupDetail.instructionCard")
    }

    // MARK: - Conversations Card

    @ViewBuilder
    private var conversationsCard: some View {
        let convos = groupConversations
        card(title: "Recent Conversations") {
            if convos.isEmpty {
                Text("No conversations yet")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 4) {
                    ForEach(convos.prefix(8)) { conv in
                        Button {
                            windowState.selectedConversationId = conv.id
                        } label: {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(isActive(conv) ? Color.green : Color.gray.opacity(0.4))
                                    .frame(width: 8, height: 8)
                                Text(conv.topic ?? "Untitled")
                                    .font(.callout)
                                    .lineLimit(1)
                                Spacer()
                                if let step = conv.workflowCurrentStep, let total = conv.workflowCompletedSteps {
                                    Text("Step \(step + 1)/\(total.count > 0 ? total.count : step + 1)")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.teal.opacity(0.15))
                                        .foregroundStyle(.teal)
                                        .clipShape(Capsule())
                                }
                                Text(conv.startedAt, style: .relative)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.03)))
                        .xrayId("groupDetail.conversationRow.\(conv.id.uuidString)")
                    }
                }
            }
        }
        .xrayId("groupDetail.conversationsCard")
    }

    // MARK: - Shared Components

    @ViewBuilder
    private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary, lineWidth: 1))
    }

    @ViewBuilder
    private func badgePill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func statBlock(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Helpers

    private func roleColor(_ role: GroupRole) -> Color {
        switch role {
        case .coordinator: .orange
        case .scribe: .purple
        case .observer: .gray
        case .participant: .secondary
        }
    }

    private func originLabel(_ group: AgentGroup) -> String {
        switch group.origin {
        case .local: "Local"
        case .peer: "Shared"
        case .imported: "Imported"
        case .builtin: "Built-in"
        }
    }

    private func isActive(_ conv: Conversation) -> Bool {
        (conv.sessions ?? []).contains { $0.status == .active }
    }

    private func duplicateGroup(_ group: AgentGroup) {
        let copy = AgentGroup(
            name: group.name + " Copy",
            groupDescription: group.groupDescription,
            icon: group.icon,
            color: group.color,
            groupInstruction: group.groupInstruction,
            defaultMission: group.defaultMission,
            agentIds: group.agentIds,
            sortOrder: group.sortOrder
        )
        copy.autoReplyEnabled = group.autoReplyEnabled
        copy.autonomousCapable = group.autonomousCapable
        copy.coordinatorAgentId = group.coordinatorAgentId
        copy.agentRolesJSON = group.agentRolesJSON
        copy.workflowJSON = group.workflowJSON
        modelContext.insert(copy)
        try? modelContext.save()
    }

    private func deleteGroup(_ group: AgentGroup) {
        for template in (group.promptTemplates ?? []) { modelContext.delete(template) }
        modelContext.delete(group)
        try? modelContext.save()
        windowState.selectedGroupId = nil
    }
}
