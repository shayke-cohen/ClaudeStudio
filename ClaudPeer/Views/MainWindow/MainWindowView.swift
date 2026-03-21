import SwiftUI
import SwiftData

struct MainWindowView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var showStatusPopover = false
    @State private var inspectorVisible = true

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
        } detail: {
            HStack(spacing: 0) {
                Group {
                    if let conversationId = appState.selectedConversationId {
                        ChatView(conversationId: conversationId)
                            .id(conversationId)
                    } else {
                        ContentUnavailableView(
                            "No Conversation Selected",
                            systemImage: "bubble.left.and.bubble.right",
                            description: Text("Select a conversation from the sidebar or start a new one.")
                        )
                        .accessibilityIdentifier("mainWindow.noConversationPlaceholder")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if inspectorVisible {
                    Divider()

                    Group {
                        if let conversationId = appState.selectedConversationId {
                            InspectorView(conversationId: conversationId)
                                .id(conversationId)
                        } else {
                            Text("Inspector")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .accessibilityIdentifier("mainWindow.inspectorPlaceholder")
                        }
                    }
                    .frame(width: 260)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 900, minHeight: 600)
        .background(WindowTitleSetter())
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    appState.showNewSessionSheet = true
                } label: {
                    Label("New Session", systemImage: "plus.bubble")
                }
                .keyboardShortcut("n", modifiers: .command)
                .help("New session (⌘N)")
                .accessibilityIdentifier("mainWindow.newSessionButton")

                Button {
                    createQuickChat()
                } label: {
                    Label("Quick Chat", systemImage: "plus.message")
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .help("Quick chat (⌘⇧N)")
                .accessibilityIdentifier("mainWindow.quickChatButton")
            }

            ToolbarItem(placement: .status) {
                sidecarStatusPill
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    inspectorVisible.toggle()
                } label: {
                    Label(
                        inspectorVisible ? "Hide Inspector" : "Show Inspector",
                        systemImage: "sidebar.trailing"
                    )
                }
                .keyboardShortcut("0", modifiers: [.command, .option])
                .help(inspectorVisible ? "Hide inspector (⌘⌥0)" : "Show inspector (⌘⌥0)")
                .accessibilityIdentifier("mainWindow.inspectorToggle")
            }
        }
        .sheet(isPresented: $appState.showNewSessionSheet) {
            NewSessionSheet()
        }
        .sheet(isPresented: $appState.showAgentLibrary) {
            AgentLibraryView()
                .frame(minWidth: 700, minHeight: 500)
        }
        .onAppear {
            appState.connectSidecar()
        }
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
        .accessibilityIdentifier("mainWindow.sidecarStatusPill")
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
                    .accessibilityIdentifier("mainWindow.statusPopover.reconnectButton")

                    Button("Stop") {
                        showStatusPopover = false
                        appState.disconnectSidecar()
                    }
                    .controlSize(.small)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("mainWindow.statusPopover.stopButton")

                case .disconnected, .error:
                    Button("Connect") {
                        showStatusPopover = false
                        appState.connectSidecar()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .accessibilityIdentifier("mainWindow.statusPopover.connectButton")

                case .connecting:
                    Text("Connecting...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(width: 240)
        .accessibilityIdentifier("mainWindow.statusPopover")
    }

    // MARK: - Actions

    private func createQuickChat() {
        let conversation = Conversation(topic: "New Chat")
        let userParticipant = Participant(type: .user, displayName: "You")
        userParticipant.conversation = conversation
        conversation.participants.append(userParticipant)
        modelContext.insert(conversation)
        try? modelContext.save()
        appState.selectedConversationId = conversation.id
    }
}

/// Sets the NSWindow title for multi-instance disambiguation.
/// Uses NSWindow.didBecomeKeyNotification so it fires after SwiftUI finishes layout.
private struct WindowTitleSetter: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = TitleSettingView()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class TitleSettingView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyTitle()
        }

        private func applyTitle() {
            guard !InstanceConfig.isDefault else { return }
            let title = "ClaudPeer — \(InstanceConfig.name)"
            window?.title = title
        }
    }
}
