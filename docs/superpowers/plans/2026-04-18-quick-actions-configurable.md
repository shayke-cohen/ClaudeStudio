# Quick Actions — Configurable Chips Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move quick-action chip definitions out of a hardcoded Swift enum and into a user-editable Settings pane (dedicated "Quick Actions" tab) with full CRUD, drag-to-reorder, and an SF Symbol picker.

**Architecture:** A new `QuickActionConfig` Codable struct is persisted as a JSON array in `AppSettings.store` (per-instance UserDefaults). A `QuickActionStore` ObservableObject replaces the existing `QuickActionUsageTracker`, owns load/save/mutate operations, and is shared between `ChatView` and the new settings pane. Five new Swift files are added; `ChatView.swift`, `AppSettings.swift`, and `SettingsView.swift` are modified.

**Tech Stack:** Swift 6, SwiftUI, `@MainActor ObservableObject`, UserDefaults (per-instance `AppSettings.store`), XCTest for store logic.

**Spec:** `docs/superpowers/specs/2026-04-18-quick-actions-configurable-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `Odyssey/Models/QuickActionConfig.swift` | Create | Codable model + static defaults + usageThreshold |
| `Odyssey/Services/QuickActionStore.swift` | Create | Load/save/mutate/usage — replaces QuickActionUsageTracker |
| `Odyssey/Views/Settings/SymbolPickerView.swift` | Create | Searchable SF Symbol grid popover |
| `Odyssey/Views/Settings/QuickActionEditSheet.swift` | Create | Edit/add chip sheet (name, prompt, icon) |
| `Odyssey/Views/Settings/QuickActionsSettingsView.swift` | Create | Settings pane: drag-reorder list, add/delete, reset |
| `Odyssey/App/AppSettings.swift` | Modify | Add `quickActionConfigsKey`, update `allKeys` |
| `Odyssey/Views/Settings/SettingsView.swift` | Modify | Add `.quickActions` case to `SettingsSection` |
| `Odyssey/Views/MainWindow/ChatView.swift` | Modify | Replace `QuickAction` enum + `QuickActionUsageTracker` with `QuickActionStore` |
| `OdysseyTests/QuickActionStoreTests.swift` | Create | Unit tests for store logic |

---

## Task 1: QuickActionConfig model

**Files:**
- Create: `Odyssey/Models/QuickActionConfig.swift`
- Create: `OdysseyTests/QuickActionStoreTests.swift` (scaffold only, filled in Task 3)

- [ ] **Step 1: Create the model file**

`Odyssey/Models/QuickActionConfig.swift`:

```swift
import Foundation

struct QuickActionConfig: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var prompt: String
    var symbolName: String

    init(id: UUID = UUID(), name: String, prompt: String, symbolName: String) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.symbolName = symbolName
    }
}

extension QuickActionConfig {
    static let usageThreshold = 10

    static let defaults: [QuickActionConfig] = [
        QuickActionConfig(id: UUID(uuidString: "A1000000-0000-0000-0000-000000000001")!, name: "Fix It",        prompt: "Fix the error above",                                                          symbolName: "wrench.and.screwdriver.fill"),
        QuickActionConfig(id: UUID(uuidString: "A1000000-0000-0000-0000-000000000002")!, name: "Continue",      prompt: "Continue where you left off",                                                  symbolName: "play.fill"),
        QuickActionConfig(id: UUID(uuidString: "A1000000-0000-0000-0000-000000000003")!, name: "Commit & Push", prompt: "Commit all changes and push to the remote",                                     symbolName: "paperplane.fill"),
        QuickActionConfig(id: UUID(uuidString: "A1000000-0000-0000-0000-000000000004")!, name: "Run Tests",     prompt: "Run the tests and show me the results",                                         symbolName: "flask.fill"),
        QuickActionConfig(id: UUID(uuidString: "A1000000-0000-0000-0000-000000000005")!, name: "Undo",          prompt: "Undo the last changes you made — revert them",                                  symbolName: "arrow.uturn.backward"),
        QuickActionConfig(id: UUID(uuidString: "A1000000-0000-0000-0000-000000000006")!, name: "TL;DR",         prompt: "Give me a TL;DR summary of what we've done and where we are",                  symbolName: "bolt.fill"),
        QuickActionConfig(id: UUID(uuidString: "A1000000-0000-0000-0000-000000000007")!, name: "Double Check",  prompt: "Double check your last response — verify it's correct and nothing is missing",  symbolName: "checkmark.seal.fill"),
        QuickActionConfig(id: UUID(uuidString: "A1000000-0000-0000-0000-000000000008")!, name: "Open It",       prompt: "Open it — launch, run, or preview what we just built",                          symbolName: "link"),
        QuickActionConfig(id: UUID(uuidString: "A1000000-0000-0000-0000-000000000009")!, name: "Visual Options",prompt: "Show me visual options for this — present alternatives I can choose from",      symbolName: "paintpalette.fill"),
        QuickActionConfig(id: UUID(uuidString: "A1000000-0000-0000-0000-000000000010")!, name: "Show Visual",   prompt: "Show me this in a visual way — diagram, mockup, or illustration",               symbolName: "eye.fill"),
    ]
}
```

- [ ] **Step 2: Write model unit tests**

`OdysseyTests/QuickActionStoreTests.swift`:

```swift
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
```

- [ ] **Step 3: Run tests — expect FAIL (QuickActionStore not yet defined)**

```bash
cd /Users/shayco/Odyssey && make build-check 2>&1 | tail -20
```

Expected: build failure mentioning `QuickActionStore` not found. That's correct — proceed to Task 2.

- [ ] **Step 4: Commit**

```bash
cd /Users/shayco/Odyssey
git add Odyssey/Models/QuickActionConfig.swift OdysseyTests/QuickActionStoreTests.swift
git commit -m "feat: add QuickActionConfig model with static defaults"
```

---

## Task 2: AppSettings — add storage key

**Files:**
- Modify: `Odyssey/App/AppSettings.swift`

- [ ] **Step 1: Add the key constant**

In `AppSettings.swift`, find the `// MARK: - Quick Actions` section (line ~52) and add the new key after the existing two:

```swift
// MARK: - Quick Actions
static let quickActionUsageOrderKey  = "odyssey.chat.quickActionUsageOrder"
static let quickActionUsageCountsKey = "odyssey.chat.quickActionUsageCounts"
static let quickActionConfigsKey     = "odyssey.chat.quickActionConfigs"    // ← add this
```

- [ ] **Step 2: Add key to allKeys**

In the `allKeys` computed property, find the line containing `quickActionUsageOrderKey, quickActionUsageCountsKey` and append the new key:

```swift
quickActionUsageOrderKey, quickActionUsageCountsKey, quickActionConfigsKey,
```

- [ ] **Step 3: Build check**

```bash
cd /Users/shayco/Odyssey && make build-check 2>&1 | tail -10
```

Expected: build failure (QuickActionStore still undefined). Proceed.

- [ ] **Step 4: Commit**

```bash
cd /Users/shayco/Odyssey
git add Odyssey/App/AppSettings.swift
git commit -m "feat: add quickActionConfigsKey to AppSettings"
```

---

## Task 3: QuickActionStore

**Files:**
- Create: `Odyssey/Services/QuickActionStore.swift`
- Modify: `OdysseyTests/QuickActionStoreTests.swift` (add store tests)

- [ ] **Step 1: Create the store**

`Odyssey/Services/QuickActionStore.swift`:

```swift
import Foundation
import Combine

@MainActor
final class QuickActionStore: ObservableObject {

    static let shared = QuickActionStore()

    @Published private(set) var configs: [QuickActionConfig] = []
    @Published var usageOrderEnabled: Bool

    private let defaults: UserDefaults

    init(defaults: UserDefaults = AppSettings.store) {
        self.defaults = defaults
        self.usageOrderEnabled = (defaults.object(forKey: AppSettings.quickActionUsageOrderKey) as? Bool) ?? true
        self.configs = Self.loadConfigs(from: defaults)
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
        objectWillChange.send()
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(configs) else { return }
        defaults.set(data, forKey: AppSettings.quickActionConfigsKey)
    }

    private func loadUsageCounts() -> [String: Int] {
        (defaults.dictionary(forKey: AppSettings.quickActionUsageCountsKey) as? [String: Int]) ?? [:]
    }

    private static func loadConfigs(from defaults: UserDefaults) -> [QuickActionConfig] {
        guard
            let data = defaults.data(forKey: AppSettings.quickActionConfigsKey),
            let configs = try? JSONDecoder().decode([QuickActionConfig].self, from: data),
            !configs.isEmpty
        else {
            return QuickActionConfig.defaults
        }
        return configs
    }
}
```

- [ ] **Step 2: Add store tests to QuickActionStoreTests.swift**

Append these test methods inside the `QuickActionStoreTests` class (before the closing `}`):

```swift
    // ─── Store: initial state ─────────────────────────────────────

    func testStoreLoadsDefaultsOnFirstLaunch() {
        XCTAssertEqual(store.configs.count, 10)
        XCTAssertEqual(store.configs.first?.name, "Fix It")
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
        let store2 = QuickActionStore(defaults: testDefaults)
        XCTAssertTrue(store2.configs.contains(where: { $0.name == "Persisted" }))
    }

    func testResetToDefaults() {
        store.delete(id: store.configs[0].id)
        XCTAssertEqual(store.configs.count, 9)
        store.resetToDefaults()
        XCTAssertEqual(store.configs.count, 10)
        XCTAssertEqual(store.configs.first?.name, "Fix It")
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
```

- [ ] **Step 3: Run the tests**

```bash
cd /Users/shayco/Odyssey && xcodebuild test -scheme Odyssey -destination 'platform=macOS' -only-testing:OdysseyTests/QuickActionStoreTests 2>&1 | grep -E "passed|failed|error:"
```

Expected: all `QuickActionStoreTests` pass.

- [ ] **Step 4: Commit**

```bash
cd /Users/shayco/Odyssey
git add Odyssey/Services/QuickActionStore.swift OdysseyTests/QuickActionStoreTests.swift
git commit -m "feat: add QuickActionStore replacing QuickActionUsageTracker"
```

---

## Task 4: SymbolPickerView

**Files:**
- Create: `Odyssey/Views/Settings/SymbolPickerView.swift`

- [ ] **Step 1: Create the view**

`Odyssey/Views/Settings/SymbolPickerView.swift`:

```swift
import SwiftUI

struct SymbolPickerView: View {
    @Binding var selectedSymbol: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [String] {
        query.isEmpty ? SymbolPickerView.catalog
            : SymbolPickerView.catalog.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search symbols…", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(10)
                .accessibilityIdentifier("symbolPicker.searchField")

            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 4), count: 6), spacing: 4) {
                    ForEach(filtered, id: \.self) { name in
                        Button {
                            selectedSymbol = name
                            dismiss()
                        } label: {
                            Image(systemName: name)
                                .font(.system(size: 18))
                                .frame(width: 36, height: 36)
                                .background(selectedSymbol == name ? Color.accentColor.opacity(0.2) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(selectedSymbol == name ? Color.accentColor : Color.clear, lineWidth: 1.5)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("symbolPicker.symbol.\(name)")
                    }
                }
                .padding(10)
            }
        }
        .frame(width: 256, height: 320)
    }

    static let catalog: [String] = [
        // Dev actions
        "wrench.and.screwdriver.fill", "hammer.fill", "terminal.fill", "flask.fill",
        "play.fill", "stop.fill", "forward.fill", "backward.fill",
        "arrow.uturn.backward", "arrow.clockwise", "arrow.2.circlepath",
        "paperplane.fill", "checkmark.seal.fill", "bolt.fill",
        "gear", "gearshape.fill", "gearshape.2", "slider.horizontal.3",
        // Files
        "doc.fill", "doc.text.fill", "folder.fill", "folder.badge.plus",
        "archivebox.fill", "tray.fill", "externaldrive.fill",
        "arrow.down.circle.fill", "arrow.up.circle.fill",
        "square.and.arrow.up.fill", "square.and.arrow.down.fill",
        // Code
        "chevron.left.forwardslash.chevron.right", "curlybraces",
        "function", "number", "rectangle.and.pencil.and.ellipsis",
        // Communication
        "message.fill", "bubble.left.fill", "bubble.right.fill",
        "envelope.fill", "bell.fill", "megaphone.fill",
        "link", "link.badge.plus",
        // Visual
        "eye.fill", "paintpalette.fill", "paintbrush.fill",
        "photo.fill", "camera.fill", "video.fill",
        "display", "macwindow", "rectangle.on.rectangle", "square.split.2x1",
        // Status
        "star.fill", "heart.fill", "checkmark.circle.fill", "xmark.circle.fill",
        "exclamationmark.triangle.fill", "info.circle.fill",
        "questionmark.circle.fill", "clock.fill", "timer", "stopwatch.fill",
        // Navigation & misc
        "house.fill", "magnifyingglass", "scope", "map.fill",
        "location.fill", "pin.fill", "tag.fill", "bookmark.fill",
        "list.bullet", "square.grid.2x2.fill", "chart.bar.fill", "waveform",
        "cpu.fill", "memorychip.fill", "network",
        "antenna.radiowaves.left.and.right",
        "lock.fill", "key.fill",
        "person.fill", "person.2.fill",
        "text.quote", "textformat", "sparkles", "wand.and.stars",
        "lightbulb.fill", "hand.tap.fill", "hand.raised.fill",
        "scissors", "trash.fill", "plus.circle.fill", "minus.circle.fill",
        "ellipsis.circle.fill", "return", "globe",
    ]
}
```

- [ ] **Step 2: Build check**

```bash
cd /Users/shayco/Odyssey && make build-check 2>&1 | tail -10
```

Expected: still fails (ChatView still references deleted types — not yet modified). The new file compiles.

- [ ] **Step 3: Commit**

```bash
cd /Users/shayco/Odyssey
git add Odyssey/Views/Settings/SymbolPickerView.swift
git commit -m "feat: add SymbolPickerView with searchable SF Symbol catalog"
```

---

## Task 5: QuickActionEditSheet

**Files:**
- Create: `Odyssey/Views/Settings/QuickActionEditSheet.swift`

- [ ] **Step 1: Create the sheet**

`Odyssey/Views/Settings/QuickActionEditSheet.swift`:

```swift
import SwiftUI

struct QuickActionEditSheet: View {
    enum Mode { case add, edit }

    let mode: Mode
    var onSave: (QuickActionConfig) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var prompt: String
    @State private var symbolName: String
    @State private var showSymbolPicker = false

    private let id: UUID

    init(mode: Mode, existing: QuickActionConfig? = nil, onSave: @escaping (QuickActionConfig) -> Void) {
        self.mode = mode
        self.onSave = onSave
        self.id = existing?.id ?? UUID()
        _name       = State(initialValue: existing?.name ?? "")
        _prompt     = State(initialValue: existing?.prompt ?? "")
        _symbolName = State(initialValue: existing?.symbolName ?? "star")
    }

    private var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !prompt.trimmingCharacters(in: .whitespaces).isEmpty }
    private var title: String { mode == .add ? "Add Chip" : "Edit Chip" }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)

            HStack(alignment: .top, spacing: 12) {
                Button {
                    showSymbolPicker = true
                } label: {
                    Image(systemName: symbolName)
                        .font(.system(size: 22))
                        .frame(width: 48, height: 48)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor.opacity(0.4), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Choose icon")
                .accessibilityIdentifier("chipEdit.iconButton")
                .popover(isPresented: $showSymbolPicker) {
                    SymbolPickerView(selectedSymbol: $symbolName)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Name").font(.caption).foregroundStyle(.secondary)
                    TextField("e.g. Fix It", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("chipEdit.nameField")
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Prompt").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $prompt)
                    .frame(minHeight: 80)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                    .accessibilityIdentifier("chipEdit.promptField")
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .accessibilityIdentifier("chipEdit.cancelButton")
                Spacer()
                Button(mode == .add ? "Add" : "Save") {
                    onSave(QuickActionConfig(id: id, name: name.trimmingCharacters(in: .whitespaces), prompt: prompt.trimmingCharacters(in: .whitespaces), symbolName: symbolName))
                    dismiss()
                }
                .disabled(!isValid)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("chipEdit.saveButton")
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
```

- [ ] **Step 2: Build check**

```bash
cd /Users/shayco/Odyssey && make build-check 2>&1 | tail -10
```

Expected: still fails on ChatView (not yet updated). New file compiles.

- [ ] **Step 3: Commit**

```bash
cd /Users/shayco/Odyssey
git add Odyssey/Views/Settings/QuickActionEditSheet.swift
git commit -m "feat: add QuickActionEditSheet with symbol picker integration"
```

---

## Task 6: QuickActionsSettingsView

**Files:**
- Create: `Odyssey/Views/Settings/QuickActionsSettingsView.swift`

- [ ] **Step 1: Create the settings pane**

`Odyssey/Views/Settings/QuickActionsSettingsView.swift`:

```swift
import SwiftUI

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
                        Image(systemName: config.symbolName)
                            .frame(width: 20)
                            .foregroundStyle(.secondary)

                        Text(config.name)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button("Edit") { editingConfig = config }
                            .buttonStyle(.plain)
                            .foregroundStyle(.accentColor)
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
                }
                .onMove { from, to in store.move(fromOffsets: from, toOffset: to) }

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

- [ ] **Step 2: Build check**

```bash
cd /Users/shayco/Odyssey && make build-check 2>&1 | tail -10
```

Expected: still fails on ChatView (not yet updated). New file compiles.

- [ ] **Step 3: Commit**

```bash
cd /Users/shayco/Odyssey
git add Odyssey/Views/Settings/QuickActionsSettingsView.swift
git commit -m "feat: add QuickActionsSettingsView with CRUD and drag-reorder"
```

---

## Task 7: Add quickActions to SettingsSection

**Files:**
- Modify: `Odyssey/Views/Settings/SettingsView.swift`

- [ ] **Step 1: Add the enum case**

In `SettingsView.swift`, find `enum SettingsSection` and add `.quickActions` after `chatDisplay`:

```swift
enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case models
    case connectors
    case chatDisplay
    case quickActions       // ← add here
    case configuration
    case labs
    case advanced
    case iosPairing
    case federation
    case acceptInvite
```

- [ ] **Step 2: Add title, subtitle, systemImage, xrayId**

In each computed property switch, add the `quickActions` case:

In `var title`:
```swift
case .quickActions: "Quick Actions"
```

In `var subtitle`:
```swift
case .quickActions: "Customize the shortcut chips in the chat bar"
```

In `var systemImage`:
```swift
case .quickActions: "rectangle.grid.1x2"
```

In `var xrayId`:
```swift
case .quickActions: "settings.tab.quickActions"
```

- [ ] **Step 3: Remove Quick Actions section from GeneralSettingsTab**

In `Odyssey/Views/Settings/SettingsView.swift` (or wherever `GeneralSettingsTab` is defined), find and **delete** the entire `Section("Quick Actions")` block including the usage toggle and its `.help(...)` modifier:

```swift
// DELETE THIS ENTIRE BLOCK:
Section("Quick Actions") {
    Toggle("Order quick actions by usage", isOn: $quickActionUsageOrder)
        .xrayId("settings.general.quickActionUsageOrderToggle")
        .help("When enabled, quick action buttons reorder based on how often you use them ...")
}
```

Also remove the `@AppStorage(AppSettings.quickActionUsageOrderKey, store: AppSettings.store) private var quickActionUsageOrder = true` property from `GeneralSettingsTab` since the toggle now lives in `QuickActionsSettingsView`.

- [ ] **Step 4: Wire the view**

In `SettingsView`'s `switch selectedSection` block (around line 208), add after `case .chatDisplay`:

```swift
case .quickActions:
    QuickActionsSettingsView()
```

- [ ] **Step 5: Build check**

```bash
cd /Users/shayco/Odyssey && make build-check 2>&1 | tail -10
```

Expected: still fails on ChatView. New settings tab compiles correctly.

- [ ] **Step 6: Commit**

```bash
cd /Users/shayco/Odyssey
git add Odyssey/Views/Settings/SettingsView.swift
git commit -m "feat: add Quick Actions tab to Settings, remove from General"
```

---

## Task 8: Refactor ChatView

**Files:**
- Modify: `Odyssey/Views/MainWindow/ChatView.swift`

This is the most impactful modification. Work carefully.

- [ ] **Step 1: Replace the QuickAction enum**

Delete the entire `// MARK: - Quick Actions` block containing `enum QuickAction` (lines 7–76 in current file). Replace with nothing — the model now lives in `QuickActionConfig.swift`.

- [ ] **Step 2: Replace QuickActionUsageTracker**

Delete the entire `// MARK: - Quick Action Usage Tracker` block containing `final class QuickActionUsageTracker` (lines 78–135). Replace with nothing.

- [ ] **Step 3: Replace the StateObject declaration**

Find (around line 302):
```swift
@StateObject private var quickActionTracker = QuickActionUsageTracker()
```

Replace with:
```swift
@ObservedObject private var quickActionStore = QuickActionStore.shared
```

- [ ] **Step 4: Update QuickActionsRow usage**

Find the `QuickActionsRow` call site (around line 2115):
```swift
QuickActionsRow(
    actions: quickActionTracker.orderedActions,
    isProcessing: isProcessing,
    onAction: { sendQuickAction($0) }
)
```

Replace with:
```swift
QuickActionsRow(
    actions: quickActionStore.orderedConfigs,
    isProcessing: isProcessing,
    onAction: { sendQuickAction($0) }
)
```

- [ ] **Step 5: Update QuickActionsRow struct signature**

Find `private struct QuickActionsRow: View` (around line 163):
```swift
private struct QuickActionsRow: View {
    let actions: [QuickAction]
    let isProcessing: Bool
    let onAction: (QuickAction) -> Void
```

Replace with:
```swift
private struct QuickActionsRow: View {
    let actions: [QuickActionConfig]
    let isProcessing: Bool
    let onAction: (QuickActionConfig) -> Void
```

- [ ] **Step 6: Update QuickActionsRow body**

Inside `QuickActionsRow.body`, update every reference from `action.icon` / `action.label` / `QuickAction` type to use `QuickActionConfig` fields:

Find any reference like `action.icon` → replace with `action.symbolName`
Find any reference like `action.label` → replace with `action.name`

The button construction will look like:
```swift
ForEach(actions) { action in
    Button {
        onAction(action)
    } label: {
        Label(action.name, systemImage: action.symbolName)
    }
    // ... accessibility etc
}
```

Check the full body and update all field accesses accordingly.

- [ ] **Step 7: Update sendQuickAction**

Find `sendQuickAction` (around line 3054):
```swift
private func sendQuickAction(_ action: QuickAction) {
    quickActionTracker.recordUsage(action)
    inputText = action.prompt
    sendMessage()
}
```

Replace with:
```swift
private func sendQuickAction(_ action: QuickActionConfig) {
    quickActionStore.recordUsage(id: action.id)
    inputText = action.prompt
    sendMessage()
}
```

- [ ] **Step 8: Build check — must pass**

```bash
cd /Users/shayco/Odyssey && make build-check 2>&1 | tail -20
```

Expected: **clean build with no errors**. Fix any remaining `QuickAction` references in `ChatView.swift` until the build is clean.

- [ ] **Step 9: Run sidecar smoke**

```bash
cd /Users/shayco/Odyssey && make feedback 2>&1 | tail -20
```

Expected: passes.

- [ ] **Step 10: Commit**

```bash
cd /Users/shayco/Odyssey
git add Odyssey/Views/MainWindow/ChatView.swift
git commit -m "refactor(chat): replace QuickAction enum + tracker with QuickActionStore"
```

---

## Task 9: Regenerate Xcode project

**Files:**
- (project.yml sources glob covers `Odyssey/` — no edits needed; just regenerate)

- [ ] **Step 1: Run xcodegen**

```bash
cd /Users/shayco/Odyssey && xcodegen generate 2>&1 | tail -10
```

Expected: `⚙️  Generating project...` followed by success with no warnings about missing files.

- [ ] **Step 2: Final build and test run**

```bash
cd /Users/shayco/Odyssey && make feedback 2>&1 | tail -20
```

Expected: clean build + sidecar smoke passes.

```bash
cd /Users/shayco/Odyssey && xcodebuild test -scheme Odyssey -destination 'platform=macOS' -only-testing:OdysseyTests/QuickActionStoreTests 2>&1 | grep -E "passed|failed|error:"
```

Expected: all `QuickActionStoreTests` tests pass (14 tests).

- [ ] **Step 3: Commit**

```bash
cd /Users/shayco/Odyssey
git add project.xcodeproj/
git commit -m "chore: regenerate Xcode project for new Quick Actions files"
```

---

## Task 10: End-to-end verification

- [ ] **Step 1: Launch the app and open Settings**

Open the app. Navigate to Settings (`⌘,`). Confirm "Quick Actions" tab appears between "Chat Display" and "Configuration".

- [ ] **Step 2: Verify pre-populated chips**

The list shows all 10 default chips: Fix It, Continue, Commit & Push, Run Tests, Undo, TL;DR, Double Check, Open It, Visual Options, Show Visual.

- [ ] **Step 3: Edit a chip**

Click Edit on "Fix It". Change name to "Fix Bug", prompt to "Fix the bug above", change icon via symbol picker. Save. Confirm the row updates.

- [ ] **Step 4: Add a chip**

Click "+ Add chip". Enter name "Explain", prompt "Explain what you just did", pick an icon. Click Add. Confirm it appears at the bottom of the list.

- [ ] **Step 5: Delete a chip**

Click ✕ on "TL;DR". Confirm it disappears from the list and from the chat input bar.

- [ ] **Step 6: Drag to reorder**

Drag "Run Tests" to the top. Confirm the chat bar reflects the new order.

- [ ] **Step 7: Reset to defaults**

Click "Reset to Defaults". Confirm the confirmation dialog appears. Accept. Confirm all 10 original chips are restored in original order.

- [ ] **Step 8: Verify chat bar**

Open a chat. Confirm chips appear and clicking one sends the correct prompt.

- [ ] **Step 9: Verify usage ordering toggle**

Turn on "Order by usage". Click any chip 11 times via the chat bar. Open Settings → Quick Actions and confirm the list reorders.

- [ ] **Step 10: Final commit**

```bash
cd /Users/shayco/Odyssey
git add -p  # review any stray changes
git commit -m "feat: configurable quick action chips with settings editor and symbol picker"
```
