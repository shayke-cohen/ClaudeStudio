import XCTest
@testable import Odyssey

@MainActor
final class QuickActionStoreTests: XCTestCase {
    private var suiteName: String!
    private var testDefaults: UserDefaults!
    private var store: QuickActionStore!

    override func setUp() async throws {
        suiteName = "test.quickActions.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        store = QuickActionStore(defaults: testDefaults)
    }

    override func tearDown() async throws {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        store = nil
        testDefaults = nil
    }

    // ─── Model ───────────────────────────────────────────────────

    func testDefaultsHasTenChips() {
        XCTAssertEqual(QuickActionConfig.defaults.count, 10)
    }

    func testConfigRoundTripsJSON() throws {
        let config = QuickActionConfig(name: "Test", prompt: "Do test", symbolName: "star")
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(QuickActionConfig.self, from: data)
        XCTAssertEqual(config, decoded)
    }

    func testDefaultIDsAreStable() {
        let first = QuickActionConfig.defaults[0]
        XCTAssertEqual(first.id, UUID(uuidString: "A1000000-0000-0000-0000-000000000001")!)
    }
}
