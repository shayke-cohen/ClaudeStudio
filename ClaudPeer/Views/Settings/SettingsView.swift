import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .accessibilityIdentifier("settings.tab.general")

            ConnectionSettingsTab()
                .tabItem {
                    Label("Connection", systemImage: "network")
                }
                .accessibilityIdentifier("settings.tab.connection")

            DeveloperSettingsTab()
                .tabItem {
                    Label("Developer", systemImage: "wrench.and.screwdriver")
                }
                .accessibilityIdentifier("settings.tab.developer")
        }
        .frame(width: 480)
        .accessibilityIdentifier("settings.tabView")
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @AppStorage(AppSettings.appearanceKey, store: AppSettings.store) private var appearance = AppAppearance.system.rawValue
    @AppStorage(AppSettings.defaultModelKey, store: AppSettings.store) private var defaultModel = AppSettings.defaultModel
    @AppStorage(AppSettings.defaultMaxTurnsKey, store: AppSettings.store) private var defaultMaxTurns = AppSettings.defaultMaxTurns
    @AppStorage(AppSettings.defaultMaxBudgetKey, store: AppSettings.store) private var defaultMaxBudget = AppSettings.defaultMaxBudget

    private var selectedAppearance: Binding<AppAppearance> {
        Binding(
            get: { AppAppearance(rawValue: appearance) ?? .system },
            set: { appearance = $0.rawValue }
        )
    }

    private var selectedModel: Binding<ClaudeModel> {
        Binding(
            get: { ClaudeModel(rawValue: defaultModel) ?? .sonnet },
            set: { defaultModel = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Picker("Appearance", selection: selectedAppearance) {
                ForEach(AppAppearance.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("settings.general.appearancePicker")

            Divider()

            Picker("Default Model", selection: selectedModel) {
                ForEach(ClaudeModel.allCases) { model in
                    Text(model.label).tag(model)
                }
            }
            .accessibilityIdentifier("settings.general.defaultModelPicker")

            Stepper("Default Max Turns: \(defaultMaxTurns)", value: $defaultMaxTurns, in: 1...200)
                .accessibilityIdentifier("settings.general.defaultMaxTurnsStepper")

            HStack {
                Text("Default Max Budget")
                Spacer()
                TextField("$", value: $defaultMaxBudget, format: .number)
                    .frame(width: 80)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .accessibilityIdentifier("settings.general.defaultMaxBudgetField")
                Text(defaultMaxBudget == 0 ? "(unlimited)" : "")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Connection

private struct ConnectionSettingsTab: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage(AppSettings.autoConnectSidecarKey, store: AppSettings.store) private var autoConnectSidecar = true
    @AppStorage(AppSettings.wsPortKey, store: AppSettings.store) private var wsPort = AppSettings.defaultWsPort
    @AppStorage(AppSettings.httpPortKey, store: AppSettings.store) private var httpPort = AppSettings.defaultHttpPort

    var body: some View {
        Form {
            Section("Sidecar Status") {
                HStack(spacing: 8) {
                    statusDot
                    VStack(alignment: .leading, spacing: 2) {
                        Text(statusLabel)
                            .font(.body)
                        if appState.sidecarStatus == .connected {
                            Text("ws://localhost:\(appState.allocatedWsPort)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("settings.connection.statusURL")
                        }
                    }
                    Spacer()
                    statusActions
                }
                .accessibilityIdentifier("settings.connection.statusRow")
            }

            Section("Preferences") {
                Toggle("Auto-connect on Launch", isOn: $autoConnectSidecar)
                    .accessibilityIdentifier("settings.connection.autoConnectToggle")
            }

            Section("Ports") {
                HStack {
                    Text("WebSocket Port")
                    Spacer()
                    TextField("9849", value: $wsPort, format: .number)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("settings.connection.wsPortField")
                }

                HStack {
                    Text("HTTP API Port")
                    Spacer()
                    TextField("9850", value: $httpPort, format: .number)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("settings.connection.httpPortField")
                }

                Text("Changes take effect after restarting the sidecar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    @ViewBuilder
    private var statusDot: some View {
        switch appState.sidecarStatus {
        case .connected:
            Circle().fill(.green).frame(width: 10, height: 10)
        case .connecting:
            ProgressView().controlSize(.small)
        case .disconnected:
            Circle().fill(.gray).frame(width: 10, height: 10)
        case .error:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        }
    }

    private var statusLabel: String {
        switch appState.sidecarStatus {
        case .connected: "Connected"
        case .connecting: "Connecting..."
        case .disconnected: "Disconnected"
        case .error(let msg): "Error: \(msg)"
        }
    }

    @ViewBuilder
    private var statusActions: some View {
        switch appState.sidecarStatus {
        case .connected:
            Button("Reconnect") {
                appState.disconnectSidecar()
                appState.connectSidecar()
            }
            .controlSize(.small)
            .accessibilityIdentifier("settings.connection.reconnectButton")

            Button("Stop") {
                appState.disconnectSidecar()
            }
            .controlSize(.small)
            .foregroundStyle(.red)
            .accessibilityIdentifier("settings.connection.stopButton")

        case .disconnected, .error:
            Button("Connect") {
                appState.connectSidecar()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .accessibilityIdentifier("settings.connection.connectButton")

        case .connecting:
            EmptyView()
        }
    }
}

// MARK: - Developer

private struct DeveloperSettingsTab: View {
    @AppStorage(AppSettings.bunPathOverrideKey, store: AppSettings.store) private var bunPathOverride = ""
    @AppStorage(AppSettings.sidecarPathKey, store: AppSettings.store) private var sidecarPath = ""
    @AppStorage(AppSettings.dataDirectoryKey, store: AppSettings.store) private var dataDirectory = AppSettings.defaultDataDirectory
    @AppStorage(AppSettings.logLevelKey, store: AppSettings.store) private var logLevel = AppSettings.defaultLogLevel
    @State private var showResetConfirmation = false

    private var selectedLogLevel: Binding<LogLevel> {
        Binding(
            get: { LogLevel(rawValue: logLevel) ?? .info },
            set: { logLevel = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section("Paths") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bun Path Override")
                    HStack {
                        TextField("Auto-detect", text: $bunPathOverride)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("settings.developer.bunPathField")
                        Button("Browse...") {
                            browseBunPath()
                        }
                        .accessibilityIdentifier("settings.developer.bunPathBrowseButton")
                    }
                    if bunPathOverride.isEmpty {
                        Text("Will search: /opt/homebrew/bin/bun, /usr/local/bin/bun, ~/.bun/bin/bun")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Project Path")
                    HStack {
                        TextField("Auto-detect", text: $sidecarPath)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("settings.developer.sidecarPathField")
                        Button("Browse...") {
                            browseProjectPath()
                        }
                        .accessibilityIdentifier("settings.developer.sidecarPathBrowseButton")
                    }
                    Text("Root directory containing the sidecar/ folder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Data") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Data Directory")
                    HStack {
                        TextField("~/.claudpeer", text: $dataDirectory)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("settings.developer.dataDirectoryField")
                        Button("Browse...") {
                            browseDataDirectory()
                        }
                        .accessibilityIdentifier("settings.developer.dataDirectoryBrowseButton")
                    }
                    Text("Stores logs, blackboard data, repos, and sandboxes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Logging") {
                Picker("Log Level", selection: selectedLogLevel) {
                    ForEach(LogLevel.allCases) { level in
                        Text(level.label).tag(level)
                    }
                }
                .accessibilityIdentifier("settings.developer.logLevelPicker")
            }

            Section {
                HStack {
                    Button("Open Data Directory in Finder") {
                        openDataDirectory()
                    }
                    .accessibilityIdentifier("settings.developer.openDataDirectoryButton")

                    Spacer()

                    Button("Reset All Settings", role: .destructive) {
                        showResetConfirmation = true
                    }
                    .accessibilityIdentifier("settings.developer.resetSettingsButton")
                    .confirmationDialog(
                        "Reset all settings to defaults?",
                        isPresented: $showResetConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Reset", role: .destructive) {
                            AppSettings.resetAll()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will revert all preferences to their default values. The sidecar will need to be restarted.")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func browseBunPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select the Bun executable"
        panel.directoryURL = URL(fileURLWithPath: "/opt/homebrew/bin")
        if panel.runModal() == .OK, let url = panel.url {
            bunPathOverride = url.path
        }
    }

    private func browseProjectPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select the ClaudPeer project directory"
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
        if panel.runModal() == .OK, let url = panel.url {
            sidecarPath = url.path
        }
    }

    private func browseDataDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select the data directory"
        let expandedPath = NSString(string: dataDirectory).expandingTildeInPath
        panel.directoryURL = URL(fileURLWithPath: expandedPath)
        if panel.runModal() == .OK, let url = panel.url {
            dataDirectory = url.path
        }
    }

    private func openDataDirectory() {
        let expandedPath = NSString(string: dataDirectory).expandingTildeInPath
        NSWorkspace.shared.open(URL(fileURLWithPath: expandedPath))
    }
}

#Preview {
    SettingsView()
}
