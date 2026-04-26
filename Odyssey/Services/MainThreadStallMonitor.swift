import Foundation
import OSLog

/// Periodic main-thread heartbeat. Schedules a high-priority block on the
/// main run loop every `expectedInterval` (default 100 ms). If the actual
/// elapsed time between two beats exceeds `stallThreshold` (default 200 ms),
/// emits a `Log.perf` warning with how long the main thread was blocked.
///
/// Use this as a background diagnostic when the app feels janky during
/// streaming or save bursts. It won't tell you *what* blocked main, but it
/// gives a precise timeline of *when* — pair it with the targeted timing
/// logs in AppState/ChatView to attribute the stall.
@MainActor
final class MainThreadStallMonitor {
    static let shared = MainThreadStallMonitor()

    private var lastBeat: ContinuousClock.Instant = .now
    private var task: Task<Void, Never>?
    private var startedAt: Date?
    private(set) var maxStall: Duration = .zero
    private(set) var stallCount: Int = 0

    /// 100 ms heartbeat = ~10 Hz. Fine-grained enough to spot a 200 ms blip
    /// without saturating the run loop.
    var expectedInterval: Duration = .milliseconds(100)
    /// Anything beyond this is reported. 200 ms = clearly noticeable to a user.
    var stallThreshold: Duration = .milliseconds(200)

    /// Begin monitoring. Idempotent.
    func start() {
        guard task == nil else { return }
        startedAt = Date()
        lastBeat = .now
        maxStall = .zero
        stallCount = 0
        Log.perf.notice("MainThreadStallMonitor started (heartbeat=\(self.expectedInterval, privacy: .public), threshold=\(self.stallThreshold, privacy: .public))")
        task = Task { [weak self] in
            await self?.run()
        }
    }

    /// Time a synchronous block of work on the main thread and emit a
    /// `Log.perf` warning if it took longer than `threshold`. Use this to
    /// attribute stalls reported by the heartbeat to specific call sites
    /// (save(), body re-eval, layout, etc.).
    @discardableResult
    static func measure<T>(
        _ label: String,
        threshold: Duration = .milliseconds(50),
        _ block: () throws -> T
    ) rethrows -> T {
        let start = ContinuousClock.now
        let result = try block()
        let elapsed = ContinuousClock.now - start
        if elapsed > threshold {
            Log.perf.warning("Slow main-thread block '\(label, privacy: .public)': \(elapsed, privacy: .public)")
        } else {
            Log.perf.debug("Block '\(label, privacy: .public)': \(elapsed, privacy: .public)")
        }
        return result
    }

    /// Stop monitoring and log a summary.
    func stop() {
        task?.cancel()
        task = nil
        let started = startedAt ?? Date()
        let total = Date().timeIntervalSince(started)
        Log.perf.notice("MainThreadStallMonitor stopped after \(String(format: "%.1f", total))s — stallCount=\(self.stallCount), maxStall=\(self.maxStall, privacy: .public)")
        startedAt = nil
    }

    private func run() async {
        while !Task.isCancelled {
            let beforeSleep = ContinuousClock.now
            try? await Task.sleep(for: expectedInterval)
            let now = ContinuousClock.now
            let gap = now - beforeSleep
            // Anything materially over `expectedInterval` means the main run
            // loop was tied up — either with our own work (SwiftData save,
            // layout pass, body re-eval) or someone else's.
            if gap > stallThreshold {
                if gap > maxStall { maxStall = gap }
                stallCount += 1
                Log.perf.warning("Main-thread stall: \(gap, privacy: .public) (expected \(self.expectedInterval, privacy: .public))")
            }
            lastBeat = now
        }
    }
}
