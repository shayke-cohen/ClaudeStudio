# Chat Header Redesign — Design Spec

**Date:** 2026-04-18
**Status:** Approved

## Problem

The current chat header fails to answer the most basic question: "who am I talking to?" Instead it shows:

1. Window title `Odyssey — Playground` — redundant app name, wrong context label
2. Conversation topic (auto-named from first message "hi") as the header title
3. `Mention-Aware — no coordinator, so sending…` routing jargon as subtitle
4. Raw skill ID chips (`agent-identity`, `blackboard-patterns`, …) in the header
5. `No mission yet | Add mission | Schedule` empty-state row always visible
6. Three competing mode controls (`Interactive`, `Auto-Answer ▾`, `Session ▾`)

## Design — Option A: Group Identity First

### Window Title

Format: `ProjectName / AgentOrGroupName`

- Project name: dim grey (`#888`)
- Agent/group name: bold white (`#ccc`, `font-weight: 500`)
- Separator: `/` in mid-grey
- No project (Playground or unassigned): just `AgentOrGroupName`, no prefix
- Never show `Odyssey —` prefix — the app is always Odyssey

**Implementation:** `WindowTitleSetter` in `MainWindowView.swift` — change title format from `"Odyssey — \(projectName)"` to `"ProjectName / GroupOrAgentName"` using an `NSAttributedString` for the dimmed project portion, or plain `"GroupName"` when no project.

### Header Row 1 (always present, fixed height)

Left → right:

| Element | Detail |
|---|---|
| Avatar | 32×32pt rounded rect (10pt radius), gradient background, emoji/initials |
| Name | 13pt semibold, `#eee` |
| Type badge | `GROUP` or `AGENT`, 9pt bold uppercase, dim blue-grey pill |
| Member subtitle | 11pt, `#666` — member names with 5×5pt status dots (grey=idle, green=running) |
| Segmented control | `Interactive / Auto` — 2-segment pill, replaces 3-button cluster |
| `⋯` menu | Holds: skills, MCPs, routing info, fork, rename, cost, set mission |

Row height: fixed ~54pt. Never reflows.

### Mission Row (conditional)

**When no mission is set:** Subtle dashed `⊕ Add mission` link below row 1.
- Low contrast (border: `1px dashed #333`, text: `#444`)
- On hover: border turns blue, text turns `#7ea8f0`
- Tapping opens mission editor

**When a mission is set:** Dashed link replaced by a green-tinted bar.
- Icon `🎯`, mission text (11pt, `#80b080`), `Edit` button
- Background: `#1a2a1a`, border: `#2a4a2a`
- Clearing the mission returns to the dashed link state

**Never show:** "No mission yet" as a label, "Schedule" as a standalone header action, or a persistent empty banner.

### Removed from Header

| Removed | Moved to |
|---|---|
| `Odyssey —` window prefix | Gone |
| Conversation topic as title | Gone (title bar shows identity, not thread name) |
| `Mention-Aware — no coordinator…` subtitle | `⋯` menu (advanced info) |
| Skill ID chips | `⋯` menu |
| MCP chips | `⋯` menu |
| `No mission yet` banner | Gone |
| `Session ▾` button | Merged into `⋯` |
| `Auto-Answer ▾` button | Merged into `Interactive / Auto` segmented control |

### 1:1 Agent Chats

Same layout. No member pills in the subtitle — just the agent's current status (`● Running` / `● Idle`) as a single status line.

## Files to Change

| File | Change |
|---|---|
| `Odyssey/Views/MainWindow/MainWindowView.swift` | `WindowTitleSetter`: new title format |
| `Odyssey/Views/MainWindow/ChatView.swift` | `simplifiedChatHeader`: new layout; `headerChips`: move to `⋯` sheet; `sendingToSubtitle`: remove from header; `simplifiedMissionSection`: conditional dashed link vs active bar |

## Out of Scope

- Conversation rename / topic editing (separate feature)
- `⋯` menu contents redesign (layout only changes here)
- Sidebar thread list titles (unchanged)
