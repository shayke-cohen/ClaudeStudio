import SwiftUI
import SwiftData

struct GlobalSchedulesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState: WindowState

    @Query(sort: \ScheduledMission.updatedAt, order: .reverse) private var allSchedules: [ScheduledMission]
    @Query(sort: \ScheduledMissionRun.startedAt, order: .reverse) private var runs: [ScheduledMissionRun]
    @Query(sort: \Project.lastOpenedAt, order: .reverse) private var projects: [Project]
    @Query(sort: \Agent.name) private var agents: [Agent]
    @Query(sort: \AgentGroup.sortOrder) private var groups: [AgentGroup]
    @Query(sort: \Conversation.startedAt, order: .reverse) private var conversations: [Conversation]

    @State private var selectedScheduleId: UUID?
    @State private var searchText = ""
    @State private var filterProjectId: UUID? = nil
    @State private var filterExecutorId: UUID? = nil
    @State private var filterEnabledOnly = false
    @State private var editingSchedule: ScheduledMission?
    @State private var editorDraft = ScheduledMissionDraft()
    @State private var showingEditor = false

    private var filteredSchedules: [ScheduledMission] {
        allSchedules.filter { schedule in
            let matchesProject = filterProjectId == nil || schedule.projectId == filterProjectId
            let matchesExecutor: Bool = {
                guard let eid = filterExecutorId else { return true }
                return schedule.targetAgentId == eid || schedule.targetGroupId == eid
            }()
            let matchesEnabled = !filterEnabledOnly || schedule.isEnabled
            let matchesSearch = searchText.isEmpty
                || schedule.name.localizedCaseInsensitiveContains(searchText)
                || schedule.promptTemplate.localizedCaseInsensitiveContains(searchText)
            return matchesProject && matchesExecutor && matchesEnabled && matchesSearch
        }
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                header
                Divider()
                filterBar
                Divider()
                if filteredSchedules.isEmpty {
                    emptyState
                } else {
                    scheduleList
                }
            }
            .frame(minWidth: 360, idealWidth: 400)

            Group {
                if let selectedScheduleId {
                    ScheduleDetailView(
                        scheduleId: selectedScheduleId,
                        onEdit: { openEditor(for: $0) },
                        onDuplicate: { duplicate($0) },
                        onDelete: { delete($0) }
                    )
                } else {
                    ContentUnavailableView("Select a schedule", systemImage: "clock")
                }
            }
            .frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 940, minHeight: 560)
        .sheet(isPresented: $showingEditor) {
            ScheduleEditorView(schedule: editingSchedule, draft: editorDraft)
                .environment(appState)
                .environment(\.modelContext, modelContext)
        }
        .stableXrayId("globalSchedules.container")
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack {
                Label("All Schedules", systemImage: "clock.badge")
                    .font(.title2.bold())
                Spacer()
                Button {
                    editingSchedule = nil
                    editorDraft = ScheduledMissionDraft(projectDirectory: windowState.projectDirectory)
                    showingEditor = true
                } label: {
                    Label("New Schedule", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .stableXrayId("globalSchedules.newButton")
                Button("Done") { dismiss() }
                    .keyboardShortcut(.escape)
                    .stableXrayId("globalSchedules.doneButton")
            }
            HStack {
                TextField("Search schedules…", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .stableXrayId("globalSchedules.searchField")
                Picker("Filter", selection: $filterEnabledOnly) {
                    Text("All").tag(false)
                    Text("Enabled").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
                .stableXrayId("globalSchedules.enabledPicker")
            }
        }
        .padding()
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip("All Projects", isSelected: filterProjectId == nil) {
                    filterProjectId = nil
                }
                ForEach(projects) { project in
                    filterChip(project.name, color: .blue, isSelected: filterProjectId == project.id) {
                        filterProjectId = filterProjectId == project.id ? nil : project.id
                    }
                }

                Divider().frame(height: 20)

                filterChip("All Executors", isSelected: filterExecutorId == nil) {
                    filterExecutorId = nil
                }
                ForEach(agents) { agent in
                    filterChip(agent.name, color: .purple, isSelected: filterExecutorId == agent.id) {
                        filterExecutorId = filterExecutorId == agent.id ? nil : agent.id
                    }
                }
                ForEach(groups) { group in
                    filterChip(group.name, color: .green, isSelected: filterExecutorId == group.id) {
                        filterExecutorId = filterExecutorId == group.id ? nil : group.id
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .stableXrayId("globalSchedules.filterBar")
    }

    @ViewBuilder
    private func filterChip(_ label: String, color: Color = .accentColor, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isSelected ? color.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
                .foregroundStyle(isSelected ? color : .secondary)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(isSelected ? color.opacity(0.4) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.badge")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No schedules found")
                .font(.headline)
            Text("Schedule recurring agent missions — daily standups, weekly reports, hourly inbox checks.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Create Schedule") {
                editingSchedule = nil
                editorDraft = ScheduledMissionDraft(projectDirectory: windowState.projectDirectory)
                showingEditor = true
            }
            .buttonStyle(.borderedProminent)
            .stableXrayId("globalSchedules.emptyCreateButton")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .stableXrayId("globalSchedules.emptyState")
    }

    private var scheduleList: some View {
        List(filteredSchedules, selection: $selectedScheduleId) { schedule in
            scheduleRow(schedule)
                .tag(schedule.id)
                .contextMenu {
                    Button("Run Now") {
                        appState.runScheduledMissionNow(schedule.id, windowState: windowState)
                    }
                    Button("Edit") { openEditor(for: schedule) }
                    Button("Duplicate") { duplicate(schedule) }
                    Button(schedule.isEnabled ? "Disable" : "Enable") {
                        schedule.isEnabled.toggle()
                        appState.syncScheduledMission(schedule)
                    }
                    Divider()
                    Button("Delete", role: .destructive) { delete(schedule) }
                }
        }
        .listStyle(.sidebar)
        .stableXrayId("globalSchedules.list")
        .onAppear {
            if selectedScheduleId == nil {
                selectedScheduleId = filteredSchedules.first?.id
            }
        }
        .onChange(of: filteredSchedules.map(\.id)) { _, ids in
            if !ids.contains(where: { $0 == selectedScheduleId }) {
                selectedScheduleId = ids.first
            }
        }
    }

    private func scheduleRow(_ schedule: ScheduledMission) -> some View {
        let latestRun = runs.first(where: { $0.scheduleId == schedule.id })
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(schedule.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Circle()
                    .fill(latestRun.map { color(for: $0.status) } ?? .gray)
                    .frame(width: 8, height: 8)
            }
            HStack(spacing: 4) {
                contextBadges(for: schedule)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(ScheduledMissionCadence.cadenceSummary(for: schedule))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.tertiary)
                sessionModeLabel(schedule.runMode)
            }
            .lineLimit(1)
            Text(schedule.nextRunAt.map { "Next: \($0.formatted(date: .omitted, time: .shortened))" } ?? "Not scheduled")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .stableXrayId("globalSchedules.row.\(schedule.id.uuidString)")
    }

    @ViewBuilder
    private func contextBadges(for schedule: ScheduledMission) -> some View {
        if let pid = schedule.projectId,
           let project = projects.first(where: { $0.id == pid }) {
            badge(project.name, color: .blue)
        }
        switch schedule.targetKind {
        case .agent:
            if let aid = schedule.targetAgentId,
               let agent = agents.first(where: { $0.id == aid }) {
                badge(agent.name, color: .purple)
            }
        case .group:
            if let gid = schedule.targetGroupId,
               let group = groups.first(where: { $0.id == gid }) {
                badge(group.name, color: .green)
            }
        case .project:
            if let pid = schedule.targetProjectId,
               let project = projects.first(where: { $0.id == pid }) {
                badge(project.name, color: .blue)
            }
        case .conversation:
            badge("Conversation", color: .orange)
        }
    }

    @ViewBuilder
    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func sessionModeLabel(_ mode: ScheduledMissionRunMode) -> some View {
        switch mode {
        case .freshConversation:
            Label("New each time", systemImage: "arrow.counterclockwise")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .reuseConversation:
            Label("Continue session", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func color(for status: ScheduledMissionRunStatus) -> Color {
        switch status {
        case .running: .blue
        case .succeeded: .green
        case .failed: .red
        case .skipped: .gray
        }
    }

    private func openEditor(for schedule: ScheduledMission) {
        editingSchedule = schedule
        editorDraft = ScheduledMissionDraft(schedule: schedule)
        showingEditor = true
    }

    private func duplicate(_ schedule: ScheduledMission) {
        let copy = ScheduledMission(
            name: "\(schedule.name) Copy",
            targetKind: schedule.targetKind,
            projectDirectory: schedule.projectDirectory,
            promptTemplate: schedule.promptTemplate
        )
        copy.projectId = schedule.projectId
        copy.isEnabled = false
        copy.targetAgentId = schedule.targetAgentId
        copy.targetGroupId = schedule.targetGroupId
        copy.targetConversationId = schedule.targetConversationId
        copy.targetProjectId = schedule.targetProjectId
        copy.sourceConversationId = schedule.sourceConversationId
        copy.sourceMessageId = schedule.sourceMessageId
        copy.runMode = schedule.runMode
        copy.cadenceKind = schedule.cadenceKind
        copy.intervalHours = schedule.intervalHours
        copy.localHour = schedule.localHour
        copy.localMinute = schedule.localMinute
        copy.daysOfWeek = schedule.daysOfWeek
        copy.runWhenAppClosed = schedule.runWhenAppClosed
        copy.usesAutonomousMode = schedule.usesAutonomousMode
        modelContext.insert(copy)
        try? modelContext.save()
        appState.syncScheduledMission(copy)
        selectedScheduleId = copy.id
    }

    private func delete(_ schedule: ScheduledMission) {
        appState.removeScheduledMission(schedule)
        modelContext.delete(schedule)
        try? modelContext.save()
        selectedScheduleId = filteredSchedules.first(where: { $0.id != schedule.id })?.id
    }
}
