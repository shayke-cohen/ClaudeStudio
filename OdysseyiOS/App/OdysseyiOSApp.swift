// OdysseyiOS/App/OdysseyiOSApp.swift
import SwiftUI
import OdysseyCore

@main
struct OdysseyiOSApp: App {
    @State private var appState = iOSAppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentRootView()
                .environment(appState)
                .onChange(of: scenePhase) { _, newPhase in
                    Task {
                        if newPhase == .background {
                            await appState.sidecarManager.suspendForBackground()
                        } else if newPhase == .active {
                            await appState.sidecarManager.reconnectIfNeeded()
                        }
                    }
                }
        }
    }
}

// MARK: - Content root

struct ContentRootView: View {
    @Environment(iOSAppState.self) private var appState
    @State private var hasPairedMac: Bool = PeerCredentialStore().hasPairedMacs

    var body: some View {
        if hasPairedMac {
            MainTabView()
                .task {
                    await appState.connectToFirstPairedMac()
                }
        } else {
            iOSPairingView {
                hasPairedMac = true
            }
        }
    }
}

// MARK: - Main tab view

struct MainTabView: View {
    @Environment(iOSAppState.self) private var appState

    var body: some View {
        TabView {
            ConversationListView()
                .tabItem {
                    Label("Conversations", systemImage: "bubble.left.and.bubble.right")
                }
                .accessibilityIdentifier("tab.conversations")

            iOSAgentListView()
                .tabItem {
                    Label("Agents", systemImage: "person.2")
                }
                .accessibilityIdentifier("tab.agents")

            iOSSettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .accessibilityIdentifier("tab.settings")
        }
    }
}

// MARK: - PeerCredentialStore convenience

private extension PeerCredentialStore {
    var hasPairedMacs: Bool {
        (try? load()).map { !$0.isEmpty } ?? false
    }
}
