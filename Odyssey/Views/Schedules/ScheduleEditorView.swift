import AppKit
import SwiftData
import SwiftUI

struct ScheduleEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Environment(WindowState.self) private var windowState: WindowState
    @Query(sort: \Agent.name) private var agents: [Agent]
    @Query(sort: \AgentGroup.sortOrder) private var groups: [AgentGroup]
    @Query(sort: \Conversation.startedAt, order: .reverse) private var conversations: [Conversation]
    @Query(sort: \Project.lastOpenedAt, order: .reverse) private var projects: [Project]

    let schedule: ScheduledMission?
    let initialDraft: ScheduledMissionDraft

    @State private var draft: ScheduledMissionDraft

    init(schedule: ScheduledMission?, draft: ScheduledMissionDraft) {
        self.schedule = schedule
        self.initialDraft = draft
        _draft = State(initialValue: draft)
    }

    private var isEditing: Bool { schedule != nil }

    private var filteredConversations: [Conversation] {
        conversations.filter {
            !$0.sessions.isEmpty
                && ($0.projectId == draft.projectId || $0.id == draft.targetConversationId)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if !isEditing {
                        templateChipsSection
                    }
                    identitySection
                    targetSection
                    missionSection
                    runBehaviorSection
                    cadenceSection
                    reliabilitySection
                }
                .padding(24)
            }
            footer
        }
        .frame(minWidth: 760, minHeight: 760)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            draft = initialDraft
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isEditing ? "Edit Schedule" : "New Schedule")
                .font(.system(size: 30, weight: .bold))
            Text("Define what should run, where it should run, and how often Odyssey should trigger it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 20)
    }

    private struct ScheduleTemplate {
        let name: String
        let displayName: String
        let scheduleName: String
        let cadenceKind: ScheduledMissionCadenceKind
        let intervalHours: Int
        let localHour: Int
        let localMinute: Int
        let daysOfWeek: [ScheduledMissionWeekday]
        let promptTemplate: String
    }

    private static let scheduleTemplates: [ScheduleTemplate] = [
        ScheduleTemplate(
            name: "dailyStandup",
            displayName: "Daily standup at 9 AM",
            scheduleName: "Daily Standup",
            cadenceKind: .dailyTime,
            intervalHours: 1,
            localHour: 9,
            localMinute: 0,
            daysOfWeek: [.monday, .tuesday, .wednesday, .thursday, .friday],
            promptTemplate: "Summarize what this project worked on yesterday and any open blockers."
        ),
        ScheduleTemplate(
            name: "weeklyCleanup",
            displayName: "Weekly cleanup on Friday",
            scheduleName: "Weekly Cleanup",
            cadenceKind: .dailyTime,
            intervalHours: 1,
            localHour: 17,
            localMinute: 0,
            daysOfWeek: [.friday],
            promptTemplate: "Review the project for stale branches, open PRs, and any cleanup tasks to wrap up the week."
        ),
        ScheduleTemplate(
            name: "hourlyCheck",
            displayName: "Hourly check",
            scheduleName: "Hourly Check",
            cadenceKind: .hourlyInterval,
            intervalHours: 1,
            localHour: 9,
            localMinute: 0,
            daysOfWeek: [],
            promptTemplate: "Check for any new issues, alerts, or important updates in the project."
        ),
    ]

    private var templateChipsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Start from a template")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(Self.scheduleTemplates, id: \.name) { template in
                    Button(template.displayName) {
                        applyTemplate(template)
                    }
                    .buttonStyle(.bordered)
                    .stableXrayId("scheduleEditor.template.\(template.name)")
                }
                Button("Custom") {
                    draft = ScheduledMissionDraft(
                        projectDirectory: draft.projectDirectory
                    )
                    draft.projectId = initialDraft.projectId
                }
                .buttonStyle(.bordered)
                .stableXrayId("scheduleEditor.template.custom")
            }
        }
    }

    private func applyTemplate(_ template: ScheduleTemplate) {
        draft.name = template.scheduleName
        draft.cadenceKind = template.cadenceKind
        draft.intervalHours = template.intervalHours
        draft.localHour = template.localHour
        draft.localMinute = template.localMinute
        draft.daysOfWeek = template.daysOfWeek
        draft.promptTemplate = template.promptTemplate
    }

    private var identitySection: some View {
        ScheduleEditorSectionCard(
            title: "Identity",
            description: "Give the mission a clear name and choose the folder Odyssey should use as the working directory."
        ) {
            VStack(alignment: .leading, spacing: 18) {
                ScheduleEditorFieldRow(
                    title: "Schedule name",
                    detail: "Appears in the schedule library, run history, and notifications."
                ) {
                    TextField("Hourly bug triage", text: $draft.name)
                        .textFieldStyle(.roundedBorder)
                        .stableXrayId("scheduleEditor.nameField")
                        .help("A short, descriptive title for this recurring mission.")
                }

                ScheduleEditorFieldRow(
                    title: "Project folder",
                    detail: "The folder the agent or group should work in when this schedule runs."
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            TextField("/Users/you/project", text: $draft.projectDirectory)
                                .textFieldStyle(.roundedBorder)
                                .stableXrayId("scheduleEditor.projectDirectoryField")
                                .help("This path is used as the working directory and is also available in the prompt as {{projectDirectory}}.")

                            Button("Browse…") {
                                browseProjectDirectory()
                            }
                            .stableXrayId("scheduleEditor.projectDirectoryBrowseButton")
                            .help("Pick a folder from Finder.")
                        }

                        if draft.projectDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Label("Choose the repository or workspace folder this mission should use.", systemImage: "folder.badge.questionmark")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .stableXrayId("scheduleEditor.projectDirectoryHint")
                        } else {
                            Label(abbreviatedPath(draft.projectDirectory), systemImage: "folder")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .stableXrayId("scheduleEditor.projectDirectorySummary")
                        }
                    }
                }
            }
        }
    }

    private var targetSection: some View {
        ScheduleEditorSectionCard(
            title: "Target",
            description: "Choose who should receive the scheduled mission when it fires."
        ) {
            VStack(alignment: .leading, spacing: 18) {
                ScheduleEditorFieldRow(
                    title: "Target type",
                    detail: "Pick whether this mission starts an agent, a group, or resumes a specific conversation."
                ) {
                    Picker("Target type", selection: $draft.targetKind) {
                        ForEach(ScheduledMissionTargetKind.allCases, id: \.self) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .stableXrayId("scheduleEditor.targetKindPicker")
                    .help("Agent starts a single agent, Group runs a team, and Conversation sends into an existing thread.")
                }

                switch draft.targetKind {
                case .agent:
                    ScheduleEditorFieldRow(
                        title: "Agent",
                        detail: "The selected agent will receive the prompt and run with its saved tools and permissions."
                    ) {
                        Picker("Agent", selection: $draft.targetAgentId) {
                            Text("Select an agent").tag(UUID?.none)
                            ForEach(agents) { agent in
                                Text(agent.name).tag(UUID?.some(agent.id))
                            }
                        }
                        .stableXrayId("scheduleEditor.agentPicker")
                        .help("Pick the agent that should handle this mission.")
                    }

                case .group:
                    ScheduleEditorFieldRow(
                        title: "Group",
                        detail: "The selected group will receive the mission and coordinate using its configured members."
                    ) {
                        VStack(alignment: .leading, spacing: 10) {
                            Picker("Group", selection: $draft.targetGroupId) {
                                Text("Select a group").tag(UUID?.none)
                                ForEach(groups) { group in
                                    Text(group.name).tag(UUID?.some(group.id))
                                }
                            }
                            .stableXrayId("scheduleEditor.groupPicker")
                            .help("Pick the group that should run this scheduled mission.")

                            if let groupId = draft.targetGroupId,
                               let group = groups.first(where: { $0.id == groupId }),
                               group.autonomousCapable {
                                Toggle("Use autonomous mode", isOn: $draft.usesAutonomousMode)
                                    .stableXrayId("scheduleEditor.autonomousToggle")
                                    .help("When enabled, the group can coordinate autonomously instead of staying in a standard group chat flow.")

                                Text("Autonomous mode lets this group self-coordinate if the selected group supports it.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                case .conversation:
                    conversationTargetField(
                        title: "Conversation",
                        detail: "The prompt will be appended to this existing thread whenever the schedule runs."
                    )
                case .project:
                    ScheduleEditorFieldRow(
                        title: "Project",
                        detail: "The mission will run in the context of the selected project using its default agent or team."
                    ) {
                        Picker("Project", selection: $draft.targetProjectId) {
                            Text("Select a project").tag(UUID?.none)
                            ForEach(projects) { project in
                                Text(project.name).tag(UUID?.some(project.id))
                            }
                        }
                        .stableXrayId("scheduleEditor.projectPicker")
                        .help("Pick the project this scheduled mission should run in.")
                    }
                }
            }
        }
    }

    private var missionSection: some View {
        ScheduleEditorSectionCard(
            title: "Mission",
            description: "Describe the recurring work clearly. The prompt should make sense on its own each time it runs."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                ScheduleEditorFieldRow(
                    title: "Prompt",
                    detail: "This text is sent when the schedule fires. Be explicit about the outcome you want."
                ) {
                    TextEditor(text: $draft.promptTemplate)
                        .font(.body)
                        .frame(minHeight: 170)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(nsColor: .textBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                        )
                        .stableXrayId("scheduleEditor.promptField")
                        .help("Write the recurring mission prompt. You can include template variables listed below.")
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Prompt variables")
                        .font(.subheadline.weight(.semibold))

                    Text("These values are filled in automatically when the mission runs.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], alignment: .leading, spacing: 10) {
                        ScheduleEditorTokenCard(token: "{{now}}", detail: "Current local date and time")
                        ScheduleEditorTokenCard(token: "{{lastRunAt}}", detail: "Most recent run, or never")
                        ScheduleEditorTokenCard(token: "{{lastSuccessAt}}", detail: "Most recent successful run, or never")
                        ScheduleEditorTokenCard(token: "{{runCount}}", detail: "How many times this schedule has run")
                        ScheduleEditorTokenCard(token: "{{projectDirectory}}", detail: "The selected working folder path")
                    }
                    .stableXrayId("scheduleEditor.promptTokens")
                }
            }
        }
    }

    private var runBehaviorSection: some View {
        ScheduleEditorSectionCard(
            title: "Run Behavior",
            description: "Decide whether the schedule starts a fresh conversation or reuses an existing thread."
        ) {
            VStack(alignment: .leading, spacing: 18) {
                ScheduleEditorFieldRow(
                    title: "Conversation mode",
                    detail: "Fresh is best for independent runs. Reuse is best when you want an ongoing thread."
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Mode", selection: $draft.runMode) {
                            ForEach(ScheduledMissionRunMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .stableXrayId("scheduleEditor.runModePicker")
                        .help("Fresh conversation creates a new thread each run. Reuse conversation appends to an existing thread.")

                        Text(runModeHelpText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if draft.runMode == .reuseConversation, draft.targetKind != .conversation {
                    conversationTargetField(
                        title: "Conversation to reuse",
                        detail: "Reuse mode needs an existing thread. Odyssey will append each run into the conversation you pick here."
                    )
                }
            }
        }
    }

    private var cadenceSection: some View {
        ScheduleEditorSectionCard(
            title: "Cadence",
            description: "Choose how often the mission should run."
        ) {
            VStack(alignment: .leading, spacing: 18) {
                cadenceKindField
                cadenceDetailSection
                Text(ScheduledMissionCadence.cadenceSummary(forDraft: draft))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .stableXrayId("scheduleEditor.cadencePreview")
            }
        }
    }

    private var cadenceKindField: some View {
        ScheduleEditorFieldRow(
            title: "Schedule type",
            detail: "Use hourly for regular repeat runs, or daily for specific times on selected weekdays."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Cadence", selection: $draft.cadenceKind) {
                    Text("Every N hours").tag(ScheduledMissionCadenceKind.hourlyInterval)
                    Text("Daily at time").tag(ScheduledMissionCadenceKind.dailyTime)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .stableXrayId("scheduleEditor.cadenceKindPicker")
                .help("Choose whether the schedule repeats every few hours or at a specific time of day.")

                Text(cadenceHelpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var cadenceDetailSection: some View {
        switch draft.cadenceKind {
        case .hourlyInterval:
            hourlyCadenceField
        case .dailyTime:
            dailyTimeField
            weekdaySelectionField
        }
    }

    private var hourlyCadenceField: some View {
        ScheduleEditorFieldRow(
            title: "Repeat interval",
            detail: "Use shorter intervals for monitoring or triage, and longer intervals for maintenance work."
        ) {
            Stepper(value: $draft.intervalHours, in: 1...24) {
                Text(draft.intervalHours == 1 ? "Every hour" : "Every \(draft.intervalHours) hours")
                    .font(.body.weight(.medium))
            }
            .stableXrayId("scheduleEditor.intervalStepper")
            .help("Controls how many hours pass between runs.")
        }
    }

    private var dailyTimeField: some View {
        ScheduleEditorFieldRow(
            title: "Run time",
            detail: "Pick the local time Odyssey should target for each scheduled run."
        ) {
            HStack(alignment: .top, spacing: 14) {
                Stepper("Hour: \(draft.localHour)", value: $draft.localHour, in: 0...23)
                    .stableXrayId("scheduleEditor.hourStepper")
                    .help("The local hour for the scheduled run.")
                Stepper("Minute: \(draft.localMinute)", value: $draft.localMinute, in: 0...59)
                    .stableXrayId("scheduleEditor.minuteStepper")
                    .help("The local minute for the scheduled run.")
            }
        }
    }

    private var weekdaySelectionField: some View {
        ScheduleEditorFieldRow(
            title: "Weekdays",
            detail: "Leave common workdays selected for weekday automations, or customize the exact days you need."
        ) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(ScheduledMissionWeekday.allCases) { day in
                    weekdayButton(for: day)
                }
            }
        }
    }

    private func weekdayButton(for day: ScheduledMissionWeekday) -> some View {
        let isSelected = draft.daysOfWeek.contains(day)

        return Button(day.shortLabel) {
            if isSelected {
                draft.daysOfWeek.removeAll { $0 == day }
            } else {
                draft.daysOfWeek.append(day)
                draft.daysOfWeek.sort { $0.rawValue < $1.rawValue }
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(isSelected ? .accentColor : Color.secondary.opacity(0.25))
        .stableXrayId("scheduleEditor.day.\(day.rawValue)")
        .help("Toggle \(day.displayName).")
    }

    private var reliabilitySection: some View {
        ScheduleEditorSectionCard(
            title: "Reliability",
            description: "Control whether the schedule is active and whether Odyssey should try to wake up for it while closed."
        ) {
            VStack(alignment: .leading, spacing: 18) {
                ScheduleEditorFieldRow(
                    title: "Enabled",
                    detail: "Turn this off to keep the schedule saved without letting it run."
                ) {
                    Toggle("Enabled", isOn: $draft.isEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .stableXrayId("scheduleEditor.enabledToggle")
                        .help("When disabled, the schedule stays saved but will not execute.")
                }

                ScheduleEditorFieldRow(
                    title: "Run while app is closed",
                    detail: "Exports a local launchd helper so Odyssey can wake up and trigger the mission."
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Run while app is closed", isOn: $draft.runWhenAppClosed)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .stableXrayId("scheduleEditor.runWhenClosedToggle")
                            .help("Lets Odyssey install a local LaunchAgent so this schedule can wake the app when needed.")

                        Text("This only works on the current Mac and still uses the target agent or group’s existing permissions.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if let error = draft.validationError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .stableXrayId("scheduleEditor.validationError")
            } else {
                Text("Schedules save immediately. Enabled schedules become eligible to run using the cadence and reliability settings above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
                    .stableXrayId("scheduleEditor.cancelButton")

                Spacer()

                Button(isEditing ? "Save Schedule" : "Create Schedule") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .disabled(draft.validationError != nil)
                .keyboardShortcut(.return)
                .stableXrayId("scheduleEditor.saveButton")
                .help("Save this schedule and apply the updated configuration.")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(.bar)
    }

    private var runModeHelpText: String {
        switch draft.runMode {
        case .freshConversation:
            return "Each run starts a new conversation, which keeps outputs isolated and easier to review later."
        case .reuseConversation:
            return "Each run appends into one existing conversation so the thread keeps its context over time. Pick the thread below if you are not already targeting a conversation."
        }
    }

    private func conversationTargetField(title: String, detail: String) -> some View {
        ScheduleEditorFieldRow(title: title, detail: detail) {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Conversation", selection: $draft.targetConversationId) {
                    Text("Select a conversation").tag(UUID?.none)
                    ForEach(filteredConversations) { conversation in
                        Text(conversation.topic ?? "Untitled")
                            .tag(UUID?.some(conversation.id))
                    }
                }
                .stableXrayId("scheduleEditor.conversationPicker")
                .help("Pick the conversation that should receive scheduled follow-up messages.")

                if draft.targetConversationId == nil {
                    Text("Choose an existing thread to preserve context between scheduled runs.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .stableXrayId("scheduleEditor.conversationHint")
                }
            }
        }
    }

    private var cadenceHelpText: String {
        switch draft.cadenceKind {
        case .hourlyInterval:
            return "Hourly cadence is useful for ongoing monitoring, issue triage, or regular cleanup."
        case .dailyTime:
            return "Daily cadence is useful for morning sweeps, handoffs, or scheduled reviews on specific weekdays."
        }
    }

    private func browseProjectDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Folder"
        panel.message = "Choose the project folder this schedule should run in."

        let trimmedPath = draft.projectDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPath.isEmpty {
            let expandedPath = NSString(string: trimmedPath).expandingTildeInPath
            panel.directoryURL = URL(fileURLWithPath: expandedPath)
        } else {
            panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
        }

        if panel.runModal() == .OK, let url = panel.url {
            draft.projectDirectory = url.path
        }
    }

    private func abbreviatedPath(_ path: String) -> String {
        NSString(string: path).abbreviatingWithTildeInPath
    }

    private func save() {
        guard draft.validationError == nil else { return }
        let now = Date()
        let project = ProjectRecords.upsertProject(at: draft.projectDirectory, in: modelContext)

        let schedule = schedule ?? ScheduledMission(
            name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            targetKind: draft.targetKind,
            projectDirectory: draft.projectDirectory,
            promptTemplate: draft.promptTemplate
        )

        schedule.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        schedule.projectId = draft.projectId ?? project.id
        schedule.isEnabled = draft.isEnabled
        schedule.targetKind = draft.targetKind
        schedule.targetAgentId = draft.targetKind == .agent ? draft.targetAgentId : nil
        schedule.targetGroupId = draft.targetKind == .group ? draft.targetGroupId : nil
        schedule.targetConversationId = draft.runMode == .reuseConversation || draft.targetKind == .conversation
            ? draft.targetConversationId
            : nil
        schedule.targetProjectId = draft.targetKind == .project ? draft.targetProjectId : nil
        schedule.projectDirectory = draft.projectDirectory
        schedule.promptTemplate = draft.promptTemplate
        schedule.sourceConversationId = draft.sourceConversationId
        schedule.sourceMessageId = draft.sourceMessageId
        schedule.runMode = draft.runMode
        schedule.cadenceKind = draft.cadenceKind
        schedule.intervalHours = draft.cadenceKind == .hourlyInterval ? draft.intervalHours : nil
        schedule.localHour = draft.cadenceKind == .dailyTime ? draft.localHour : nil
        schedule.localMinute = draft.cadenceKind == .dailyTime ? draft.localMinute : nil
        schedule.daysOfWeek = draft.cadenceKind == .dailyTime ? draft.daysOfWeek : []
        schedule.runWhenAppClosed = draft.runWhenAppClosed
        schedule.usesAutonomousMode = draft.usesAutonomousMode
        schedule.updatedAt = now

        if self.schedule == nil {
            modelContext.insert(schedule)
        }
        try? modelContext.save()
        windowState.selectProject(project, preserveSelection: true)
        appState.syncScheduledMission(schedule)
        dismiss()
    }
}

private struct ScheduleEditorSectionCard<Content: View>: View {
    let title: String
    let description: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        )
    }
}

private struct ScheduleEditorFieldRow<Content: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 200, alignment: .leading)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ScheduleEditorTokenCard: View {
    let token: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(token)
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(.primary)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
        .help(detail)
    }
}
