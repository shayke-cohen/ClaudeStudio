import SwiftUI
import SwiftData
import Combine

@MainActor
final class AppState: ObservableObject {
    enum SidecarStatus: Equatable {
        case disconnected
        case connecting
        case connected
        case error(String)
    }

    @Published var sidecarStatus: SidecarStatus = .disconnected
    @Published var selectedConversationId: UUID?
    @Published var showAgentLibrary = false
    @Published var showPeerNetwork = false
    @Published var activeSessions: [UUID: SessionInfo] = [:]
    @Published var streamingText: [String: String] = [:]

    struct SessionInfo: Identifiable {
        let id: UUID
        let agentName: String
        var tokenCount: Int = 0
        var cost: Double = 0
        var isStreaming: Bool = false
    }

    private(set) var sidecarManager: SidecarManager?
    private var eventTask: Task<Void, Never>?

    func connectSidecar() {
        sidecarStatus = .connecting
        let manager = SidecarManager()
        self.sidecarManager = manager
        Task {
            do {
                try await manager.start()
                sidecarStatus = .connected
                listenForEvents(from: manager)
            } catch {
                sidecarStatus = .error(error.localizedDescription)
            }
        }
    }

    func disconnectSidecar() {
        eventTask?.cancel()
        eventTask = nil
        sidecarManager?.stop()
        sidecarManager = nil
        sidecarStatus = .disconnected
    }

    func sendToSidecar(_ command: SidecarCommand) {
        guard let manager = sidecarManager else { return }
        Task {
            try? await manager.send(command)
        }
    }

    private func listenForEvents(from manager: SidecarManager) {
        eventTask = Task {
            for await event in manager.events {
                handleEvent(event)
            }
        }
    }

    private func handleEvent(_ event: SidecarEvent) {
        switch event {
        case .streamToken(let sessionId, let text):
            let current = streamingText[sessionId] ?? ""
            streamingText[sessionId] = current + text
            activeSessions[UUID(uuidString: sessionId) ?? UUID()]?.isStreaming = true

        case .sessionResult(let sessionId, _, let cost):
            activeSessions[UUID(uuidString: sessionId) ?? UUID()]?.isStreaming = false
            activeSessions[UUID(uuidString: sessionId) ?? UUID()]?.cost += cost
            objectWillChange.send()

        case .sessionError(let sessionId, let error):
            activeSessions[UUID(uuidString: sessionId) ?? UUID()]?.isStreaming = false
            print("[AppState] Session \(sessionId) error: \(error)")

        case .connected:
            sidecarStatus = .connected

        case .disconnected:
            sidecarStatus = .disconnected

        default:
            break
        }
    }
}
