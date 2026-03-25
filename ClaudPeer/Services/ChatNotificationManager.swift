import AppKit
import UserNotifications

/// Manages macOS notifications and sound alerts for agent events.
@MainActor
final class ChatNotificationManager {
    static let shared = ChatNotificationManager()

    private init() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: - Public API

    func notifySessionCompleted(agentName: String, conversationTopic: String?) {
        let title = "\(agentName) finished"
        let body = conversationTopic ?? "Task complete"
        post(title: title, body: body, sound: "Glass")
    }

    func notifyAgentQuestion(agentName: String, question: String) {
        let title = "\(agentName) has a question"
        let body = String(question.prefix(100))
        post(title: title, body: body, sound: "Sosumi")
    }

    func notifySessionError(agentName: String, error: String) {
        let title = "\(agentName) encountered an error"
        let body = String(error.prefix(100))
        post(title: title, body: body, sound: "Basso")
    }

    // MARK: - Private

    private func post(title: String, body: String, sound: String) {
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
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
