# Schedule Run History — Navigate to Conversation

**Date:** 2026-04-18  
**Status:** Approved

## Problem

Clicking a run history item in `ScheduleDetailView` sets `windowState.selectedConversationId` but leaves the schedule library sheet open, doesn't select the right project, and doesn't expand the owning agent/group tree in the sidebar. The conversation is selected but invisible.

## Goal

Clicking any run history row (including in the "View all" sheet) should:
1. Dismiss the schedule library sheet
2. Switch to the conversation's project
3. Expand the owning agent or group in the sidebar
4. If the conversation is archived, also expand that agent/group's Archived subfolder
5. Select and scroll to the conversation

## Approach: Signal via `WindowState` (`sidebarRevealConversationId`)

Matches the existing `inspectorFileSelectionRequest` pattern. Sidebar expansion logic stays inside `SidebarView`; callers just fire a signal.

---

## Changes

### 1. `WindowState` — add signal + helper

```swift
var sidebarRevealConversationId: UUID? = nil

func navigateToConversation(_ conversationId: UUID, projectId: UUID?) {
    if let projectId { selectProject(id: projectId, preserveSelection: true) }
    selectedConversationId = conversationId
    sidebarRevealConversationId = conversationId
    showScheduleLibrary = false
}
```

`selectedConversationId` is set first so the chat opens immediately.  
`sidebarRevealConversationId` is the separate signal for sidebar expansion.

### 2. `AgentSidebarRowView` — lift `isArchivedExpanded` to a binding

Replace:
```swift
@State private var isArchivedExpanded = false
```
With:
```swift
var isArchivedExpanded: Binding<Bool>
```

Update all usages of `isArchivedExpanded` → `isArchivedExpanded.wrappedValue` (or use `$isArchivedExpanded` → `isArchivedExpanded`).

### 3. `GroupSidebarRowView` — same as above

Replace `@State private var isArchivedExpanded = false` with `var isArchivedExpanded: Binding<Bool>`.

### 4. `SidebarView` — add archived expansion state + reveal logic

Add two new state sets:
```swift
@State private var expandedArchivedAgentIds: Set<UUID> = []
@State private var expandedArchivedGroupIds: Set<UUID> = []
```

Pass bindings into each row call site:
```swift
// agentSidebarRow
isArchivedExpanded: Binding(
    get: { expandedArchivedAgentIds.contains(agent.id) },
    set: { if $0 { expandedArchivedAgentIds.insert(agent.id) } else { expandedArchivedAgentIds.remove(agent.id) } }
)

// groupSidebarRow
isArchivedExpanded: Binding(
    get: { expandedArchivedGroupIds.contains(group.id) },
    set: { if $0 { expandedArchivedGroupIds.insert(group.id) } else { expandedArchivedGroupIds.remove(group.id) } }
)
```

Add `onChange` on the sidebar body:
```swift
.onChange(of: windowState.sidebarRevealConversationId) { _, convId in
    guard let convId else { return }
    expandForReveal(convId)
    windowState.sidebarRevealConversationId = nil
}
```

Add `expandForReveal(_:)` private helper:
```swift
private func expandForReveal(_ conversationId: UUID) {
    guard let convo = conversations.first(where: { $0.id == conversationId }) else { return }
    let isArchived = convo.isArchived

    if let groupId = convo.sourceGroupId {
        expandedGroupIds.insert(groupId)
        if isArchived { expandedArchivedGroupIds.insert(groupId) }
        return
    }

    for agent in agents {
        let inActive = conversationsForAgent(agent).contains { $0.id == conversationId }
        let inArchived = archivedConversationsForAgent(agent).contains { $0.id == conversationId }
        if inActive || inArchived {
            expandedAgentIds.insert(agent.id)
            if inArchived { expandedArchivedAgentIds.insert(agent.id) }
            return
        }
    }
}
```

### 5. `ScheduleDetailView` — use `navigateToConversation`

In `runRow()`, replace:
```swift
windowState.selectedConversationId = convoId
```
With:
```swift
let convo = conversations.first { $0.id == convoId }
windowState.navigateToConversation(convoId, projectId: convo?.projectId)
```

In `historyCard()`, the `ScheduleRunListSheet` closure currently just sets `selectedConversationId` and dismisses the all-runs sheet. Replace with `navigateToConversation` (the schedule library dismiss is handled inside the method):
```swift
ScheduleRunListSheet(runs: scheduleRuns) { convoId in
    let convo = conversations.first { $0.id == convoId }
    windowState.navigateToConversation(convoId, projectId: convo?.projectId)
    showingAllRuns = false
}
```

### 6. `ScheduleHistorySheet` — use `navigateToConversation`

Replace the existing `onSelect` closure body with:
```swift
windowState.navigateToConversation(convoId, projectId: convo?.projectId)
dismiss()
```

---

## Files Changed

| File | Change |
|------|--------|
| `Odyssey/App/WindowState.swift` | Add `sidebarRevealConversationId`, `navigateToConversation()` |
| `Odyssey/Views/MainWindow/AgentSidebarRowView.swift` | `isArchivedExpanded` → binding |
| `Odyssey/Views/GroupLibrary/GroupSidebarRowView.swift` | `isArchivedExpanded` → binding |
| `Odyssey/Views/MainWindow/SidebarView.swift` | Add archived sets, pass bindings, `onChange` + `expandForReveal` |
| `Odyssey/Views/Schedules/ScheduleDetailView.swift` | Use `navigateToConversation` in `runRow` + `historyCard` + `ScheduleHistorySheet` |

## Out of Scope

- Scrolling within the chat view to the first message (the existing scroll-to-bottom on selection handles this)
- Handling conversations not belonging to any agent/group (e.g. project-direct threads) — those are selected but no tree expansion is needed
