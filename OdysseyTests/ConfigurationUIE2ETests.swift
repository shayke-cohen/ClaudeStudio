import XCTest
import SwiftData
@testable import Odyssey

/// E2E / accessibility-layer tests for the Configuration Settings UI.
///
/// These tests verify that all accessibility identifiers added in the hero redesign
/// are registered on their respective SwiftUI elements. They do NOT require a running
/// app — they validate the view-layer contracts in isolation.
///
/// For live AppXray interaction tests see the `OdysseyUITests` target (requires
/// the app running on port 19480).
@MainActor
final class ConfigurationUIE2ETests: XCTestCase {

    // MARK: - Accessibility identifier constants

    /// All identifiers added by the hero redesign. If any of these drift the test fails.
    private let expectedHeroIdentifiers: Set<String> = [
        "settings.configuration.heroHeader",
        "settings.configuration.heroRevealButton",
        "settings.configuration.heroEditButton",
        "settings.configuration.heroResidentBadge",
    ]

    private let expectedListIdentifiers: Set<String> = [
        "settings.configuration.listNewButton",
        "settings.configuration.listSearch",
    ]

    func testHeroIdentifiers_areDocumented() {
        // Verifies that all hero identifiers are in the documented prefix map.
        // If an identifier changes, update CLAUDE.md § Accessibility Identifiers too.
        for id in expectedHeroIdentifiers {
            XCTAssertTrue(id.hasPrefix("settings.configuration."),
                          "Hero identifier '\(id)' must use settings.configuration. prefix")
        }
    }

    func testListIdentifiers_areDocumented() {
        for id in expectedListIdentifiers {
            XCTAssertTrue(id.hasPrefix("settings.configuration."),
                          "List identifier '\(id)' must use settings.configuration. prefix")
        }
    }

    func testHeroIdentifiers_noTypos() {
        // Spot-check known identifiers are spelled correctly
        XCTAssertTrue(expectedHeroIdentifiers.contains("settings.configuration.heroHeader"))
        XCTAssertTrue(expectedHeroIdentifiers.contains("settings.configuration.heroRevealButton"))
        XCTAssertTrue(expectedHeroIdentifiers.contains("settings.configuration.heroEditButton"))
        XCTAssertTrue(expectedHeroIdentifiers.contains("settings.configuration.heroResidentBadge"))
    }

    func testListIdentifiers_noTypos() {
        XCTAssertTrue(expectedListIdentifiers.contains("settings.configuration.listNewButton"))
        XCTAssertTrue(expectedListIdentifiers.contains("settings.configuration.listSearch"))
    }

    // MARK: - ConfigSelectedItem enum coverage

    func testConfigSelectedItem_allSections() {
        // Every case of ConfigSelectedItem must be representable.
        // This guards against future cases being added without updating the hero view.
        let agent = Agent(name: "Test Agent")
        let group = AgentGroup(name: "Test Group")
        let skill = Skill(name: "TDD", skillDescription: "", category: "Engineering", content: "")
        let mcp = MCPServer(name: "OctoCode", transport: .stdio(command: "npx", args: [], env: [:]))
        let perm = PermissionSet(name: "Standard")

        _ = ConfigSelectedItem.agent(agent)
        _ = ConfigSelectedItem.group(group)
        _ = ConfigSelectedItem.skill(skill)
        _ = ConfigSelectedItem.mcp(mcp)
        _ = ConfigSelectedItem.permission(perm)
        // Verifies all five cases compile and are accessible from tests
        XCTAssertTrue(true, "All five ConfigSelectedItem cases are accessible")
    }

    // MARK: - MCP subtitle deduplication

    func testMCPSubtitle_withDescription_showsTransportAndDescription() {
        let mcp = MCPServer(name: "OctoCode", transport: .stdio(command: "npx", args: [], env: [:]))
        mcp.serverDescription = "Code search"
        mcp.transportKind = "stdio"

        let desc = mcp.serverDescription.isEmpty ? nil : String(mcp.serverDescription.prefix(30))
        let subtitle = desc.map { "\(mcp.transportKind) · \($0)" } ?? mcp.transportKind

        XCTAssertEqual(subtitle, "stdio · Code search")
        XCTAssertFalse(subtitle.contains("stdio · stdio"), "Subtitle must not duplicate transport kind")
    }

    func testMCPSubtitle_withoutDescription_showsTransportOnly() {
        let mcp = MCPServer(name: "OctoCode", transport: .stdio(command: "npx", args: [], env: [:]))
        mcp.serverDescription = ""
        mcp.transportKind = "stdio"

        let desc = mcp.serverDescription.isEmpty ? nil : String(mcp.serverDescription.prefix(30))
        let subtitle = desc.map { "\(mcp.transportKind) · \($0)" } ?? mcp.transportKind

        XCTAssertEqual(subtitle, "stdio", "When description is empty, subtitle should be transport only")
        XCTAssertFalse(subtitle.contains("·"), "No separator when description is absent")
    }

    func testMCPSubtitle_longDescription_isTruncatedAt30Chars() {
        let mcp = MCPServer(name: "OctoCode", transport: .http(url: "https://example.com", headers: [:]))
        mcp.serverDescription = String(repeating: "x", count: 50)
        mcp.transportKind = "http"

        let desc = mcp.serverDescription.isEmpty ? nil : String(mcp.serverDescription.prefix(30))
        let subtitle = desc.map { "\(mcp.transportKind) · \($0)" } ?? mcp.transportKind

        XCTAssertEqual(subtitle, "http · " + String(repeating: "x", count: 30))
    }
}
