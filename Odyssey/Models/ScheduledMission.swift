import Foundation
import SwiftData

enum ScheduledMissionTargetKind: String, Codable, CaseIterable, Sendable {
    case agent
    case group
    case conversation
    case project

    var displayName: String {
        switch self {
        case .agent: return "Agent"
        case .group: return "Group"
        case .conversation: return "Conversation"
        case .project: return "Project"
        }
    }
}

enum ScheduledMissionRunMode: String, Codable, CaseIterable, Sendable {
    case freshConversation
    case reuseConversation

    var displayName: String {
        switch self {
        case .freshConversation: return "Fresh conversation"
        case .reuseConversation: return "Reuse conversation"
        }
    }
}

enum ScheduledMissionCadenceKind: String, Codable, CaseIterable, Sendable {
    case hourlyInterval
    case dailyTime
}

enum ScheduledMissionOverlapPolicy: String, Codable, Sendable {
    case skip
}

enum ScheduledMissionMissedRunPolicy: String, Codable, Sendable {
    case catchUpLatest
}

enum ScheduledMissionWeekday: Int, CaseIterable, Codable, Sendable, Identifiable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7

    var id: Int { rawValue }

    var shortLabel: String {
        switch self {
        case .sunday: return "Sun"
        case .monday: return "Mon"
        case .tuesday: return "Tue"
        case .wednesday: return "Wed"
        case .thursday: return "Thu"
        case .friday: return "Fri"
        case .saturday: return "Sat"
        }
    }

    var displayName: String {
        switch self {
        case .sunday: return "Sunday"
        case .monday: return "Monday"
        case .tuesday: return "Tuesday"
        case .wednesday: return "Wednesday"
        case .thursday: return "Thursday"
        case .friday: return "Friday"
        case .saturday: return "Saturday"
        }
    }
}

@Model
final class ScheduledMission {
    var id: UUID
    var projectId: UUID?
    var name: String
    var isEnabled: Bool
    var createdAt: Date
    var updatedAt: Date

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
    var intervalHours: Int?
    var localHour: Int?
    var localMinute: Int?
    var daysOfWeekJSON: String?
    var runWhenAppClosed: Bool
    var usesAutonomousMode: Bool

    var overlapPolicy: ScheduledMissionOverlapPolicy
    var missedRunPolicy: ScheduledMissionMissedRunPolicy
    var nextRunAt: Date?
    var lastEvaluatedAt: Date?
    var lastScheduledOccurrenceAt: Date?
    var lastStartedAt: Date?
    var lastSucceededAt: Date?
    var lastFailedAt: Date?
    var launchdJobLabel: String?

    @Transient
    var daysOfWeek: [ScheduledMissionWeekday] {
        get {
            guard let daysOfWeekJSON,
                  let data = daysOfWeekJSON.data(using: .utf8),
                  let rawValues = try? JSONDecoder().decode([Int].self, from: data) else {
                return []
            }
            return rawValues.compactMap(ScheduledMissionWeekday.init(rawValue:))
        }
        set {
            let rawValues = newValue.map(\.rawValue)
            daysOfWeekJSON = try? String(
                data: JSONEncoder().encode(rawValues),
                encoding: .utf8
            )
        }
    }

    init(
        name: String,
        targetKind: ScheduledMissionTargetKind,
        projectDirectory: String,
        promptTemplate: String
    ) {
        let now = Date()
        self.id = UUID()
        self.projectId = nil
        self.name = name
        self.isEnabled = true
        self.createdAt = now
        self.updatedAt = now
        self.targetKind = targetKind
        self.projectDirectory = projectDirectory
        self.promptTemplate = promptTemplate
        self.runMode = .freshConversation
        self.cadenceKind = .hourlyInterval
        self.intervalHours = 1
        self.runWhenAppClosed = false
        self.usesAutonomousMode = false
        self.overlapPolicy = .skip
        self.missedRunPolicy = .catchUpLatest
    }
}
