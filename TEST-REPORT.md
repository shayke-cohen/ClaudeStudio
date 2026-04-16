# Odyssey Test Report

> Historical note: this report predates the project-first shell reset. References to sidebar agent sections or global chat lists describe the old layout, not the current project-scoped navigation.

**Date:** 2026-03-21
**Platform:** macOS (darwin 24.6.0)
**Build:** Debug (Xcode)

---

## 1. Sidecar API Tests (Automated)

**Test runner:** `sidecar/test/sidecar-api.script.ts`
**Result:** 11/11 PASSED (7.8s total)

### HTTP API

| # | Test | Result | Duration |
|---|------|--------|----------|
| 1 | `GET /health` returns ok | PASS | 9ms |
| 2 | `POST /blackboard/write` creates entry | PASS | 2ms |
| 3 | `GET /blackboard/read` returns entry | PASS | 1ms |
| 4 | `GET /blackboard/read` returns 404 for missing key | PASS | <1ms |
| 5 | `GET /blackboard/query` returns matching entries | PASS | 2ms |
| 6 | `GET /blackboard/keys` returns key list | PASS | 1ms |
| 7 | `POST /blackboard/write` rejects missing value (400) | PASS | <1ms |

### WebSocket Session API

| # | Test | Result | Duration |
|---|------|--------|----------|
| 8 | `session.message` to unknown session returns error | PASS | 3ms |
| 9 | `session.create` + `session.message` round-trip (real Claude) | PASS | 3741ms |
| 10 | `session.fork` creates forked session | PASS | 2ms |
| 11 | `session.pause` stops running session | PASS | 3312ms |

### Streaming Events Verified
- `sidecar.ready` — received on WebSocket connect
- `stream.token` — received during Claude response streaming
- `session.result` — received after Claude completes response
- `session.error` — received for unknown session IDs

---

## 2. UI Tests (Argus MCP — macOS)

**Tool:** Argus MCP (macOS platform, screenshot + AI assertion)
**App:** Odyssey.app (Debug build, PID 56176)

### Layout & Structure

| # | Test | Result | Notes |
|---|------|--------|-------|
| 1 | Three-panel layout renders correctly | PASS | Sidebar, chat, inspector all visible |
| 2 | Sidebar shows Active section with conversations | PASS | 5 "New Chat" items with green dots |
| 3 | Sidebar shows Agents section | PASS | Empty (no agents created) |
| 4 | Empty state shows "No Conversation Selected" | PASS | Verified before selecting chat |
| 5 | Search field in toolbar | PASS | "Search conversations..." placeholder |

### Conversation Selection

| # | Test | Result | Notes |
|---|------|--------|-------|
| 6 | Tap conversation selects it (blue highlight) | PASS | First "New Chat" selected |
| 7 | Chat header shows conversation name + participants | PASS | "New Chat" / "You" |
| 8 | Chat header has fork and pause buttons | PASS | Branch icon + pause icon |
| 9 | Inspector shows conversation metadata | PASS | Status, Participants, Messages, Started |
| 10 | Inspector shows correct participant count | PASS | "Participants 1" / "You" |
| 11 | Inspector shows correct message count | PASS | "Messages 0" |
| 12 | Message input field visible | PASS | "Type a message..." placeholder |
| 13 | Send button visible (disabled when empty) | PASS | Arrow circle icon |

### Agent Library

| # | Test | Result | Notes |
|---|------|--------|-------|
| 14 | Agent Library button opens modal | PASS | Toolbar CPU icon triggers sheet |
| 15 | Modal shows "Agent Library" title | PASS | Header with title |
| 16 | Filter segmented control (All/Mine/Shared) | PASS | Three segments, "All" selected |
| 17 | Search field in Agent Library | PASS | "Search..." placeholder |
| 18 | "+ New Agent" button visible | PASS | Bordered prominent style |
| 19 | Close button dismisses modal | PASS | Escape key closes sheet |
| 20 | Empty state (no agents) | PASS | Content area empty |

### Toolbar & Status

| # | Test | Result | Notes |
|---|------|--------|-------|
| 21 | Odyssey title in toolbar | PASS | Centered in title bar |
| 22 | New Chat button (plus.bubble) | PASS | Creates new conversations |
| 23 | Agent Library button (cpu) | PASS | Opens agent library sheet |
| 24 | Peer Network button (network) | PASS | Visible in toolbar |
| 25 | Sidecar status indicator | PASS | Green dot visible (connected to sidecar) |
| 26 | Sidebar toggle buttons | PASS | Layout toggle visible |

---

## 3. Backend Connectivity

| Component | Status | Port | Notes |
|-----------|--------|------|-------|
| Sidecar WebSocket | Running | 9849 | PID 46993 |
| Sidecar HTTP API | Running | 9850 | Health returns ok |
| AppXray Relay | Down | 19400 | Connection refused (non-critical) |
| Claude Agent SDK | Working | — | Real responses verified in test 9 |

---

## 4. Known Issues

| # | Severity | Description |
|---|----------|-------------|
| 1 | Low | AppXray relay (port 19400) not running — `Connection refused` errors in logs. Non-functional impact since AppXray is optional for testing. |
| 2 | Low | Zombie Odyssey process (PID 99899, UE state) from prior SwiftData crash still present. Requires reboot to clear. |
| 3 | Medium | Sidecar EADDRINUSE when app launches while standalone sidecar is already running. App's embedded sidecar launch fails gracefully but doesn't connect to existing instance. |
| 4 | Low | All sidebar conversations show "New Chat" — no auto-rename based on first message content. |

---

## Summary

**API Tests:** 11/11 passed (100%)
**UI Tests:** 26/26 passed (100%)
**Total:** 37/37 passed

All core Phase 1 functionality is working:
- SwiftUI three-panel layout renders correctly
- Conversation list, selection, and inspector work
- Agent Library modal opens/closes with filter and search
- Sidecar WebSocket and HTTP APIs fully functional
- Claude Agent SDK integration works (real streaming responses)
- Blackboard read/write/query/keys all operational
- Session lifecycle (create, message, fork, pause) verified
