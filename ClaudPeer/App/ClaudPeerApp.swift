import SwiftUI
import SwiftData
#if DEBUG
import AppXray
#endif

@main
struct ClaudPeerApp: App {
    @StateObject private var appState = AppState()

    init() {
        #if DEBUG
        AppXray.shared.start(config: AppXrayConfig(
            appName: "ClaudPeer",
            mode: .client
        ))
        #endif
    }

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environmentObject(appState)
                .onAppear {
                    appState.connectSidecar()
                    #if DEBUG
                    AppXray.shared.registerObservableObject(appState, name: "appState")
                    #endif
                }
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
