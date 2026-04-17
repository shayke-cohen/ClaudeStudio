import XCTest
import SwiftData
@testable import Odyssey

final class AgentCreationSheetTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUp() async throws {
        let schema = Schema([Agent.self, Skill.self, MCPServer.self, PermissionSet.self])
        container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = ModelContext(container)
    }

    func test_slugify_kebabCasesName() {
        XCTAssertEqual(ConfigFileManager.slugify("Security Reviewer"), "security-reviewer")
        XCTAssertEqual(ConfigFileManager.slugify("My Agent!"), "my-agent")
    }

    func test_saveCreatesFileAndInsertsSwiftData() throws {
        XCTFail("Implement after AgentCreationSheet.save() is written")
    }
}
