# Config Delete & Duplicate — Design Spec

**Date:** 2026-04-20  
**Scope:** Agents and groups in the Configuration settings tab

---

## Overview

Add **Delete** (with confirmation) and **Duplicate** actions to agents and groups in `ConfigurationSettingsTab`. Actions are surfaced in two places: the hero header of the detail pane, and a right-click context menu on list rows.

---

## Architecture

`ConfigurationSettingsTab` owns all SwiftData mutations and selection state. It gains:

- `@State private var itemPendingDelete: ConfigSelectedItem?` — set when delete is triggered, drives the confirmation dialog
- `private func deleteItem(_ item: ConfigSelectedItem)` — cascades deletes, clears `selectedItem`
- `private func duplicateItem(_ item: ConfigSelectedItem) -> ConfigSelectedItem?` — copies all fields, inserts new item, returns it for selection

`ConfigurationDetailView` gains two new callbacks:
- `onDelete: (() -> Void)?` — called when the Delete hero button is tapped; nil for non-agent/group items (hides button)
- `onDuplicate: (() -> Void)?` — called when the Duplicate hero button is tapped; nil for non-agent/group items (hides button)

The tab passes these closures when constructing `ConfigurationDetailView`, setting `itemPendingDelete` (for delete) or calling `duplicateItem` and updating `selectedItem` (for duplicate).

---

## UI Changes

### Hero Header (detail pane)

For agents and groups only, two additional buttons appear after "Edit":

```
[ Reveal ]  [ Edit ]  [ Duplicate ]  [ Delete ]
```

- All use `HeroButtonStyle` (white ghost on gradient background)
- "Delete" button: same style but label text is rendered in a red-tinted white (`Color.red.opacity(0.85)`) to signal destructive intent
- Hero buttons are hidden for skills, MCPs, and permissions (no `onDelete`/`onDuplicate` callbacks passed)

### Context Menu (list rows)

Right-click on any agent or group row in the middle list pane:

```
Edit
Duplicate
─────────
Delete    ← .destructive role
```

No context menu changes to skills, MCPs, or permissions rows.

### Delete Confirmation

`confirmationDialog` attached to `ConfigurationSettingsTab`:
- **Title:** "Delete \(itemName)?"
- **Message:** "This action cannot be undone."
- **Buttons:** "Delete" (`.destructive`) · "Cancel"
- Triggered by both the hero button and the context menu item

---

## Delete Behavior

Mirrors the cascade already used in `AgentLibraryView` and `GroupDetailView`:

**Agent:**
```swift
for session in (agent.sessions ?? []) { modelContext.delete(session) }
for template in (agent.promptTemplates ?? []) { modelContext.delete(template) }
modelContext.delete(agent)
try? modelContext.save()
selectedItem = nil
```

**Group:**
```swift
for template in (group.promptTemplates ?? []) { modelContext.delete(template) }
modelContext.delete(group)
try? modelContext.save()
selectedItem = nil
```

The config file watcher detects the missing directory on next sync and soft-disables — no manual file cleanup is needed.

---

## Duplicate Behavior

Mirrors the copy logic already in `AgentLibraryView.duplicateAgent` and `GroupDetailView.duplicateGroup`:

- All fields copied; `configSlug` left `nil` so the sync service generates a fresh slug
- Name becomes `"\(original.name) Copy"`
- `isResident`, `showInSidebar`, `originKind` etc. are copied as-is
- After insert + save: `selectedItem` is set to the new `.agent(copy)` / `.group(copy)`, auto-selecting it in the list

---

## Accessibility Identifiers

| Element | Identifier |
|---|---|
| Hero Duplicate button | `settings.configuration.heroDuplicateButton` |
| Hero Delete button | `settings.configuration.heroDeleteButton` |

Context menu items use SwiftUI's default accessibility for `.contextMenu` buttons.

---

## Out of Scope

- Delete/duplicate for Skills, MCPs, Permissions (not requested)
- Undo support
- Bulk delete/duplicate
