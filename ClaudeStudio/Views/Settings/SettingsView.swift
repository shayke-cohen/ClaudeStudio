import SwiftUI
import SwiftData

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .xrayId("settings.tab.general")

            ConnectionSettingsTab()
                .tabItem {
                    Label("Connection", systemImage: "network")
                }
                .xrayId("settings.tab.connection")

            ConnectorsSettingsTab()
                .tabItem {
                    Label("Connectors", systemImage: "link.badge.plus")
                }
                .xrayId("settings.tab.connectors")

            ChatDisplaySettingsTab()
                .tabItem {
                    Label("Chat Display", systemImage: "bubble.left.and.text.bubble.right")
                }
                .xrayId("settings.tab.chatDisplay")

            DeveloperSettingsTab()
                .tabItem {
                    Label("Developer", systemImage: "wrench.and.screwdriver")
                }
                .xrayId("settings.tab.developer")
        }
        .frame(width: 480)
        .xrayId("settings.tabView")
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @AppStorage(AppSettings.appearanceKey, store: AppSettings.store) private var appearance = AppAppearance.system.rawValue
    @AppStorage(AppSettings.textSizeKey, store: AppSettings.store) private var textSize = AppSettings.defaultTextSize
    @AppStorage(AppSettings.defaultProviderKey, store: AppSettings.store) private var defaultProvider = AppSettings.defaultProvider
    @AppStorage(AppSettings.defaultClaudeModelKey, store: AppSettings.store) private var defaultClaudeModel = AppSettings.defaultClaudeModel
    @AppStorage(AppSettings.defaultCodexModelKey, store: AppSettings.store) private var defaultCodexModel = AppSettings.defaultCodexModel
    @AppStorage(AppSettings.defaultFoundationModelKey, store: AppSettings.store) private var defaultFoundationModel = AppSettings.defaultFoundationModel
    @AppStorage(AppSettings.defaultMLXModelKey, store: AppSettings.store) private var defaultMLXModel = AppSettings.defaultMLXModel
    @AppStorage(AppSettings.defaultMaxTurnsKey, store: AppSettings.store) private var defaultMaxTurns = AppSettings.defaultMaxTurns
    @AppStorage(AppSettings.defaultMaxBudgetKey, store: AppSettings.store) private var defaultMaxBudget = AppSettings.defaultMaxBudget
    @AppStorage(AppSettings.quickActionUsageOrderKey, store: AppSettings.store) private var quickActionUsageOrder = true

    private var selectedAppearance: Binding<AppAppearance> {
        Binding(
            get: { AppAppearance(rawValue: appearance) ?? .system },
            set: { appearance = $0.rawValue }
        )
    }

    private var selectedProvider: Binding<ProviderSelection> {
        Binding(
            get: { ProviderSelection(rawValue: defaultProvider) ?? .claude },
            set: { defaultProvider = $0.rawValue }
        )
    }

    private var selectedClaudeModel: Binding<ClaudeModel> {
        Binding(
            get: { ClaudeModel(rawValue: AgentDefaults.normalizedModelSelection(defaultClaudeModel)) ?? .sonnet },
            set: { defaultClaudeModel = $0.rawValue }
        )
    }

    private var selectedCodexModel: Binding<CodexModel> {
        Binding(
            get: { CodexModel(rawValue: AgentDefaults.normalizedModelSelection(defaultCodexModel)) ?? .gpt5Codex },
            set: { defaultCodexModel = $0.rawValue }
        )
    }

    private var selectedFoundationModel: Binding<FoundationModel> {
        Binding(
            get: { FoundationModel(rawValue: AgentDefaults.normalizedModelSelection(defaultFoundationModel)) ?? .system },
            set: { defaultFoundationModel = $0.rawValue }
        )
    }

    private var selectedTextSize: Binding<AppTextSize> {
        Binding(
            get: { AppTextSize(rawValue: textSize) ?? .standard },
            set: { textSize = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Appearance", selection: selectedAppearance) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .xrayId("settings.general.appearancePicker")

                Picker("Text Size", selection: selectedTextSize) {
                    ForEach(AppTextSize.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .xrayId("settings.general.textSizePicker")

                Text("Use View > Increase Text Size or the shortcuts ⌘+ / ⌘- to adjust it anytime.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Defaults") {
                Picker("Default Provider", selection: selectedProvider) {
                    ForEach([ProviderSelection.claude, ProviderSelection.codex, ProviderSelection.foundation, ProviderSelection.mlx]) { provider in
                        Text(provider.label).tag(provider)
                    }
                }
                .xrayId("settings.general.defaultProviderPicker")

                Picker("Default Claude Model", selection: selectedClaudeModel) {
                    ForEach(ClaudeModel.allCases) { model in
                        Text(model.label).tag(model)
                    }
                }
                .xrayId("settings.general.defaultClaudeModelPicker")

                Picker("Default Codex Model", selection: selectedCodexModel) {
                    ForEach(CodexModel.allCases) { model in
                        Text(model.label).tag(model)
                    }
                }
                .xrayId("settings.general.defaultCodexModelPicker")

                Picker("Default Foundation Model", selection: selectedFoundationModel) {
                    ForEach(FoundationModel.allCases) { model in
                        Text(model.label).tag(model)
                    }
                }
                .xrayId("settings.general.defaultFoundationModelPicker")

                VStack(alignment: .leading, spacing: 4) {
                    Text("Default MLX Model")
                    TextField("Enter a model id or local path", text: $defaultMLXModel)
                        .textFieldStyle(.roundedBorder)
                        .xrayId("settings.general.defaultMLXModelField")
                    Text("Example: `mlx-community/Qwen2.5-1.5B-Instruct-4bit` or a local MLX model directory.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Stepper("Default Max Turns: \(defaultMaxTurns)", value: $defaultMaxTurns, in: 1...200)
                    .xrayId("settings.general.defaultMaxTurnsStepper")

                HStack {
                    Text("Default Max Budget")
                    Spacer()
                    TextField("$", value: $defaultMaxBudget, format: .number)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .xrayId("settings.general.defaultMaxBudgetField")
                    Text(defaultMaxBudget == 0 ? "(unlimited)" : "")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }

            Section("Quick Actions") {
                Toggle("Order quick actions by usage", isOn: $quickActionUsageOrder)
                    .xrayId("settings.general.quickActionUsageOrderToggle")
                    .help("When enabled, quick action buttons reorder based on how often you use them (after 10 uses). When disabled, uses the default popularity order.")
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
                                .xrayId("settings.connection.statusURL")
                        }
                    }
                    Spacer()
                    statusActions
                }
                .xrayId("settings.connection.statusRow")
            }

            Section("Preferences") {
                Toggle("Auto-connect on Launch", isOn: $autoConnectSidecar)
                    .xrayId("settings.connection.autoConnectToggle")
            }

            Section("Ports") {
                HStack {
                    Text("WebSocket Port")
                    Spacer()
                    TextField("9849", value: $wsPort, format: .number)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .xrayId("settings.connection.wsPortField")
                }

                HStack {
                    Text("HTTP API Port")
                    Spacer()
                    TextField("9850", value: $httpPort, format: .number)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .xrayId("settings.connection.httpPortField")
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
            .xrayId("settings.connection.reconnectButton")

            Button("Stop") {
                appState.disconnectSidecar()
            }
            .controlSize(.small)
            .foregroundStyle(.red)
            .xrayId("settings.connection.stopButton")

        case .disconnected, .error:
            Button("Connect") {
                appState.connectSidecar()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .xrayId("settings.connection.connectButton")

        case .connecting:
            EmptyView()
        }
    }

}

private struct ConnectorsSettingsTab: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Connection.displayName) private var connections: [Connection]
    @AppStorage(AppSettings.connectorBrokerBaseURLKey, store: AppSettings.store) private var connectorBrokerBaseURL = ""
    @AppStorage(AppSettings.xClientIdKey, store: AppSettings.store) private var xClientId = ""
    @AppStorage(AppSettings.linkedinClientIdKey, store: AppSettings.store) private var linkedinClientId = ""
    @State private var editingProvider: ConnectionProvider?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Setup") {
                Text("Set the provider app details here once, then use Connect on each service. Manual tokens are tucked into Advanced only for fallback cases.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .xrayId("settings.connectors.setupSummary")
            }

            Section("Brokered Connectors") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Broker Base URL")
                    TextField("https://broker.example.com/", text: $connectorBrokerBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .xrayId("settings.connectors.brokerURL")
                    Text("Used for Slack, Facebook, and WhatsApp. Once configured, those providers should connect with one click.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Native OAuth Apps") {
                providerSettingField(
                    title: "X Client ID",
                    text: $xClientId,
                    callbackURL: ConnectorCatalog.callbackURL(for: .x),
                    xrayId: "settings.connectors.xClientId"
                )

                providerSettingField(
                    title: "LinkedIn Client ID",
                    text: $linkedinClientId,
                    callbackURL: ConnectorCatalog.callbackURL(for: .linkedin),
                    xrayId: "settings.connectors.linkedinClientId"
                )
            }

            Section("Available Connectors") {
                ForEach(ConnectionProvider.allCases) { provider in
                    ConnectorRowView(
                        provider: provider,
                        connection: connection(for: provider),
                        missingConfiguration: ConnectorCatalog.missingConfiguration(for: provider),
                        onConfigure: { editingProvider = provider },
                        onConnect: { startAuth(for: provider) },
                        onTest: { test(provider: provider) },
                        onRevoke: { revoke(provider: provider) }
                    )
                }
            }

            if let errorMessage {
                Section("Connector Status") {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .xrayId("settings.connectors.error")
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .sheet(item: $editingProvider) { provider in
            ConnectorEditorSheet(
                provider: provider,
                existingConnection: connection(for: provider)
            )
            .environmentObject(appState)
        }
    }

    @ViewBuilder
    private func providerSettingField(
        title: String,
        text: Binding<String>,
        callbackURL: String,
        xrayId: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            TextField("Paste the provider client ID", text: text)
                .textFieldStyle(.roundedBorder)
                .xrayId(xrayId)
            Text("Callback URL: \(callbackURL)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private func connection(for provider: ConnectionProvider) -> Connection? {
        ConnectorService.providerConnection(for: provider, in: connections)
    }

    private func startAuth(for provider: ConnectionProvider) {
        do {
            try ConnectorService.beginAuth(provider: provider, in: modelContext, appState: appState)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func test(provider: ConnectionProvider) {
        guard let connection = connection(for: provider) else { return }
        appState.sendToSidecar(.connectorTest(connectionId: connection.id.uuidString))
    }

    private func revoke(provider: ConnectionProvider) {
        guard let connection = connection(for: provider) else { return }
        ConnectorService.revoke(connection, in: modelContext, appState: appState)
    }
}

private struct ConnectorRowView: View {
    let provider: ConnectionProvider
    let connection: Connection?
    let missingConfiguration: [String]
    let onConfigure: () -> Void
    let onConnect: () -> Void
    let onTest: () -> Void
    let onRevoke: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Label(provider.displayName, systemImage: provider.iconName)
                    .font(.headline)
                Spacer()
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(statusColor)
                    .xrayId("settings.connectors.status.\(provider.rawValue)")
            }

            if let connection {
                VStack(alignment: .leading, spacing: 4) {
                    Text(connection.displayName)
                    Text("\(connection.authMode.displayName) · \(connection.writePolicy.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !connection.grantedScopes.isEmpty {
                        Text(connection.grantedScopes.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let accountHandle = connection.accountHandle, !accountHandle.isEmpty {
                        Text("Account: \(accountHandle)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let auditSummary = connection.auditSummary, !auditSummary.isEmpty {
                        Text(auditSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let statusMessage = connection.statusMessage, !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text(ConnectorCatalog.definition(for: provider).setupSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !missingConfiguration.isEmpty {
                Text("Needs setup: \(missingConfiguration.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Button("Configure") {
                    onConfigure()
                }
                .xrayId("settings.connectors.configureButton.\(provider.rawValue)")

                Button(connection == nil ? "Connect" : "Reconnect") {
                    onConnect()
                }
                .disabled(!missingConfiguration.isEmpty)
                .xrayId("settings.connectors.connectButton.\(provider.rawValue)")

                Button("Test") {
                    onTest()
                }
                .disabled(connection == nil)
                .xrayId("settings.connectors.testButton.\(provider.rawValue)")

                Button("Revoke") {
                    onRevoke()
                }
                .disabled(connection == nil)
                .foregroundStyle(.red)
                .xrayId("settings.connectors.revokeButton.\(provider.rawValue)")

                Link("Docs", destination: ConnectorCatalog.definition(for: provider).docsURL)
                    .xrayId("settings.connectors.docsLink.\(provider.rawValue)")
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
        .xrayId("settings.connectors.row.\(provider.rawValue)")
    }

    private var statusText: String {
        connection?.status.displayName ?? "Not Installed"
    }

    private var statusColor: Color {
        switch connection?.status {
        case .connected: return .green
        case .authorizing: return .orange
        case .needsAttention: return .yellow
        case .revoked: return .gray
        case .failed: return .red
        case .disconnected, .none: return .secondary
        }
    }
}

private struct ConnectorEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState

    let provider: ConnectionProvider
    let existingConnection: Connection?

    @State private var displayName: String
    @State private var scopesText: String
    @State private var authMode: ConnectionAuthMode
    @State private var writePolicy: ConnectionWritePolicy
    @State private var accountId: String
    @State private var accountHandle: String
    @State private var accountMetadataJSON: String
    @State private var brokerReference: String
    @State private var accessToken: String
    @State private var refreshToken: String
    @State private var tokenType: String
    @State private var expiresAt: Date
    @State private var hasExpiry: Bool
    @State private var showAdvanced = false
    @State private var errorMessage: String?

    init(provider: ConnectionProvider, existingConnection: Connection?) {
        self.provider = provider
        self.existingConnection = existingConnection

        let definition = ConnectorCatalog.definition(for: provider)
        let storedCredentials = existingConnection.flatMap { try? ConnectionVault.loadCredentials(connectionId: $0.id) }

        _displayName = State(initialValue: existingConnection?.displayName ?? provider.displayName)
        _scopesText = State(initialValue: (existingConnection?.grantedScopes ?? definition.defaultScopes).joined(separator: ", "))
        _authMode = State(initialValue: existingConnection?.authMode ?? definition.authMode)
        _writePolicy = State(initialValue: existingConnection?.writePolicy ?? .requireApproval)
        _accountId = State(initialValue: existingConnection?.accountId ?? "")
        _accountHandle = State(initialValue: existingConnection?.accountHandle ?? "")
        _accountMetadataJSON = State(initialValue: existingConnection?.accountMetadataJSON ?? "")
        _brokerReference = State(initialValue: storedCredentials?.brokerReference ?? existingConnection?.brokerReference ?? "")
        _accessToken = State(initialValue: storedCredentials?.accessToken ?? "")
        _refreshToken = State(initialValue: storedCredentials?.refreshToken ?? "")
        _tokenType = State(initialValue: storedCredentials?.tokenType ?? "Bearer")
        _expiresAt = State(initialValue: storedCredentials?.expiresAt ?? Date())
        _hasExpiry = State(initialValue: storedCredentials?.expiresAt != nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(existingConnection == nil ? "Install \(provider.displayName)" : "Edit \(provider.displayName)")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Button("Done") { dismiss() }
                    .xrayId("settings.connectors.editor.doneButton.\(provider.rawValue)")
            }
            .padding()

            Form {
                Section("Connection") {
                    Text(ConnectorCatalog.definition(for: provider).setupSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("Display Name", text: $displayName)
                        .xrayId("settings.connectors.editor.displayName.\(provider.rawValue)")

                    Picker("Auth Mode", selection: $authMode) {
                        ForEach(ConnectionAuthMode.allCases, id: \.rawValue) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .xrayId("settings.connectors.editor.authMode.\(provider.rawValue)")

                    Picker("Write Policy", selection: $writePolicy) {
                        ForEach(ConnectionWritePolicy.allCases, id: \.rawValue) { policy in
                            Text(policy.displayName).tag(policy)
                        }
                    }
                    .xrayId("settings.connectors.editor.writePolicy.\(provider.rawValue)")

                    TextField("Scopes (comma-separated)", text: $scopesText, axis: .vertical)
                        .lineLimit(2...4)
                        .xrayId("settings.connectors.editor.scopes.\(provider.rawValue)")
                }

                Section("Advanced") {
                    DisclosureGroup("Manual account and credential overrides", isExpanded: $showAdvanced) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Use this only when automatic auth is unavailable. Most users should click Connect instead.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            TextField("Account ID", text: $accountId)
                                .xrayId("settings.connectors.editor.accountId.\(provider.rawValue)")
                            TextField("Account Handle", text: $accountHandle)
                                .xrayId("settings.connectors.editor.accountHandle.\(provider.rawValue)")
                            TextField("Account Metadata JSON", text: $accountMetadataJSON, axis: .vertical)
                                .lineLimit(2...5)
                                .xrayId("settings.connectors.editor.accountMetadata.\(provider.rawValue)")
                            TextField("Broker Reference", text: $brokerReference)
                                .xrayId("settings.connectors.editor.brokerReference.\(provider.rawValue)")

                            SecureField("Access Token", text: $accessToken)
                                .xrayId("settings.connectors.editor.accessToken.\(provider.rawValue)")
                            SecureField("Refresh Token", text: $refreshToken)
                                .xrayId("settings.connectors.editor.refreshToken.\(provider.rawValue)")
                            TextField("Token Type", text: $tokenType)
                                .xrayId("settings.connectors.editor.tokenType.\(provider.rawValue)")
                            Toggle("Has Expiry", isOn: $hasExpiry)
                                .xrayId("settings.connectors.editor.hasExpiry.\(provider.rawValue)")
                            if hasExpiry {
                                DatePicker("Expires At", selection: $expiresAt)
                                    .xrayId("settings.connectors.editor.expiresAt.\(provider.rawValue)")
                            }
                            Text("Tokens are stored in macOS Keychain and never in SwiftData.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let errorMessage {
                    Section("Error") {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .xrayId("settings.connectors.editor.cancelButton.\(provider.rawValue)")

                Button("Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .xrayId("settings.connectors.editor.saveButton.\(provider.rawValue)")
            }
            .padding()
        }
        .frame(width: 520, height: 640)
    }

    private func save() {
        let scopes = scopesText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        do {
            let connection = ConnectorService.upsertConnection(provider: provider, in: modelContext)
            let trimmedMetadata = accountMetadataJSON.trimmingCharacters(in: .whitespacesAndNewlines)
            connection.accountMetadataJSON = trimmedMetadata.isEmpty ? nil : trimmedMetadata
            try ConnectorService.saveManualConnection(
                provider: provider,
                displayName: displayName,
                scopes: scopes,
                authMode: authMode,
                writePolicy: writePolicy,
                accountId: accountId,
                accountHandle: accountHandle,
                brokerReference: brokerReference,
                accessToken: accessToken,
                refreshToken: refreshToken,
                tokenType: tokenType,
                expiresAt: hasExpiry ? expiresAt : nil,
                in: modelContext,
                appState: appState
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Chat Display

private struct ChatDisplaySettingsTab: View {
    @AppStorage(AppSettings.renderAdmonitionsKey, store: AppSettings.store) private var renderAdmonitions = true
    @AppStorage(AppSettings.renderDiffsKey, store: AppSettings.store) private var renderDiffs = true
    @AppStorage(AppSettings.renderTerminalKey, store: AppSettings.store) private var renderTerminal = true
    @AppStorage(AppSettings.renderMermaidKey, store: AppSettings.store) private var renderMermaid = true
    @AppStorage(AppSettings.renderHTMLKey, store: AppSettings.store) private var renderHTML = true
    @AppStorage(AppSettings.renderPDFKey, store: AppSettings.store) private var renderPDF = true
    @AppStorage(AppSettings.showSessionSummaryKey, store: AppSettings.store) private var showSessionSummary = true
    @AppStorage(AppSettings.showSuggestionChipsKey, store: AppSettings.store) private var showSuggestionChips = true

    var body: some View {
        Form {
            Section("Rich Content") {
                Toggle("Callout Cards", isOn: $renderAdmonitions)
                    .xrayId("settings.chatDisplay.renderAdmonitions")
                Text("Render > [!info], > [!warning], etc. as styled cards")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Inline HTML", isOn: $renderHTML)
                    .xrayId("settings.chatDisplay.renderHTML")
                Text("Render HTML file cards inline via WebView")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Mermaid Diagrams", isOn: $renderMermaid)
                    .xrayId("settings.chatDisplay.renderMermaid")
                Text("Render ```mermaid``` blocks as visual diagrams")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Inline PDF", isOn: $renderPDF)
                    .xrayId("settings.chatDisplay.renderPDF")
                Text("Show PDF pages inline instead of file card icon")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Tool Output") {
                Toggle("Inline Diffs", isOn: $renderDiffs)
                    .xrayId("settings.chatDisplay.renderDiffs")
                Text("Show file edits as colored diffs instead of raw JSON")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Terminal Output", isOn: $renderTerminal)
                    .xrayId("settings.chatDisplay.renderTerminal")
                Text("Style bash/shell output with terminal appearance")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Session") {
                Toggle("Session Summary Card", isOn: $showSessionSummary)
                    .xrayId("settings.chatDisplay.showSessionSummary")
                Text("Show cost, tokens, and files touched when a session completes")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Suggestion Chips", isOn: $showSuggestionChips)
                    .xrayId("settings.chatDisplay.showSuggestionChips")
                Text("Show follow-up action chips after agent responses")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Developer

private struct DeveloperSettingsTab: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage(AppSettings.bunPathOverrideKey, store: AppSettings.store) private var bunPathOverride = ""
    @AppStorage(AppSettings.sidecarPathKey, store: AppSettings.store) private var sidecarPath = ""
    @AppStorage(AppSettings.localAgentHostPathOverrideKey, store: AppSettings.store) private var localAgentHostPathOverride = ""
    @AppStorage(AppSettings.mlxRunnerPathOverrideKey, store: AppSettings.store) private var mlxRunnerPathOverride = ""
    @AppStorage(AppSettings.defaultMLXModelKey, store: AppSettings.store) private var defaultMLXModel = AppSettings.defaultMLXModel
    @AppStorage(AppSettings.dataDirectoryKey, store: AppSettings.store) private var dataDirectory = AppSettings.defaultDataDirectory
    @AppStorage(AppSettings.logLevelKey, store: AppSettings.store) private var logLevel = AppSettings.defaultLogLevel
    @AppStorage(AppSettings.useLegacyChatChromeKey, store: AppSettings.store) private var useLegacyChatChrome = false
    @State private var showResetConfirmation = false
    @State private var isInstallingMLXRunner = false
    @State private var isInstallingMLXModel = false
    @State private var mlxInstallStatusMessage: String?
    @State private var mlxModelInstallStatusMessage: String?

    private var selectedLogLevel: Binding<LogLevel> {
        Binding(
            get: { LogLevel(rawValue: logLevel) ?? .info },
            set: { logLevel = $0.rawValue }
        )
    }

    private var localProviderReport: LocalProviderStatusReport {
        LocalProviderSupport.statusReport(
            projectRootOverride: sidecarPath.isEmpty ? nil : sidecarPath,
            hostOverride: localAgentHostPathOverride.isEmpty ? nil : localAgentHostPathOverride,
            mlxRunnerOverride: mlxRunnerPathOverride.isEmpty ? nil : mlxRunnerPathOverride,
            dataDirectoryPath: dataDirectory,
            defaultMLXModel: defaultMLXModel
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
                            .xrayId("settings.developer.bunPathField")
                        Button("Browse...") {
                            browseBunPath()
                        }
                        .xrayId("settings.developer.bunPathBrowseButton")
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
                            .xrayId("settings.developer.sidecarPathField")
                        Button("Browse...") {
                            browseProjectPath()
                        }
                        .xrayId("settings.developer.sidecarPathBrowseButton")
                    }
                    Text("Root directory containing the sidecar/ folder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Local Agent Host Override")
                    HStack {
                        TextField("Use bundled host when available", text: $localAgentHostPathOverride)
                            .textFieldStyle(.roundedBorder)
                            .xrayId("settings.developer.localAgentHostField")
                        Button("Browse...") {
                            browseExecutablePath(
                                message: "Select the ClaudeStudio local-agent host executable"
                            ) { localAgentHostPathOverride = $0 }
                        }
                        .xrayId("settings.developer.localAgentHostBrowseButton")
                    }
                    Text("Normally the app uses the bundled local-agent host automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("MLX Runner Override")
                    HStack {
                        TextField("Auto-detect llm-tool", text: $mlxRunnerPathOverride)
                            .textFieldStyle(.roundedBorder)
                            .xrayId("settings.developer.mlxRunnerField")
                        Button("Browse...") {
                            browseExecutablePath(
                                message: "Select the MLX runner executable"
                            ) { mlxRunnerPathOverride = $0 }
                        }
                        .xrayId("settings.developer.mlxRunnerBrowseButton")
                    }
                    Text("Leave blank to auto-detect `llm-tool` in PATH.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Data") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Data Directory")
                    HStack {
                        TextField("~/.claudestudio", text: $dataDirectory)
                            .textFieldStyle(.roundedBorder)
                            .xrayId("settings.developer.dataDirectoryField")
                        Button("Browse...") {
                            browseDataDirectory()
                        }
                        .xrayId("settings.developer.dataDirectoryBrowseButton")
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
                .xrayId("settings.developer.logLevelPicker")
                .onChange(of: logLevel) { _, newValue in
                    guard appState.sidecarStatus == .connected,
                          let manager = appState.sidecarManager else { return }
                    Task {
                        try? await manager.send(.configSetLogLevel(level: newValue))
                    }
                }
            }

            Section("UI Experiments") {
                Toggle("Use legacy chat chrome", isOn: $useLegacyChatChrome)
                    .xrayId("settings.developer.useLegacyChatChromeToggle")
                Text("Temporary comparison toggle for the Focus First chat redesign. Turn this on to restore the previous toolbar, header, and composer layout locally.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Local Providers") {
                statusRow(
                    title: "Host",
                    summary: localProviderReport.hostSummary,
                    available: localProviderReport.hostBinaryPath != nil || localProviderReport.packagePath != nil,
                    identifier: "settings.developer.localProviders.hostStatus"
                )
                statusRow(
                    title: "Foundation Models",
                    summary: localProviderReport.foundationSummary,
                    available: localProviderReport.foundationAvailable,
                    identifier: "settings.developer.localProviders.foundationStatus"
                )
                statusRow(
                    title: "MLX",
                    summary: localProviderReport.mlxSummary,
                    available: localProviderReport.mlxAvailable,
                    identifier: "settings.developer.localProviders.mlxStatus"
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text("Managed MLX Cache")
                        .font(.headline)
                    Text(localProviderReport.mlxDownloadDirectory)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .xrayId("settings.developer.mlxDownloadDirectory")

                    HStack {
                        Button(isInstallingMLXRunner ? "Installing MLX Runner…" : "Install MLX Runner") {
                            installMLXRunner()
                        }
                        .disabled(isInstallingMLXRunner)
                        .xrayId("settings.developer.installMLXRunnerButton")

                        Button(isInstallingMLXModel ? "Installing MLX Model…" : "Install Default MLX Model") {
                            installDefaultMLXModel()
                        }
                        .disabled(isInstallingMLXModel || defaultMLXModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .xrayId("settings.developer.installDefaultMLXModelButton")

                        Spacer()
                    }

                    Text("ClaudeStudio can install `llm-tool` and pre-download the current default MLX model into its own managed cache.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let mlxInstallStatusMessage {
                        Text(mlxInstallStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .xrayId("settings.developer.mlxInstallStatus")
                    }

                    if let mlxModelInstallStatusMessage {
                        Text(mlxModelInstallStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .xrayId("settings.developer.mlxModelInstallStatus")
                    }

                    if localProviderReport.installedMLXModels.isEmpty {
                        Text("No managed MLX models are installed yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Installed MLX Models")
                                .font(.subheadline)
                            ForEach(localProviderReport.installedMLXModels) { model in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.modelIdentifier)
                                    Text(model.downloadDirectory)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }

            Section {
                HStack {
                    Button("Open Data Directory in Finder") {
                        openDataDirectory()
                    }
                    .xrayId("settings.developer.openDataDirectoryButton")

                    Spacer()

                    Button("Reset All Settings", role: .destructive) {
                        showResetConfirmation = true
                    }
                    .xrayId("settings.developer.resetSettingsButton")
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
        browseExecutablePath(
            message: "Select the Bun executable",
            directoryURL: URL(fileURLWithPath: "/opt/homebrew/bin")
        ) { bunPathOverride = $0 }
    }

    private func browseExecutablePath(
        message: String,
        directoryURL: URL? = nil,
        assign: (String) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = message
        panel.directoryURL = directoryURL
        if panel.runModal() == .OK, let url = panel.url {
            assign(url.path)
        }
    }

    private func browseProjectPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select the ClaudeStudio project directory"
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

    private func installMLXRunner() {
        isInstallingMLXRunner = true
        mlxInstallStatusMessage = "Downloading and building the MLX runner…"

        Task {
            do {
                let installedPath = try await LocalProviderInstaller.installMLXRunner(dataDirectoryPath: dataDirectory)
                await MainActor.run {
                    isInstallingMLXRunner = false
                    mlxInstallStatusMessage = "Installed MLX runner at \(installedPath)."
                    mlxRunnerPathOverride = ""
                }
            } catch {
                await MainActor.run {
                    isInstallingMLXRunner = false
                    mlxInstallStatusMessage = error.localizedDescription
                }
            }
        }
    }

    private func installDefaultMLXModel() {
        isInstallingMLXModel = true
        mlxModelInstallStatusMessage = "Downloading \(defaultMLXModel)…"

        Task {
            do {
                let result = try await LocalProviderInstaller.installMLXModel(
                    modelIdentifier: defaultMLXModel,
                    dataDirectoryPath: dataDirectory,
                    bundleResourcePath: Bundle.main.resourcePath,
                    currentDirectoryPath: FileManager.default.currentDirectoryPath,
                    projectRootOverride: sidecarPath.isEmpty ? nil : sidecarPath,
                    hostOverride: localAgentHostPathOverride.isEmpty ? nil : localAgentHostPathOverride,
                    runnerOverride: mlxRunnerPathOverride.isEmpty ? nil : mlxRunnerPathOverride
                )
                await MainActor.run {
                    isInstallingMLXModel = false
                    let verb = result.alreadyInstalled ? "Already installed" : "Installed"
                    mlxModelInstallStatusMessage = "\(verb) \(result.modelIdentifier) in \(result.downloadDirectory)."
                    mlxRunnerPathOverride = ""
                }
            } catch {
                await MainActor.run {
                    isInstallingMLXModel = false
                    mlxModelInstallStatusMessage = error.localizedDescription
                }
            }
        }
    }

    @ViewBuilder
    private func statusRow(title: String, summary: String, available: Bool, identifier: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: available ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(available ? .green : .orange)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
        }
        .xrayId(identifier)
    }
}

#Preview {
    SettingsView()
}
