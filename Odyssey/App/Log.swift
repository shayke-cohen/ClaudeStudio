import OSLog

/// Centralized structured logging for Odyssey.
///
/// Usage:  `Log.appState.info("Session created")`
///
/// Each category maps to a `[Prefix]` that was previously used in `print()` calls.
/// All loggers share the subsystem `com.odyssey.app` so they can be queried
/// together via `OSLogStore`.
enum Log {
    static let subsystem = "com.odyssey.app"

    static let appState    = Logger(subsystem: subsystem, category: "appState")
    static let sidecar     = Logger(subsystem: subsystem, category: "sidecar")
    static let configSync  = Logger(subsystem: subsystem, category: "configSync")
    static let configFile  = Logger(subsystem: subsystem, category: "configFile")
    static let seeder      = Logger(subsystem: subsystem, category: "seeder")
    static let peerCatalog = Logger(subsystem: subsystem, category: "peerCatalog")
    static let chat        = Logger(subsystem: subsystem, category: "chat")
    static let p2p         = Logger(subsystem: subsystem, category: "p2p")
    static let general     = Logger(subsystem: subsystem, category: "general")
    static let github      = Logger(subsystem: subsystem, category: "github")
    /// Diagnostics for main-thread stalls, slow saves, hot-path latency.
    /// Emits at `.debug` (silent in release builds) so it can be left wired in.
    static let perf        = Logger(subsystem: subsystem, category: "perf")
}
