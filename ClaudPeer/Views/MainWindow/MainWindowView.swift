import SwiftUI
import SwiftData

struct MainWindowView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
        } content: {
            if let conversationId = appState.selectedConversationId {
                ChatView(conversationId: conversationId)
            } else {
                ContentUnavailableView(
                    "No Conversation Selected",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Select a conversation from the sidebar or start a new one.")
                )
                .accessibilityIdentifier("mainWindow.noConversationPlaceholder")
            }
        } detail: {
            if let conversationId = appState.selectedConversationId {
                InspectorView(conversationId: conversationId)
            } else {
                Text("Inspector")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("mainWindow.inspectorPlaceholder")
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 900, minHeight: 600)
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

                Button {
                    appState.showAgentLibrary = true
                } label: {
                    Label("Agent Library", systemImage: "cpu")
                }
                .help("Agent library")
                .accessibilityIdentifier("mainWindow.agentLibraryButton")

                Button {
                    appState.showPeerNetwork = true
                } label: {
                    Label("Peer Network", systemImage: "network")
                }
                .help("Peer network")
                .accessibilityIdentifier("mainWindow.peerNetworkButton")

                sidecarStatusIndicator
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

    @ViewBuilder
    private var sidecarStatusIndicator: some View {
        switch appState.sidecarStatus {
        case .connected:
            Image(systemName: "circle.fill")
                .foregroundStyle(.green)
                .help("Sidecar connected")
                .accessibilityIdentifier("mainWindow.sidecarStatus")
                .accessibilityLabel("Sidecar connected")
        case .connecting:
            ProgressView()
                .controlSize(.small)
                .help("Connecting to sidecar...")
                .accessibilityIdentifier("mainWindow.sidecarStatus")
                .accessibilityLabel("Connecting to sidecar")
        case .disconnected:
            Image(systemName: "circle.fill")
                .foregroundStyle(.gray)
                .help("Sidecar disconnected")
                .accessibilityIdentifier("mainWindow.sidecarStatus")
                .accessibilityLabel("Sidecar disconnected")
        case .error(let msg):
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .help("Sidecar error: \(msg)")
                .accessibilityIdentifier("mainWindow.sidecarStatus")
                .accessibilityLabel("Sidecar error: \(msg)")
        }
    }

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
