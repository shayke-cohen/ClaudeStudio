import SwiftUI

// MARK: - Labs Settings

struct LabsSettingsView: View {
    @AppStorage(FeatureFlags.showAdvancedKey, store: AppSettings.store)
    private var showAdvanced = false

    var body: some View {
        Form {
            // Master gate toggle
            Section {
                Toggle("Show advanced features", isOn: $showAdvanced)
                    .xrayId("settings.labs.toggle.showAdvanced")
            } footer: {
                Text("Reveals experimental and power-user features below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if showAdvanced {
                collaborationSection
                developerSection
            } else {
                Section {
                    Text("Turn on advanced features to choose which experiments to enable.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .settingsDetailLayout()
        .xrayId("settings.labs.form")
    }

    // MARK: - Sections

    @ViewBuilder
    private var collaborationSection: some View {
        Section("Collaboration") {
            LabsToggleRow(
                key: FeatureFlags.peerNetworkKey,
                title: "Peer Network",
                description: "Discover and import agents from other Macs on your local network."
            )
            LabsToggleRow(
                key: FeatureFlags.workflowsKey,
                title: "Group Workflows",
                description: "Author multi-step task sequences for agent groups."
            )
            LabsToggleRow(
                key: FeatureFlags.autoAssembleKey,
                title: "Auto-Assemble",
                description: "AI-suggested groupings of agents for a goal."
            )
            LabsToggleRow(
                key: FeatureFlags.autonomousMissionsKey,
                title: "Autonomous Missions",
                description: "Run agent groups headlessly without interaction."
            )
            LabsToggleRow(
                key: FeatureFlags.federationKey,
                title: "Federation",
                description: "iOS Pairing, Matrix, Nostr accept-invite, and shared rooms."
            )
            LabsToggleRow(
                key: FeatureFlags.agentCommsKey,
                title: "Agent Comms",
                description: "Unified timeline of agent-to-agent messages and delegations."
            )
        }
    }

    @ViewBuilder
    private var developerSection: some View {
        Section("Developer") {
            LabsToggleRow(
                key: FeatureFlags.debugLogsKey,
                title: "Debug Logs",
                description: "Internal log aggregator combining sidecar JSON + OSLog."
            )
            LabsToggleRow(
                key: FeatureFlags.advancedAgentConfigKey,
                title: "Advanced Agent Config",
                description: "Max turns, budget caps, instance policy controls in the Agent Editor."
            )
            LabsToggleRow(
                key: FeatureFlags.devModeKey,
                title: "Developer Mode",
                description: "Launch parameters and multi-instance UI surfaces."
            )
        }
    }
}

// MARK: - Row helper

private struct LabsToggleRow: View {
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
        .xrayId("settings.labs.toggle.\(suffix)")
    }
}
