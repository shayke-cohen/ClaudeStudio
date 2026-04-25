import Foundation

/// Central feature-flag registry for Odyssey V1.
///
/// Flags are stored in the per-instance `AppSettings.store` (`UserDefaults` suite),
/// readable via `@AppStorage(FeatureFlags.xxxKey, store: AppSettings.store)` in views.
///
/// Three flip mechanisms (in priority order for `isEnabled(_:)`):
/// 1. **Env var** `ODYSSEY_FEATURES=peerNetwork,workshop,...` — bypasses the master gate.
/// 2. **JSON file** `~/.odyssey/config/features.json` — synced by `ConfigSyncService`.
/// 3. **UI** — `@AppStorage` toggles in Settings › Labs, gated by the master `showAdvanced` switch.
///
/// All keys are included in `AppSettings.allKeys` so "Reset All Settings" clears them.
/// Setting `showAdvanced` in `ODYSSEY_FEATURES` also force-enables the master gate, since the env-var path bypasses gating.
enum FeatureFlags {

    // MARK: - Master switch

    /// When OFF (default), every per-feature flag is treated as OFF regardless of its stored value.
    /// When ON, individual per-feature flags take effect (UI/JSON path).
    static let showAdvancedKey = "odyssey.features.showAdvanced"

    // MARK: - Per-feature flags (all default OFF for V1)

    /// P2P LAN peer discovery and agent sharing.
    static let peerNetworkKey = "odyssey.features.peerNetwork"

    /// Group Workflows editor (step authoring).
    static let workflowsKey = "odyssey.features.workflows"

    /// Auto-Assemble — AI-suggested agent group creation.
    static let autoAssembleKey = "odyssey.features.autoAssemble"

    /// Autonomous Missions — headless long-running agent sessions.
    static let autonomousMissionsKey = "odyssey.features.autonomousMissions"

    /// Federation surfaces: iOS Pairing, Matrix, Nostr, Shared Rooms.
    static let federationKey = "odyssey.features.federation"

    /// Debug Logs view — structured log viewer for internal use.
    static let debugLogsKey = "odyssey.features.debugLogs"

    /// Advanced Agent Config — max turns, budget caps, instance policy radios.
    static let advancedAgentConfigKey = "odyssey.features.advancedAgentConfig"

    /// Dev Mode — multi-instance UI affordances and launch-parameter helpers.
    static let devModeKey = "odyssey.features.devMode"

    /// Agent Comms — unified agent-to-agent messaging timeline.
    static let agentCommsKey = "odyssey.features.agentComms"

    /// Connectors — OAuth apps, broker config, and integration tokens.
    static let connectorsKey = "odyssey.features.connectors"

    // MARK: - Collections

    /// All flag keys in a stable order (master + per-feature).
    /// Included in `AppSettings.allKeys` so "Reset All Settings" clears them.
    static let all: [String] = [
        showAdvancedKey,
        peerNetworkKey,
        workflowsKey,
        autoAssembleKey,
        autonomousMissionsKey,
        federationKey,
        debugLogsKey,
        advancedAgentConfigKey,
        devModeKey,
        agentCommsKey,
        connectorsKey,
    ]

    /// Default values — all `false` for a focused V1 experience.
    static let defaults: [String: Bool] = [
        showAdvancedKey: false,
        peerNetworkKey: false,
        workflowsKey: false,
        autoAssembleKey: false,
        autonomousMissionsKey: false,
        federationKey: false,
        debugLogsKey: false,
        advancedAgentConfigKey: false,
        devModeKey: false,
        agentCommsKey: false,
        connectorsKey: false,
    ]

    // MARK: - Accessor

    /// Returns `true` if the named feature flag is currently enabled.
    ///
    /// Resolution order:
    /// 1. If `ODYSSEY_FEATURES` env var contains the flag's suffix (e.g. `"workshop"`), return `true`
    ///    (bypasses the master gate — for developer one-off testing).
    /// 2. For `showAdvancedKey` itself, return its `UserDefaults` value directly.
    /// 3. For any per-feature flag, the master `showAdvancedKey` must also be `true`.
    nonisolated static func isEnabled(_ key: String) -> Bool {
        // Env-var bypass — `ODYSSEY_FEATURES=peerNetwork,workshop` skips the master gate.
        if let env = ProcessInfo.processInfo.environment["ODYSSEY_FEATURES"] {
            let suffix = key.replacingOccurrences(of: "odyssey.features.", with: "")
            if env.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }).contains(suffix) {
                return true
            }
        }

        // Read the per-feature value (falls back to the declared default).
        let perFeature = AppSettings.store.object(forKey: key) as? Bool ?? defaults[key] ?? false

        // The master switch is returned as-is (not gated by itself).
        guard key != showAdvancedKey else { return perFeature }

        // All other flags require the master switch to be ON.
        let masterOn = AppSettings.store.object(forKey: showAdvancedKey) as? Bool
            ?? defaults[showAdvancedKey]
            ?? false
        return masterOn && perFeature
    }
}
