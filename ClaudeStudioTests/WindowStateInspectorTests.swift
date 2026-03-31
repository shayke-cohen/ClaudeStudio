import XCTest
@testable import ClaudeStudio

@MainActor
final class WindowStateInspectorTests: XCTestCase {
    func testOpenInspectorSetsVisibilityAndSelectedTab() {
        let project = Project(
            name: "Repo",
            rootPath: "/tmp/repo",
            canonicalRootPath: "/tmp/repo"
        )
        let windowState = WindowState(project: project)
        windowState.inspectorVisible = false
        windowState.selectedInspectorTab = .info

        windowState.openInspector(tab: .blackboard)

        XCTAssertTrue(windowState.inspectorVisible)
        XCTAssertEqual(windowState.selectedInspectorTab, .blackboard)
    }
}
