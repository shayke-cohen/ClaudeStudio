import XCTest
@testable import Odyssey

final class SidebarBottomBarTests: XCTestCase {

    func testAllCasesCount() {
        XCTAssertEqual(SidebarBottomBarItem.allCases.count, 5)
    }

    func testCaseOrder() {
        let cases = SidebarBottomBarItem.allCases
        XCTAssertEqual(cases[0], .workshop)
        XCTAssertEqual(cases[1], .schedules)
        XCTAssertEqual(cases[2], .agents)
        XCTAssertEqual(cases[3], .autoAssemble)
        XCTAssertEqual(cases[4], .newSession)
    }

    func testRawValues() {
        XCTAssertEqual(SidebarBottomBarItem.workshop.rawValue, "Workshop")
        XCTAssertEqual(SidebarBottomBarItem.schedules.rawValue, "Schedules")
        XCTAssertEqual(SidebarBottomBarItem.agents.rawValue, "Agents")
        XCTAssertEqual(SidebarBottomBarItem.autoAssemble.rawValue, "Auto-assemble")
        XCTAssertEqual(SidebarBottomBarItem.newSession.rawValue, "New session")
    }

    func testIcons() {
        XCTAssertEqual(SidebarBottomBarItem.workshop.icon, "wrench.and.screwdriver")
        XCTAssertEqual(SidebarBottomBarItem.schedules.icon, "clock.badge")
        XCTAssertEqual(SidebarBottomBarItem.agents.icon, "cpu")
        XCTAssertEqual(SidebarBottomBarItem.autoAssemble.icon, "wand.and.stars")
        XCTAssertEqual(SidebarBottomBarItem.newSession.icon, "plus")
    }

    func testHelpText() {
        XCTAssertEqual(SidebarBottomBarItem.workshop.helpText, "Entity workshop (⌘⇧W)")
        XCTAssertEqual(SidebarBottomBarItem.schedules.helpText, "Scheduled missions (⌘⇧S)")
        XCTAssertEqual(SidebarBottomBarItem.agents.helpText, "Agent library")
        XCTAssertEqual(SidebarBottomBarItem.autoAssemble.helpText, "Auto-assemble team")
        XCTAssertEqual(SidebarBottomBarItem.newSession.helpText, "New session")
    }

    func testXrayIds() {
        XCTAssertEqual(SidebarBottomBarItem.workshop.xrayId, "sidebar.workshopButton")
        XCTAssertEqual(SidebarBottomBarItem.schedules.xrayId, "sidebar.schedulesButton")
        XCTAssertEqual(SidebarBottomBarItem.agents.xrayId, "sidebar.agentsButton")
        XCTAssertEqual(SidebarBottomBarItem.autoAssemble.xrayId, "sidebar.autoAssembleButton")
        XCTAssertEqual(SidebarBottomBarItem.newSession.xrayId, "sidebar.newSessionButton")
    }

    func testIdentifiable() {
        for item in SidebarBottomBarItem.allCases {
            XCTAssertEqual(item.id, item.rawValue)
        }
    }

    func testXrayIdsAreUnique() {
        let ids = SidebarBottomBarItem.allCases.map(\.xrayId)
        XCTAssertEqual(Set(ids).count, ids.count, "xrayIds must be unique")
    }

    // MARK: - Adaptive label behavior

    func testHasTextLabel_threeItemsHaveText() {
        let withText = SidebarBottomBarItem.allCases.filter(\.hasTextLabel)
        XCTAssertEqual(withText.count, 3)
        XCTAssertTrue(withText.contains(.workshop))
        XCTAssertTrue(withText.contains(.schedules))
        XCTAssertTrue(withText.contains(.agents))
    }

    func testHasTextLabel_twoItemsAreIconOnly() {
        let iconOnly = SidebarBottomBarItem.allCases.filter { !$0.hasTextLabel }
        XCTAssertEqual(iconOnly.count, 2)
        XCTAssertTrue(iconOnly.contains(.autoAssemble))
        XCTAssertTrue(iconOnly.contains(.newSession))
    }

    func testAdaptiveItems_matchesHasTextLabel() {
        let adaptive = SidebarBottomBarItem.adaptiveItems
        let filtered = SidebarBottomBarItem.allCases.filter(\.hasTextLabel)
        XCTAssertEqual(adaptive, filtered)
    }

    func testIconOnlyItems_matchesNotHasTextLabel() {
        let iconOnly = SidebarBottomBarItem.iconOnlyItems
        let filtered = SidebarBottomBarItem.allCases.filter { !$0.hasTextLabel }
        XCTAssertEqual(iconOnly, filtered)
    }

    func testAdaptiveAndIconOnly_coverAllCases() {
        let all = SidebarBottomBarItem.adaptiveItems + SidebarBottomBarItem.iconOnlyItems
        XCTAssertEqual(Set(all), Set(SidebarBottomBarItem.allCases))
    }

    func testAdaptiveAndIconOnly_noOverlap() {
        let adaptive = Set(SidebarBottomBarItem.adaptiveItems)
        let iconOnly = Set(SidebarBottomBarItem.iconOnlyItems)
        XCTAssertTrue(adaptive.isDisjoint(with: iconOnly))
    }
}
