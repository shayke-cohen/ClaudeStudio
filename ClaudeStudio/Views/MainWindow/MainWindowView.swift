import SwiftUI
import SwiftData

struct MainWindowView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var p2pNetworkManager: P2PNetworkManager
    @Environment(WindowState.self) private var windowState: WindowState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @Query private var conversations: [Conversation]
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var showStatusPopover = false

    var body: some View {
        @Bindable var ws = windowState
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
                            .frame(minWidth: 220, idealWidth: 380, maxWidth: 720, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(SplitViewConfigurator(autosaveName: "claudestudio.chatInspectorSplit"))
                    .xrayId("mainWindow.chatInspectorSplit")
                } else {
                    mainDetailPane
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 900, minHeight: 600)
        .background(WindowTitleSetter(projectName: windowState.projectName))
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Settings")
                .xrayId("mainWindow.settingsButton")
                .accessibilityIdentifier("mainWindow.settingsButton")
                .accessibilityLabel("Settings")
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    windowState.showNewSessionSheet = true
                } label: {
                    MainToolbarActionLabel(title: "New Thread", systemImage: "plus.bubble")
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("n", modifiers: .command)
                .help("New thread (⌘N)")
                .xrayId("mainWindow.newSessionButton")
                .accessibilityIdentifier("mainWindow.newSessionButton")
                .accessibilityLabel("New Session")

                Button {
                    windowState.showNewGroupThreadSheet = true
                } label: {
                    MainToolbarActionLabel(title: "Group Thread", systemImage: "bubble.left.and.bubble.right.fill")
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("n", modifiers: [.command, .option])
                .help("New group thread (⌘⌥N)")
                .xrayId("mainWindow.newGroupThreadButton")
                .accessibilityIdentifier("mainWindow.newGroupThreadButton")
                .accessibilityLabel("New Group Thread")

                Button {
                    createQuickChat()
                } label: {
                    MainToolbarActionLabel(title: "Quick Chat", systemImage: "plus.message")
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .help("Quick chat (⌘⇧N)")
                .xrayId("mainWindow.quickChatButton")
                .accessibilityIdentifier("mainWindow.quickChatButton")
                .accessibilityLabel("Quick Chat")
            }

            ToolbarItem(placement: .status) {
                sidecarStatusPill
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    windowState.showScheduleLibrary = true
                } label: {
                    Label("Schedules", systemImage: "clock.badge")
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .help("Schedules (⌘⇧S)")
                .xrayId("mainWindow.schedulesButton")
                .accessibilityIdentifier("mainWindow.schedulesButton")
                .accessibilityLabel("Schedules")
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    windowState.showAgentComms = true
                } label: {
                    Label("Agent Comms", systemImage: "antenna.radiowaves.left.and.right")
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .help("Agent comms (⌘⇧A)")
                .xrayId("mainWindow.agentCommsButton")
                .accessibilityIdentifier("mainWindow.agentCommsButton")
                .accessibilityLabel("Agent Comms")
                .badge(appState.commsEvents.count)
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    windowState.showPeerNetwork = true
                } label: {
                    Label("Peer Network", systemImage: "network")
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .help("Peer network (⌘⇧P)")
                .xrayId("mainWindow.peerNetworkButton")
                .accessibilityIdentifier("mainWindow.peerNetworkButton")
                .accessibilityLabel("Peer Network")
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    openWindow(id: "debug-log")
                } label: {
                    Label("Debug Log", systemImage: "ladybug")
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .help("Debug log (⌘⇧D)")
                .xrayId("mainWindow.debugLogButton")
                .accessibilityIdentifier("mainWindow.debugLogButton")
                .accessibilityLabel("Debug Log")
            }

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
                .accessibilityIdentifier("mainWindow.inspectorToggle")
                .accessibilityLabel(ws.inspectorVisible ? "Hide Inspector" : "Show Inspector")
            }
        }
        .sheet(isPresented: $ws.showNewSessionSheet) {
            NewSessionSheet()
        }
        .sheet(isPresented: $ws.showNewGroupThreadSheet) {
            NewGroupThreadSheet()
        }
        .sheet(isPresented: $ws.showLibraryHub) {
            IntentLibraryHubView(
                selectedSection: $ws.selectedLibrarySection,
                selectedBuildSection: $ws.selectedLibraryBuildSection,
                selectedDiscoverSection: $ws.selectedLibraryDiscoverSection
            )
                .frame(minWidth: 760, minHeight: 560)
        }
        .sheet(isPresented: $ws.showScheduleLibrary) {
            ScheduleLibraryView()
                .frame(minWidth: 900, minHeight: 560)
        }
        .sheet(isPresented: $ws.showAgentComms) {
            AgentCommsView()
                .environmentObject(appState)
                .frame(minWidth: 600, minHeight: 400)
        }
        .sheet(isPresented: $ws.showPeerNetwork) {
            PeerNetworkView()
                .environmentObject(p2pNetworkManager)
                .environment(\.modelContext, modelContext)
        }
        .sheet(isPresented: $ws.showWorkshop) {
            WorkshopView()
                .environmentObject(appState)
                .frame(minWidth: 960, minHeight: 640)
        }
        .onAppear {
            appState.connectSidecar()
        }
        .alert("Launch Error", isPresented: launchErrorBinding) {
            Button("OK") { windowState.launchError = nil }
        } message: {
            Text(windowState.launchError ?? "")
        }
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
        session.workingDirectory = agent.defaultWorkingDirectory ?? windowState.projectDirectory
        let conversation = Conversation(
            topic: agent.name,
            sessions: [session],
            projectId: windowState.selectedProjectId,
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
            projectDirectory: windowState.projectDirectory,
            projectId: windowState.selectedProjectId,
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

    func makeNSView(context: Context) -> NSView {
        let view = TitleSettingView(projectName: projectName)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class TitleSettingView: NSView {
        let projectName: String

        init(projectName: String) {
            self.projectName = projectName
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.title = "ClaudeStudio — \(projectName)"
        }
    }
}
