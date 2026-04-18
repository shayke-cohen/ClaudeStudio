import XCTest
@testable import Odyssey

@MainActor
final class QuickActionStoreTests: XCTestCase {
    private var suiteName: String!
    private var testDefaults: UserDefaults!
    private var tempDir: URL!
    private var store: QuickActionStore!

    override func setUp() async throws {
        suiteName = "test.quickActions.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = QuickActionStore(configDirectory: tempDir, defaults: testDefaults)
    }

    override func tearDown() async throws {
        testDefaults.removeSuite(named: suiteName)
        try? FileManager.default.removeItem(at: tempDir)
        store = nil
        testDefaults = nil
        tempDir = nil
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

    // ─── Store: initial state ─────────────────────────────────────

    func testStoreLoadsDefaultsOnFirstLaunch() {
        XCTAssertEqual(store.configs.count, 10)
        XCTAssertEqual(store.configs.first?.name, "Fix It")
    }

    func testFirstLaunchSeedsFile() {
        let fileURL = tempDir.appendingPathComponent("quick-actions.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    // ─── Store: CRUD ─────────────────────────────────────────────

    func testAdd() {
        let before = store.configs.count
        store.add(QuickActionConfig(name: "New", prompt: "Do new", symbolName: "star"))
        XCTAssertEqual(store.configs.count, before + 1)
        XCTAssertEqual(store.configs.last?.name, "New")
    }

    func testUpdate() {
        var updated = store.configs[0]
        updated.name = "Renamed"
        store.update(updated)
        XCTAssertEqual(store.configs[0].name, "Renamed")
    }

    func testDelete() {
        let target = store.configs[0].id
        store.delete(id: target)
        XCTAssertFalse(store.configs.contains(where: { $0.id == target }))
        XCTAssertEqual(store.configs.count, 9)
    }

    func testMove() {
        let first = store.configs[0].id
        let second = store.configs[1].id
        store.move(fromOffsets: IndexSet(integer: 0), toOffset: 2)
        XCTAssertEqual(store.configs[0].id, second)
        XCTAssertEqual(store.configs[1].id, first)
    }

    // ─── Store: persistence ───────────────────────────────────────

    func testPersistsAcrossReInit() {
        store.add(QuickActionConfig(name: "Persisted", prompt: "p", symbolName: "star"))
        let store2 = QuickActionStore(configDirectory: tempDir, defaults: testDefaults)
        XCTAssertTrue(store2.configs.contains(where: { $0.name == "Persisted" }))
    }

    func testResetToDefaults() {
        store.delete(id: store.configs[0].id)
        XCTAssertEqual(store.configs.count, 9)
        store.resetToDefaults()
        XCTAssertEqual(store.configs.count, 10)
        XCTAssertEqual(store.configs.first?.name, "Fix It")
    }

    // ─── Store: UserDefaults migration ───────────────────────────

    func testMigratesFromUserDefaults() throws {
        let migrationSuite = "test.migration.\(UUID().uuidString)"
        let migrationDefaults = UserDefaults(suiteName: migrationSuite)!
        defer { migrationDefaults.removeSuite(named: migrationSuite) }

        let migrationDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: migrationDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: migrationDir) }

        let custom = [QuickActionConfig(name: "Old Chip", prompt: "old", symbolName: "star")]
        migrationDefaults.set(try JSONEncoder().encode(custom), forKey: "odyssey.chat.quickActionConfigs")

        let migratedStore = QuickActionStore(configDirectory: migrationDir, defaults: migrationDefaults)

        XCTAssertEqual(migratedStore.configs.first?.name, "Old Chip")
        XCTAssertNil(migrationDefaults.data(forKey: "odyssey.chat.quickActionConfigs"), "Legacy key must be removed after migration")
        XCTAssertTrue(FileManager.default.fileExists(atPath: migrationDir.appendingPathComponent("quick-actions.json").path))
    }

    // ─── Store: usage ordering ────────────────────────────────────

    func testUsageOrderDisabledReturnsConfigsOrder() {
        store.setUsageOrderEnabled(false)
        XCTAssertEqual(store.orderedConfigs.map(\.id), store.configs.map(\.id))
    }

    func testUsageOrderReordersAfterThreshold() {
        store.setUsageOrderEnabled(true)
        let targetId = store.configs[5].id // TL;DR by default
        for _ in 0..<11 {
            store.recordUsage(id: targetId)
        }
        XCTAssertEqual(store.orderedConfigs.first?.id, targetId)
    }

    func testUsageOrderBelowThresholdKeepsConfigsOrder() {
        store.setUsageOrderEnabled(true)
        let targetId = store.configs[5].id
        for _ in 0..<9 { // under threshold
            store.recordUsage(id: targetId)
        }
        XCTAssertEqual(store.orderedConfigs.map(\.id), store.configs.map(\.id))
    }
}
