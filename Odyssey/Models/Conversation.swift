import Foundation
import SwiftData
import OdysseyCore

enum ThreadKind: String, Codable, CaseIterable, Sendable {
    case direct
    case group
    case freeform
    case autonomous
    case delegation
    case scheduled
}

enum ConversationStatus: String, Codable, Sendable {
    case active
    case closed
}

enum GroupRoutingMode: String, Codable, CaseIterable, Sendable {
    case mentionAware
    case broad

    var displayName: String {
        switch self {
        case .mentionAware: return "Mention-Aware"
        case .broad: return "Broad"
        }
    }

    var shortLabel: String {
        switch self {
        case .mentionAware: return "Mentions"
        case .broad: return "Broad"
        }
    }
}

enum ConversationExecutionMode: String, Codable, CaseIterable, Sendable {
    case interactive
    case autonomous
    case worker

    var displayName: String {
        switch self {
        case .interactive: return "Interactive"
        case .autonomous: return "Autonomous"
        case .worker: return "Worker"
        }
    }
}

@Model
final class Project {
    var id: UUID = UUID()
    var name: String = ""
    var rootPath: String = ""
    var canonicalRootPath: String = ""
    var createdAt: Date = Date()
    var lastOpenedAt: Date = Date()
    var isPinned: Bool = false
    var icon: String = "folder"
    var color: String = "blue"
    var pinnedAgentIds: [UUID] = []
    var pinnedGroupIds: [UUID] = []

    init(
        name: String,
        rootPath: String,
        canonicalRootPath: String,
        icon: String = "folder",
        color: String = "blue"
    ) {
        let now = Date()
        self.id = UUID()
        self.name = name
        self.rootPath = rootPath
        self.canonicalRootPath = canonicalRootPath
        self.createdAt = now
        self.lastOpenedAt = now
        self.icon = icon
        self.color = color
        self.pinnedAgentIds = []
        self.pinnedGroupIds = []
    }
}

@Model
final class Conversation {
    var id: UUID = UUID()
    var topic: String?
    var projectId: UUID?
    private var threadKindRaw: String?
    var parentConversationId: UUID?
    var status: ConversationStatus = ConversationStatus.active
    var summary: String?
    var isPinned: Bool = false
    var isArchived: Bool = false
    var sourceGroupId: UUID?
    var workflowCurrentStep: Int?
    var workflowCompletedSteps: [Int]?
    var isUnread: Bool = false
    var isAutonomous: Bool = false
    var planModeEnabled: Bool = false
    var selectiveRepliesEnabled: Bool = false
    private var routingModeRaw: String?
    private var executionModeRaw: String?
    var worktreePath: String?
    var worktreeBranch: String?
    var roomId: String?
    var roomOwnerUserId: String?
    var roomShareURL: String?
    var roomMembershipVersion: Int = 0
    var lastCloudKitSyncToken: String?
    var lastRoomHostSequence: Int = 0
    private var roomRoleRaw: String?
    private var roomStatusRaw: String?
    private var roomHistorySyncStateRaw: String?
    private var roomTransportModeRaw: String?
    // Phase 6 — transport origin
    var roomOriginKind: String = "local"
    var roomOriginHomeserver: String? = nil
    var roomOriginMatrixId: String? = nil
    // Delegation
    private var delegationModeRaw: String?
    var delegationTargetAgentName: String?
    var goal: String?
    var startedAt: Date = Date()
    var closedAt: Date?

    @Transient var pendingQuestionRouting: [String: String] = [:]
    @Transient var resolvedQuestions: [String: ResolvedQuestionInfo] = [:]

    @Relationship(deleteRule: .nullify, inverse: \Session.conversations)
    var sessions: [Session]? = nil

    @Relationship(deleteRule: .nullify, inverse: \Participant.conversation)
    var participants: [Participant]? = nil

    @Relationship(deleteRule: .nullify, inverse: \ConversationMessage.conversation)
    var messages: [ConversationMessage]? = nil

    init(
        topic: String? = nil,
        sessions: [Session] = [],
        projectId: UUID? = nil,
        threadKind: ThreadKind = .direct
    ) {
        self.id = UUID()
        self.topic = topic
        self.projectId = projectId
        self.threadKindRaw = threadKind.rawValue
        self.status = .active
        self.isPinned = false
        self.isArchived = false
        self.roomMembershipVersion = 0
        self.lastRoomHostSequence = 0
        self.startedAt = Date()
        self.sessions = sessions
    }

    /// First session by start time; used for inspector, delegate source, and single-agent UX.
    var primarySession: Session? {
        (sessions ?? []).min(by: { $0.startedAt < $1.startedAt })
    }

    var threadKind: ThreadKind {
        get { ThreadKind(rawValue: threadKindRaw ?? "") ?? .freeform }
        set { threadKindRaw = newValue.rawValue }
    }

    var routingMode: GroupRoutingMode {
        get {
            if let raw = routingModeRaw, let mode = GroupRoutingMode(rawValue: raw) {
                return mode
            }
            return selectiveRepliesEnabled ? .mentionAware : .broad
        }
        set {
            routingModeRaw = newValue.rawValue
            // Preserve the legacy flag so older persisted data can migrate lazily.
            selectiveRepliesEnabled = (newValue == .mentionAware)
        }
    }

    var executionMode: ConversationExecutionMode {
        get {
            if let raw = executionModeRaw, let mode = ConversationExecutionMode(rawValue: raw) {
                return mode
            }
            if (sessions ?? []).contains(where: { $0.mode == .worker }) {
                return .worker
            }
            if isAutonomous || threadKind == .autonomous || (sessions ?? []).contains(where: { $0.mode == .autonomous }) {
                return .autonomous
            }
            return .interactive
        }
        set {
            executionModeRaw = newValue.rawValue
            isAutonomous = (newValue == .autonomous)
        }
    }

    var delegationMode: DelegationMode {
        get { delegationModeRaw.flatMap(DelegationMode.init(rawValue:)) ?? .off }
        set { delegationModeRaw = newValue.rawValue }
    }

    var roomRole: SharedRoomRole? {
        get { roomRoleRaw.flatMap(SharedRoomRole.init(rawValue:)) }
        set { roomRoleRaw = newValue?.rawValue }
    }

    var roomStatus: SharedRoomStatus {
        get { roomStatusRaw.flatMap(SharedRoomStatus.init(rawValue:)) ?? .localOnly }
        set { roomStatusRaw = newValue.rawValue }
    }

    var roomHistorySyncState: SharedRoomHistorySyncState {
        get { roomHistorySyncStateRaw.flatMap(SharedRoomHistorySyncState.init(rawValue:)) ?? .idle }
        set { roomHistorySyncStateRaw = newValue.rawValue }
    }

    var roomTransportMode: SharedRoomTransportMode {
        get { roomTransportModeRaw.flatMap(SharedRoomTransportMode.init(rawValue:)) ?? .cloudSync }
        set { roomTransportModeRaw = newValue.rawValue }
    }

    var roomOrigin: RoomOrigin {
        get {
            RoomOrigin.from(
                kind: roomOriginKind,
                homeserver: roomOriginHomeserver,
                matrixRoomId: roomOriginMatrixId
            )
        }
        set {
            roomOriginKind = newValue.kindString
            roomOriginHomeserver = newValue.homeserver
            roomOriginMatrixId = newValue.matrixRoomId
        }
    }

    var isSharedRoom: Bool {
        guard let roomId else { return false }
        return !roomId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct ResolvedQuestionInfo {
    let answeredBy: String
    let isFallback: Bool
    let answer: String?
}
