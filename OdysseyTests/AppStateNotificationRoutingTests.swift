import SwiftData
import XCTest
@testable import Odyssey

/// Verifies that `AppState.routeToConversation(id:)` — invoked when the user taps a
/// macOS notification banner — selects the right conversation, including the cold-launch
/// case where the tap fires before the window is constructed.
@MainActor
final class AppStateNotificationRoutingTests: XCTestCase {

    private var appState: AppState!

    override func setUp() async throws {
        appState = AppState()
    }

    override func tearDown() async throws {
        appState = nil
    }

    func testRouteToConversation_whenWindowRegistered_selectsImmediately() {
        let ws = WindowState()
        appState.registerPrimaryWindowState(ws)
        XCTAssertNil(ws.selectedConversationId)
        XCTAssertNil(appState.pendingConversationRoute)

        let target = UUID()
        appState.routeToConversation(id: target)

        XCTAssertEqual(ws.selectedConversationId, target)
        XCTAssertNil(appState.pendingConversationRoute, "no route should be queued once the window has consumed it")
    }

    func testRouteToConversation_whenWindowNotReady_queuesUntilRegistration() {
        XCTAssertNil(appState.primaryWindowState)
        XCTAssertNil(appState.pendingConversationRoute)

        let target = UUID()
        appState.routeToConversation(id: target)

        XCTAssertEqual(appState.pendingConversationRoute, target)

        let ws = WindowState()
        appState.registerPrimaryWindowState(ws)

        XCTAssertEqual(ws.selectedConversationId, target, "queued route should drain into the window when it registers")
        XCTAssertNil(appState.pendingConversationRoute, "queue should clear after draining")
    }

    func testRouteToConversation_overwritesPreviousSelection() {
        let ws = WindowState()
        appState.registerPrimaryWindowState(ws)
        let first = UUID()
        let second = UUID()

        appState.routeToConversation(id: first)
        XCTAssertEqual(ws.selectedConversationId, first)

        appState.routeToConversation(id: second)
        XCTAssertEqual(ws.selectedConversationId, second)
    }

    func testAppStateInit_wiresChatNotificationManagerBackReference() {
        // Singleton is shared across tests; just confirm AppState.init connects itself.
        let fresh = AppState()
        XCTAssertTrue(ChatNotificationManager.shared.appState === fresh)
    }
}
