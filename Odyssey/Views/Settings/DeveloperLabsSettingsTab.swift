import SwiftUI

struct DeveloperLabsSettingsTab: View {
    @AppStorage(AppSettings.logLevelKey, store: AppSettings.store) private var logLevel = AppSettings.defaultLogLevel

    private var selectedLogLevel: Binding<LogLevel> {
        Binding(
            get: { LogLevel(rawValue: logLevel) ?? .info },
            set: { logLevel = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section("Experimental Features") {
                LabsRow(key: FeatureFlags.peerNetworkKey,
                        title: "Peer Network",
                        description: "Discover and import agents from other Macs on your local network.")
                LabsRow(key: FeatureFlags.workflowsKey,
                        title: "Group Workflows",
                        description: "Author multi-step task sequences for agent groups.")
                LabsRow(key: FeatureFlags.autoAssembleKey,
                        title: "Auto-Assemble",
                        description: "AI-suggested groupings of agents for a goal.")
                LabsRow(key: FeatureFlags.autonomousMissionsKey,
                        title: "Autonomous Missions",
                        description: "Run agent groups headlessly without interaction.")
                LabsRow(key: FeatureFlags.federationKey,
                        title: "Federation",
                        description: "iOS Pairing, Matrix, Nostr accept-invite, and shared rooms.")
                LabsRow(key: FeatureFlags.agentCommsKey,
                        title: "Agent Comms",
                        description: "Unified timeline of agent-to-agent messages and delegations.")
                LabsRow(key: FeatureFlags.connectorsKey,
                        title: "Connectors",
                        description: "OAuth apps, broker config, and integration tokens for Slack, LinkedIn, X, and more.")
            }

            Section("Developer") {
                LabsRow(key: FeatureFlags.debugLogsKey,
                        title: "Debug Logs",
                        description: "Internal log aggregator combining sidecar JSON + OSLog.")
                LabsRow(key: FeatureFlags.advancedAgentConfigKey,
                        title: "Advanced Agent Config",
                        description: "Max turns, budget caps, instance policy controls in the Agent Editor.")
                LabsRow(key: FeatureFlags.devModeKey,
                        title: "Developer Mode",
                        description: "Launch parameters and multi-instance UI surfaces.")

                Picker("Log Level", selection: selectedLogLevel) {
                    ForEach(LogLevel.allCases, id: \.self) { level in
                        Text(level.rawValue.capitalized).tag(level)
                    }
                }
                .accessibilityIdentifier("settings.devLabs.logLevelPicker")
            }
        }
        .formStyle(.grouped)
        .settingsDetailLayout()
        .accessibilityIdentifier("settings.devLabs.form")
    }
}

// MARK: - Row helper (local copy, same as LabsToggleRow)

private struct LabsRow: View {
    let title: String
    let description: String
    let suffix: String

    @AppStorage private var enabled: Bool

    init(key: String, title: String, description: String) {
        self.title = title
        self.description = description
        self.suffix = key.replacingOccurrences(of: "odyssey.features.", with: "")
        self._enabled = AppStorage(wrappedValue: false, key, store: AppSettings.store)
    }

    var body: some View {
        Toggle(isOn: $enabled) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("settings.devLabs.toggle.\(suffix)")
    }
}
