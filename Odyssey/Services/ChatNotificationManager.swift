import AppKit
import UserNotifications

/// Manages macOS notifications and sound alerts for agent events.
@MainActor
final class ChatNotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ChatNotificationManager()

    nonisolated private static let conversationIdKey = "conversationId"

    weak var appState: AppState?

    private override init() {
        super.init()
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: - Public API

    func notifySessionCompleted(agentName: String, conversationTopic: String?, conversationId: UUID?) {
        let title = "\(agentName) finished"
        let body = conversationTopic ?? "Task complete"
        post(title: title, body: body, sound: "Glass", conversationId: conversationId)
    }

    func notifyAgentQuestion(agentName: String, question: String, conversationId: UUID?) {
        let title = "\(agentName) has a question"
        let body = String(question.prefix(100))
        post(title: title, body: body, sound: "Sosumi", conversationId: conversationId)
    }

    func notifySessionError(agentName: String, error: String, conversationId: UUID?) {
        let title = "\(agentName) encountered an error"
        let body = String(error.prefix(100))
        post(title: title, body: body, sound: "Basso", conversationId: conversationId)
    }

    func notifyGHIssueTriggered(issueNumber: Int, repo: String, title: String, conversationId: UUID?) {
        let notifTitle = "GitHub Issue #\(issueNumber)"
        let body = "[\(repo)] \(String(title.prefix(80)))"
        post(title: notifTitle, body: body, sound: "Glass", conversationId: conversationId)
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show banner + sound even when Odyssey is the frontmost app — the
        // notifyIfNeeded gate already filters out cases where the user is
        // looking at the relevant conversation.
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let convoIdString = userInfo[Self.conversationIdKey] as? String
        // Acknowledge synchronously; the actual routing hops to the main actor.
        completionHandler()
        guard let str = convoIdString, let uuid = UUID(uuidString: str) else { return }
        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)
            ChatNotificationManager.shared.appState?.routeToConversation(id: uuid)
        }
    }

    // MARK: - Private

    private func post(title: String, body: String, sound: String, conversationId: UUID?) {
        let defaults = AppSettings.store
        let notificationsEnabled = defaults.object(forKey: AppSettings.notificationsEnabledKey) as? Bool ?? true
        guard notificationsEnabled else { return }

        let soundEnabled = defaults.object(forKey: AppSettings.notificationSoundEnabledKey) as? Bool ?? true

        // Play sound
        if soundEnabled {
            NSSound(named: NSSound.Name(sound))?.play()
        }

        // Send macOS notification (useful when app is in background)
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if soundEnabled {
            content.sound = .default
        }
        if let conversationId {
            content.userInfo = [Self.conversationIdKey: conversationId.uuidString]
        }
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
