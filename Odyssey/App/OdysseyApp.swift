import SwiftUI
import SwiftData
import OSLog
import Sparkle
#if DEBUG
import AppXray
#endif

@main
struct OdysseyApp: App {
    @StateObject private var appState: AppState
    @StateObject private var p2pNetworkManager = P2PNetworkManager()
    @StateObject private var sharedRoomService: SharedRoomService
    @StateObject private var sharedRoomTestAPIService: SharedRoomTestAPIService
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    @State private var configSyncService = ConfigSyncService()
    @AppStorage(AppSettings.appearanceKey, store: AppSettings.store) private var appearance = AppAppearance.system.rawValue
    @AppStorage(AppSettings.textSizeKey, store: AppSettings.store) private var textSize = AppSettings.defaultTextSize
    @AppStorage(AppSettings.autoConnectSidecarKey, store: AppSettings.store) private var autoConnectSidecar = true
    @FocusedValue(\.openProjectSettingsAction) private var openProjectSettingsAction

    @Environment(\.openWindow) private var openWindow

    let modelContainer: ModelContainer
    private let launchIntent: LaunchIntent?

    init() {
        let appState = AppState()
        let sharedRoomService = SharedRoomService()
        let sharedRoomTestAPIService = SharedRoomTestAPIService()
        _appState = StateObject(wrappedValue: appState)
        _sharedRoomService = StateObject(wrappedValue: sharedRoomService)
        _sharedRoomTestAPIService = StateObject(wrappedValue: sharedRoomTestAPIService)

        #if DEBUG
        // Auto mode: SDK tries relay-client first, falls back to server on port 19480.
        // Port 19480 is in the discovery probe range (19400-19499) so both paths work.
        AppXray.shared.start(config: AppXrayConfig(appName: "Odyssey", port: 19480, mode: .auto))
        #endif

        AppTextSizeShortcutMonitor.shared.start()

        LegacyInstanceMigration.migrateIfNeeded(
            instanceName: InstanceConfig.name,
            destinationBaseDirectory: InstanceConfig.baseDirectory,
            destinationDefaults: InstanceConfig.userDefaults
        )
        InstanceConfig.ensureDirectories()

        do {
            let storeURL = InstanceConfig.dataDirectory.appendingPathComponent("Odyssey.store")
            let config = ModelConfiguration(url: storeURL, cloudKitDatabase: .none)
            let schema = Schema([
                Project.self,
                Agent.self,
                Session.self,
                Conversation.self,
                ConversationMessage.self,
                MessageAttachment.self,
                Skill.self,
                Connection.self,
                MCPServer.self,
                PermissionSet.self,
                SharedWorkspace.self,
                BlackboardEntry.self,
                Peer.self,
                AgentGroup.self,
                PromptTemplate.self,
                TaskItem.self,
                ScheduledMission.self,
                ScheduledMissionRun.self,
                SharedRoomInvite.self,
                NostrPeer.self,
            ])
            modelContainer = try ModelContainer(
                for: schema,
                configurations: config
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }

        launchIntent = LaunchIntent.fromCommandLine()
        Self.performProjectFirstResetIfNeeded(modelContainer: modelContainer)
        sharedRoomService.configure(modelContext: modelContainer.mainContext)
        sharedRoomTestAPIService.configure(
            sharedRoomService: sharedRoomService,
            modelContext: modelContainer.mainContext,
            appState: appState  // local var, same instance SwiftUI will use
        )
        sharedRoomTestAPIService.startIfEnabled()

        // Set modelContext and sharedRoomService on AppState early so that headless paths
        // (test API, no visible window) can persist agent messages without waiting for onAppear.
        appState.modelContext = modelContainer.mainContext
        appState.sharedRoomService = sharedRoomService
    }

    private var resolvedColorScheme: ColorScheme? {
        (AppAppearance(rawValue: appearance) ?? .system).colorScheme
    }

    private var resolvedTextSize: AppTextSize {
        AppTextSize(rawValue: textSize) ?? .standard
    }

    var body: some Scene {
        WindowGroup("Odyssey", for: String.self) { $projectDir in
            ProjectWindowContent(
                initialProjectDirectory: projectDir,
                appState: appState,
                p2pNetworkManager: p2pNetworkManager,
                configSyncService: $configSyncService,
                modelContainer: modelContainer,
                launchIntent: launchIntent,
                autoConnectSidecar: autoConnectSidecar,
                resolvedColorScheme: resolvedColorScheme,
                lastProjectDirectory: lastProjectDirectory,
                sharedRoomService: sharedRoomService,
                sharedRoomTestAPIService: sharedRoomTestAPIService
            )
            .environment(\.appTextScale, resolvedTextSize.scaleFactor)
        }
        .modelContainer(modelContainer)
        .defaultSize(width: 1200, height: 800)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Project\u{2026}") {
                    // Open a new window with no project — shows the project picker
                    openWindow(value: "" as String)
                }
                .keyboardShortcut("o")
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings\u{2026}") {
                    openProjectSettingsAction?()
                }
                .keyboardShortcut(",", modifiers: .command)
                .disabled(openProjectSettingsAction == nil)
            }
            CommandGroup(after: .sidebar) {
                Button("Increase Text Size") {
                    increaseTextSize()
                }
                .keyboardShortcut("=", modifiers: .command)
                .disabled(!resolvedTextSize.canIncrease)

                Button("Decrease Text Size") {
                    decreaseTextSize()
                }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(!resolvedTextSize.canDecrease)

                Button("Actual Size") {
                    resetTextSize()
                }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(resolvedTextSize == .standard)
            }
            CommandMenu("Debug") {
                Button("Send Test Message") {
                    sendTestMessage()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .help) {
                Button("Report a Bug...") {
                    if let url = URL(string: "https://forms.gle/Cq4bWNwUVaX8zZr67") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates\u{2026}") {
                    updaterController.updater.checkForUpdates()
                }
                .disabled(!updaterController.updater.canCheckForUpdates)
            }
        }

        Window("Debug Log", id: "debug-log") {
            DebugLogView()
                .environmentObject(appState)
                .environment(\.appTextScale, resolvedTextSize.scaleFactor)
                .preferredColorScheme(resolvedColorScheme)
        }
        .defaultSize(width: 900, height: 600)
        .keyboardShortcut("d", modifiers: [.command, .shift])
    }

    // MARK: - Recent project persistence

    private var lastProjectDirectory: String? {
        InstanceConfig.userDefaults.string(forKey: AppSettings.instanceWorkingDirectoryKey)
    }

    private func saveLastProjectDirectory(_ path: String) {
        InstanceConfig.userDefaults.set(path, forKey: AppSettings.instanceWorkingDirectoryKey)
    }

    private func increaseTextSize() {
        textSize = resolvedTextSize.increased().rawValue
    }

    private func decreaseTextSize() {
        textSize = resolvedTextSize.decreased().rawValue
    }

    private func resetTextSize() {
        textSize = AppTextSize.standard.rawValue
    }

    // MARK: - Test

    @MainActor
    private func sendTestMessage() {
        let context = modelContainer.mainContext
        let projectPath = lastProjectDirectory ?? NSHomeDirectory()
        let project = ProjectRecords.upsertProject(at: projectPath, in: context)
        let conversation = Conversation(topic: "Test Chat", projectId: project.id)
        let userParticipant = Participant(type: .user, displayName: "You")
        userParticipant.conversation = conversation
        conversation.participants.append(userParticipant)

        let testSession = Session(agent: nil, mode: .interactive, workingDirectory: projectPath)
        testSession.conversations = [conversation]
        conversation.sessions.append(testSession)
        context.insert(testSession)

        let agentParticipant = Participant(
            type: .agentSession(sessionId: testSession.id),
            displayName: AgentDefaults.displayName(forProvider: testSession.provider)
        )
        agentParticipant.conversation = conversation
        conversation.participants.append(agentParticipant)

        let userMessage = ConversationMessage(
            senderParticipantId: userParticipant.id,
            text: "What is 2+2? Reply with just the number.",
            type: .chat,
            conversation: conversation
        )
        conversation.messages.append(userMessage)

        context.insert(conversation)
        try? context.save()

        guard appState.sidecarStatus == .connected,
              let manager = appState.sidecarManager else {
            Log.general.warning("Sidecar not connected")
            return
        }

        let sessionId = testSession.id.uuidString
        let config = AgentDefaults.makeFreeformAgentConfig(
            provider: testSession.provider,
            model: testSession.model,
            workingDirectory: projectPath,
            maxTurns: 1,
            interactive: nil
        )

        appState.streamingText.removeValue(forKey: sessionId)
        appState.lastSessionEvent.removeValue(forKey: sessionId)

        Task {
            try? await manager.send(.sessionCreate(
                conversationId: sessionId,
                agentConfig: config
            ))
            try? await manager.send(.sessionMessage(
                sessionId: sessionId,
                text: "What is 2+2? Reply with just the number."
            ))
            Log.general.info("Sent test message for session \(sessionId, privacy: .public)")
        }
    }

    private static func performProjectFirstResetIfNeeded(modelContainer: ModelContainer) {
        let defaults = InstanceConfig.userDefaults
        let resetKey = "projectFirstShell.reset.v1"
        guard !defaults.bool(forKey: resetKey) else { return }

        let context = modelContainer.mainContext

        let conversations = (try? context.fetch(FetchDescriptor<Conversation>())) ?? []
        for item in conversations {
            context.delete(item)
        }

        let tasks = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        for item in tasks {
            context.delete(item)
        }

        let schedules = (try? context.fetch(FetchDescriptor<ScheduledMission>())) ?? []
        for item in schedules {
            context.delete(item)
        }

        let runs = (try? context.fetch(FetchDescriptor<ScheduledMissionRun>())) ?? []
        for item in runs {
            context.delete(item)
        }

        try? context.save()

        let taskboardDir = InstanceConfig.baseDirectory.appendingPathComponent("taskboard")
        if let paths = try? FileManager.default.contentsOfDirectory(at: taskboardDir, includingPropertiesForKeys: nil) {
            for path in paths {
                try? FileManager.default.removeItem(at: path)
            }
        }

        defaults.set(true, forKey: resetKey)
    }
}

// MARK: - Project Window Content

/// Wrapper view that creates and owns the WindowState for a project window.
/// Shows a project picker if no project directory is set yet.
private struct ProjectWindowContent: View {
    let initialProjectDirectory: String?
    let appState: AppState
    let p2pNetworkManager: P2PNetworkManager
    @Binding var configSyncService: ConfigSyncService
    let modelContainer: ModelContainer
    let launchIntent: LaunchIntent?
    let autoConnectSidecar: Bool
    let resolvedColorScheme: ColorScheme?
    let lastProjectDirectory: String?
    let sharedRoomService: SharedRoomService
    let sharedRoomTestAPIService: SharedRoomTestAPIService

    @State private var windowState: WindowState?
    @State private var chosenDirectory: String?
    @State private var hasInitialized = false

    private var effectiveDirectory: String? {
        // Empty string means "show picker" (from Cmd+O)
        if let chosen = chosenDirectory, !chosen.isEmpty { return chosen }
        if let initial = initialProjectDirectory, !initial.isEmpty { return initial }
        return lastProjectDirectory
    }

    var body: some View {
        Group {
            if let ws = windowState {
                MainWindowView()
                    .environment(ws)
            } else if effectiveDirectory != nil || hasExistingProjects {
                ProgressView("Opening project\u{2026}")
            } else {
                ProjectPickerView { path in
                    chosenDirectory = path
                }
            }
        }
        .environmentObject(appState)
        .environmentObject(p2pNetworkManager)
        .environmentObject(sharedRoomService)
        .preferredColorScheme(resolvedColorScheme)
        .onChange(of: effectiveDirectory) { _, newDir in
            if let dir = newDir, windowState == nil {
                initializeWindow(projectDirectory: dir)
            }
        }
        .onAppear {
            guard !hasInitialized else { return }
            hasInitialized = true

            // Boot shared services (only once across windows)
            appState.modelContext = modelContainer.mainContext
            appState.configSyncService = configSyncService
            appState.sharedRoomService = sharedRoomService
            configSyncService.start(container: modelContainer)
            appState.configureScheduling(modelContext: modelContainer.mainContext)
            sharedRoomService.configure(modelContext: modelContainer.mainContext)
            sharedRoomTestAPIService.configure(
                sharedRoomService: sharedRoomService,
                modelContext: modelContainer.mainContext
            )
            sharedRoomTestAPIService.startIfEnabled()

            if autoConnectSidecar, appState.sidecarStatus == .disconnected {
                appState.connectSidecar()
            }

            p2pNetworkManager.attach(modelContext: modelContainer.mainContext)
            p2pNetworkManager.sidecarManager = appState.sidecarManager
            p2pNetworkManager.sharedRoomService = sharedRoomService
            sharedRoomService.p2pNetworkManager = p2pNetworkManager
            p2pNetworkManager.setSidecarWsPort(appState.allocatedWsPort)
            p2pNetworkManager.start()

            ProjectRecords.repairMissingProjects(in: modelContainer.mainContext)

            #if DEBUG
            AppXray.shared.registerObservableObject(appState, name: "appState", setters: [
                "showAddResidentSheet": { [weak appState] v in
                    let val = (v as? Bool) ?? false
                    DispatchQueue.main.async { appState?.showAddResidentSheet = val }
                }
            ])
            #endif

            // If we already have a directory, initialize immediately
            if let dir = effectiveDirectory {
                initializeWindow(projectDirectory: dir)
            } else if let project = preferredProject() {
                initializeWindow(project: project)
            }
        }
        .onOpenURL { url in
            guard let ws = windowState else { return }
            if ConnectorService.handleCallback(url, in: modelContainer.mainContext, appState: appState) {
                return
            }
            if let intent = LaunchIntent.fromURL(url) {
                appState.executeLaunchIntent(intent, modelContext: modelContainer.mainContext, windowState: ws)
            }
        }
        .navigationTitle(windowState.map { "Odyssey — \($0.projectName)" } ?? "Odyssey")
    }

    private var hasExistingProjects: Bool {
        let descriptor = FetchDescriptor<Project>()
        return ((try? modelContainer.mainContext.fetch(descriptor)) ?? []).isEmpty == false
    }

    private func preferredProject() -> Project? {
        let descriptor = FetchDescriptor<Project>()
        let projects = (try? modelContainer.mainContext.fetch(descriptor)) ?? []
        if let lastProjectDirectory {
            let canonical = ProjectRecords.canonicalPath(for: lastProjectDirectory)
            if let match = projects.first(where: { $0.canonicalRootPath == canonical }) {
                return match
            }
        }
        return projects.sorted(by: { $0.lastOpenedAt > $1.lastOpenedAt }).first
    }

    private func initializeWindow(projectDirectory: String) {
        guard windowState == nil else { return }

        let project = ProjectRecords.upsertProject(at: projectDirectory, in: modelContainer.mainContext)
        initializeWindow(project: project)
    }

    private func initializeWindow(project: Project) {
        guard windowState == nil else { return }

        let ws = WindowState(project: project)
        ws.appState = appState
        windowState = ws

        // Save as last-used
        InstanceConfig.userDefaults.set(project.rootPath, forKey: AppSettings.instanceWorkingDirectoryKey)
        RecentDirectories.add(project.rootPath)

        // Execute launch intent if present
        if let intent = launchIntent {
            let ctx = modelContainer.mainContext
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(800))
                appState.executeLaunchIntent(intent, modelContext: ctx, windowState: ws)
            }
        }
    }
}

// MARK: - Project Picker View

/// Shown when a new window is opened without a project directory.
/// Embeds the shared ChangeProjectSheet inline (full-window, not as a sheet).
private struct ProjectPickerView: View {
    let onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)
                Text("Open a Project")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("Choose a folder to add to the project-first shell.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }
            .padding(.bottom, 8)

            ChangeProjectSheet(onSelect: onSelect)
                .frame(maxWidth: 500, maxHeight: 400)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
