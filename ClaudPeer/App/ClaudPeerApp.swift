import SwiftUI
import SwiftData
#if DEBUG
import AppXray
#endif

@main
struct ClaudPeerApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var p2pNetworkManager = P2PNetworkManager()
    @AppStorage(AppSettings.appearanceKey, store: AppSettings.store) private var appearance = AppAppearance.system.rawValue
    @AppStorage(AppSettings.autoConnectSidecarKey, store: AppSettings.store) private var autoConnectSidecar = true

    let modelContainer: ModelContainer

    init() {
        #if DEBUG
        AppXray.shared.start(appName: "ClaudPeer")
        #endif

        InstanceConfig.ensureDirectories()

        do {
            let storeURL = InstanceConfig.dataDirectory.appendingPathComponent("ClaudPeer.store")
            let config = ModelConfiguration(url: storeURL)
            let schema = Schema([
                Agent.self,
                Session.self,
                Conversation.self,
                ConversationMessage.self,
                MessageAttachment.self,
                Skill.self,
                MCPServer.self,
                PermissionSet.self,
                SharedWorkspace.self,
                BlackboardEntry.self,
                Peer.self,
                AgentGroup.self,
            ])
            modelContainer = try ModelContainer(
                for: schema,
                configurations: config
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }

        DefaultsSeeder.seedIfNeeded(container: modelContainer)
        DefaultsSeeder.seedGroupsIfNeeded(container: modelContainer)
    }

    private var resolvedColorScheme: ColorScheme? {
        (AppAppearance(rawValue: appearance) ?? .system).colorScheme
    }

    private var windowTitle: String {
        InstanceConfig.isDefault ? "ClaudPeer" : "ClaudPeer — \(InstanceConfig.name)"
    }

    var body: some Scene {
        WindowGroup(windowTitle) {
            Group {
                if appState.showDirectoryPicker {
                    WorkingDirectoryPicker { path in
                        RecentDirectories.add(path)
                        appState.setInstanceWorkingDirectory(path)
                        appState.showDirectoryPicker = false
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .windowBackgroundColor))
                } else {
                    MainWindowView()
                }
            }
            .environmentObject(appState)
            .environmentObject(p2pNetworkManager)
            .preferredColorScheme(resolvedColorScheme)
            .onAppear {
                appState.modelContext = modelContainer.mainContext
                appState.loadInstanceWorkingDirectory()
                if autoConnectSidecar {
                    appState.connectSidecar()
                }
                // Start P2P discovery & advertising so peers can find us even when the sheet is closed
                p2pNetworkManager.attach(modelContext: modelContainer.mainContext)
                p2pNetworkManager.sidecarManager = appState.sidecarManager
                p2pNetworkManager.setSidecarWsPort(appState.allocatedWsPort)
                p2pNetworkManager.start()

                // Prune orphaned git worktrees from crashed sessions
                Task {
                    let ctx = modelContainer.mainContext
                    let kind = "worktree"
                    let descriptor = FetchDescriptor<Session>(predicate: #Predicate { s in
                        s.workspaceTypeKind == kind
                    })
                    let worktreeSessions = (try? ctx.fetch(descriptor)) ?? []
                    let active = worktreeSessions.filter { $0.status == .active || $0.status == .paused }
                    await WorktreeCleanup.pruneOrphaned(activeSessions: active)
                }
                #if DEBUG
                AppXray.shared.registerObservableObject(appState, name: "appState")
                #endif
            }
        }
        .modelContainer(modelContainer)
        .defaultSize(width: 1200, height: 800)
        .windowResizability(.contentMinSize)
        .commands {
            CommandMenu("Debug") {
                Button("Send Test Message") {
                    sendTestMessage()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
                .preferredColorScheme(resolvedColorScheme)
        }
    }

    @MainActor
    private func sendTestMessage() {
        let context = modelContainer.mainContext
        let conversation = Conversation(topic: "Test Chat")
        let userParticipant = Participant(type: .user, displayName: "You")
        userParticipant.conversation = conversation
        conversation.participants.append(userParticipant)

        let testSession = Session(agent: nil, mode: .interactive, workingDirectory: appState.instanceWorkingDirectory ?? NSHomeDirectory())
        testSession.conversations = [conversation]
        conversation.sessions.append(testSession)
        context.insert(testSession)

        let agentParticipant = Participant(
            type: .agentSession(sessionId: testSession.id),
            displayName: "Claude"
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

        appState.selectedConversationId = conversation.id

        guard appState.sidecarStatus == .connected,
              let manager = appState.sidecarManager else {
            print("[Test] Sidecar not connected")
            return
        }

        let sessionId = testSession.id.uuidString
        let config = AgentConfig(
            name: "Claude",
            systemPrompt: "You are a helpful assistant. Be concise and clear.",
            allowedTools: [],
            mcpServers: [],
            model: "claude-sonnet-4-6",
            maxTurns: 1,
            maxBudget: nil,
            maxThinkingTokens: 10000,
            workingDirectory: appState.instanceWorkingDirectory ?? NSHomeDirectory(),
            skills: []
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
            print("[Test] Sent test message for session \(sessionId)")
        }
    }
}
