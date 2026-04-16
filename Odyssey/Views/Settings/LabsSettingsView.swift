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
                    .accessibilityIdentifier("settings.labs.toggle.showAdvanced")
            } footer: {
                Text("Reveals experimental and power-user features below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if showAdvanced {
                productivitySection
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
        .scrollContentBackground(.hidden)
        .frame(maxWidth: 1040, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 24)
        .padding(.bottom, 28)
        .accessibilityIdentifier("settings.labs.form")
    }

    // MARK: - Sections

    @ViewBuilder
    private var productivitySection: some View {
        Section("Productivity") {
            LabsToggleRow(
                key: FeatureFlags.workshopKey,
                title: "Workshop",
                description: "Experimental config-agent designer."
            )
        }
    }

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
    let key: String
    let title: String
    let description: String

    var body: some View {
        Toggle(isOn: binding) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier(
            "settings.labs.toggle.\(key.replacingOccurrences(of: "odyssey.features.", with: ""))"
        )
    }

    private var binding: Binding<Bool> {
        Binding(
            get: { AppSettings.store.bool(forKey: key) },
            set: { AppSettings.store.set($0, forKey: key) }
        )
    }
}
