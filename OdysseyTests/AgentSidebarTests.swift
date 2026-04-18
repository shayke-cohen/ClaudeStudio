import XCTest
@testable import Odyssey

final class AgentSidebarTests: XCTestCase {
    func testAgentShowInSidebarDefaultsTrue() {
        let agent = Agent(name: "Test Agent")
        XCTAssertTrue(agent.showInSidebar)
    }

    func testAgentGroupShowInSidebarDefaultsTrue() {
        let group = AgentGroup(name: "Test Group")
        XCTAssertTrue(group.showInSidebar)
    }
}
