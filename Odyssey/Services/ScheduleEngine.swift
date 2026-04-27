import AppKit
import Foundation
import SwiftData

@MainActor
final class ScheduleEngine {
    static let staleRunTimeout: TimeInterval = 60 * 60

    private let modelContext: ModelContext
    private let coordinator: ScheduleRunCoordinator
    private let launchdManager: ScheduleLaunchdManager
    private let executeHandler: @MainActor (ScheduledMission, ScheduledMissionRun, WindowState?) async -> Void
    private var timer: Timer?
    private var becameActiveObserver: NSObjectProtocol?
    private var hasStarted = false

    init(
        modelContext: ModelContext,
        coordinator: ScheduleRunCoordinator,
        launchdManager: ScheduleLaunchdManager = ScheduleLaunchdManager(),
        executeHandler: (@MainActor (ScheduledMission, ScheduledMissionRun, WindowState?) async -> Void)? = nil
    ) {
        self.modelContext = modelContext
        self.coordinator = coordinator
        self.launchdManager = launchdManager
        self.executeHandler = executeHandler ?? { schedule, run, windowState in
            await coordinator.execute(schedule: schedule, run: run, windowState: windowState)
        }
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        recoverStaleRuns(now: Date())
        evaluateDueSchedules(now: Date(), triggerSource: .timer)
        exportSchedules()

        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.evaluateDueSchedules(now: Date(), triggerSource: .timer)
            }
        }

        becameActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.evaluateDueSchedules(now: Date(), triggerSource: .timer)
            }
        }
    }

    func syncSchedule(_ schedule: ScheduledMission, now: Date = Date()) {
        schedule.updatedAt = now
        schedule.nextRunAt = schedule.isEnabled
            ? ScheduledMissionCadence.nextOccurrence(for: schedule, after: now)
            : nil
        launchdManager.sync(schedule: schedule)
        try? modelContext.save()
        exportSchedules()
    }

    func removeSchedule(_ schedule: ScheduledMission) {
        launchdManager.remove(schedule: schedule)
        try? modelContext.save()
        exportSchedules()
    }

    func exportSchedules() {
        let descriptor = FetchDescriptor<ScheduledMission>()
        guard let schedules = try? modelContext.fetch(descriptor) else { return }
        let agentDescriptor = FetchDescriptor<Agent>()
        let groupDescriptor = FetchDescriptor<AgentGroup>()
        let agents = (try? modelContext.fetch(agentDescriptor)) ?? []
        let groups = (try? modelContext.fetch(groupDescriptor)) ?? []
        let iso = ISO8601DateFormatter()
        let dtos = schedules.map { s -> [String: Any?] in
            let targetName: String?
            switch s.targetKind {
            case .agent: targetName = agents.first(where: { $0.id == s.targetAgentId })?.name
            case .group: targetName = groups.first(where: { $0.id == s.targetGroupId })?.name
            default: targetName = nil
            }
            return [
                "id": s.id.uuidString,
                "name": s.name,
                "isEnabled": s.isEnabled,
                "targetKind": s.targetKind.rawValue,
                "targetName": targetName,
                "cadenceKind": s.cadenceKind.rawValue,
                "intervalHours": s.intervalHours,
                "localHour": s.localHour,
                "localMinute": s.localMinute,
                "daysOfWeek": s.daysOfWeek.map(\.shortLabel),
                "promptTemplate": s.promptTemplate,
                "projectDirectory": s.projectDirectory,
                "runMode": s.runMode.rawValue,
                "usesAutonomousMode": s.usesAutonomousMode,
                "nextRunAt": s.nextRunAt.map { iso.string(from: $0) },
                "lastStartedAt": s.lastStartedAt.map { iso.string(from: $0) },
                "lastSucceededAt": s.lastSucceededAt.map { iso.string(from: $0) },
                "lastFailedAt": s.lastFailedAt.map { iso.string(from: $0) },
                "createdAt": iso.string(from: s.createdAt),
            ]
        }
        let dataDir: URL
        let customDir = ProcessInfo.processInfo.environment["ODYSSEY_DATA_DIR"]
            ?? ProcessInfo.processInfo.environment["CLAUDESTUDIO_DATA_DIR"]
        if let dir = customDir {
            dataDir = URL(fileURLWithPath: dir)
        } else {
            dataDir = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".odyssey")
        }
        let dir = dataDir.appending(path: "data")
        let fileURL = dir.appending(path: "schedules.json")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: dtos, options: [.prettyPrinted]) {
            try? data.write(to: fileURL)
        }
    }

    func runNow(scheduleId: UUID, windowState: WindowState? = nil) {
        let descriptor = FetchDescriptor<ScheduledMission>(predicate: #Predicate { $0.id == scheduleId })
        guard let schedule = try? modelContext.fetch(descriptor).first else { return }
        let now = Date()
        let run = ScheduledMissionRun(
            scheduleId: schedule.id,
            occurrenceKey: ScheduledMissionRun.occurrenceKey(scheduleId: schedule.id, scheduledFor: now),
            status: .running,
            triggerSource: .manual,
            scheduledFor: now
        )
        schedule.lastStartedAt = now
        schedule.updatedAt = now
        modelContext.insert(run)
        try? modelContext.save()
        Task { @MainActor in
            await executeHandler(schedule, run, windowState)
        }
    }

    func runLaunchdSchedule(
        scheduleId: UUID,
        occurrence: Date?,
        windowState: WindowState? = nil
    ) {
        let descriptor = FetchDescriptor<ScheduledMission>(predicate: #Predicate { $0.id == scheduleId })
        guard let schedule = try? modelContext.fetch(descriptor).first else { return }
        let due = occurrence ?? schedule.nextRunAt ?? Date()
        claimAndExecute(schedule: schedule, scheduledFor: due, triggerSource: .launchd, windowState: windowState)
    }

    func evaluateDueSchedules(now: Date, triggerSource: ScheduledMissionRunTriggerSource) {
        let _evalStart = ContinuousClock.now
        defer {
            let elapsed = ContinuousClock.now - _evalStart
            if elapsed > .milliseconds(50) {
                Log.perf.warning("ScheduleEngine.evaluateDueSchedules: \(elapsed, privacy: .public)")
            }
        }
        recoverStaleRuns(now: now)
        let schedules = (try? modelContext.fetch(
            FetchDescriptor<ScheduledMission>()
        )) ?? []

        for schedule in schedules where schedule.isEnabled {
            // We deliberately do NOT touch `schedule.lastEvaluatedAt` here.
            // The field is currently unread anywhere in the codebase, and
            // writing it on every enabled schedule every 60 s caused the
            // unconditional `try? ctx.save()` below to persist a no-op
            // mutation — which invalidates every @Query in the app and
            // burned ~1 s of main-thread re-eval per cycle for users with
            // a large sidebar. If telemetry needs it later, populate it
            // only on the cycles that actually claim a run.
            if schedule.nextRunAt == nil {
                schedule.nextRunAt = ScheduledMissionCadence.nextOccurrence(for: schedule, after: now)
            }
            guard let nextRunAt = schedule.nextRunAt else { continue }
            guard nextRunAt <= now else { continue }

            var due = nextRunAt
            while let next = ScheduledMissionCadence.nextOccurrence(for: schedule, after: due), next <= now {
                due = next
            }

            claimAndExecute(schedule: schedule, scheduledFor: due, triggerSource: triggerSource, windowState: nil)
        }

        // Skip the save when nothing changed. The common steady-state path
        // (no schedules due, no nextRunAt seeding) leaves `hasChanges` false
        // and avoids the @Query cascade entirely.
        if modelContext.hasChanges {
            try? modelContext.save()
        }
    }

    private func claimAndExecute(
        schedule: ScheduledMission,
        scheduledFor: Date,
        triggerSource: ScheduledMissionRunTriggerSource,
        windowState: WindowState?
    ) {
        let occurrenceKey = ScheduledMissionRun.occurrenceKey(scheduleId: schedule.id, scheduledFor: scheduledFor)
        let existingRunDescriptor = FetchDescriptor<ScheduledMissionRun>(
            predicate: #Predicate { $0.occurrenceKey == occurrenceKey }
        )
        if (try? modelContext.fetch(existingRunDescriptor).first) != nil {
            return
        }

        // Filter at the query level — the previous unfiltered fetch+in-memory
        // filter pulled the whole run history just to find one row.
        let scheduleId = schedule.id
        let runningStatus: ScheduledMissionRunStatus = .running
        let activeRunDescriptor = FetchDescriptor<ScheduledMissionRun>(
            predicate: #Predicate<ScheduledMissionRun> { run in
                run.scheduleId == scheduleId && run.status == runningStatus
            }
        )
        let activeRun = try? modelContext.fetch(activeRunDescriptor).first
        if activeRun != nil {
            let skipped = ScheduledMissionRun(
                scheduleId: schedule.id,
                occurrenceKey: occurrenceKey,
                status: .skipped,
                triggerSource: triggerSource,
                scheduledFor: scheduledFor
            )
            skipped.completedAt = Date()
            skipped.skipReason = "previousRunStillActive"
            modelContext.insert(skipped)
            schedule.lastScheduledOccurrenceAt = scheduledFor
            schedule.nextRunAt = ScheduledMissionCadence.nextOccurrence(for: schedule, after: scheduledFor)
            schedule.updatedAt = Date()
            try? modelContext.save()
            return
        }

        let run = ScheduledMissionRun(
            scheduleId: schedule.id,
            occurrenceKey: occurrenceKey,
            status: .running,
            triggerSource: triggerSource,
            scheduledFor: scheduledFor
        )
        modelContext.insert(run)
        schedule.lastScheduledOccurrenceAt = scheduledFor
        schedule.lastStartedAt = run.startedAt
        schedule.nextRunAt = ScheduledMissionCadence.nextOccurrence(for: schedule, after: scheduledFor)
        schedule.updatedAt = run.startedAt
        try? modelContext.save()

        Task { @MainActor in
            await executeHandler(schedule, run, windowState)
        }
    }

    private func recoverStaleRuns(now: Date) {
        // Only fetch runs that are *both* still marked running AND old enough
        // to be stale. The unfiltered version pulled the entire run history
        // into memory every 60 s — for a long-lived store that's hundreds or
        // thousands of rows of synchronous main-thread SwiftData work, which
        // showed up as a regular ~1 s stall once per minute.
        let cutoff = now.addingTimeInterval(-Self.staleRunTimeout)
        let runningStatus: ScheduledMissionRunStatus = .running
        let descriptor = FetchDescriptor<ScheduledMissionRun>(
            predicate: #Predicate<ScheduledMissionRun> { run in
                run.status == runningStatus && run.startedAt < cutoff
            }
        )
        let staleRuns = (try? modelContext.fetch(descriptor)) ?? []
        guard !staleRuns.isEmpty else { return }

        for run in staleRuns {
            run.status = .failed
            run.completedAt = now
            run.errorMessage = "schedulerRecoveryTimeout"

            let scheduleId = run.scheduleId
            let scheduleDesc = FetchDescriptor<ScheduledMission>(
                predicate: #Predicate<ScheduledMission> { $0.id == scheduleId }
            )
            if let schedule = try? modelContext.fetch(scheduleDesc).first {
                schedule.lastFailedAt = now
                schedule.updatedAt = now
            }
        }
        try? modelContext.save()
    }
}
