import Foundation

struct ScheduledMissionDraft: Identifiable, Sendable {
    var id: UUID?
    var projectId: UUID?
    var name: String
    var isEnabled: Bool
    var targetKind: ScheduledMissionTargetKind
    var targetAgentId: UUID?
    var targetGroupId: UUID?
    var targetConversationId: UUID?
    var targetProjectId: UUID?
    var projectDirectory: String
    var promptTemplate: String
    var sourceConversationId: UUID?
    var sourceMessageId: UUID?
    var runMode: ScheduledMissionRunMode
    var cadenceKind: ScheduledMissionCadenceKind
    var intervalHours: Int
    var localHour: Int
    var localMinute: Int
    var daysOfWeek: [ScheduledMissionWeekday]
    var runWhenAppClosed: Bool
    var usesAutonomousMode: Bool

    init(
        name: String = "",
        targetKind: ScheduledMissionTargetKind = .agent,
        projectDirectory: String = "",
        promptTemplate: String = ""
    ) {
        self.name = name
        self.projectId = nil
        self.isEnabled = true
        self.targetKind = targetKind
        self.projectDirectory = projectDirectory
        self.promptTemplate = promptTemplate
        self.runMode = .freshConversation
        self.cadenceKind = .hourlyInterval
        self.intervalHours = 1
        self.localHour = 9
        self.localMinute = 0
        self.daysOfWeek = [.monday, .tuesday, .wednesday, .thursday, .friday]
        self.runWhenAppClosed = false
        self.usesAutonomousMode = false
    }

    init(schedule: ScheduledMission) {
        self.id = schedule.id
        self.projectId = schedule.projectId
        self.name = schedule.name
        self.isEnabled = schedule.isEnabled
        self.targetKind = schedule.targetKind
        self.targetAgentId = schedule.targetAgentId
        self.targetGroupId = schedule.targetGroupId
        self.targetConversationId = schedule.targetConversationId
        self.targetProjectId = schedule.targetProjectId
        self.projectDirectory = schedule.projectDirectory
        self.promptTemplate = schedule.promptTemplate
        self.sourceConversationId = schedule.sourceConversationId
        self.sourceMessageId = schedule.sourceMessageId
        self.runMode = schedule.runMode
        self.cadenceKind = schedule.cadenceKind
        self.intervalHours = schedule.intervalHours ?? 1
        self.localHour = schedule.localHour ?? 9
        self.localMinute = schedule.localMinute ?? 0
        self.daysOfWeek = schedule.daysOfWeek
        self.runWhenAppClosed = schedule.runWhenAppClosed
        self.usesAutonomousMode = schedule.usesAutonomousMode
    }

    var validationError: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "A schedule name is required."
        }
        if promptTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Mission prompt is required."
        }
        if projectDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Project directory is required."
        }
        switch targetKind {
        case .agent:
            if targetAgentId == nil { return "Pick an agent target." }
        case .group:
            if targetGroupId == nil { return "Pick a group target." }
        case .conversation:
            if targetConversationId == nil { return "Pick a conversation target." }
        case .project:
            if targetProjectId == nil { return "Pick a project target." }
        }
        switch runMode {
        case .freshConversation:
            if targetKind == .conversation {
                return "Fresh conversation mode requires an agent or group target."
            }
        case .reuseConversation:
            if targetConversationId == nil {
                return "Reuse conversation mode requires a conversation target."
            }
        }
        switch cadenceKind {
        case .hourlyInterval:
            if !(1...24).contains(intervalHours) {
                return "Hourly schedules must be between 1 and 24 hours."
            }
        case .dailyTime:
            if !(0...23).contains(localHour) || !(0...59).contains(localMinute) {
                return "Pick a valid daily time."
            }
        }
        return nil
    }
}
