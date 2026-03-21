import SwiftUI
import SwiftData

@main
struct ClaudPeerApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environmentObject(appState)
        }
        .modelContainer(for: [
            Agent.self,
            Session.self,
            Conversation.self,
            ConversationMessage.self,
            Skill.self,
            MCPServer.self,
            PermissionSet.self,
            SharedWorkspace.self,
            BlackboardEntry.self,
            Peer.self,
        ])
        .defaultSize(width: 1200, height: 800)
        .windowResizability(.contentMinSize)

        Settings {
            Text("ClaudPeer Settings")
                .padding()
        }
    }
}
