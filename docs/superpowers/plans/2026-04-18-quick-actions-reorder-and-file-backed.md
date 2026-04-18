# Quick Actions — Drag-to-Reorder & File-backed Storage

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add visible drag-to-reorder to the Quick Actions settings list and move chip storage from UserDefaults to `~/.odyssey/config/quick-actions.json` with live file-watching.

**Architecture:** `ConfigFileManager` gains static helpers to read/write `quick-actions.json`. `QuickActionStore` replaces its UserDefaults blob with file I/O, migrates any existing UserDefaults data on first run, and watches the config directory with a `DispatchSource` FSEvents source so external edits are picked up live. The settings view replaces the invisible `.onMove` with an explicit `"line.3.horizontal"` drag-handle icon and SwiftUI `.draggable`/`.dropDestination` modifiers.

**Tech Stack:** Swift 6, SwiftUI, macOS 14+, Foundation `DispatchSource`, `JSONEncoder/Decoder`

---

## Files

| File | Change |
|------|--------|
| `Odyssey/Services/ConfigFileManager.swift` | Add `quickActionsFile`, `readQuickActions()`, `writeQuickActions()` |
| `Odyssey/Services/QuickActionStore.swift` | File-backed load/save + DispatchSource directory watcher; UserDefaults migration |
| `Odyssey/App/AppSettings.swift` | Remove `quickActionConfigsKey` and from `allKeys` |
| `Odyssey/Views/Settings/QuickActionsSettingsView.swift` | Drag handle icon + `.draggable`/`.dropDestination`; remove `.onMove` |
| `OdysseyTests/QuickActionStoreTests.swift` | Inject temp directory; add migration test |

No new files. No `project.yml` changes.

---

## Task 1: ConfigFileManager — quick-actions file helpers

**Files:**
- Modify: `Odyssey/Services/ConfigFileManager.swift`

- [ ] **Step 1: Add the three static members to `ConfigFileManager`**

Open `Odyssey/Services/ConfigFileManager.swift`. Find the `// MARK: - Write` section (around line 427). Add a new `// MARK: - Quick Actions` section immediately **before** `// MARK: - Factory Defaults`:

```swift
// MARK: - Quick Actions

static var quickActionsFile: URL {
    configDirectory.appendingPathComponent("quick-actions.json")
}

static func readQuickActions() -> [QuickActionConfig]? {
    guard let data = try? Data(contentsOf: quickActionsFile),
          let configs = try? JSONDecoder().decode([QuickActionConfig].self, from: data),
          !configs.isEmpty
    else { return nil }
    return configs
}

static func writeQuickActions(_ configs: [QuickActionConfig]) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(configs)
    try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
    try data.write(to: quickActionsFile)
}
```

- [ ] **Step 2: Build-check**

```bash
cd /Users/shayco/Odyssey && make build-check
```

Expected: build succeeds with no errors.

- [ ] **Step 3: Commit**

```bash
git add Odyssey/Services/ConfigFileManager.swift
git commit -m "feat: add ConfigFileManager helpers for quick-actions.json"
```

---

## Task 2: QuickActionStore — file-backed storage + directory watcher

**Files:**
- Modify: `Odyssey/Services/QuickActionStore.swift`
- Modify: `OdysseyTests/QuickActionStoreTests.swift`

- [ ] **Step 1: Rewrite `QuickActionStore.swift`**

Replace the entire file contents with:

```swift
import Foundation

@MainActor
final class QuickActionStore: ObservableObject {

    static let shared = QuickActionStore()

    @Published private(set) var configs: [QuickActionConfig] = []
    @Published var usageOrderEnabled: Bool
    @Published private var usageVersion: Int = 0

    let configDirectory: URL
    private let defaults: UserDefaults

    private var watchFileDescriptor: Int32 = -1
    private var watchSource: DispatchSourceFileSystemObject?
    private var reloadWorkItem: DispatchWorkItem?

    init(
        configDirectory: URL = ConfigFileManager.configDirectory,
        defaults: UserDefaults = AppSettings.store
    ) {
        self.configDirectory = configDirectory
        self.defaults = defaults
        self.usageOrderEnabled = (defaults.object(forKey: AppSettings.quickActionUsageOrderKey) as? Bool) ?? true

        // Load order: file → migrate from UserDefaults → factory defaults + seed file
        let fileURL = configDirectory.appendingPathComponent("quick-actions.json")
        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? JSONDecoder().decode([QuickActionConfig].self, from: data),
           !loaded.isEmpty {
            self.configs = loaded
        } else {
            let legacyKey = "odyssey.chat.quickActionConfigs"
            if let data = defaults.data(forKey: legacyKey),
               let legacy = try? JSONDecoder().decode([QuickActionConfig].self, from: data),
               !legacy.isEmpty {
                self.configs = legacy
                defaults.removeObject(forKey: legacyKey)
                try? Self.writeFile(legacy, to: fileURL, in: configDirectory)
            } else {
                self.configs = QuickActionConfig.defaults
                try? Self.writeFile(QuickActionConfig.defaults, to: fileURL, in: configDirectory)
            }
        }

        startDirectoryWatcher()
    }

    deinit {
        watchSource?.cancel()
    }

    // MARK: - Derived order (used by ChatView)

    var orderedConfigs: [QuickActionConfig] {
        guard usageOrderEnabled else { return configs }
        let counts = loadUsageCounts()
        let total = counts.values.reduce(0, +)
        guard total >= QuickActionConfig.usageThreshold else { return configs }
        return configs.sorted { a, b in
            let ca = counts[a.id.uuidString] ?? 0
            let cb = counts[b.id.uuidString] ?? 0
            if ca != cb { return ca > cb }
            let ia = configs.firstIndex(where: { $0.id == a.id }) ?? 0
            let ib = configs.firstIndex(where: { $0.id == b.id }) ?? 0
            return ia < ib
        }
    }

    // MARK: - Mutations

    func add(_ config: QuickActionConfig) {
        configs.append(config)
        save()
    }

    func update(_ config: QuickActionConfig) {
        guard let i = configs.firstIndex(where: { $0.id == config.id }) else { return }
        configs[i] = config
        save()
    }

    func delete(id: UUID) {
        configs.removeAll { $0.id == id }
        save()
    }

    func move(fromOffsets: IndexSet, toOffset: Int) {
        configs.move(fromOffsets: fromOffsets, toOffset: toOffset)
        save()
    }

    func resetToDefaults() {
        configs = QuickActionConfig.defaults
        defaults.removeObject(forKey: AppSettings.quickActionUsageCountsKey)
        save()
    }

    func setUsageOrderEnabled(_ enabled: Bool) {
        usageOrderEnabled = enabled
        defaults.set(enabled, forKey: AppSettings.quickActionUsageOrderKey)
    }

    // MARK: - Usage tracking

    func recordUsage(id: UUID) {
        var counts = loadUsageCounts()
        counts[id.uuidString, default: 0] += 1
        defaults.set(counts, forKey: AppSettings.quickActionUsageCountsKey)
        usageVersion += 1
    }

    // MARK: - Persistence

    private func save() {
        let fileURL = configDirectory.appendingPathComponent("quick-actions.json")
        try? Self.writeFile(configs, to: fileURL, in: configDirectory)
    }

    private static func writeFile(_ configs: [QuickActionConfig], to url: URL, in directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configs)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url)
    }

    private func loadUsageCounts() -> [String: Int] {
        (defaults.dictionary(forKey: AppSettings.quickActionUsageCountsKey) as? [String: Int]) ?? [:]
    }

    // MARK: - Directory watcher

    private func startDirectoryWatcher() {
        try? FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        let fd = open(configDirectory.path, O_EVTONLY)
        guard fd != -1 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: DispatchQueue.global(qos: .background)
        )
        source.setEventHandler { [weak self] in self?.scheduleFileReload() }
        source.setCancelHandler { close(fd) }
        source.resume()

        watchFileDescriptor = fd
        watchSource = source
    }

    private func scheduleFileReload() {
        reloadWorkItem?.cancel()
        let fileURL = configDirectory.appendingPathComponent("quick-actions.json")
        let item = DispatchWorkItem {
            guard let data = try? Data(contentsOf: fileURL),
                  let loaded = try? JSONDecoder().decode([QuickActionConfig].self, from: data),
                  !loaded.isEmpty
            else { return }
            Task { @MainActor [weak self] in
                guard let self, loaded != self.configs else { return }
                self.configs = loaded
            }
        }
        reloadWorkItem = item
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 0.3, execute: item)
    }
}
```

- [ ] **Step 2: Build-check**

```bash
cd /Users/shayco/Odyssey && make build-check
```

Expected: build succeeds.

- [ ] **Step 3: Update the test file**

Replace `OdysseyTests/QuickActionStoreTests.swift` with:

```swift
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
```

- [ ] **Step 4: Run the tests**

```bash
cd /Users/shayco/Odyssey
xcodebuild test \
  -scheme Odyssey \
  -destination 'platform=macOS' \
  -only-testing:OdysseyTests/QuickActionStoreTests \
  -skipPackagePluginValidation \
  2>&1 | grep -E "Test (Suite|Case|session)|PASS|FAIL|error:"
```

Expected: all 15 tests pass (`testFirstLaunchSeedsFile` and `testMigratesFromUserDefaults` are new; total count is 15).

- [ ] **Step 5: Commit**

```bash
git add Odyssey/Services/QuickActionStore.swift OdysseyTests/QuickActionStoreTests.swift
git commit -m "feat: move QuickActionStore to file-backed storage with directory watcher"
```

---

## Task 3: AppSettings — remove `quickActionConfigsKey`

**Files:**
- Modify: `Odyssey/App/AppSettings.swift`

- [ ] **Step 1: Remove the constant**

In `Odyssey/App/AppSettings.swift`, find the `// MARK: - Quick Actions` block (around line 52):

Remove this line:
```swift
static let quickActionConfigsKey     = "odyssey.chat.quickActionConfigs"
```

The block should read:
```swift
// MARK: - Quick Actions
static let quickActionUsageOrderKey  = "odyssey.chat.quickActionUsageOrder"
static let quickActionUsageCountsKey = "odyssey.chat.quickActionUsageCounts"
```

- [ ] **Step 2: Remove from `allKeys`**

In the `allKeys` computed property (around line 94), find this entry and remove `quickActionConfigsKey`:

Before:
```swift
quickActionUsageOrderKey, quickActionUsageCountsKey, quickActionConfigsKey,
```

After:
```swift
quickActionUsageOrderKey, quickActionUsageCountsKey,
```

- [ ] **Step 3: Build-check**

```bash
cd /Users/shayco/Odyssey && make build-check
```

Expected: build succeeds (no remaining references to `quickActionConfigsKey` exist after Task 2 rewrote `QuickActionStore`).

- [ ] **Step 4: Commit**

```bash
git add Odyssey/App/AppSettings.swift
git commit -m "chore: remove quickActionConfigsKey from AppSettings (moved to file)"
```

---

## Task 4: QuickActionsSettingsView — drag handles + `.draggable`/`.dropDestination`

**Files:**
- Modify: `Odyssey/Views/Settings/QuickActionsSettingsView.swift`

- [ ] **Step 1: Rewrite `QuickActionsSettingsView.swift`**

Replace the entire file with:

```swift
import SwiftUI

@MainActor
struct QuickActionsSettingsView: View {
    @ObservedObject private var store = QuickActionStore.shared
    @State private var editingConfig: QuickActionConfig? = nil
    @State private var showAddSheet = false
    @State private var showResetConfirmation = false

    var body: some View {
        Form {
            Section {
                ForEach(store.configs) { config in
                    HStack(spacing: 10) {
                        Image(systemName: "line.3.horizontal")
                            .frame(width: 16)
                            .foregroundStyle(.tertiary)

                        Image(systemName: config.symbolName)
                            .frame(width: 20)
                            .foregroundStyle(.secondary)

                        Text(config.name)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button("Edit") { editingConfig = config }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.accentColor)
                            .accessibilityIdentifier("settings.quickActions.editButton.\(config.id.uuidString)")

                        Button {
                            store.delete(id: config.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Delete \(config.name)")
                        .accessibilityIdentifier("settings.quickActions.deleteButton.\(config.id.uuidString)")
                    }
                    .accessibilityIdentifier("settings.quickActions.row.\(config.id.uuidString)")
                    .draggable(config.id.uuidString)
                    .dropDestination(for: String.self) { items, _ in
                        guard let draggedIdString = items.first,
                              let draggedId = UUID(uuidString: draggedIdString),
                              draggedId != config.id,
                              let fromIndex = store.configs.firstIndex(where: { $0.id == draggedId }),
                              let toIndex = store.configs.firstIndex(where: { $0.id == config.id })
                        else { return false }
                        store.move(
                            fromOffsets: IndexSet(integer: fromIndex),
                            toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
                        )
                        return true
                    }
                }

                Button {
                    showAddSheet = true
                } label: {
                    Label("Add chip", systemImage: "plus.circle.fill")
                }
                .accessibilityIdentifier("settings.quickActions.addButton")
            } header: {
                HStack {
                    Text("Chips")
                    Spacer()
                    Button("Reset to Defaults") { showResetConfirmation = true }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .accessibilityIdentifier("settings.quickActions.resetButton")
                }
            } footer: {
                Text("Drag to reorder. Changes appear immediately in the chat bar.")
                    .foregroundStyle(.secondary)
            }

            Section("Ordering") {
                Toggle("Order by usage", isOn: Binding(
                    get: { store.usageOrderEnabled },
                    set: { store.setUsageOrderEnabled($0) }
                ))
                .help("Reorders chips by how often you use them after \(QuickActionConfig.usageThreshold) total uses.")
                .xrayId("settings.quickActions.usageOrderToggle")
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editingConfig) { config in
            QuickActionEditSheet(mode: .edit, existing: config) { updated in
                store.update(updated)
            }
        }
        .sheet(isPresented: $showAddSheet) {
            QuickActionEditSheet(mode: .add) { newConfig in
                store.add(newConfig)
            }
        }
        .confirmationDialog("Reset all chips to defaults?", isPresented: $showResetConfirmation, titleVisibility: .visible) {
            Button("Reset to Defaults", role: .destructive) { store.resetToDefaults() }
            Button("Cancel", role: .cancel) {}
        }
        .navigationTitle("Quick Actions")
    }
}
```

- [ ] **Step 2: Build-check**

```bash
cd /Users/shayco/Odyssey && make build-check
```

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Odyssey/Views/Settings/QuickActionsSettingsView.swift
git commit -m "feat: add drag-to-reorder handles to Quick Actions settings"
```

---

## Task 5: Final verification

- [ ] **Step 1: Run `make feedback`**

```bash
cd /Users/shayco/Odyssey && make feedback
```

Expected: all checks pass.

- [ ] **Step 2: Build and run the app**

```bash
open /Users/shayco/Odyssey/Odyssey.xcodeproj
```

Build and run in Xcode (⌘R). 

- [ ] **Step 3: Manual verification checklist**

1. Open Settings → Quick Actions. Each row shows a `≡` drag handle on the left.
2. Drag "Fix It" below "Continue" by clicking and holding the drag handle then dropping. Order updates in the list and in the chat bar.
3. Inspect `~/.odyssey/config/quick-actions.json` (or `$ODYSSEY_DATA_DIR/config/quick-actions.json`): file exists and contains chips in the new order.
4. Edit `quick-actions.json` externally — rename a chip's `"name"` field, save the file → within ~1 second the Settings list and chat bar reflect the new name without restarting the app.
5. Drag reorder again → `quick-actions.json` updates on disk.
6. Reset to Defaults → 10 original chips restored; `quick-actions.json` updated.
7. Usage-order toggle still works (reorders after 10 total uses).

- [ ] **Step 4: Commit final state (if any cleanup needed)**

```bash
git add -p  # stage any cleanup
git commit -m "chore: quick-actions reorder and file-backed — final cleanup"
```
