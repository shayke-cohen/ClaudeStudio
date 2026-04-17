# Thread Creation Redesign — Spec

**Date:** 2026-04-17
**Status:** Approved

## Context

The current thread creation flow presents an 860×720 modal with three tabs (Blank / Agents / Groups), full agent lists, model/provider overrides, and a separate Quick Chat concept. The goal is to replace this with a lean, keyboard-friendly popover that gets out of the way — click an agent, thread opens. No tabs, no modal, no overrides up front.

## Menu Changes

The sidebar "+ New" dropdown collapses from three items to two:

| Before              | After                    |
| ------------------- | ------------------------ |
| New Thread (⌘N)     | Chat with Agent (⌘N)     |
| Group Thread (⌘⌥N)  | Chat with Group (⌘⌥N)    |
| Quick Chat (⌘⇧N)    | *(removed — see below)*  |

⌘⇧N still works: it opens the agent popover with "No specialized agent" auto-focused.

**Files to change:**

- `Odyssey/Views/MainWindow/SidebarView.swift` — menu button labels and actions

## Quick Chat Replacement

Quick Chat is absorbed into the agent popover as a pinned "No specialized agent" row (∅ icon, dashed border) at the top of the list, above recent agents. Clicking it opens a blank thread immediately — same behavior as the old Quick Chat, but discoverable within the agent flow rather than a separate concept.

No new model or ViewModel changes needed — this still calls the existing `createBlankThread()` path.

## Agent Popover — "Chat with Agent"

Triggered by: ⌘N, clicking "Chat with Agent" in the menu.
Anchors to: the "+ New" button in the sidebar.
Width: ~260px. Height: auto (fits content).

### Structure (top to bottom)

1. **Search bar** — filters agent list in real time. Placeholder: "Search agents…"
2. **"No specialized agent" row** — pinned, always first, dashed border, ∅ icon. Opens blank thread on click/↵.
3. **Recent section** — horizontal pills for the last 2–3 agents used. Click pill = open thread immediately.
4. **All Agents list** — name + model subtitle. Highlighted row = keyboard focus. ↵ opens thread.
5. **Footer** — left: "Click to start" hint. Right: "⌘↵ add mission" hint.

### Mission field (on-demand)

Default state: hidden. Triggered by ⌘↵ (or ⌘↵ while an agent is highlighted).

When triggered:

- A mission section slides in between the search bar and the "No specialized agent" row.
- Purple-tinted background (`#130e1f`), purple border, `#c4b5fd` text.
- Label: "MISSION" in small uppercase purple.
- Multiline text field, auto-focused.
- ↵ on an agent row (while mission field has text) = start thread with that mission.
- Esc = collapses mission field back, returns focus to agent list.
- ⌘↵ shortcut hint updates to "⌘↵ hide mission" while expanded.

### Keyboard behavior

| Key    | Action                            |
| ------ | --------------------------------- |
| ↑ / ↓  | Move focus through agent list     |
| ↵      | Open thread with focused agent    |
| ⌘↵     | Toggle mission field              |
| Type   | Filters list (focuses search bar) |
| Esc    | Dismiss popover                   |

## Group Popover — "Chat with Group"

Same structural pattern as the agent popover. No "No specialized agent" row (groups always have members).

### Structure

1. **Search bar** — "Search groups…"
2. **Recent section** — horizontal pills (group name + emoji icon).
3. **All Groups list** — group name + row of colored member-agent squares + agent count. ↵ opens thread.
4. **Footer** — "Click to start" · "⌘↵ add mission"

Mission field behavior is identical to the agent popover.

## Prompt Templates — Empty State Chips in ChatView

Templates are not shown in the popover. Instead they surface inside the thread as part of the empty state.

### How it works

When a thread is newly opened and has no messages yet, `ChatView` renders template chips in the center of the empty chat area:

- Agent thread: shows templates linked to that agent (`PromptTemplate.agent == session.agent`)
- Group thread: shows templates linked to that group (`PromptTemplate.group == conversation.group`)
- Blank thread ("No specialized agent"): no chips shown — empty state is just the input

Up to 4 chips shown inline; if more exist, a `+N` overflow chip opens a small popover listing the rest.

Clicking a chip fills the input bar with `template.prompt` (does not auto-send). The user can edit before sending.

Chips disappear permanently once the first message is sent (`conversation.messages.isEmpty` gate). No ongoing UI footprint after that.

**Files to change:**

- `Odyssey/Views/MainWindow/ChatView.swift` — add empty state view with template chips
- `TemplatePickerRow` (currently in `NewSessionSheet.swift`) is removed from the creation flow; `TemplatesSettingsTab.swift` and `PromptTemplate` model are unchanged.

## What Is Removed

- `NewGroupThreadSheet.swift` — replaced entirely by the group popover.
- `NewSessionSheet.swift` — replaced entirely by the agent popover. The Blank / Agents / Groups tabs, model/provider override pickers, execution mode selector, session mode selector, and `TemplatePickerRow` are all removed from this entry point.
- The `showNewSessionSheet` and `showNewGroupThreadSheet` state flags in `WindowState.swift` — replaced with popover presentation state.

## State & Navigation

`WindowState` gains two new flags:

```swift
var showAgentPopover: Bool = false
var showGroupPopover: Bool = false
```

The existing `selectedConversationId` assignment on thread creation is unchanged.

Thread creation still delegates to the existing `AppState` methods:

- Blank thread → `createBlankThread()`
- Agent thread → `createAgentThread(agents:mission:)`
- Group thread → `startGroupChat(group:mission:)`

No SwiftData model changes required.

## Popover Presentation

Use SwiftUI `.popover(isPresented:)` anchored to the "+ New" button. On macOS this renders as a native arrow popover. The popover should dismiss on click-outside and on Esc.

## Verification

1. ⌘N opens agent popover anchored to the sidebar button.
2. Clicking an agent immediately creates a thread and opens ChatView — no intermediate step.
3. Clicking "No specialized agent" opens a blank thread (same as old Quick Chat).
4. ⌘↵ in the agent popover reveals the mission field; ↵ on an agent row starts the thread with that mission.
5. ⌘⌥N opens the group popover; clicking a group starts the thread immediately.
6. ⌘⇧N opens the agent popover with "No specialized agent" row highlighted.
7. The old NewSessionSheet and NewGroupThreadSheet no longer appear from these entry points.
8. Template chips appear in the empty chat area for agent/group threads; clicking one fills the input bar.
9. Existing threads, SwiftData records, and in-thread options are unaffected.
