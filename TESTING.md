# Odyssey — Testing Guide

This document covers how to test Odyssey across all three testing layers, provides a complete inventory of every screen and interactive control with its accessibility identifier, and explains how to target elements in AppXray and Argus automation.

---

## Table of Contents

1. [Testing Overview](#1-testing-overview)
2. [XCTest (Unit / Integration)](#2-xctest-unit--integration)
3. [AppXray Setup (Inside-Out Testing)](#3-appxray-setup-inside-out-testing)
4. [AppXray Selector Syntax](#4-appxray-selector-syntax)
5. [Screen-by-Screen Control Reference](#5-screen-by-screen-control-reference)
6. [Reusable Components](#6-reusable-components)
7. [Argus macOS Testing (Outside-In E2E)](#7-argus-macos-testing-outside-in-e2e)
8. [Dynamic Identifiers](#8-dynamic-identifiers)
9. [Naming Convention](#9-naming-convention)
10. [Known Gaps](#10-known-gaps)

---

## 1. Testing Overview

Odyssey uses three complementary testing layers:

| Layer | Tool | Scope | When to Use |
|-------|------|-------|-------------|
| **Unit / Integration** | XCTest | Models, services, protocol encoding, catalog logic | After changing Swift models, services, or protocol types |
| **Inside-out** | AppXray MCP | Live app state, component tree, network, storage, chaos injection | Debugging in a running DEBUG build — inspect state, trace renders, mock network |
| **Outside-in E2E** | Argus MCP | Full macOS app automation — screenshot, tap, type, assert | End-to-end flows, regression tests, visual regression, CI automation |

**AppXray** requires the AppXray SDK embedded in the app (DEBUG only). It connects via WebSocket and gives you deep access to internal state, component trees, and network traffic.

**Argus** drives the app externally by app name — no SDK required. It takes screenshots, reads the accessibility tree, and simulates user interactions. Best for E2E and regression testing.

---

## 2. XCTest (Unit / Integration)

### Existing Test Files

All tests live in `OdysseyTests/`:

| File | What It Tests |
|------|---------------|
| `AppStateEventTests.swift` | AppState event handling from sidecar events |
| `CatalogModelTests.swift` | Catalog data model encoding/decoding |
| `CatalogServiceTests.swift` | Catalog fetch, install, uninstall logic |
| `FileExplorerIntegrationTests.swift` | File explorer tree loading and filtering |
| `FileNodeTests.swift` | FileNode model, sorting, git status |
| `FileSystemServiceTests.swift` | File reading, directory listing, metadata |
| `GitServiceTests.swift` | Git status, diff, changed files detection |
| `InstanceConfigTests.swift` | Agent instance configuration resolution |
| `SidecarProtocolTests.swift` | Wire protocol encode/decode for commands and events |
| `GroupPromptBuilderTests.swift` | Group chat transcript injection, peer-notify prompts, @-mention highlights, `GroupPeerFanOutContext` budget/dedup |

### Running Tests

From Xcode:
```
Product > Test (Cmd+U)
```

From the command line:
```bash
xcodebuild test \
  -project Odyssey.xcodeproj \
  -scheme Odyssey \
  -destination 'platform=macOS'
```

### Sidecar Tests

The TypeScript sidecar has its own test suite:

```bash
cd sidecar
bun run start &   # tests require a running sidecar
bun test
```

Test files in `sidecar/test/`:
- `unit/stores.test.ts` — blackboard and session registry
- `integration/peerbus-tools.test.ts` — PeerBus tool handlers
- `api/ws-protocol.test.ts` — WebSocket protocol conformance
- `e2e/full-flow.test.ts` — end-to-end session lifecycle
- `e2e/scenarios.test.ts` — multi-session scenarios (includes **GC-1** group transcript chain and **GC-2** peer-notify prompt shape; live sidecar + API key)
- `e2e/backend-live.test.ts` — focused live backend regressions for native Claude and Ollama-backed Claude
- `e2e/connector-live.test.ts` — live connector/provider smoke tests (env-gated; WhatsApp read smoke supported, write smoke opt-in)

### Live backend regression smokes

Run the focused native Claude regression:

```bash
ODYSSEY_E2E_CLAUDE=1 \
bun test sidecar/test/e2e/backend-live.test.ts
```

Optional model override:

```bash
ODYSSEY_E2E_CLAUDE=1 \
ODYSSEY_E2E_CLAUDE_MODEL=claude-sonnet-4-6 \
bun test sidecar/test/e2e/backend-live.test.ts
```

Run the focused Ollama-backed Claude regression against a real local daemon:

```bash
ODYSSEY_E2E_OLLAMA=1 \
ODYSSEY_OLLAMA_BASE_URL=http://127.0.0.1:11434 \
bun test sidecar/test/e2e/backend-live.test.ts
```

Optional explicit local model selection:

```bash
ODYSSEY_E2E_OLLAMA=1 \
ODYSSEY_OLLAMA_BASE_URL=http://127.0.0.1:11434 \
ODYSSEY_E2E_OLLAMA_MODEL=qwen3-coder:latest \
bun test sidecar/test/e2e/backend-live.test.ts
```

If `ODYSSEY_E2E_OLLAMA_MODEL` is omitted, the suite discovers installed models from `GET /api/tags` and uses the first returned tag.

### Live Connector Smoke

Run the WhatsApp live smoke in read-only mode:

```bash
ODYSSEY_CONNECTOR_LIVE=1 \
WHATSAPP_ACCESS_TOKEN=... \
WHATSAPP_WABA_ID=... \
bun test sidecar/test/e2e/connector-live.test.ts
```

Optional write smoke, only when you intentionally want to send a real template:

```bash
ODYSSEY_CONNECTOR_LIVE=1 \
ODYSSEY_CONNECTOR_LIVE_WRITE=1 \
WHATSAPP_ACCESS_TOKEN=... \
WHATSAPP_WABA_ID=... \
WHATSAPP_PHONE_NUMBER_ID=... \
WHATSAPP_TEMPLATE_NAME=... \
WHATSAPP_TO=... \
bun test sidecar/test/e2e/connector-live.test.ts
```

---

## 3. AppXray Setup (Inside-Out Testing)

### Architecture

```
Odyssey (DEBUG, server mode on 19480) ──WebSocket──> AppXray MCP/CLI relay (default 127.0.0.1:19400) <──stdio── AI Agent
```

### Prerequisites

1. The AppXray SDK is integrated as a local SPM package at `Dependencies/appxray/packages/sdk-ios` (DEBUG builds only).
2. The AppXray MCP server must be configured in Cursor's MCP settings.
3. The relay starts automatically with the MCP server.
4. Odyssey's DEBUG build pins AppXray server mode to port `19480` to avoid the relay's default `19400` port.

### Connecting

```javascript
// 1. Discover running AppXray-enabled apps
session({ action: "discover" })

// 2. Connect to Odyssey
session({ action: "connect", appId: "com.odyssey.app" })
```

### Available AppXray Tools

| Tool | Purpose |
|------|---------|
| `session` | Discover apps, connect/disconnect, list sessions |
| `inspect` | Read-only: component tree, state, network, storage, routes, errors, logs, accessibility |
| `act` | Mutate state, trigger navigation |
| `interact` | UI automation: find, tap, type, swipe, wait, fillForm, screenshot |
| `diagnose` | One-shot health scans (quick/standard/deep) |
| `suggest` | Pattern-based root-cause hypotheses |
| `trace` | Render/state/data-flow tracing |
| `diff` | Baseline snapshots and compare |
| `mock` | Network mocks and overrides |
| `config` | Feature flags and environment config |
| `timetravel` | Checkpoints, restore, history |
| `chaos` | Inject failures (network errors, slow responses, crashes) |
| `batch` | Multiple operations in one call |
| `advanced` | eval, coverage, event subscribe, storage writes |
| `report` | File bugs/features as GitHub issues |

---

## 4. AppXray Selector Syntax

AppXray uses a universal selector syntax to target elements:

| Selector | Swift Equivalent | Example |
|----------|-----------------|---------|
| `@testId("chat.sendButton")` | `.accessibilityIdentifier("chat.sendButton")` | Target by identifier |
| `@label("Send message")` | `.accessibilityLabel("Send message")` | Target by label |
| `@text("Login")` | Visible text content | Target by displayed text |
| `@type("Button")` | SwiftUI component type | Target by type |
| `@placeholder("Enter email")` | Placeholder text | Target by placeholder |
| `@index(2, @type("Button"))` | N/A | Nth match of a selector |

### Examples

```javascript
// Tap the send button by testId
interact({ action: "tap", selector: '@testId("chat.sendButton")' })

// Type into the message input
interact({ action: "type", selector: '@testId("chat.messageInput")', text: "Hello" })

// Find by accessibility label (icon-only buttons)
interact({ action: "tap", selector: '@label("Send message")' })

// Combine type + index
interact({ action: "tap", selector: '@index(0, @type("Button"))' })
```

---

## 5. Screen-by-Screen Control Reference

Each table lists every interactive control, its `accessibilityIdentifier`, its `accessibilityLabel` (if set), and the AppXray selector to target it.

### 5.1 MainWindowView

**File:** `Views/MainWindow/MainWindowView.swift`
**Navigation:** Root window. Contains `SidebarView` (leading), `ChatView` (detail), `InspectorView` (trailing).

| Control | Identifier | Label | Selector |
|---------|-----------|-------|----------|
| No-conversation placeholder | `mainWindow.noConversationPlaceholder` | — | `@testId("mainWindow.noConversationPlaceholder")` |
| Inspector placeholder | `mainWindow.inspectorPlaceholder` | — | `@testId("mainWindow.inspectorPlaceholder")` |
| Toolbar: Workspace menu | `mainWindow.workspaceMenu` | `Workspace` | `@testId("mainWindow.workspaceMenu")` |
| Toolbar: Inspector toggle | `mainWindow.inspectorToggle` | — | `@testId("mainWindow.inspectorToggle")` |
| Sidecar status pill | `mainWindow.sidecarStatusPill` | `Sidecar {status}` | `@testId("mainWindow.sidecarStatusPill")` |
| Status popover | `mainWindow.statusPopover` | — | `@testId("mainWindow.statusPopover")` |
| Popover: Reconnect | `mainWindow.statusPopover.reconnectButton` | — | `@testId("mainWindow.statusPopover.reconnectButton")` |
| Popover: Stop | `mainWindow.statusPopover.stopButton` | — | `@testId("mainWindow.statusPopover.stopButton")` |
| Popover: Connect | `mainWindow.statusPopover.connectButton` | — | `@testId("mainWindow.statusPopover.connectButton")` |

Legacy comparison mode also exposes:
- `mainWindow.newSessionButton`
- `mainWindow.quickChatButton`
- `mainWindow.schedulesButton`
- `mainWindow.agentCommsButton`
- `mainWindow.peerNetworkButton`
- `mainWindow.newGroupThreadButton`

**Sheets opened from MainWindowView:**
- `NewSessionSheet` via `appState.showNewSessionSheet`
- `IntentLibraryHubView` via `windowState.showLibraryHub`
- `AgentCommsView` via `appState.showAgentComms`

---

### 5.2 SidebarView

**File:** `Views/MainWindow/SidebarView.swift`
**Access:** Left column of the project-first `NavigationSplitView`.

| Control | Identifier | Label | Selector |
|---------|-----------|-------|----------|
| Sidebar list | `sidebar.conversationList` | — | `@testId("sidebar.conversationList")` |
| Utility: New menu | `sidebar.utility.newMenu` | `New` | `@testId("sidebar.utility.newMenu")` |
| Utility: Library | `sidebar.utility.library` | — | `@testId("sidebar.utility.library")` |
| Utility: Add Project | `sidebar.utility.addProject` | — | `@testId("sidebar.utility.addProject")` |
| Project row | `sidebar.projectRow.{uuid}` | — | `@testId("sidebar.projectRow.{uuid}")` |
| Project tasks add | `sidebar.projectTasksAdd.{uuid}` | — | `@testId("sidebar.projectTasksAdd.{uuid}")` |
| Empty state: New Session | `sidebar.emptyState.newSessionButton` | — | `@testId("sidebar.emptyState.newSessionButton")` |
| Agent roster row | `sidebar.agentRow.{uuid}` | — | `@testId("sidebar.agentRow.{uuid}")` |
| Group roster row | `sidebar.groupRow.{uuid}` | — | `@testId("sidebar.groupRow.{uuid}")` |
| Thread row | `sidebar.conversationRow.{uuid}` | — | `@testId("sidebar.conversationRow.{uuid}")` |
| Archived threads section | `sidebar.archivedSection` | — | `@testId("sidebar.archivedSection")` |

The sidebar is now **project-first**: utilities live above projects, and each project disclosure contains Threads, Tasks, Team, and Schedules subsections. In legacy comparison mode, the utility section still exposes `sidebar.utility.newThread`; new tests should prefer `sidebar.utility.newMenu`.

**Context menu on thread rows** (Rename, Pin/Unpin, Close, Duplicate, Archive/Unarchive, Delete) and **swipe actions** do not have explicit identifiers.

---

### 5.3 ChatView

**File:** `Views/MainWindow/ChatView.swift`
**Access:** Detail column when a conversation is selected.

| Control | Identifier | Label | Selector |
|---------|-----------|-------|----------|
| Topic text (display) | `chat.topicTitle` | — | `@testId("chat.topicTitle")` |
| Topic text field (editing) | `chat.topicField` | — | `@testId("chat.topicField")` |
| Mission preview | `chat.missionPreview` | — | `@testId("chat.missionPreview")` |
| Mission card | `chat.missionCard` | — | `@testId("chat.missionCard")` |
| Mission editor | `chat.missionEditor` | — | `@testId("chat.missionEditor")` |
| Mission save | `chat.missionSaveButton` | — | `@testId("chat.missionSaveButton")` |
| Mission cancel | `chat.missionCancelButton` | — | `@testId("chat.missionCancelButton")` |
| Mission edit | `chat.missionEditButton` | — | `@testId("chat.missionEditButton")` |
| Mission add | `chat.missionAddButton` | — | `@testId("chat.missionAddButton")` |
| Mission expand/collapse | `chat.missionToggleButton` | — | `@testId("chat.missionToggleButton")` |
| Session menu | `chat.sessionMenu` | `Session menu` | `@testId("chat.sessionMenu")` |
| Tools menu | `chat.toolsMenu` | `Tools` | `@testId("chat.toolsMenu")` |
| Group settings menu | `chat.groupSettingsMenu` | `Group settings` | `@testId("chat.groupSettingsMenu")` |
| Agent icon button | `chat.agentIconButton` | `Open agent {name}` | `@testId("chat.agentIconButton")` |
| Default chat icon | `chat.chatIcon` | — | `@testId("chat.chatIcon")` |
| Stop button | `chat.stopButton` | `Stop agent` | `@testId("chat.stopButton")` |
| Resume button | `chat.resumeButton` | `Resume agent` | `@testId("chat.resumeButton")` |
| Menu: Close Conversation | `chat.moreOptions.closeConversation` | `Close conversation` | `@testId("chat.moreOptions.closeConversation")` |
| More options menu | `chat.moreOptionsMenu` | `More options` | `@testId("chat.moreOptionsMenu")` |
| Menu: Fork | `chat.moreOptions.fork` | — | `@testId("chat.moreOptions.fork")` |
| Menu: Rename | `chat.moreOptions.rename` | — | `@testId("chat.moreOptions.rename")` |
| Menu: Schedule This Mission | `chat.moreOptions.scheduleMission` | `Schedule This Mission` | `@testId("chat.moreOptions.scheduleMission")` |
| Menu: Duplicate | `chat.moreOptions.duplicate` | — | `@testId("chat.moreOptions.duplicate")` |
| Menu: Export (submenu) | `chat.exportSubmenu` | `Export chat` | `@testId("chat.exportSubmenu")` |
| Menu: Export Markdown | `chat.export.markdown` | — | `@testId("chat.export.markdown")` |
| Menu: Export HTML | `chat.export.html` | — | `@testId("chat.export.html")` |
| Menu: Export PDF | `chat.export.pdf` | — | `@testId("chat.export.pdf")` |
| Menu: Share (submenu) | `chat.shareSubmenu` | `Share chat` | `@testId("chat.shareSubmenu")` |
| Menu: Share Markdown | `chat.share.markdown` | — | `@testId("chat.share.markdown")` |
| Menu: Share HTML | `chat.share.html` | — | `@testId("chat.share.html")` |
| Menu: Share PDF | `chat.share.pdf` | — | `@testId("chat.share.pdf")` |
| Menu: Clear Messages | `chat.moreOptions.clearMessages` | — | `@testId("chat.moreOptions.clearMessages")` |
| Message scroll view | `chat.messageScrollView` | — | `@testId("chat.messageScrollView")` |
| Attach button | `chat.attachButton` | `Attach file` | `@testId("chat.attachButton")` |
| Message input | `chat.messageInput` | — | `@testId("chat.messageInput")` |
| Group “Sending to” hint | `chat.sendingToHint` | — | `@testId("chat.sendingToHint")` |
| Mention suggestion strip | `chat.mentionSuggestions` | — | `@testId("chat.mentionSuggestions")` |
| Mention suggestion row | `chat.mentionSuggestion.{agentUuid}` | — | `@testId("chat.mentionSuggestion.{agentUuid}")` |
| Jump to latest | `chat.jumpToLatestButton` | `Jump to latest message` | `@testId("chat.jumpToLatestButton")` |
| Send button | `chat.sendButton` | `Send message` | `@testId("chat.sendButton")` |
| Pending attachments strip | `chat.pendingAttachments` | — | `@testId("chat.pendingAttachments")` |

Legacy comparison mode also exposes:
- `chat.modelPill`
- `chat.liveCostLabel`
- `chat.openBlackboardButton`
- `chat.moreOptionsMenu`
- `chat.attachButton`
| Pending attachment thumb | `chat.pendingAttachment.{index}` | — | `@testId("chat.pendingAttachment.{index}")` |
| Remove pending attachment | `chat.pendingAttachment.remove.{index}` | `Remove attachment` | `@testId("chat.pendingAttachment.remove.{index}")` |
| Delegate button | `chat.delegateButton` | `Delegate to agent` | `@testId("chat.delegateButton")` |
| Streaming bubble | `chat.streamingBubble` | — | `@testId("chat.streamingBubble")` |
| Streaming thinking toggle | `chat.streamingThinkingToggle` | `Expand/Collapse thinking` | `@testId("chat.streamingThinkingToggle")` |
| Session summary card | `chat.sessionSummaryCard` | — | `@testId("chat.sessionSummaryCard")` |
| Session summary header | `chat.sessionSummaryCard.header` | — | `@testId("chat.sessionSummaryCard.header")` |
| Session summary file row | `chat.sessionSummaryCard.file.{index}` | `Open file {displayPath}` | `@testId("chat.sessionSummaryCard.file.{index}")` |

**Note:** The inner `NSTextField` of `PasteableTextField` also exposes `pasteableTextField.input` at the AppKit level. **Return** submits when there is text or pending attachments (and the session is not processing); **Shift+Return** inserts a newline; **⌘↩** also submits; the Send button submits as well. Opening a chat restores the last in-window reading position when available; otherwise it opens at the latest message.

---

### Scheduled Missions

**Files:** `Views/Schedules/ScheduleLibraryView.swift`, `Views/Schedules/ScheduleDetailView.swift`, `Views/Schedules/ScheduleEditorView.swift`
**Access:** Main window toolbar `Schedules`, sidebar bottom bar `Schedules`, chat `More` menu, or group detail `Schedule`.

| Control | Identifier | Label | Selector |
|---------|-----------|-------|----------|
| Library: empty state | `scheduleLibrary.emptyState` | — | `@testId("scheduleLibrary.emptyState")` |
| Library: list | `scheduleLibrary.list` | — | `@testId("scheduleLibrary.list")` |
| Library: New Schedule | `scheduleLibrary.newButton` | — | `@testId("scheduleLibrary.newButton")` |
| Library: Done | `scheduleLibrary.doneButton` | — | `@testId("scheduleLibrary.doneButton")` |
| Library: search | `scheduleLibrary.searchField` | — | `@testId("scheduleLibrary.searchField")` |
| Library: enabled filter | `scheduleLibrary.filterPicker` | — | `@testId("scheduleLibrary.filterPicker")` |
| Library: schedule row | `scheduleLibrary.row.{uuid}` | — | `@testId("scheduleLibrary.row.{uuid}")` |
| Detail: scroll view | `scheduleDetail.scrollView` | — | `@testId("scheduleDetail.scrollView")` |
| Detail: header | `scheduleDetail.header` | — | `@testId("scheduleDetail.header")` |
| Detail: Run Now | `scheduleDetail.runNowButton` | — | `@testId("scheduleDetail.runNowButton")` |
| Detail: Enable/Pause | `scheduleDetail.enableToggleButton` | — | `@testId("scheduleDetail.enableToggleButton")` |
| Detail: Edit | `scheduleDetail.editButton` | — | `@testId("scheduleDetail.editButton")` |
| Detail: Open last conversation | `scheduleDetail.openConversationButton` | — | `@testId("scheduleDetail.openConversationButton")` |
| Detail: More menu | `scheduleDetail.moreMenu` | — | `@testId("scheduleDetail.moreMenu")` |
| Detail: mission card | `scheduleDetail.missionCard` | — | `@testId("scheduleDetail.missionCard")` |
| Detail: settings card | `scheduleDetail.settingsCard` | — | `@testId("scheduleDetail.settingsCard")` |
| Detail: linked conversation | `scheduleDetail.linkedConversationButton` | — | `@testId("scheduleDetail.linkedConversationButton")` |
| Detail: history card | `scheduleDetail.historyCard` | — | `@testId("scheduleDetail.historyCard")` |
| Editor: name | `scheduleEditor.nameField` | — | `@testId("scheduleEditor.nameField")` |
| Editor: project directory | `scheduleEditor.projectDirectoryField` | — | `@testId("scheduleEditor.projectDirectoryField")` |
| Editor: target kind | `scheduleEditor.targetKindPicker` | — | `@testId("scheduleEditor.targetKindPicker")` |
| Editor: agent picker | `scheduleEditor.agentPicker` | — | `@testId("scheduleEditor.agentPicker")` |
| Editor: group picker | `scheduleEditor.groupPicker` | — | `@testId("scheduleEditor.groupPicker")` |
| Editor: autonomous toggle | `scheduleEditor.autonomousToggle` | — | `@testId("scheduleEditor.autonomousToggle")` |
| Editor: conversation picker | `scheduleEditor.conversationPicker` | — | `@testId("scheduleEditor.conversationPicker")` |
| Editor: prompt field | `scheduleEditor.promptField` | — | `@testId("scheduleEditor.promptField")` |
| Editor: run mode | `scheduleEditor.runModePicker` | — | `@testId("scheduleEditor.runModePicker")` |
| Editor: cadence kind | `scheduleEditor.cadenceKindPicker` | — | `@testId("scheduleEditor.cadenceKindPicker")` |
| Editor: interval stepper | `scheduleEditor.intervalStepper` | — | `@testId("scheduleEditor.intervalStepper")` |
| Editor: hour stepper | `scheduleEditor.hourStepper` | — | `@testId("scheduleEditor.hourStepper")` |
| Editor: minute stepper | `scheduleEditor.minuteStepper` | — | `@testId("scheduleEditor.minuteStepper")` |
| Editor: weekday chip | `scheduleEditor.day.{weekday}` | — | `@testId("scheduleEditor.day.{weekday}")` |
| Editor: enabled toggle | `scheduleEditor.enabledToggle` | — | `@testId("scheduleEditor.enabledToggle")` |
| Editor: run when closed toggle | `scheduleEditor.runWhenClosedToggle` | — | `@testId("scheduleEditor.runWhenClosedToggle")` |
| Editor: validation error | `scheduleEditor.validationError` | — | `@testId("scheduleEditor.validationError")` |
| Editor: Cancel | `scheduleEditor.cancelButton` | — | `@testId("scheduleEditor.cancelButton")` |
| Editor: Save | `scheduleEditor.saveButton` | — | `@testId("scheduleEditor.saveButton")` |
| Group detail: Schedule | `groupDetail.scheduleButton` | `Schedule` | `@testId("groupDetail.scheduleButton")` |

---

### 5.4 NewSessionSheet

**File:** `Views/MainWindow/NewSessionSheet.swift`
**Access:** `New Thread` opens this sheet on the `Agents` tab. `Group Thread` opens the same sheet on the `Groups` tab.

| Control | Identifier | Label | Selector |
|---------|-----------|-------|----------|
| Title | `newSession.title` | — | `@testId("newSession.title")` |
| Close button | `newSession.closeButton` | `Close` | `@testId("newSession.closeButton")` |
| Start kind: Blank | `newSession.startKind.blank` | `Blank` | `@testId("newSession.startKind.blank")` |
| Start kind: Agents | `newSession.startKind.agents` | `Agents` | `@testId("newSession.startKind.agents")` |
| Start kind: Groups | `newSession.startKind.groups` | `Groups` | `@testId("newSession.startKind.groups")` |
| Blank starter card | `newSession.blankStateCard` | — | `@testId("newSession.blankStateCard")` |
| Recent agent chip | `newSession.recentAgent.{uuid}` | — | `@testId("newSession.recentAgent.{uuid}")` |
| Recent group chip | `newSession.recentGroup.{uuid}` | — | `@testId("newSession.recentGroup.{uuid}")` |
| Selected agents summary (multi-select) | `newSession.selectedAgentsSummary` | — | `@testId("newSession.selectedAgentsSummary")` |
| Agent search field | `newSession.agentSearchField` | — | `@testId("newSession.agentSearchField")` |
| Group search field | `newSession.groupSearchField` | — | `@testId("newSession.groupSearchField")` |
| Agent picker: List | `newSession.agentPickerStyle.list` | — | `@testId("newSession.agentPickerStyle.list")` |
| Agent picker: Cards | `newSession.agentPickerStyle.cards` | — | `@testId("newSession.agentPickerStyle.cards")` |
| Group picker: List | `newSession.groupPickerStyle.list` | — | `@testId("newSession.groupPickerStyle.list")` |
| Group picker: Cards | `newSession.groupPickerStyle.cards` | — | `@testId("newSession.groupPickerStyle.cards")` |
| Agent card | `newSession.agentCard.{uuid}` | — | `@testId("newSession.agentCard.{uuid}")` |
| Agent row | `newSession.agentRow.{uuid}` | — | `@testId("newSession.agentRow.{uuid}")` |
| Group card | `newSession.groupCard.{uuid}` | — | `@testId("newSession.groupCard.{uuid}")` |
| Group row | `newSession.groupRow.{uuid}` | — | `@testId("newSession.groupRow.{uuid}")` |
| Expanded group members | `newSession.groupMembers.{groupUuid}` | — | `@testId("newSession.groupMembers.{groupUuid}")` |
| Expanded group member | `newSession.groupMember.{groupUuid}.{agentUuid}` | — | `@testId("newSession.groupMember.{groupUuid}.{agentUuid}")` |
| Model picker | `newSession.modelPicker` | — | `@testId("newSession.modelPicker")` |
| Mission field | `newSession.missionField` | — | `@testId("newSession.missionField")` |
| Options disclosure | `newSession.optionsDisclosure` | — | `@testId("newSession.optionsDisclosure")` |
| Quick Chat button | `newSession.quickChatButton` | — | `@testId("newSession.quickChatButton")` |
| Start Session button | `newSession.startSessionButton` | — | `@testId("newSession.startSessionButton")` |
| Group mode constraint | `newSession.groupModeConstraint` | — | `@testId("newSession.groupModeConstraint")` |

The unified sheet now covers the former group-thread entry as well. `NewGroupThreadSheet` remains in the repo, but the main window routes new group creation into `NewSessionSheet` on the `Groups` tab.

#### Add agents to chat (`/agents`)

| Control | Identifier | Label (if icon-only) | AppXray |
|---|---|---|---|
| Title | `addAgents.title` | — | `@testId("addAgents.title")` |
| Toggle per agent | `addAgents.toggle.{agentUuid}` | — | `@testId("addAgents.toggle.{agentUuid}")` |
| Cancel | `addAgents.cancelButton` | — | `@testId("addAgents.cancelButton")` |
| Confirm | `addAgents.confirmButton` | — | `@testId("addAgents.confirmButton")` |

---

### 5.5 InspectorView

**File:** `Views/MainWindow/InspectorView.swift`
**Access:** Trailing column, toggled via toolbar inspector button.

| Control | Identifier | Label | Selector |
|---------|-----------|-------|----------|
| Tab picker (Info / Files / Blackboard / Group) | `inspector.tabPicker` | — | `@testId("inspector.tabPicker")` |
| Info scroll view | `inspector.scrollView` | — | `@testId("inspector.scrollView")` |
| Blackboard search | `inspector.blackboard.searchField` | — | `@testId("inspector.blackboard.searchField")` |
| Blackboard filter | `inspector.blackboard.filterPicker` | — | `@testId("inspector.blackboard.filterPicker")` |
| Blackboard refresh | `inspector.blackboard.refreshButton` | `Refresh blackboard` | `@testId("inspector.blackboard.refreshButton")` |
| Blackboard entry list | `inspector.blackboard.entryList` | — | `@testId("inspector.blackboard.entryList")` |
| Blackboard entry row | `inspector.blackboard.entryRow.{sluggedKey}` | — | `@testId("inspector.blackboard.entryRow.{sluggedKey}")` |
| Blackboard copy key | `inspector.blackboard.copyKey.{sluggedKey}` | — | `@testId("inspector.blackboard.copyKey.{sluggedKey}")` |
| Blackboard copy value | `inspector.blackboard.copyValue.{sluggedKey}` | — | `@testId("inspector.blackboard.copyValue.{sluggedKey}")` |
| Session heading | `inspector.sessionHeading` | — | `@testId("inspector.sessionHeading")` |
| Multi-session list heading | `inspector.sessionsListHeading` | — | `@testId("inspector.sessionsListHeading")` |
| Multi-session row | `inspector.sessionRow.{sessionUuid}` | — | `@testId("inspector.sessionRow.{sessionUuid}")` |
| Session row agent link | `inspector.sessionRow.agentLink.{sessionUuid}` | — | `@testId("inspector.sessionRow.agentLink.{sessionUuid}")` |
| Usage heading | `inspector.usageHeading` | — | `@testId("inspector.usageHeading")` |
| Turns label | `inspector.turnsLabel` | — | `@testId("inspector.turnsLabel")` |
| Turns progress | `inspector.turnsProgress` | — | `@testId("inspector.turnsProgress")` |
| Working directory heading | `inspector.workspaceHeading` | — | `@testId("inspector.workspaceHeading")` |
| Working directory path | `infoRow.path` | `Path: {abbreviated path}` | `@testId("infoRow.path")` |
| Switch branch menu | `inspector.switchBranchMenu` | — | `@testId("inspector.switchBranchMenu")` |
| Fetch branches | `inspector.fetchBranchesButton` | — | `@testId("inspector.fetchBranchesButton")` |
| Workspace git error | `inspector.workspaceError` | — | `@testId("inspector.workspaceError")` |
| Reveal in Finder | `inspector.openFinderButton` | `Reveal in Finder` | `@testId("inspector.openFinderButton")` |
| Open in Terminal | `inspector.openTerminalButton` | — | `@testId("inspector.openTerminalButton")` |
| Agent heading | `inspector.agentHeading` | — | `@testId("inspector.agentHeading")` |
| Agent name button | `inspector.agentNameButton` | — | `@testId("inspector.agentNameButton")` |
| Agent capabilities | `inspector.agentCapabilities` | — | `@testId("inspector.agentCapabilities")` |
| History heading | `inspector.historyHeading` | — | `@testId("inspector.historyHeading")` |

**InfoRow** (inline component): Each row gets `infoRow.{labelSlug}` where the slug is the label lowercased with spaces removed (e.g., `infoRow.status`, `infoRow.model`, `infoRow.tokens`). Label is `"{label}: {value}"`.

---

### 5.6 FileExplorerView

**File:** `Views/MainWindow/FileExplorerView.swift`
**Access:** Inspector "Files" tab when a session has a `workingDirectory`.

| Control | Identifier | Label | Selector |
|---------|-----------|-------|----------|
| Path label | `inspector.fileTree.pathLabel` | — | `@testId("inspector.fileTree.pathLabel")` |
| Refresh button | `inspector.fileTree.refreshButton` | `Refresh file tree` | `@testId("inspector.fileTree.refreshButton")` |
| Settings menu (gear) | `inspector.fileTree.settingsButton` | `File explorer settings` | `@testId("inspector.fileTree.settingsButton")` |
| Show Hidden toggle | `inspector.fileTree.showHiddenToggle` | — | `@testId("inspector.fileTree.showHiddenToggle")` |
| Changes Only (menu) | `inspector.fileTree.changesOnlyMenuToggle` | — | `@testId("inspector.fileTree.changesOnlyMenuToggle")` |
| Reveal in Finder | `inspector.fileTree.revealInFinderButton` | — | `@testId("inspector.fileTree.revealInFinderButton")` |
| Open in Terminal | `inspector.fileTree.openInTerminalButton` | — | `@testId("inspector.fileTree.openInTerminalButton")` |
| Changes-only quick toggle | `inspector.fileTree.changesOnlyToggle` | `Show changes only` / `Show all files` | `@testId("inspector.fileTree.changesOnlyToggle")` |

---

### 5.7 FileTreeView

**File:** `Views/MainWindow/FileTreeView.swift`
**Access:** Rendered inside `FileExplorerView`.

| Control | Identifier | Label | Selector |
|---------|-----------|-------|----------|
| Loading indicator | `inspector.fileTree.loading` | — | `@testId("inspector.fileTree.loading")` |
| File list | `inspector.fileTree.list` | — | `@testId("inspector.fileTree.list")` |
| Directory row | `inspector.fileTree.directoryRow.{name}` | — | `@testId("inspector.fileTree.directoryRow.{name}")` |
| File row | `inspector.fileTree.fileRow.{name}` | — | `@testId("inspector.fileTree.fileRow.{name}")` |

---

### 5.8 FileContentView

**File:** `Views/MainWindow/FileContentView.swift`
**Access:** Selecting a file in `FileTreeView`.

| Control | Identifier | Label | Selector |
|---------|-----------|-------|----------|
| Back button | `inspector.fileContent.backButton` | `Back to file tree` | `@testId("inspector.fileContent.backButton")` |
| File name | `inspector.fileContent.fileName` | — | `@testId("inspector.fileContent.fileName")` |
| Metadata bar | `inspector.fileContent.metadataBar` | — | `@testId("inspector.fileContent.metadataBar")` |
| Mode picker | `inspector.fileContent.modePicker` | — | `@testId("inspector.fileContent.modePicker")` |
| Loading indicator | `inspector.fileContent.loading` | — | `@testId("inspector.fileContent.loading")` |
| Markdown preview | `inspector.fileContent.markdownPreview` | — | `@testId("inspector.fileContent.markdownPreview")` |
| Source view | `inspector.fileContent.sourceView` | — | `@testId("inspector.fileContent.sourceView")` |
| Diff view | `inspector.fileContent.diffView` | — | `@testId("inspector.fileContent.diffView")` |
| Binary placeholder | `inspector.fileContent.binaryPlaceholder` | — | `@testId("inspector.fileContent.binaryPlaceholder")` |
| Empty placeholder | `inspector.fileContent.emptyPlaceholder` | — | `@testId("inspector.fileContent.emptyPlaceholder")` |
| Open in Editor | `inspector.fileContent.openInEditorButton` | — | `@testId("inspector.fileContent.openInEditorButton")` |
| Copy Path | `inspector.fileContent.copyPathButton` | — | `@testId("inspector.fileContent.copyPathButton")` |

---

### 5.9 WorkingDirectoryPicker

**File:** `Views/MainWindow/WorkingDirectoryPicker.swift`
**Access:** Shown on first launch when no working directory is set.

| Control | Identifier | Label | Selector |
|---------|-----------|-------|----------|
| Recent directory | `directoryPicker.recent.{index}` | — | `@testId("directoryPicker.recent.{index}")` |
| Custom path field | `directoryPicker.customPathField` | — | `@testId("directoryPicker.customPathField")` |
| Browse button | `directoryPicker.browseButton` | — | `@testId("directoryPicker.browseButton")` |
| Use Home Directory | `directoryPicker.useHomeButton` | — | `@testId("directoryPicker.useHomeButton")` |
| Use Custom Path | `directoryPicker.useCustomButton` | — | `@testId("directoryPicker.useCustomButton")` |

---

### 5.10 IntentLibraryHubView

**File:** `Views/MainWindow/IntentLibraryHubView.swift`
**Access:** Sidebar `Library`, welcome `Browse Agents` / `Browse Groups`, chat/inspector shortcuts, or peer import follow-up flows.

| Control | Identifier | Label | Selector |
|---------|-----------|-------|----------|
| Sheet root | `libraryHub.sheet` | — | `@testId("libraryHub.sheet")` |
| Title | `libraryHub.title` | — | `@testId("libraryHub.title")` |
| Search field | `libraryHub.searchField` | — | `@testId("libraryHub.searchField")` |
| Close button | `libraryHub.closeButton` | `Close library` | `@testId("libraryHub.closeButton")` |
| Top-level section: Run | `libraryHub.section.run` | `Run` | `@testId("libraryHub.section.run")` |
| Top-level section: Build | `libraryHub.section.build` | `Build` | `@testId("libraryHub.section.build")` |
| Top-level section: Discover | `libraryHub.section.discover` | `Discover` | `@testId("libraryHub.section.discover")` |
| Summary card | `libraryHub.summaryCard` | — | `@testId("libraryHub.summaryCard")` |
| Run scroll view | `libraryHub.runScrollView` | — | `@testId("libraryHub.runScrollView")` |
| Run: Start Agent | `libraryHub.run.startAgentButton` | — | `@testId("libraryHub.run.startAgentButton")` |
| Run: Start Group | `libraryHub.run.startGroupButton` | — | `@testId("libraryHub.run.startGroupButton")` |
| Run: Quick Chat | `libraryHub.run.quickChatButton` | — | `@testId("libraryHub.run.quickChatButton")` |
| Build section picker | `libraryHub.build.sectionPicker` | — | `@testId("libraryHub.build.sectionPicker")` |
| Build scroll view | `libraryHub.buildScrollView` | — | `@testId("libraryHub.buildScrollView")` |
| Build filter | `libraryHub.build.filter.{all|mine|shared|builtIn}` | — | `@testId("libraryHub.build.filter.{filter}")` |
| Build: New Agent | `libraryHub.newAgentButton` | — | `@testId("libraryHub.newAgentButton")` |
| Build: New Group | `libraryHub.newGroupButton` | — | `@testId("libraryHub.newGroupButton")` |
| Discover section picker | `libraryHub.discover.sectionPicker` | — | `@testId("libraryHub.discover.sectionPicker")` |
| Discover scroll view | `libraryHub.discoverScrollView` | — | `@testId("libraryHub.discoverScrollView")` |
| Discover category row | `libraryHub.discover.categoryRow` | — | `@testId("libraryHub.discover.categoryRow")` |
| Discover category | `libraryHub.discover.category.{title}` | — | `@testId("libraryHub.discover.category.{title}")` |
| Discover agent card | `libraryHub.discover.agentCard.{catalogId}` | — | `@testId("libraryHub.discover.agentCard.{catalogId}")` |
| Discover skill card | `libraryHub.discover.skillCard.{catalogId}` | — | `@testId("libraryHub.discover.skillCard.{catalogId}")` |
| Discover integration card | `libraryHub.discover.mcpCard.{catalogId}` | — | `@testId("libraryHub.discover.mcpCard.{catalogId}")` |
| New agent entry sheet | `libraryHub.newAgentEntrySheet` | — | `@testId("libraryHub.newAgentEntrySheet")` |

---

### 5.11 AgentEditorView

**File:** `Views/AgentLibrary/AgentEditorView.swift`
**Access:** Sheet from Agent Library (new or edit).

**Step tabs:** `agentEditor.step.identity`, `agentEditor.step.capabilities`, `agentEditor.step.systemprompt`

#### Identity Step

| Control | Identifier | Label | Selector |
|---------|-----------|-------|----------|
| Title | `agentEditor.title` | — | `@testId("agentEditor.title")` |
| Close button | `agentEditor.closeButton` | `Close` | `@testId("agentEditor.closeButton")` |
| Name field | `agentEditor.nameField` | — | `@testId("agentEditor.nameField")` |
| Description field | `agentEditor.descriptionField` | — | `@testId("agentEditor.descriptionField")` |
| Icon field | `agentEditor.iconField` | — | `@testId("agentEditor.iconField")` |
| Color picker | `agentEditor.colorPicker` | — | `@testId("agentEditor.colorPicker")` |
| Model picker | `agentEditor.modelPicker` | — | `@testId("agentEditor.modelPicker")` |

#### Capabilities Step

| Control | Identifier | Label | Selector |
|---------|-----------|-------|----------|
| Max turns field | `agentEditor.maxTurnsField` | — | `@testId("agentEditor.maxTurnsField")` |
| Max budget field | `agentEditor.maxBudgetField` | — | `@testId("agentEditor.maxBudgetField")` |
| Instance policy picker | `agentEditor.instancePolicyPicker` | — | `@testId("agentEditor.instancePolicyPicker")` |
| Pool max field | `agentEditor.poolMaxField` | — | `@testId("agentEditor.poolMaxField")` |
| Working directory field | `agentEditor.workingDirectoryField` | — | `@testId("agentEditor.workingDirectoryField")` |
| GitHub repo field | `agentEditor.githubRepoField` | — | `@testId("agentEditor.githubRepoField")` |
| GitHub branch field | `agentEditor.githubBranchField` | — | `@testId("agentEditor.githubBranchField")` |
| Skills disclosure | `agentEditor.skillsDisclosure` | — | `@testId("agentEditor.skillsDisclosure")` |
| Skills selected list | `agentEditor.skills.selectedList` | — | `@testId("agentEditor.skills.selectedList")` |
| Skills available list | `agentEditor.skills.availableList` | — | `@testId("agentEditor.skills.availableList")` |
| Skill remove button | `agentEditor.skills.removeButton.{uuid}` | `Remove {name}` | `@testId("agentEditor.skills.removeButton.{uuid}")` |
| Skill add button | `agentEditor.skills.addButton.{uuid}` | `Add {name}` | `@testId("agentEditor.skills.addButton.{uuid}")` |
| Manage Skills | `agentEditor.manageSkills` | — | `@testId("agentEditor.manageSkills")` |
| MCPs disclosure | `agentEditor.mcpsDisclosure` | — | `@testId("agentEditor.mcpsDisclosure")` |
| Manage MCPs | `agentEditor.manageMCPs` | — | `@testId("agentEditor.manageMCPs")` |
| Permissions disclosure | `agentEditor.permissionsDisclosure` | — | `@testId("agentEditor.permissionsDisclosure")` |
| Permission preset picker | `agentEditor.permissionPresetPicker` | — | `@testId("agentEditor.permissionPresetPicker")` |

#### System Prompt Step

| Control | Identifier | Label | Selector |
|---------|-----------|-------|----------|
| System prompt editor | `agentEditor.systemPromptEditor` | — | `@testId("agentEditor.systemPromptEditor")` |
| Char count | `agentEditor.systemPromptCharCount` | — | `@testId("agentEditor.systemPromptCharCount")` |

#### Navigation

| Control | Identifier | Label | Selector |
|---------|-----------|-------|----------|
| Back button | `agentEditor.backButton` | — | `@testId("agentEditor.backButton")` |
| Cancel button | `agentEditor.cancelButton` | — | `@testId("agentEditor.cancelButton")` |
| Next button | `agentEditor.nextButton` | — | `@testId("agentEditor.nextButton")` |
| Save button | `agentEditor.saveButton` | — | `@testId("agentEditor.saveButton")` |
| GitHub clone path | `agentEditor.githubClonePathLabel` | — | `@testId("agentEditor.githubClonePathLabel")` |
| GitHub validate/update | `agentEditor.githubValidateButton` | — | `@testId("agentEditor.githubValidateButton")` |
| GitHub workspace message | `agentEditor.githubWorkspaceMessage` | — | `@testId("agentEditor.githubWorkspaceMessage")` |

---

### 5.12 AgentCommsView

**File:** `Views/AgentComms/AgentCommsView.swift`
**Access:** Toolbar "Agent Comms" button.

| Control | Identifier | Label | Selector |
|---------|-----------|-------|----------|
| Title | `agentComms.title` | — | `@testId("agentComms.title")` |
| Event count | `agentComms.eventCount` | — | `@testId("agentComms.eventCount")` |
| Filter picker | `agentComms.filterPicker` | — | `@testId("agentComms.filterPicker")` |
| Event list | `agentComms.eventList` | — | `@testId("agentComms.eventList")` |
| Empty state | `agentComms.emptyState` | — | `@testId("agentComms.emptyState")` |
| Event row | `agentComms.event.{uuid}` | — | `@testId("agentComms.event.{uuid}")` |
| Event icon | `agentComms.eventIcon.{uuid}` | `Chat` / `Delegation` / `Blackboard update` | `@testId("agentComms.eventIcon.{uuid}")` |
| Event timestamp | `agentComms.eventTimestamp.{uuid}` | — | `@testId("agentComms.eventTimestamp.{uuid}")` |

---

### 5.12a PeerNetworkView

**File:** `Views/MainWindow/PeerNetworkView.swift`
**Access:** Toolbar "Peer Network" (⌘⇧P).

| Control | Identifier | Label | Selector |
|---------|-----------|-------|----------|
| Title | `peerNetwork.title` | — | `@testId("peerNetwork.title")` |
| Close | `peerNetwork.closeButton` | Close | `@testId("peerNetwork.closeButton")` |
| Banner error | `peerNetwork.bannerError` | — | `@testId("peerNetwork.bannerError")` |
| Empty peers | `peerNetwork.emptyPeers` | — | `@testId("peerNetwork.emptyPeers")` |
| Peer list | `peerNetwork.peerList` | — | `@testId("peerNetwork.peerList")` |
| Peer row | `peerNetwork.peerRow.{id}` | — | `@testId("peerNetwork.peerRow.{id}")` |
| Detail title | `peerNetwork.detailTitle` | — | `@testId("peerNetwork.detailTitle")` |
| Browse agents | `peerNetwork.browseAgentsButton` | — | `@testId("peerNetwork.browseAgentsButton")` |
| List error | `peerNetwork.listError` | — | `@testId("peerNetwork.listError")` |
| Import message | `peerNetwork.importMessage` | — | `@testId("peerNetwork.importMessage")` |
| Remote agent list | `peerNetwork.remoteAgentList` | — | `@testId("peerNetwork.remoteAgentList")` |
| Import button | `peerNetwork.importButton.{uuid}` | — | `@testId("peerNetwork.importButton.{uuid}")` |
| Select peer placeholder | `peerNetwork.selectPeerPlaceholder` | — | `@testId("peerNetwork.selectPeerPlaceholder")` |
| Refresh browse | `peerNetwork.refreshButton` | — | `@testId("peerNetwork.refreshButton")` |

---

### 5.13 CatalogBrowserView

**File:** `Views/Catalog/CatalogBrowserView.swift`
**Access:** Supporting/legacy catalog surface. Primary user flow now enters catalog content through `IntentLibraryHubView` > `Discover`.

| Control | Identifier | Label | Selector |
|---------|-----------|-------|----------|
| Search field | `catalog.searchField` | — | `@testId("catalog.searchField")` |
| Close button | `catalog.closeButton` | `Close` | `@testId("catalog.closeButton")` |
| Tab picker | `catalog.tabPicker` | — | `@testId("catalog.tabPicker")` |
| Category chip | `catalog.categoryChip.{title}` | — | `@testId("catalog.categoryChip.{title}")` |
| Agent card | `catalog.agentCard.{id}` | — | `@testId("catalog.agentCard.{id}")` |
| Skill card | `catalog.skillCard.{id}` | — | `@testId("catalog.skillCard.{id}")` |
| MCP card | `catalog.mcpCard.{id}` | — | `@testId("catalog.mcpCard.{id}")` |
| Card grid | `catalog.cardGrid` | — | `@testId("catalog.cardGrid")` |
| Context: Install | `catalog.contextMenu.install.{id}` | — | `@testId("catalog.contextMenu.install.{id}")` |
| Context: Uninstall | `catalog.contextMenu.uninstall.{id}` | — | `@testId("catalog.contextMenu.uninstall.{id}")` |
| Install button | `catalog.installButton.{catalogId}` | — | `@testId("catalog.installButton.{catalogId}")` |

---

### 5.14 CatalogDetailView

**File:** `Views/Catalog/CatalogDetailView.swift`
**Access:** Tapping a catalog card.

| Control | Identifier | Label | Selector |
|---------|-----------|-------|----------|
| Scroll view | `catalogDetail.scrollView` | — | `@testId("catalogDetail.scrollView")` |
| Close button | `catalogDetail.closeButton` | `Close` | `@testId("catalogDetail.closeButton")` |
| System prompt disclosure | `catalogDetail.systemPromptDisclosure` | — | `@testId("catalogDetail.systemPromptDisclosure")` |
| Homepage link | `catalogDetail.homepageLink` | — | `@testId("catalogDetail.homepageLink")` |
| Uninstall button | `catalogDetail.uninstallButton` | — | `@testId("catalogDetail.uninstallButton")` |
| Install button | `catalogDetail.installButton` | — | `@testId("catalogDetail.installButton")` |

---

### 5.15 SettingsView

**File:** `Views/Settings/SettingsView.swift`
**Access:** macOS Settings menu (Cmd+,).

**Tab selection:**

| Control | Identifier | Selector |
|---------|-----------|----------|
| Tab view | `settings.tabView` | `@testId("settings.tabView")` |
| General tab | `settings.tab.general` | `@testId("settings.tab.general")` |
| Agents & Models tab | `settings.tab.agentsModels` | `@testId("settings.tab.agentsModels")` |
| Connection tab | `settings.tab.connection` | `@testId("settings.tab.connection")` |
| Connectors tab | `settings.tab.connectors` | `@testId("settings.tab.connectors")` |
| Chat Display tab | `settings.tab.chatDisplay` | `@testId("settings.tab.chatDisplay")` |
| Developer tab | `settings.tab.developer` | `@testId("settings.tab.developer")` |

#### General Tab

| Control | Identifier | Selector |
|---------|-----------|----------|
| Appearance picker | `settings.general.appearancePicker` | `@testId("settings.general.appearancePicker")` |
| Text size picker | `settings.general.textSizePicker` | `@testId("settings.general.textSizePicker")` |
| Quick action ordering toggle | `settings.general.quickActionUsageOrderToggle` | `@testId("settings.general.quickActionUsageOrderToggle")` |

#### Agents & Models Tab

| Control | Identifier | Selector |
|---------|-----------|----------|
| Default provider picker | `settings.agentsModels.defaultProviderPicker` | `@testId("settings.agentsModels.defaultProviderPicker")` |
| Default Claude model picker | `settings.agentsModels.defaultClaudeModelPicker` | `@testId("settings.agentsModels.defaultClaudeModelPicker")` |
| Default Codex model picker | `settings.agentsModels.defaultCodexModelPicker` | `@testId("settings.agentsModels.defaultCodexModelPicker")` |
| Default Foundation model picker | `settings.agentsModels.defaultFoundationModelPicker` | `@testId("settings.agentsModels.defaultFoundationModelPicker")` |
| Default MLX downloaded-model picker | `settings.agentsModels.defaultMLXModelPicker` | `@testId("settings.agentsModels.defaultMLXModelPicker")` |
| Default MLX model field | `settings.agentsModels.defaultMLXModelField` | `@testId("settings.agentsModels.defaultMLXModelField")` |
| Current MLX default summary | `settings.agentsModels.currentDefaultMLXModel` | `@testId("settings.agentsModels.currentDefaultMLXModel")` |
| Default max turns stepper | `settings.agentsModels.defaultMaxTurnsStepper` | `@testId("settings.agentsModels.defaultMaxTurnsStepper")` |
| Default max budget field | `settings.agentsModels.defaultMaxBudgetField` | `@testId("settings.agentsModels.defaultMaxBudgetField")` |
| Local host status | `settings.agentsModels.localProviders.hostStatus` | `@testId("settings.agentsModels.localProviders.hostStatus")` |
| Foundation status | `settings.agentsModels.localProviders.foundationStatus` | `@testId("settings.agentsModels.localProviders.foundationStatus")` |
| MLX status | `settings.agentsModels.localProviders.mlxStatus` | `@testId("settings.agentsModels.localProviders.mlxStatus")` |
| Managed MLX cache path | `settings.agentsModels.mlxDownloadDirectory` | `@testId("settings.agentsModels.mlxDownloadDirectory")` |
| Install MLX runner | `settings.agentsModels.installMLXRunnerButton` | `@testId("settings.agentsModels.installMLXRunnerButton")` |
| Open MLX cache | `settings.agentsModels.openMLXCacheButton` | `@testId("settings.agentsModels.openMLXCacheButton")` |
| Preset card | `settings.agentsModels.presetCard.{modelId}` | `@testId("settings.agentsModels.presetCard.{modelId}")` |
| Preset download button | `settings.agentsModels.downloadPreset.{modelId}` | `@testId("settings.agentsModels.downloadPreset.{modelId}")` |
| Preset set default button | `settings.agentsModels.setDefaultPreset.{modelId}` | `@testId("settings.agentsModels.setDefaultPreset.{modelId}")` |
| Custom MLX field | `settings.agentsModels.customMLXModelField` | `@testId("settings.agentsModels.customMLXModelField")` |
| Custom MLX download button | `settings.agentsModels.installCustomMLXModelButton` | `@testId("settings.agentsModels.installCustomMLXModelButton")` |
| Empty installed state | `settings.agentsModels.noInstalledModels` | `@testId("settings.agentsModels.noInstalledModels")` |
| Installed model card | `settings.agentsModels.installedCard.{modelId}` | `@testId("settings.agentsModels.installedCard.{modelId}")` |
| Installed set default button | `settings.agentsModels.setDefaultInstalled.{modelId}` | `@testId("settings.agentsModels.setDefaultInstalled.{modelId}")` |
| Installed delete button | `settings.agentsModels.deleteInstalled.{modelId}` | `@testId("settings.agentsModels.deleteInstalled.{modelId}")` |
| Catalog loading state | `settings.agentsModels.loadingCatalog` | `@testId("settings.agentsModels.loadingCatalog")` |
| Catalog status message | `settings.agentsModels.catalogMessage` | `@testId("settings.agentsModels.catalogMessage")` |

#### Connection Tab

| Control | Identifier | Selector |
|---------|-----------|----------|
| Status URL | `settings.connection.statusURL` | `@testId("settings.connection.statusURL")` |
| Status row | `settings.connection.statusRow` | `@testId("settings.connection.statusRow")` |
| Auto-connect toggle | `settings.connection.autoConnectToggle` | `@testId("settings.connection.autoConnectToggle")` |
| WS port field | `settings.connection.wsPortField` | `@testId("settings.connection.wsPortField")` |
| HTTP port field | `settings.connection.httpPortField` | `@testId("settings.connection.httpPortField")` |
| Reconnect button | `settings.connection.reconnectButton` | `@testId("settings.connection.reconnectButton")` |
| Stop button | `settings.connection.stopButton` | `@testId("settings.connection.stopButton")` |
| Connect button | `settings.connection.connectButton` | `@testId("settings.connection.connectButton")` |

#### Developer Tab

| Control | Identifier | Selector |
|---------|-----------|----------|
| Bun path field | `settings.developer.bunPathField` | `@testId("settings.developer.bunPathField")` |
| Bun path browse | `settings.developer.bunPathBrowseButton` | `@testId("settings.developer.bunPathBrowseButton")` |
| Sidecar path field | `settings.developer.sidecarPathField` | `@testId("settings.developer.sidecarPathField")` |
| Sidecar path browse | `settings.developer.sidecarPathBrowseButton` | `@testId("settings.developer.sidecarPathBrowseButton")` |
| Local host field | `settings.developer.localAgentHostField` | `@testId("settings.developer.localAgentHostField")` |
| Local host browse | `settings.developer.localAgentHostBrowseButton` | `@testId("settings.developer.localAgentHostBrowseButton")` |
| MLX runner field | `settings.developer.mlxRunnerField` | `@testId("settings.developer.mlxRunnerField")` |
| MLX runner browse | `settings.developer.mlxRunnerBrowseButton` | `@testId("settings.developer.mlxRunnerBrowseButton")` |
| Data directory field | `settings.developer.dataDirectoryField` | `@testId("settings.developer.dataDirectoryField")` |
| Data directory browse | `settings.developer.dataDirectoryBrowseButton` | `@testId("settings.developer.dataDirectoryBrowseButton")` |
| Log level picker | `settings.developer.logLevelPicker` | `@testId("settings.developer.logLevelPicker")` |
| Legacy chat chrome toggle | `settings.developer.useLegacyChatChromeToggle` | `@testId("settings.developer.useLegacyChatChromeToggle")` |
| Open data directory | `settings.developer.openDataDirectoryButton` | `@testId("settings.developer.openDataDirectoryButton")` |
| Reset settings | `settings.developer.resetSettingsButton` | `@testId("settings.developer.resetSettingsButton")` |

---

### 5.16 MCPLibraryView

**File:** `Views/MCPs/MCPLibraryView.swift`
**Access:** Agent Editor "Manage MCPs" button.

| Control | Identifier | Label | Selector |
|---------|-----------|-------|----------|
| MCP row | `mcpLibrary.mcpRow.{uuid}` | — | `@testId("mcpLibrary.mcpRow.{uuid}")` |
| Context: Edit | `mcpLibrary.contextMenu.edit.{uuid}` | — | `@testId("mcpLibrary.contextMenu.edit.{uuid}")` |
| Context: Duplicate | `mcpLibrary.contextMenu.duplicate.{uuid}` | — | `@testId("mcpLibrary.contextMenu.duplicate.{uuid}")` |
| Context: Delete | `mcpLibrary.contextMenu.delete.{uuid}` | — | `@testId("mcpLibrary.contextMenu.delete.{uuid}")` |
| MCP list | `mcpLibrary.mcpList` | — | `@testId("mcpLibrary.mcpList")` |
| Search field | `mcpLibrary.searchField` | — | `@testId("mcpLibrary.searchField")` |
| New button | `mcpLibrary.newButton` | — | `@testId("mcpLibrary.newButton")` |
| Catalog button | `mcpLibrary.catalogButton` | — | `@testId("mcpLibrary.catalogButton")` |
| Close button | `mcpLibrary.closeButton` | `Close` | `@testId("mcpLibrary.closeButton")` |
| Status dot | `mcpLibrary.statusDot` | `{status}` | `@testId("mcpLibrary.statusDot")` |

**MCPCatalogSheet** (sub-sheet):

| Control | Identifier | Label | Selector |
|---------|-----------|-------|----------|
| Row | `mcpCatalogSheet.row.{catalogId}` | — | `@testId("mcpCatalogSheet.row.{catalogId}")` |
| Install button | `mcpCatalogSheet.installButton.{catalogId}` | — | `@testId("mcpCatalogSheet.installButton.{catalogId}")` |
| Context: Install | `mcpCatalogSheet.contextMenu.install.{catalogId}` | — | `@testId("mcpCatalogSheet.contextMenu.install.{catalogId}")` |
| List | `mcpCatalogSheet.list` | — | `@testId("mcpCatalogSheet.list")` |
| Done button | `mcpCatalogSheet.doneButton` | — | `@testId("mcpCatalogSheet.doneButton")` |

---

### 5.17 MCPEditorView

**File:** `Views/MCPs/MCPEditorView.swift`
**Access:** MCPLibrary edit or new.

| Control | Identifier | Label | Selector |
|---------|-----------|-------|----------|
| Close button | `mcpEditor.closeButton` | `Close` | `@testId("mcpEditor.closeButton")` |
| Name field | `mcpEditor.nameField` | — | `@testId("mcpEditor.nameField")` |
| Description field | `mcpEditor.descriptionField` | — | `@testId("mcpEditor.descriptionField")` |
| Transport picker | `mcpEditor.transportPicker` | — | `@testId("mcpEditor.transportPicker")` |
| Command field | `mcpEditor.commandField` | — | `@testId("mcpEditor.commandField")` |
| Args field | `mcpEditor.argsField` | — | `@testId("mcpEditor.argsField")` |
| Env key | `mcpEditor.envKey.{pairId}` | — | `@testId("mcpEditor.envKey.{pairId}")` |
| Env value | `mcpEditor.envValue.{pairId}` | — | `@testId("mcpEditor.envValue.{pairId}")` |
| Env remove button | `mcpEditor.envRemoveButton.{pairId}` | `Remove environment variable` | `@testId("mcpEditor.envRemoveButton.{pairId}")` |
| Add env button | `mcpEditor.addEnvButton` | — | `@testId("mcpEditor.addEnvButton")` |
| URL field | `mcpEditor.urlField` | — | `@testId("mcpEditor.urlField")` |
| Header key | `mcpEditor.headerKey.{pairId}` | — | `@testId("mcpEditor.headerKey.{pairId}")` |
| Header value | `mcpEditor.headerValue.{pairId}` | — | `@testId("mcpEditor.headerValue.{pairId}")` |
| Header remove | `mcpEditor.headerRemoveButton.{pairId}` | `Remove header` | `@testId("mcpEditor.headerRemoveButton.{pairId}")` |
| Add header button | `mcpEditor.addHeaderButton` | — | `@testId("mcpEditor.addHeaderButton")` |
| Cancel button | `mcpEditor.cancelButton` | — | `@testId("mcpEditor.cancelButton")` |
| Save button | `mcpEditor.saveButton` | — | `@testId("mcpEditor.saveButton")` |

---

### 5.18 SkillLibraryView

**File:** `Views/Skills/SkillLibraryView.swift`
**Access:** Agent Editor "Manage Skills" button.

| Control | Identifier | Label | Selector |
|---------|-----------|-------|----------|
| Skill card | `skillLibrary.skillCard.{uuid}` | — | `@testId("skillLibrary.skillCard.{uuid}")` |
| Context: Edit | `skillLibrary.contextMenu.edit.{uuid}` | — | `@testId("skillLibrary.contextMenu.edit.{uuid}")` |
| Context: Duplicate | `skillLibrary.contextMenu.duplicate.{uuid}` | — | `@testId("skillLibrary.contextMenu.duplicate.{uuid}")` |
| Context: Delete | `skillLibrary.contextMenu.delete.{uuid}` | — | `@testId("skillLibrary.contextMenu.delete.{uuid}")` |
| Skill grid | `skillLibrary.skillGrid` | — | `@testId("skillLibrary.skillGrid")` |
| Search field | `skillLibrary.searchField` | — | `@testId("skillLibrary.searchField")` |
| New button | `skillLibrary.newButton` | — | `@testId("skillLibrary.newButton")` |
| Catalog button | `skillLibrary.catalogButton` | — | `@testId("skillLibrary.catalogButton")` |
| Close button | `skillLibrary.closeButton` | `Close` | `@testId("skillLibrary.closeButton")` |
| Empty: Browse Catalog | `skillLibrary.emptyState.browseButton` | — | `@testId("skillLibrary.emptyState.browseButton")` |

---

### 5.19 SkillEditorView

**File:** `Views/Skills/SkillEditorView.swift`
**Access:** SkillLibrary edit or new.

| Control | Identifier | Label | Selector |
|---------|-----------|-------|----------|
| Close button | `skillEditor.closeButton` | `Close` | `@testId("skillEditor.closeButton")` |
| Name field | `skillEditor.nameField` | — | `@testId("skillEditor.nameField")` |
| Description field | `skillEditor.descriptionField` | — | `@testId("skillEditor.descriptionField")` |
| Category picker | `skillEditor.categoryPicker` | — | `@testId("skillEditor.categoryPicker")` |
| Version field | `skillEditor.versionField` | — | `@testId("skillEditor.versionField")` |
| Triggers field | `skillEditor.triggersField` | — | `@testId("skillEditor.triggersField")` |
| Char count | `skillEditor.charCount` | — | `@testId("skillEditor.charCount")` |
| Content editor | `skillEditor.contentEditor` | — | `@testId("skillEditor.contentEditor")` |
| MCP selected list | `skillEditor.mcps.selectedList` | — | `@testId("skillEditor.mcps.selectedList")` |
| MCP remove button | `skillEditor.mcps.removeButton.{uuid}` | `Remove {name}` | `@testId("skillEditor.mcps.removeButton.{uuid}")` |
| MCP add button | `skillEditor.mcps.addButton.{uuid}` | `Add {name}` | `@testId("skillEditor.mcps.addButton.{uuid}")` |
| MCP available list | `skillEditor.mcps.availableList` | — | `@testId("skillEditor.mcps.availableList")` |
| Cancel button | `skillEditor.cancelButton` | — | `@testId("skillEditor.cancelButton")` |
| Save button | `skillEditor.saveButton` | — | `@testId("skillEditor.saveButton")` |

---

## 6. Reusable Components

These components appear inside multiple screens.

### MessageBubble

**File:** `Views/Components/MessageBubble.swift`

| Control | Identifier | Label | Selector |
|---------|-----------|-------|----------|
| Root | `messageBubble.{type}.{uuid}` | — | `@testId("messageBubble.{type}.{uuid}")` |
| Sender label | `messageBubble.senderLabel.{uuid}` | — | `@testId("messageBubble.senderLabel.{uuid}")` |
| Copy button (hover) | `messageBubble.copyButton.{uuid}` | `Copy message` | `@testId("messageBubble.copyButton.{uuid}")` |
| Fork from here (context menu) | `messageBubble.forkFromHere.{uuid}` | — | `@testId("messageBubble.forkFromHere.{uuid}")` |
| Attachment | `messageBubble.attachment.{attachmentUuid}` | — | `@testId("messageBubble.attachment.{attachmentUuid}")` |
| Thinking toggle | `messageBubble.thinkingToggle.{uuid}` | expand/collapse | `@testId("messageBubble.thinkingToggle.{uuid}")` |

Message `{type}` values: `text`, `toolCall`, `toolResult`, `delegation`, `blackboard`.

### ToolCallView

**File:** `Views/Components/ToolCallView.swift`

| Control | Identifier | Label | Selector |
|---------|-----------|-------|----------|
| Container | `toolCall.container.{uuid}` | — | `@testId("toolCall.container.{uuid}")` |
| Title | `toolCall.title.{uuid}` | — | `@testId("toolCall.title.{uuid}")` |
| Toggle button | `toolCall.toggleButton.{uuid}` | `{toolName} - expand/collapse` | `@testId("toolCall.toggleButton.{uuid}")` |

### CodeBlockView

**File:** `Views/Components/CodeBlockView.swift`

| Control | Identifier | Label | Selector |
|---------|-----------|-------|----------|
| Language label | `codeBlock.languageLabel` | — | `@testId("codeBlock.languageLabel")` |
| Copy button | `codeBlock.copyButton` | `Copy code` | `@testId("codeBlock.copyButton")` |
| Code scroll view | `codeBlock.codeScrollView` | — | `@testId("codeBlock.codeScrollView")` |

### ImagePreviewOverlay

**File:** `Views/Components/ImagePreviewOverlay.swift`

| Control | Identifier | Label | Selector |
|---------|-----------|-------|----------|
| Overlay root | `imagePreview.overlay` | — | `@testId("imagePreview.overlay")` |
| Close button | `imagePreview.closeButton` | `Close preview` | `@testId("imagePreview.closeButton")` |
| Zoom in | `imagePreview.zoomInButton` | `Zoom in` | `@testId("imagePreview.zoomInButton")` |
| Zoom out | `imagePreview.zoomOutButton` | `Zoom out` | `@testId("imagePreview.zoomOutButton")` |
| Reset zoom | `imagePreview.resetZoomButton` | `Reset zoom` | `@testId("imagePreview.resetZoomButton")` |
| Copy | `imagePreview.copyButton` | `Copy to clipboard` | `@testId("imagePreview.copyButton")` |
| Show in Finder | `imagePreview.openInFinderButton` | `Show in Finder` | `@testId("imagePreview.openInFinderButton")` |

### StreamingIndicator

**File:** `Views/Components/StreamingIndicator.swift`

| Control | Identifier | Label | Selector |
|---------|-----------|-------|----------|
| Dots container | `streamingIndicator` | `Loading` | `@testId("streamingIndicator")` |

### StatusBadge

**File:** `Views/Components/StatusBadge.swift`

| Control | Identifier | Label | Selector |
|---------|-----------|-------|----------|
| Badge | `statusBadge.{status}` | `Status: {status}` | `@testId("statusBadge.{status}")` |

Status values (lowercased): `idle`, `running`, `streaming`, `paused`, `completed`, `error`.

### AttachmentThumbnail

**File:** `Views/Components/AttachmentThumbnail.swift`

| Control | Identifier | Label | Selector |
|---------|-----------|-------|----------|
| Thumbnail | `attachmentThumbnail.{uuid}` | `Image attachment` or `File: {fileName}` | `@testId("attachmentThumbnail.{uuid}")` |

### AgentCardView

**File:** `Views/Components/AgentCardView.swift`

| Control | Identifier | Label | Selector |
|---------|-----------|-------|----------|
| Name | `agentCard.name` | — | `@testId("agentCard.name")` |
| Origin label | `agentCard.originLabel` | — | `@testId("agentCard.originLabel")` |
| Description | `agentCard.description` | — | `@testId("agentCard.description")` |
| Start button | `agentCard.startButton` | — | `@testId("agentCard.startButton")` |
| Edit button | `agentCard.editButton` | — | `@testId("agentCard.editButton")` |

### DelegateSheet

**File:** `Views/Components/DelegateSheet.swift`

| Control | Identifier | Label | Selector |
|---------|-----------|-------|----------|
| Agent header | `delegate.agentHeader` | — | `@testId("delegate.agentHeader")` |
| Task field | `delegate.taskField` | — | `@testId("delegate.taskField")` |
| Context field | `delegate.contextField` | — | `@testId("delegate.contextField")` |
| Wait toggle | `delegate.waitToggle` | — | `@testId("delegate.waitToggle")` |
| Cancel button | `delegate.cancelButton` | — | `@testId("delegate.cancelButton")` |
| Submit button | `delegate.submitButton` | — | `@testId("delegate.submitButton")` |

### MarkdownContent

**File:** `Views/Components/MarkdownContent.swift`

| Control | Identifier | Selector |
|---------|-----------|----------|
| Root | `markdownContent` | `@testId("markdownContent")` |

### HighlightedCodeView (NSViewRepresentable)

**File:** `Views/Components/HighlightedCodeView.swift`

| Control | Identifier | Selector |
|---------|-----------|----------|
| Scroll view | `highlightedCode.scrollView` | `@testId("highlightedCode.scrollView")` |
| Text view | `highlightedCode.textView` | `@testId("highlightedCode.textView")` |

### PasteableTextField (NSViewRepresentable)

**File:** `Views/Components/PasteableTextField.swift`

| Control | Identifier | Selector |
|---------|-----------|----------|
| Inner NSTextField | `pasteableTextField.input` | `@testId("pasteableTextField.input")` |

Set via AppKit `setAccessibilityIdentifier`. The SwiftUI wrapper gets its own identifier from the parent (e.g., `chat.messageInput`).

---

## 7. Argus macOS Testing (Outside-In E2E)

Argus can drive Odyssey as a macOS app without the AppXray SDK.

### Starting a Session

```javascript
inspect({ platform: "macos", appName: "Odyssey" })
```

This captures a screenshot and the accessibility element tree.

### Interacting

```javascript
// Tap by accessibility identifier
act({ action: "tap", selector: "chat.sendButton" })

// Type into a field
act({ action: "input", selector: "chat.messageInput", text: "Hello, agent!" })

// Press keyboard keys
act({ action: "press", key: "Enter" })

// Swipe/scroll
act({ action: "swipe", direction: "down" })
```

### Asserting

```javascript
// Check element is visible
assert({ type: "visible", selector: "chat.streamingBubble" })

// Check text content
assert({ type: "text", selector: "chat.topicTitle", text: "My Conversation" })

// AI vision assertion (screenshot-based)
assert({ type: "ai", prompt: "The chat view shows a streaming response with code blocks" })

// Check element is hidden
assert({ type: "hidden", selector: "chat.streamingBubble" })
```

### Waiting

```javascript
// Wait for an element to appear
wait({ for: "element", selector: "chat.streamingBubble" })

// Wait for element to disappear
wait({ for: "hidden", selector: "streamingIndicator" })

// Wait for text
wait({ for: "text", text: "Session completed" })

// Fixed delay
wait({ for: "duration", duration: 2000 })
```

### YAML Regression Tests

Argus supports YAML test files for repeatable regression testing:

```yaml
name: Create and send message
platform: macos
appName: Odyssey
steps:
  - inspect: {}
  - act:
      action: tap
      selector: "mainWindow.newSessionButton"
  - wait:
      for: element
      selector: "newSession.title"
  - act:
      action: tap
      selector: "newSession.startKind.blank"
  - act:
      action: tap
      selector: "newSession.startSessionButton"
  - wait:
      for: element
      selector: "chat.messageInput"
  - act:
      action: input
      selector: "chat.messageInput"
      text: "What is 2 + 2?"
  - act:
      action: tap
      selector: "chat.sendButton"
  - wait:
      for: element
      selector: "chat.streamingBubble"
      timeout: 10000
  - assert:
      type: visible
      selector: "chat.streamingBubble"
```

Run with:
```javascript
test({ action: "run", path: "tests/create-session.yaml", platform: "macos", appName: "Odyssey" })
```

### Example: Full Session Flow

```javascript
// 1. Launch and inspect
inspect({ platform: "macos", appName: "Odyssey" })

// 2. Check sidecar is connected
assert({ type: "ai", prompt: "The sidecar status pill shows Connected" })

// 3. Open new session sheet
act({ action: "tap", selector: "mainWindow.newSessionButton" })
wait({ for: "element", selector: "newSession.title" })

// 4. Switch to Blank and start
act({ action: "tap", selector: "newSession.startKind.blank" })
act({ action: "tap", selector: "newSession.startSessionButton" })
wait({ for: "element", selector: "chat.messageInput" })

// 5. Send a message
act({ action: "input", selector: "chat.messageInput", text: "Hello!" })
act({ action: "tap", selector: "chat.sendButton" })

// 6. Wait for response
wait({ for: "element", selector: "chat.streamingBubble", timeout: 15000 })
wait({ for: "hidden", selector: "streamingIndicator", timeout: 60000 })

// 7. Verify response appeared
inspect({})
assert({ type: "ai", prompt: "The chat shows at least one assistant response message" })
```

---

## 8. Dynamic Identifiers

Many identifiers include runtime values. Here are the patterns:

### UUID-based

Used for any SwiftData entity row/card. The UUID is the entity's `id.uuidString`.

| Pattern | Used In |
|---------|--------|
| `sidebar.conversationRow.{uuid}` | SidebarView |
| `sidebar.agentRow.{uuid}` | SidebarView |
| `sidebar.agentRow.startSession.{uuid}` | SidebarView context menu |
| `newSession.recentAgent.{uuid}` | NewSessionSheet recent chips |
| `newSession.recentGroup.{uuid}` | NewSessionSheet recent chips |
| `newSession.agentRow.{uuid}` | NewSessionSheet list picker |
| `newSession.agentCard.{uuid}` | NewSessionSheet card picker |
| `newSession.groupRow.{uuid}` | NewSessionSheet list picker |
| `newSession.groupCard.{uuid}` | NewSessionSheet card picker |
| `newSession.groupMembers.{groupUuid}` | NewSessionSheet expanded group panel |
| `newSession.groupMember.{groupUuid}.{agentUuid}` | NewSessionSheet expanded group member |
| `agentLibrary.card.{uuid}` | AgentLibraryView |
| `agentLibrary.card.context.{action}.{uuid}` | AgentLibraryView context menu |
| `newSession.recentAgent.{uuid}` | NewSessionSheet |
| `newSession.agentCard.{uuid}` | NewSessionSheet |
| `agentComms.event.{uuid}` | AgentCommsView |
| `agentComms.eventIcon.{uuid}` | AgentCommsView |
| `agentComms.eventTimestamp.{uuid}` | AgentCommsView |
| `messageBubble.{type}.{uuid}` | MessageBubble |
| `messageBubble.senderLabel.{uuid}` | MessageBubble |
| `messageBubble.copyButton.{uuid}` | MessageBubble |
| `messageBubble.forkFromHere.{uuid}` | MessageBubble |
| `messageBubble.thinkingToggle.{uuid}` | MessageBubble |
| `messageBubble.attachment.{uuid}` | MessageBubble |
| `toolCall.container.{uuid}` | ToolCallView |
| `toolCall.title.{uuid}` | ToolCallView |
| `toolCall.toggleButton.{uuid}` | ToolCallView |
| `attachmentThumbnail.{uuid}` | AttachmentThumbnail |
| `mcpLibrary.mcpRow.{uuid}` | MCPLibraryView |
| `skillLibrary.skillCard.{uuid}` | SkillLibraryView |
| `agentEditor.skills.removeButton.{uuid}` | AgentEditorView |
| `agentEditor.skills.addButton.{uuid}` | AgentEditorView |
| `skillEditor.mcps.removeButton.{uuid}` | SkillEditorView |
| `skillEditor.mcps.addButton.{uuid}` | SkillEditorView |

### Index-based

| Pattern | Used In |
|---------|--------|
| `chat.pendingAttachment.{index}` | ChatView |
| `chat.pendingAttachment.remove.{index}` | ChatView |
| `directoryPicker.recent.{index}` | WorkingDirectoryPicker |

### Name / String-based

| Pattern | Used In |
|---------|--------|
| `inspector.fileTree.directoryRow.{name}` | FileTreeView |
| `inspector.fileTree.fileRow.{name}` | FileTreeView |
| `catalog.categoryChip.{title}` | CatalogBrowserView |
| `catalog.agentCard.{catalogId}` | CatalogBrowserView |
| `catalog.skillCard.{catalogId}` | CatalogBrowserView |
| `catalog.mcpCard.{catalogId}` | CatalogBrowserView |
| `mcpCatalogSheet.row.{catalogId}` | MCPCatalogSheet |

### Label Slug-based

| Pattern | Used In |
|---------|--------|
| `infoRow.{labelSlug}` | InspectorView |

The slug is the label text lowercased with spaces removed. Examples: `infoRow.status`, `infoRow.model`, `infoRow.tokens`, `infoRow.cost`.

---

## 9. Naming Convention

All accessibility identifiers follow a consistent pattern:

```
{viewPrefix}.{elementName}
{viewPrefix}.{elementName}.{dynamicSuffix}
```

- **viewPrefix**: camelCase, unique per view (e.g., `chat`, `sidebar`, `agentEditor`)
- **elementName**: camelCase descriptor (e.g., `sendButton`, `messageInput`, `conversationRow`)
- **dynamicSuffix**: UUID string, index, or name for dynamic elements

### Prefix Map

| View | Prefix |
|------|--------|
| MainWindowView | `mainWindow` |
| SidebarView | `sidebar` |
| ChatView | `chat` |
| InspectorView | `inspector` |
| FileExplorerView | `inspector.fileTree` |
| FileContentView | `inspector.fileContent` |
| NewSessionSheet | `newSession` |
| WorkingDirectoryPicker | `directoryPicker` |
| IntentLibraryHubView | `libraryHub` |
| AgentLibraryView | `agentLibrary` |
| AgentEditorView | `agentEditor` |
| AgentCommsView | `agentComms` |
| CatalogBrowserView | `catalog` |
| CatalogDetailView | `catalogDetail` |
| SettingsView | `settings.{tab}` |
| MCPLibraryView | `mcpLibrary` |
| MCPEditorView | `mcpEditor` |
| MCPCatalogSheet | `mcpCatalogSheet` |
| SkillLibraryView | `skillLibrary` |
| SkillEditorView | `skillEditor` |
| MessageBubble | `messageBubble` |
| ToolCallView | `toolCall` |
| CodeBlockView | `codeBlock` |
| ImagePreviewOverlay | `imagePreview` |
| StreamingIndicator | `streamingIndicator` |
| StatusBadge | `statusBadge` |
| AttachmentThumbnail | `attachmentThumbnail` |
| AgentCardView | `agentCard` |
| DelegateSheet | `delegate` |
| MarkdownContent | `markdownContent` |
| HighlightedCodeView | `highlightedCode` |
| PasteableTextField | `pasteableTextField` |
| InfoRow | `infoRow` |

### Rules

- **Buttons with text**: `.accessibilityIdentifier()` only
- **Icon-only buttons**: `.accessibilityIdentifier()` + `.accessibilityLabel("Human-readable action")`
- **TextFields / TextEditors / Pickers / Toggles / Steppers**: `.accessibilityIdentifier()`
- **Lists / ScrollViews**: `.accessibilityIdentifier()` on the container
- **Dynamic ForEach rows**: suffix with `.{item.id.uuidString}`
- **Decorative elements**: `.accessibilityElement(children: .ignore)`
- **Never reuse** an identifier across different views

---

## 10. Known Gaps

The following interactive elements do not have explicit accessibility identifiers:

| Area | Missing |
|------|---------|
| **Alerts / Confirmation Dialogs** | "Clear Messages" alert, delete confirmation dialogs, reset settings dialog — buttons within these have no identifiers |
| **Swipe Actions** | Sidebar conversation row swipe-to-delete and swipe-to-pin |
| **Some Context Menus** | Rename, Pin/Unpin, Close, Duplicate, Delete on sidebar conversation rows |
| **DiffTextView** | `NSViewRepresentable` with no SwiftUI accessibility identifier |
| **System Search Fields** | `.searchable()` fields use system-provided controls |
| **Markdown Links** | Links rendered by MarkdownUI have no custom identifiers |
| **File Importer** | System file picker dialog |

When automating around these gaps, use Argus `@text("...")` or `@label("...")` selectors, or AI vision assertions (`assert({ type: "ai", prompt: "..." })`).
