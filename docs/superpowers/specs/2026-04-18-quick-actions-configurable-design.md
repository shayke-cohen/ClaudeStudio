# Quick Actions — Configurable Chips Design

**Date:** 2026-04-18  
**Status:** Approved

---

## Problem

The 10 quick-action chips (Fix It, Continue, Commit & Push, etc.) are hardcoded in a Swift enum inside `ChatView.swift`. Users cannot rename them, change their prompts, add new ones, remove ones they never use, or reorder them manually. The only existing setting is a toggle for usage-based auto-ordering.

---

## Goal

Move chip definitions out of code and into a dedicated Settings pane where users can fully manage them: edit names/prompts/icons, add new chips, delete chips, and drag to reorder. The 10 existing chips become editable defaults, with a "Reset to Defaults" button as a safety net.

---

## Data Model

### `QuickActionConfig` (new — `Odyssey/Models/QuickActionConfig.swift`)

```swift
struct QuickActionConfig: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String        // display label on chip
    var prompt: String      // text injected into chat input
    var symbolName: String  // SF Symbol name (e.g. "wrench.and.screwdriver.fill")
}
```

Stored as a JSON-encoded `[QuickActionConfig]` in UserDefaults under `odyssey.chat.quickActionConfigs`.

A `static var defaults: [QuickActionConfig]` on the type mirrors the current 10 hardcoded chips exactly. First-launch (key missing) seeds from defaults.

---

## Storage

New key in `AppSettings.swift`:
```swift
static let quickActionConfigsKey = "odyssey.chat.quickActionConfigs"
```
Added to the `allKeys` array alongside the existing `quickActionUsageOrderKey` and `quickActionUsageCountsKey`.

---

## QuickActionStore (new — `Odyssey/Services/QuickActionStore.swift`)

`@MainActor final class QuickActionStore: ObservableObject`

Responsibilities:
- Load/save `[QuickActionConfig]` from UserDefaults
- Expose `orderedConfigs: [QuickActionConfig]` — user-defined order, or usage-sorted when the toggle is on (same threshold logic as today: 10+ total uses)
- `recordUsage(id: UUID)` — increments count, persists usage dict, recomputes order
- `resetToDefaults()` — replaces configs with `QuickActionConfig.defaults`, clears usage counts
- `move(from:to:)`, `delete(at:)`, `add(_:)`, `update(_:)` mutating operations, each followed by `save()`

This replaces `QuickActionUsageTracker` entirely. `QuickActionUsageTracker` is deleted.

---

## Settings UI

### New section in `SettingsSection` enum (`SettingsView.swift`)

```swift
case quickActions
```

Properties:
- `title`: `"Quick Actions"`
- `subtitle`: `"Customize the shortcut chips in the chat bar"`
- `systemImage`: `"rectangle.grid.1x2"`
- `xrayId`: `"settings.tab.quickActions"`

Inserted between `chatDisplay` and `configuration` in `allCases` order.

`visibleSections` filter: always visible (no conditional hiding needed).

### `QuickActionsSettingsView` (new — `Odyssey/Views/Settings/QuickActionsSettingsView.swift`)

**Layout:**
- Header: title + "Reset to Defaults" button (trailing, secondary style, shows confirmation alert)
- Subtitle: "Drag to reorder. Chips appear in the chat input bar."
- `List` with `.onMove` and `.onDelete` — each row shows:
  - Drag handle (automatic with EditButton / always-on edit mode)
  - SF Symbol icon (rendered with `Image(systemName:)`)
  - Chip name
  - "Edit" button → opens `QuickActionEditSheet` as a sheet
  - Delete (×) button
- Below list: "+ Add chip" button → opens `QuickActionEditSheet` with blank config
- Footer toggle: "Order by usage" (existing `quickActionUsageOrder` key, same behavior as today)

Uses `@ObservedObject private var store = QuickActionStore.shared` (singleton shared instance — `@ObservedObject` is correct here since the store is externally owned).

### `QuickActionEditSheet` (new — `Odyssey/Views/Settings/QuickActionEditSheet.swift`)

Sheet presented for both editing existing and adding new chips.

**Layout:**
- Icon preview button (48×48, tappable) — tap opens `SymbolPickerView` as a popover
- Name `TextField`
- Prompt `TextEditor` (multi-line, min height ~80pt)
- Save / Cancel buttons
- Validation: Save disabled if name or prompt is empty

### `SymbolPickerView` (new — `Odyssey/Views/Settings/SymbolPickerView.swift`)

Presented as a popover from the icon preview button.

**Layout:**
- Search `TextField` (filters by substring match on symbol name)
- Scrollable `LazyVGrid` (6-column) of `Image(systemName:)` icons
- Tapping a symbol: updates binding, dismisses popover
- Currently selected symbol highlighted (purple tint border)

**Symbol catalog:** A hardcoded `static let catalog: [String]` of ~120 SF Symbol names covering: actions (wrench, play, bolt, arrow variants), dev (terminal, code, hammer, flask), communication (message, paperplane, link, bubble), files (doc, folder, arrow.down.circle), media (eye, photo, paintpalette), status (checkmark, xmark, seal, clock), misc (star, pin, magnifyingglass, lightbulb, rocket, house).

---

## ChatView Changes (`ChatView.swift`)

1. Replace `enum QuickAction` with a `@StateObject private var quickActionStore = QuickActionStore.shared`
2. Replace `QuickActionUsageTracker` instantiation and usage with `quickActionStore`
3. `QuickActionsRow` receives `[QuickActionConfig]` instead of `[QuickAction]` — update its type signature and rendering (uses `config.symbolName`, `config.name`, `config.prompt`)
4. `sendQuickAction()` calls `quickActionStore.recordUsage(id: config.id)`
5. Delete `QuickActionUsageTracker` class entirely

---

## Files Changed

| File | Change |
|------|--------|
| `Odyssey/Models/QuickActionConfig.swift` | **New** — Codable model + static defaults |
| `Odyssey/Services/QuickActionStore.swift` | **New** — replaces QuickActionUsageTracker |
| `Odyssey/Views/Settings/QuickActionsSettingsView.swift` | **New** — settings pane |
| `Odyssey/Views/Settings/QuickActionEditSheet.swift` | **New** — edit/add sheet |
| `Odyssey/Views/Settings/SymbolPickerView.swift` | **New** — SF Symbol picker |
| `Odyssey/App/AppSettings.swift` | Add `quickActionConfigsKey`, update `allKeys` |
| `Odyssey/Views/Settings/SettingsView.swift` | Add `.quickActions` case to `SettingsSection` |
| `Odyssey/Views/MainWindow/ChatView.swift` | Replace `QuickAction` enum + tracker with `QuickActionStore` |
| `project.yml` | Register all 5 new Swift files |

---

## Accessibility

- Each chip row in settings list: `.accessibilityIdentifier("settings.quickActions.row.\(config.id.uuidString)")`
- Edit button per row: `.accessibilityIdentifier("settings.quickActions.editButton.\(config.id.uuidString)")`
- Delete button per row: `.accessibilityIdentifier("settings.quickActions.deleteButton.\(config.id.uuidString)")`
- Add chip button: `.accessibilityIdentifier("settings.quickActions.addButton")`
- Reset button: `.accessibilityIdentifier("settings.quickActions.resetButton")`
- Symbol picker grid items: `.accessibilityIdentifier("symbolPicker.symbol.\(name)")`
- Settings tab: `xrayId "settings.tab.quickActions"` (via existing `.xrayId()` modifier pattern)

---

## Verification

1. `make build-check` — Swift build must pass with no errors
2. Open Settings → Quick Actions tab appears between "Chat Display" and "Configuration"
3. Edit "Fix It" chip → change name to "Fix Bug", prompt to "Fix the bug above", change icon → save → chip row updates, chat input bar reflects new name/icon/prompt
4. Add a new chip "Explain" with a custom symbol and prompt → appears at bottom of list, visible in chat bar
5. Delete "TL;DR" → removed from list and chat bar
6. Drag "Run Tests" to top → reorder persists after closing/reopening settings
7. "Reset to Defaults" → confirmation alert → chips restored to original 10
8. Usage-based order toggle still works (reorders after 10 uses)
9. `make feedback` passes
</content>
