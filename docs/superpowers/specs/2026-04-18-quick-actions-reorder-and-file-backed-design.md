# Quick Actions — Drag-to-Reorder & File-backed Storage Design

**Date:** 2026-04-18  
**Status:** Approved

---

## Problem

Two gaps remain after the initial configurable quick-actions implementation:

1. **Reorder UI is missing.** `QuickActionsSettingsView` has `.onMove` wired but macOS `Form(.grouped)` does not render drag handles. Users cannot reorder chips.

2. **Config is not file-backed.** Chips are stored as a JSON blob in `UserDefaults`. Users cannot edit them in external apps (Cursor, VS Code, etc.), and the format is inconsistent with the file-backed pattern used by agents, groups, skills, and MCPs.

---

## Goal

1. Add visible drag-to-reorder handles to the chip list in Settings.
2. Move chip config to `~/.odyssey/config/quick-actions.json`, watched live for external edits.

---

## Design

### 1. Drag-to-Reorder UI (`QuickActionsSettingsView.swift`)

Add `Image(systemName: "line.3.horizontal")` as the **leading element** in each chip row, styled `.foregroundStyle(.tertiary)`. This is the standard macOS drag-handle affordance.

For the actual drag mechanics, switch from `.onMove` (invisible on macOS `Form`) to SwiftUI's `.draggable()` + `.dropDestination()` API (macOS 13+):

- Each row `.draggable(config.id.uuidString)` — transfers the UUID string as a `String` draggable item.
- Each row `.dropDestination(for: String.self)` — on drop, finds the dragged UUID in `store.configs` and calls `store.move(fromOffsets:toOffset:)` to reposition it.

Remove the now-unused `.onMove` modifier. The `store.move(fromOffsets:toOffset:)` method remains unchanged.

**Row layout (updated):**
```
[line.3.horizontal]  [symbol]  [chip name ...]  [Edit]  [×]
```

### 2. File-backed Storage (`QuickActionStore.swift` + `ConfigFileManager.swift`)

**File location:** `ConfigFileManager.configDirectory` / `"quick-actions.json"`  
→ `~/.odyssey/config/quick-actions.json` (or `$ODYSSEY_DATA_DIR/config/quick-actions.json`)

**File format:** Pretty-printed JSON array of `QuickActionConfig` objects (same Codable struct, no changes needed):
```json
[
  { "id": "A1000000-...", "name": "Fix It", "prompt": "Fix the issue...", "symbolName": "wrench.and.screwdriver.fill" },
  ...
]
```

**`ConfigFileManager` additions** (pure static helpers, no SwiftData dependency):
- `static var quickActionsFile: URL` — `configDirectory/quick-actions.json`
- `static func readQuickActions() -> [QuickActionConfig]?` — reads + decodes the file; returns `nil` on missing/invalid
- `static func writeQuickActions(_ configs: [QuickActionConfig]) throws` — encodes + writes (pretty-printed, atomic write via temp file + rename)

**`QuickActionStore` changes:**

_Load order (init):_
1. Try `ConfigFileManager.readQuickActions()` → use if non-nil and non-empty
2. Try UserDefaults migration: if `odyssey.chat.quickActionConfigs` key exists, decode it, write to file, delete the key
3. Fallback to `QuickActionConfig.defaults`

_Save:_ `ConfigFileManager.writeQuickActions(configs)` (replace the UserDefaults save). Remove `AppSettings.quickActionConfigsKey` usage from `save()`.

_File watching:_ Add a `DispatchSource` FSEvents watcher on `quick-actions.json`. When the file changes externally, reload and publish on `@MainActor`. Debounce 300 ms to avoid reload storms from editors that write incrementally.

**UserDefaults keys:**
- `odyssey.chat.quickActionConfigs` — **removed** after migration (one-time, on first load)
- `odyssey.chat.quickActionUsageOrder` — **kept** (UI preference, not config)
- `odyssey.chat.quickActionUsageCounts` — **kept** (ephemeral usage data, not config)

**`AppSettings.swift`:** Remove `quickActionConfigsKey` constant and remove it from `allKeys`.

---

## Files Changed

| File | Change |
|------|--------|
| `Odyssey/Views/Settings/QuickActionsSettingsView.swift` | Add drag handle icon; replace `.onMove` with `.draggable`/`.dropDestination` |
| `Odyssey/Services/QuickActionStore.swift` | File-backed load/save; FSEvents watcher; UserDefaults migration |
| `Odyssey/Services/ConfigFileManager.swift` | Add `quickActionsFile`, `readQuickActions()`, `writeQuickActions()` |
| `Odyssey/App/AppSettings.swift` | Remove `quickActionConfigsKey` and from `allKeys` |

---

## Verification

1. `make build-check` passes
2. Open Settings → Quick Actions → drag handles visible on each row → drag "Fix It" below "Continue" → order persists after closing/reopening Settings
3. Inspect `~/.odyssey/config/quick-actions.json` — file exists, contains all chips in the new order
4. Edit the file externally (change a chip name), save → Settings list and chat bar update within 1 second
5. `make feedback` passes
