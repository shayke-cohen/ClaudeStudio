import SwiftUI
import SwiftData

struct ScheduleLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Environment(WindowState.self) private var windowState: WindowState
    @Query(sort: \ScheduledMission.updatedAt, order: .reverse) private var schedules: [ScheduledMission]
    @Query(sort: \ScheduledMissionRun.startedAt, order: .reverse) private var runs: [ScheduledMissionRun]
    @Query(sort: \Agent.name) private var agents: [Agent]
    @Query(sort: \AgentGroup.sortOrder) private var groups: [AgentGroup]
    @Query(sort: \Conversation.startedAt, order: .reverse) private var conversations: [Conversation]

    @State private var selectedScheduleId: UUID?
    @State private var searchText = ""
    @State private var filterEnabledOnly = false
    @State private var editingSchedule: ScheduledMission?
    @State private var editorDraft = ScheduledMissionDraft()
    @State private var showingEditor = false

    private var filteredSchedules: [ScheduledMission] {
        schedules.filter { schedule in
            let matchesProject = schedule.projectId == windowState.selectedProjectId
            let matchesSearch = searchText.isEmpty
                || schedule.name.localizedCaseInsensitiveContains(searchText)
                || schedule.promptTemplate.localizedCaseInsensitiveContains(searchText)
            let matchesFilter = !filterEnabledOnly || schedule.isEnabled
            return matchesProject && matchesSearch && matchesFilter
        }
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                header
                Divider()
                if filteredSchedules.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "clock.badge")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("No schedules for this project")
                            .font(.headline)
                        Text("Schedule recurring agent missions — daily standups, weekly cleanups, hourly inbox checks.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        Button("Create Your First Schedule") {
                            editingSchedule = nil
                            editorDraft = ScheduledMissionDraft(projectDirectory: windowState.projectDirectory)
                            editorDraft.projectId = windowState.selectedProjectId
                            showingEditor = true
                        }
                        .buttonStyle(.borderedProminent)
                        .stableXrayId("scheduleLibrary.createFirstButton")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .stableXrayId("scheduleLibrary.emptyState")
                } else {
                    List(filteredSchedules, selection: $selectedScheduleId) { schedule in
                        row(for: schedule)
                            .tag(schedule.id)
                            .contextMenu {
                                Button("Run Now") {
                                    appState.runScheduledMissionNow(schedule.id, windowState: windowState)
                                }
                                Button("Edit") {
                                    openEditor(for: schedule)
                                }
                                Button("Duplicate") {
                                    duplicate(schedule)
                                }
                                Button(schedule.isEnabled ? "Disable" : "Enable") {
                                    schedule.isEnabled.toggle()
                                    appState.syncScheduledMission(schedule)
                                }
                                Divider()
                                Button("Delete", role: .destructive) {
                                    delete(schedule)
                                }
                            }
                    }
                    .listStyle(.sidebar)
                    .stableXrayId("scheduleLibrary.list")
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
            }
            .frame(minWidth: 320, idealWidth: 360)

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
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 900, minHeight: 560)
        .sheet(isPresented: $showingEditor) {
            ScheduleEditorView(schedule: editingSchedule, draft: editorDraft)
                .environmentObject(appState)
                .environment(\.modelContext, modelContext)
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Scheduled Missions")
                    .font(.title2.bold())
                Spacer()
                Button {
                    editingSchedule = nil
                    editorDraft = ScheduledMissionDraft(projectDirectory: windowState.projectDirectory)
                    editorDraft.projectId = windowState.selectedProjectId
                    showingEditor = true
                } label: {
                    Label("New Schedule", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .stableXrayId("scheduleLibrary.newButton")

                Button("Done") { dismiss() }
                    .keyboardShortcut(.escape)
                    .stableXrayId("scheduleLibrary.doneButton")
            }

            HStack {
                TextField("Search schedules...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .stableXrayId("scheduleLibrary.searchField")

                Picker("Filter", selection: $filterEnabledOnly) {
                    Text("All").tag(false)
                    Text("Enabled").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                .stableXrayId("scheduleLibrary.filterPicker")
            }
        }
        .padding()
    }

    private func row(for schedule: ScheduledMission) -> some View {
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
            Text("\(targetName(for: schedule)) · \(ScheduledMissionCadence.cadenceSummary(for: schedule))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(schedule.nextRunAt.map { "Next: \($0.formatted(date: .omitted, time: .shortened))" } ?? "Not scheduled")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .stableXrayId("scheduleLibrary.row.\(schedule.id.uuidString)")
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

    private func targetName(for schedule: ScheduledMission) -> String {
        switch schedule.targetKind {
        case .agent:
            return agents.first(where: { $0.id == schedule.targetAgentId })?.name ?? "Agent"
        case .group:
            return groups.first(where: { $0.id == schedule.targetGroupId })?.name ?? "Group"
        case .conversation:
            return conversations.first(where: { $0.id == schedule.targetConversationId })?.topic ?? "Conversation"
        case .project:
            return "Project"
        }
    }

    private func color(for status: ScheduledMissionRunStatus) -> Color {
        switch status {
        case .running: return .blue
        case .succeeded: return .green
        case .failed: return .red
        case .skipped: return .orange
        }
    }
}
