import XCTest
@testable import ClaudPeer

final class WorkshopViewTests: XCTestCase {

    func testWorkshopTabCases() {
        let tabs = WorkshopTab.allCases
        XCTAssertEqual(tabs.count, 5)
        XCTAssertEqual(tabs.map(\.rawValue), ["Agents", "Groups", "Skills", "MCPs", "Permissions"])
    }

    func testWorkshopTabIcons() {
        XCTAssertEqual(WorkshopTab.agents.icon, "cpu")
        XCTAssertEqual(WorkshopTab.groups.icon, "person.3")
        XCTAssertEqual(WorkshopTab.skills.icon, "book")
        XCTAssertEqual(WorkshopTab.mcps.icon, "server.rack")
        XCTAssertEqual(WorkshopTab.permissions.icon, "lock.shield")
    }

    func testWorkshopTabIdentifiable() {
        for tab in WorkshopTab.allCases {
            XCTAssertEqual(tab.id, tab.rawValue)
        }
    }
}
