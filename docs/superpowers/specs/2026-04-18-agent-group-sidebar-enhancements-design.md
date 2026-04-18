# Agent & Group Sidebar Enhancements — Design Spec

**Date:** 2026-04-18  
**Status:** Approved for implementation

---

## Context

The sidebar's conversation/thread context menus are rich (rename, pin, archive, duplicate, mark read, close, delete). Agent and group context menus are sparse by comparison — agents have only 3 items, groups have 5. There's also no way to hide rarely-used agents from the sidebar without deleting them, and no way to browse an agent's conversation history inline.

This spec covers two problems:
1. **Organization:** Too many agents/groups with no way to control sidebar visibility
2. **Session-focused sidebar menus:** Sidebar context menus should be scoped to session/chat actions only — CRUD operations (duplicate, delete, open config, open in finder) belong in Configuration settings, not the sidebar

---

## Design

### 1. Data Model Changes

**`Agent` model** (`Odyssey/Models/Agent.swift`):
- Add `var showInSidebar: Bool = true`
- `isResident` agents always show regardless of `showInSidebar` (resident = pinned to top; the hide toggle only applies to non-resident agents)

**`AgentGroup` model** (`Odyssey/Models/AgentGroup.swift`):
- Add `var showInSidebar: Bool = true`

No changes to `Conversation`, `Session`, or any other model.

---

### 2. Sidebar Agent/Group Visibility

**File:** `Odyssey/Views/MainWindow/SidebarView.swift`

- In the agents section, filter out agents where `!agent.showInSidebar && !agent.isResident`
- In the groups section, filter out groups where `!group.showInSidebar`
- Each visible agent/group row shows a thread count hint (e.g. "7 threads") on the trailing edge
- At the bottom of the Agents section (and Groups section), if any items are hidden, show a muted hint: **"N hidden · manage →"** that navigates to the Configuration settings tab. This is the only path to re-show a hidden agent/group.

---

### 3. Inline Session History Expansion

**State:** Add `expandedAgentIds: Set<UUID>` and `expandedGroupIds: Set<UUID>` to `AppState` (UI state only, not persisted).

**Trigger:** Clicking the agent/group row chevron (▶/▼) or selecting "View Session History" from the context menu toggles the expanded state.

**Thread query:** Fetch `Conversation` records where any `session` in `Conversation.sessions` has `session.agent?.id == agentId` (for agents) or `session.agent?.id` matches any member of `group.agentIds` (for groups). Sort by `startedAt` descending, limit 8.

**Inline row layout:**
- Colored status dot (accent = active, gray = closed/archived)
- Thread name, truncated to one line
- Relative timestamp (right-aligned, e.g. "2h", "3d", "1w")
- Right-click (context menu) on each inline thread row: **Open Thread**, **Archive**, **Delete…**
- Below the last thread: `+ New Session` shortcut link
- If the agent has more than 8 threads: `Show all N threads →` hint that removes the 8-thread cap and renders the full list inline (drops the `.prefix(8)` limit — no new view)

---

### 4. Updated Agent Context Menu

**File:** `Odyssey/Views/MainWindow/SidebarView.swift` — agent context menu block

Sidebar context menus are session-focused only. CRUD actions (duplicate, delete, open config, open in finder) are removed — they live in Configuration settings.

```
💬 New Session
📂 New Thread in Project…       ← NEW
─────────────────────────
📜 View Session History         ← NEW (toggles inline expansion)
─────────────────────────
📌 Pin / Unpin
👁 Hide from Sidebar            ← NEW (label flips to "Show in Sidebar" when hidden — but re-show is done in Configuration)
─────────────────────────
🕐 Schedule Mission…            ← NEW
```

**"New Thread in Project…"**: Renders as a SwiftUI submenu listing available projects by name. Selecting a project calls the existing `createConversation(in:)` flow with the agent pre-set as participant.

**"View Session History"**: Inserts the agent's UUID into `AppState.expandedAgentIds` (or removes it if already present).

**"Hide from Sidebar"**: Sets `agent.showInSidebar = false`, saves `modelContext`. Agent disappears from sidebar immediately. To re-show: Configuration settings → agent row → toggle "Show in Sidebar".

**"Schedule Mission…"**: Opens `ScheduleEditorView` as a sheet with `targetAgentId` pre-filled.

---

### 5. Updated Group Context Menu

**File:** `Odyssey/Views/MainWindow/SidebarView.swift` — group context menu block

Same principle — CRUD moves to Configuration settings. "Edit" is retained as a quick shortcut since groups have no dedicated settings row equivalent.

```
💬 Start Chat
📂 New Thread in Project…       ← NEW
─────────────────────────
📜 View Session History         ← NEW
─────────────────────────
👁 Hide from Sidebar            ← NEW
─────────────────────────
🕐 Schedule Mission…            ← NEW
─────────────────────────
✏️ Edit
```

Removed from group sidebar menu: Duplicate, Open Configuration, Delete — all accessible in Configuration settings.

---

### 6. Configuration Settings — Show in Sidebar Toggle

**File:** `Odyssey/Views/Settings/ConfigurationDetailView.swift`

Add a **"Show in Sidebar"** `Toggle` to both the agent and group detail editor views. This is the authoritative place to:
- Re-show an agent/group that was hidden from the sidebar
- See and manage all agents/groups including hidden ones (the Configuration list shows everything regardless of `showInSidebar`)

The toggle should appear in the "General" or top section of the editor, near `isEnabled` and `isResident`, since it controls visibility rather than behavior.

**File:** `Odyssey/Views/Settings/ConfigurationSettingsTab.swift`

The agent/group list in this tab already shows all items. No changes needed to the list itself — hidden items are naturally visible here.

---

### 7. Accessibility Identifiers

New identifiers to add (following dot-separated camelCase convention from CLAUDE.md):

| Element | Identifier |
|---|---|
| Inline thread row | `sidebar.agentThreadRow.\(conversation.id.uuidString)` |
| Inline "New Session" link | `sidebar.agentNewSessionLink.\(agent.id.uuidString)` |
| Inline "Show all" link | `sidebar.agentShowAllThreads.\(agent.id.uuidString)` |
| Agent expand/collapse chevron | `sidebar.agentExpandButton.\(agent.id.uuidString)` |
| Group expand/collapse chevron | `sidebar.groupExpandButton.\(group.id.uuidString)` |
| "N hidden · manage →" hint (agents) | `sidebar.agentsHiddenHint` |
| "N hidden · manage →" hint (groups) | `sidebar.groupsHiddenHint` |
| Show in Sidebar toggle (agent editor) | `configDetail.showInSidebarToggle` |
| Show in Sidebar toggle (group editor) | `configDetail.groupShowInSidebarToggle` |

---

### 8. Conversation/Thread Context Menu — Remove Duplicate

**File:** `Odyssey/Views/MainWindow/SidebarView.swift` — `conversationMenuContent()` function

Remove the **Duplicate** item from the conversation context menu. This applies to all thread rows — project threads, agent session threads, group session threads, and inline expansion rows.

Updated menu:

```text
✏️  Rename
📌  Pin / Unpin
📬  Mark as Read / Unread
📂  Open Project Folder     (only if thread is in a project)
⏹   Close Session           (only if status is active)
📦  Archive / Unarchive
🗑  Delete…
```

Swipe actions (Archive, Delete, Pin/Unpin) are unchanged.

---

## Verification

1. **Model defaults**: `Agent.showInSidebar` and `AgentGroup.showInSidebar` default to `true`. Toggling persists via `ModelContext`.
2. **Hide from sidebar**: Right-click agent → Hide → agent disappears from sidebar immediately. Resident agents unaffected.
3. **Re-show via Configuration**: Configuration settings → agent → "Show in Sidebar" toggle → agent reappears in sidebar.
4. **"N hidden" hint**: Appears only when ≥1 agent is hidden; tapping navigates to Configuration settings.
5. **Inline expansion**: Expand an agent → threads render with correct status dots, names, timestamps.
6. **Thread actions**: Right-click inline thread → Archive → `isArchived` toggled; Delete → removed from list.
7. **New menu items**: New Thread in Project submenu lists projects; selecting creates conversation. Schedule Mission opens editor pre-filled.
8. **AppXray**: `@testId("sidebar.agentExpandButton.<uuid>")` → expand → assert `@testId("sidebar.agentThreadRow.<uuid>")` visible.
