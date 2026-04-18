import SwiftUI
import SwiftData

struct OpenProjectSettingsAction {
    let handler: () -> Void

    func callAsFunction() {
        handler()
    }
}

private struct OpenProjectSettingsActionKey: FocusedValueKey {
    typealias Value = OpenProjectSettingsAction
}

extension FocusedValues {
    var openProjectSettingsAction: OpenProjectSettingsAction? {
        get { self[OpenProjectSettingsActionKey.self] }
        set { self[OpenProjectSettingsActionKey.self] = newValue }
    }
}

struct MainWindowView: View {
    @Environment(AppState.self) private var appState
    @EnvironmentObject private var p2pNetworkManager: P2PNetworkManager
    @EnvironmentObject private var sharedRoomService: SharedRoomService
    @Environment(WindowState.self) private var windowState: WindowState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @AppStorage(FeatureFlags.showAdvancedKey, store: AppSettings.store) private var masterFlag = false
    @AppStorage(FeatureFlags.peerNetworkKey, store: AppSettings.store) private var peerNetworkFlag = false
    @AppStorage(FeatureFlags.debugLogsKey, store: AppSettings.store) private var debugLogsFlag = false
    @AppStorage(FeatureFlags.federationKey, store: AppSettings.store) private var federationFlag = false
    @AppStorage(FeatureFlags.agentCommsKey, store: AppSettings.store) private var agentCommsFlag = false
    @Query private var conversations: [Conversation]
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var showStatusPopover = false

    private var showPeerNetwork: Bool { FeatureFlags.isEnabled(FeatureFlags.peerNetworkKey) || (masterFlag && peerNetworkFlag) }
    private var showDebugLogs: Bool { FeatureFlags.isEnabled(FeatureFlags.debugLogsKey) || (masterFlag && debugLogsFlag) }
    private var showFederation: Bool { FeatureFlags.isEnabled(FeatureFlags.federationKey) || (masterFlag && federationFlag) }
    private var showAgentComms: Bool { FeatureFlags.isEnabled(FeatureFlags.agentCommsKey) || (masterFlag && agentCommsFlag) }
    private var showWorkspaceMenu: Bool { showFederation || showAgentComms || showPeerNetwork || showDebugLogs }

    var body: some View {
        @Bindable var ws = windowState
        Group {
            if ws.activeRoute == .settings {
                SettingsView(
                    pendingConfigSection: ws.pendingConfigSection,
                    pendingConfigSlug: ws.pendingConfigSlug
                ) {
                    ws.pendingConfigSection = nil
                    ws.pendingConfigSlug = nil
                    ws.closeSettings()
                }
                .environment(appState)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .xrayId("mainWindow.settingsScreen")
            } else {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    SidebarView()
                } detail: {
                    Group {
                        if ws.inspectorVisible && windowState.selectedConversationId != nil {
                            HSplitView {
                                mainDetailPane
                                    .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
                                    .layoutPriority(1)
                                inspectorPane
                                    .frame(minWidth: 320, idealWidth: 380, maxWidth: 720, maxHeight: .infinity)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(SplitViewConfigurator(autosaveName: "odyssey.chatInspectorSplit"))
                            .xrayId("mainWindow.chatInspectorSplit")
                        } else {
                            mainDetailPane
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
                .navigationSplitViewStyle(.balanced)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(WindowTitleSetter(projectName: windowState.projectName, chatTitle: windowState.chatTitle))
        .toolbar {
            if ws.activeRoute != .settings {
                ToolbarItem(placement: .status) {
                    sidecarStatusPill
                }
            }

            if ws.activeRoute != .settings, showWorkspaceMenu {
                ToolbarItem(placement: .automatic) {
                    Menu {
                        if showFederation {
                            Button {
                                ws.showSharedRoomInbox = true
                            } label: {
                                Label("Invites", systemImage: "person.badge.plus")
                            }
                            .keyboardShortcut("i", modifiers: [.command, .shift])
                            .xrayId("mainWindow.workspaceMenu.invitesButton")
                        }

                        if showAgentComms {
                            Button {
                                windowState.showAgentComms = true
                            } label: {
                                Label("Agent Comms", systemImage: "antenna.radiowaves.left.and.right")
                            }
                            .keyboardShortcut("a", modifiers: [.command, .shift])
                            .xrayId("mainWindow.workspaceMenu.agentCommsButton")
                        }

                        if showPeerNetwork {
                            Button {
                                windowState.showPeerNetwork = true
                            } label: {
                                Label("Peer Network", systemImage: "network")
                            }
                            .keyboardShortcut("p", modifiers: [.command, .shift])
                            .xrayId("mainWindow.workspaceMenu.peerNetworkButton")
                        }

                        if showDebugLogs {
                            Button {
                                openWindow(id: "debug-log")
                            } label: {
                                Label("Debug Log", systemImage: "ladybug")
                            }
                            .keyboardShortcut("d", modifiers: [.command, .shift])
                            .xrayId("mainWindow.workspaceMenu.debugLogButton")
                        }
                    } label: {
                        MainToolbarActionLabel(title: "Workspace", systemImage: "rectangle.grid.1x2")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Open invites, agent comms, peer network, or debug tools")
                    .xrayId("mainWindow.workspaceMenu")
                    .accessibilityLabel("Workspace")
                }
            }

            if ws.activeRoute != .settings {
                ToolbarItem(placement: .automatic) {
                    Button {
                        ws.inspectorVisible.toggle()
                    } label: {
                        Label(
                            ws.inspectorVisible ? "Hide Inspector" : "Show Inspector",
                            systemImage: "sidebar.trailing"
                        )
                    }
                    .keyboardShortcut("0", modifiers: [.command, .option])
                    .help(ws.inspectorVisible ? "Hide inspector (⌘⌥0)" : "Show inspector (⌘⌥0)")
                    .xrayId("mainWindow.inspectorToggle")
                    .accessibilityLabel(ws.inspectorVisible ? "Hide Inspector" : "Show Inspector")
                }
            }
        }
        .sheet(isPresented: $ws.showScheduleLibrary) {
            ScheduleLibraryView()
                .frame(minWidth: 900, minHeight: 560)
        }
        .sheet(isPresented: $ws.showAllSchedules) {
            GlobalSchedulesView()
                .environment(appState)
        }
        .sheet(isPresented: $ws.showAgentComms) {
            AgentCommsView()
                .environment(appState)
                .frame(minWidth: 600, minHeight: 400)
        }
        .sheet(isPresented: $ws.showSharedRoomInbox) {
            SharedRoomInviteInboxView()
                .frame(minWidth: 560, minHeight: 420)
        }
        .sheet(isPresented: $ws.showSharedRoomInviteSheet) {
            if let conversationId = ws.sharedRoomInviteConversationId {
                SharedRoomInviteSheet(conversationId: conversationId)
                    .frame(minWidth: 460, minHeight: 360)
            }
        }
        .sheet(isPresented: $ws.showPeerNetwork) {
            PeerNetworkView()
                .environmentObject(p2pNetworkManager)
                .environment(\.modelContext, modelContext)
        }
        .sheet(isPresented: $ws.showWorkshop) {
            WorkshopView()
                .environment(appState)
                .frame(minWidth: 960, minHeight: 640)
        }
        .onAppear {
            appState.connectSidecar()
        }
        .alert("Launch Error", isPresented: launchErrorBinding) {
            Button("Dismiss") { windowState.launchError = nil }
        } message: {
            Text(windowState.launchError ?? "")
        }
        .focusedSceneValue(
            \.openProjectSettingsAction,
            OpenProjectSettingsAction { windowState.openSettings() }
        )
    }

    private var launchErrorBinding: Binding<Bool> {
        Binding(
            get: { windowState.launchError != nil },
            set: { if !$0 { windowState.launchError = nil } }
        )
    }

    // MARK: - Detail panes

    @ViewBuilder
    private var mainDetailPane: some View {
        if let conversation = selectedConversation {
            ChatView(selectedConversation: conversation)
                .id(conversation.id)
        } else if let groupId = windowState.selectedGroupId {
            GroupDetailView(groupId: groupId)
                .id(groupId)
        } else {
            WelcomeView(
                onQuickChat: { createQuickChat() },
                onStartAgent: { agent in startSessionWithAgent(agent) },
                onStartGroup: { group in startGroupChat(group) }
            )
            .stableXrayId("mainWindow.welcomeView")
        }
    }

    @ViewBuilder
    private var inspectorPane: some View {
        if let conversation = selectedConversation {
            InspectorView(conversation: conversation)
                .id(conversation.id)
        } else {
            Text("Inspector")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .xrayId("mainWindow.inspectorPlaceholder")
        }
    }

    private var selectedConversation: Conversation? {
        guard let conversationId = windowState.selectedConversationId else { return nil }
        return conversations.first { $0.id == conversationId }
    }

    // MARK: - Status Pill

    private var sidecarStatusPill: some View {
        Button {
            showStatusPopover.toggle()
        } label: {
            HStack(spacing: 4) {
                statusDot
                Text(statusShortLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
        }
        .buttonStyle(.plain)
        .help("Sidecar status")
        .xrayId("mainWindow.sidecarStatusPill")
        .accessibilityLabel("Sidecar \(statusShortLabel)")
        .popover(isPresented: $showStatusPopover, arrowEdge: .bottom) {
            statusPopoverContent
        }
    }

    @ViewBuilder
    private var statusDot: some View {
        switch appState.sidecarStatus {
        case .connected:
            Circle().fill(.green).frame(width: 7, height: 7)
        case .connecting:
            ProgressView().controlSize(.mini)
        case .disconnected:
            Circle().fill(.gray).frame(width: 7, height: 7)
        case .error:
            Circle().fill(.red).frame(width: 7, height: 7)
        }
    }

    private var statusShortLabel: String {
        switch appState.sidecarStatus {
        case .connected: "Connected"
        case .connecting: "Connecting"
        case .disconnected: "Disconnected"
        case .error: "Error"
        }
    }

    private var statusPopoverContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                statusDot
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sidecar")
                        .font(.headline)
                    switch appState.sidecarStatus {
                    case .connected:
                        Text("ws://localhost:\(appState.allocatedWsPort)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case .error(let msg):
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(3)
                    default:
                        EmptyView()
                    }
                }
            }

            Divider()

            HStack {
                switch appState.sidecarStatus {
                case .connected:
                    Button("Reconnect") {
                        showStatusPopover = false
                        appState.disconnectSidecar()
                        appState.connectSidecar()
                    }
                    .controlSize(.small)
                    .xrayId("mainWindow.statusPopover.reconnectButton")

                    Button("Stop") {
                        showStatusPopover = false
                        appState.disconnectSidecar()
                    }
                    .controlSize(.small)
                    .foregroundStyle(.red)
                    .xrayId("mainWindow.statusPopover.stopButton")

                case .disconnected, .error:
                    Button("Connect") {
                        showStatusPopover = false
                        appState.connectSidecar()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .xrayId("mainWindow.statusPopover.connectButton")

                case .connecting:
                    Text("Connecting...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(width: 240)
        .xrayId("mainWindow.statusPopover")
    }

    // MARK: - Actions

    private func createQuickChat() {
        let conversation = Conversation(
            topic: "New Thread",
            projectId: windowState.selectedProjectId,
            threadKind: .freeform
        )
        let userParticipant = Participant(type: .user, displayName: "You")
        userParticipant.conversation = conversation
        conversation.participants.append(userParticipant)
        modelContext.insert(conversation)
        try? modelContext.save()
        windowState.selectedConversationId = conversation.id
    }

    private func startSessionWithAgent(_ agent: Agent) {
        let session = Session(agent: agent, mode: .interactive)
        // Agent home always wins when set; project dir is fallback for non-resident agents
        let rawDir = agent.defaultWorkingDirectory?.isEmpty == false
            ? agent.defaultWorkingDirectory!
            : windowState.projectDirectory
        if !rawDir.isEmpty {
            session.workingDirectory = NSString(string: rawDir).expandingTildeInPath
        }
        let conversation = Conversation(
            topic: agent.name,
            sessions: [session],
            projectId: nil,
            threadKind: .direct
        )
        let userParticipant = Participant(type: .user, displayName: "You")
        let agentParticipant = Participant(
            type: .agentSession(sessionId: session.id),
            displayName: agent.name
        )
        userParticipant.conversation = conversation
        agentParticipant.conversation = conversation
        conversation.participants = [userParticipant, agentParticipant]
        session.conversations = [conversation]

        modelContext.insert(session)
        modelContext.insert(conversation)
        try? modelContext.save()
        windowState.selectedConversationId = conversation.id
    }

    private func startGroupChat(_ group: AgentGroup) {
        if let convoId = appState.startGroupChat(
            group: group,
            projectDirectory: "",
            projectId: nil,
            modelContext: modelContext
        ) {
            windowState.selectedConversationId = convoId
        }
    }
}

private struct MainToolbarActionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.body)
            Text(title)
                .font(.callout)
                .lineLimit(1)
        }
    }
}

/// Finds the nearest NSSplitView ancestor and sets its autosaveName so macOS
/// persists the divider position between app launches.
private struct SplitViewConfigurator: NSViewRepresentable {
    let autosaveName: String

    func makeNSView(context: Context) -> NSView {
        let view = SplitViewFinderView(name: autosaveName)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class SplitViewFinderView: NSView {
        let name: String
        init(name: String) {
            self.name = name
            super.init(frame: .zero)
        }
        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                self?.configureSplitView()
            }
        }

        private func configureSplitView() {
            var current: NSView? = superview
            while let view = current {
                if let splitView = view as? NSSplitView {
                    if splitView.autosaveName == nil || splitView.autosaveName!.isEmpty {
                        splitView.autosaveName = name
                    }
                    return
                }
                current = view.superview
            }
        }
    }
}

/// Sets the NSWindow title for multi-instance disambiguation.
/// Uses NSWindow.didBecomeKeyNotification so it fires after SwiftUI finishes layout.
private struct WindowTitleSetter: NSViewRepresentable {
    let projectName: String
    let chatTitle: String?

    private var computedTitle: String {
        guard let name = chatTitle, !name.isEmpty else { return projectName }
        let isDefault = projectName == "Playground" || projectName == "No Project"
        return isDefault ? name : "\(projectName) / \(name)"
    }

    func makeNSView(context: Context) -> NSView {
        TitleSettingView(title: computedTitle)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? TitleSettingView)?.setTitle(computedTitle)
    }

    private final class TitleSettingView: NSView {
        private var title: String

        init(title: String) {
            self.title = title
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError() }

        func setTitle(_ newTitle: String) {
            title = newTitle
            window?.title = newTitle
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.title = title
        }
    }
}
