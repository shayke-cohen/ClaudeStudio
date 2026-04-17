import XCTest
import AppKit
import SwiftUI
@testable import Odyssey

/// Unit tests for the Configuration UI hero redesign.
/// Covers: Color.darkened, Color.fromAgentColor, ConfigFileManager.slugify,
/// and revealInFinder URL construction logic.
final class ConfigurationUITests: XCTestCase {

    // MARK: - Color.darkened

    func testDarkened_reduceBrightness() throws {
        let color = Color(hue: 0.6, saturation: 0.8, brightness: 0.9, opacity: 1.0)
        let darkened = color.darkened(by: 0.25)

        let nsOriginal = NSColor(color).usingColorSpace(.sRGB)!
        let nsDarkened = NSColor(darkened).usingColorSpace(.sRGB)!

        var origB: CGFloat = 0
        var darkB: CGFloat = 0
        nsOriginal.getHue(nil, saturation: nil, brightness: &origB, alpha: nil)
        nsDarkened.getHue(nil, saturation: nil, brightness: &darkB, alpha: nil)

        XCTAssertEqual(Double(darkB), Double(origB) * 0.75, accuracy: 0.001)
    }

    func testDarkened_preservesHueAndSaturation() throws {
        let color = Color(hue: 0.3, saturation: 0.7, brightness: 0.8, opacity: 1.0)
        let darkened = color.darkened(by: 0.1)

        let nsOriginal = NSColor(color).usingColorSpace(.sRGB)!
        let nsDarkened = NSColor(darkened).usingColorSpace(.sRGB)!

        var origH: CGFloat = 0, origS: CGFloat = 0
        var darkH: CGFloat = 0, darkS: CGFloat = 0
        nsOriginal.getHue(&origH, saturation: &origS, brightness: nil, alpha: nil)
        nsDarkened.getHue(&darkH, saturation: &darkS, brightness: nil, alpha: nil)

        XCTAssertEqual(Double(darkH), Double(origH), accuracy: 0.001)
        XCTAssertEqual(Double(darkS), Double(origS), accuracy: 0.001)
    }

    func testDarkened_zeroFraction_returnsEquivalentColor() {
        let color = Color(hue: 0.5, saturation: 0.5, brightness: 0.5, opacity: 1.0)
        let darkened = color.darkened(by: 0.0)

        let nsOriginal = NSColor(color).usingColorSpace(.sRGB)!
        let nsDarkened = NSColor(darkened).usingColorSpace(.sRGB)!

        var origB: CGFloat = 0, darkB: CGFloat = 0
        nsOriginal.getHue(nil, saturation: nil, brightness: &origB, alpha: nil)
        nsDarkened.getHue(nil, saturation: nil, brightness: &darkB, alpha: nil)

        XCTAssertEqual(Double(darkB), Double(origB), accuracy: 0.001)
    }

    func testDarkened_defaultFractionIs25Percent() {
        let color = Color(hue: 0.2, saturation: 0.9, brightness: 1.0, opacity: 1.0)
        let darkened = color.darkened()

        let nsDarkened = NSColor(darkened).usingColorSpace(.sRGB)!
        var darkB: CGFloat = 0
        nsDarkened.getHue(nil, saturation: nil, brightness: &darkB, alpha: nil)

        XCTAssertEqual(Double(darkB), 0.75, accuracy: 0.001)
    }

    func testDarkened_preservesOpacity() {
        let color = Color(hue: 0.4, saturation: 0.6, brightness: 0.8, opacity: 0.5)
        let darkened = color.darkened(by: 0.2)

        let nsDarkened = NSColor(darkened).usingColorSpace(.sRGB)!
        var alpha: CGFloat = 0
        nsDarkened.getHue(nil, saturation: nil, brightness: nil, alpha: &alpha)

        XCTAssertEqual(Double(alpha), 0.5, accuracy: 0.01)
    }

    // MARK: - Color.fromAgentColor

    func testFromAgentColor_knownColors() {
        let knownColors = ["blue", "red", "green", "purple", "orange", "yellow", "pink", "teal", "indigo", "gray"]
        for name in knownColors {
            let color = Color.fromAgentColor(name)
            XCTAssertNotEqual(color, .accentColor, "'\(name)' should map to a named color, not accentColor")
        }
    }

    func testFromAgentColor_unknownFallsBackToAccent() {
        XCTAssertEqual(Color.fromAgentColor("magenta"), .accentColor)
        XCTAssertEqual(Color.fromAgentColor(""), .accentColor)
        XCTAssertEqual(Color.fromAgentColor("BLUE"), .accentColor, "Case mismatch should fall through to accent")
    }

    // MARK: - ConfigFileManager.slugify

    func testSlugify_lowercasesAndHyphenatesSpaces() {
        XCTAssertEqual(ConfigFileManager.slugify("My Agent"), "my-agent")
        XCTAssertEqual(ConfigFileManager.slugify("Code Reviewer"), "code-reviewer")
    }

    func testSlugify_replacesAmpersandAndPlus() {
        XCTAssertEqual(ConfigFileManager.slugify("Design & Dev"), "design-and-dev")
        XCTAssertEqual(ConfigFileManager.slugify("A + B"), "a-plus-b")
    }

    func testSlugify_stripsSpecialCharacters() {
        XCTAssertEqual(ConfigFileManager.slugify("Agent (Beta)!"), "agent-beta")
        XCTAssertEqual(ConfigFileManager.slugify("Test@Agent"), "testagent")
    }

    func testSlugify_emptyString() {
        XCTAssertEqual(ConfigFileManager.slugify(""), "")
    }

    // MARK: - revealInFinder URL construction

    func testRevealURL_agent_isDirectory() {
        let base = ConfigFileManager.configDirectory
        let slug = "my-agent"
        let url = base.appendingPathComponent("agents").appendingPathComponent(slug)
        XCTAssertEqual(url.pathExtension, "", "Agent reveal URL should have no extension (it's a directory)")
        XCTAssertTrue(url.path.hasSuffix("agents/my-agent"))
    }

    func testRevealURL_group_isDirectory() {
        let base = ConfigFileManager.configDirectory
        let slug = "code-team"
        let url = base.appendingPathComponent("groups").appendingPathComponent(slug)
        XCTAssertEqual(url.pathExtension, "", "Group reveal URL should have no extension (it's a directory)")
        XCTAssertTrue(url.path.hasSuffix("groups/code-team"))
    }

    func testRevealURL_skill_isMarkdownFile() {
        let base = ConfigFileManager.configDirectory
        let slug = "tdd"
        let url = base.appendingPathComponent("skills").appendingPathComponent(slug).appendingPathExtension("md")
        XCTAssertEqual(url.pathExtension, "md", "Skill reveal URL should end in .md")
        XCTAssertTrue(url.path.hasSuffix("skills/tdd.md"))
    }

    func testRevealURL_mcp_isJSONFile() {
        let base = ConfigFileManager.configDirectory
        let slug = "octocode"
        let url = base.appendingPathComponent("mcps").appendingPathComponent(slug).appendingPathExtension("json")
        XCTAssertEqual(url.pathExtension, "json", "MCP reveal URL should end in .json")
        XCTAssertTrue(url.path.hasSuffix("mcps/octocode.json"))
    }

    func testRevealURL_permission_isJSONFile() {
        let base = ConfigFileManager.configDirectory
        let slug = "standard"
        let url = base.appendingPathComponent("permissions").appendingPathComponent(slug).appendingPathExtension("json")
        XCTAssertEqual(url.pathExtension, "json", "Permission reveal URL should end in .json")
        XCTAssertTrue(url.path.hasSuffix("permissions/standard.json"))
    }
}
