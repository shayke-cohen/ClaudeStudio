import Foundation
import Observation

@MainActor
@Observable
final class BrowserOverlayCoordinator {

    // MARK: - State

    enum HandoffState: Equatable {
        case agentDriving
        case yieldedToUser(message: String)
        case userDriving
    }

    private(set) var state: HandoffState = .agentDriving

    /// The action log — list of completed agent actions, newest at end.
    private(set) var actionLog: [ActionLogEntry] = []

    /// The message shown when agent yields control to user.
    var yieldMessage: String {
        if case .yieldedToUser(let msg) = state { return msg }
        return ""
    }

    // MARK: - State transitions (agent-initiated)

    /// Called by WKWebViewBrowserController when `yieldToUser(message:)` tool fires.
    /// Records the yield state. The `controller.resumeFromYield()` is called later by `userResumed()`.
    func agentYielded(message: String, controller: any BrowserController) {
        state = .yieldedToUser(message: message)
        // controller.yieldToUser suspends internally — no need to call anything here
        // The continuation is stored in the controller; userResumed() will resolve it
    }

    /// Called by WKWebViewBrowserController to signal it is now actively driving.
    func agentTookControl() {
        state = .agentDriving
    }

    // MARK: - State transitions (user-initiated)

    /// User clicked "Take over" — switches to user driving.
    /// Returns a closure that AppState can use to send the stateChange wire event.
    func userTookOver() -> HandoffState {
        state = .userDriving
        actionLog.append(ActionLogEntry(action: "User took control", timestamp: Date()))
        return state
    }

    /// User clicked "Resume" or "Resume agent" — switches back to agent driving.
    /// Calls `controller.resumeFromYield()` to unblock the `yieldToUser` tool.
    func userResumed(controller: any BrowserController) -> HandoffState {
        state = .agentDriving
        controller.resumeFromYield()
        actionLog.append(ActionLogEntry(action: "Agent resumed", timestamp: Date()))
        return state
    }

    // MARK: - Action log

    func logAction(_ description: String) {
        actionLog.append(ActionLogEntry(action: description, timestamp: Date()))
        if actionLog.count > 200 { actionLog.removeFirst() }
    }

    func clearLog() {
        actionLog.removeAll()
    }
}

// MARK: - Supporting types

struct ActionLogEntry: Identifiable {
    let id = UUID()
    let action: String
    let timestamp: Date

    var formattedTime: String {
        ActionLogEntry.timeFormatter.string(from: timestamp)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
