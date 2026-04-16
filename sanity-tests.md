# Odyssey — Sanity Test Plan

Rerunnable sanity test plan for the Odyssey sidecar. Covers unit, integration, API, protocol, and E2E layers.

> Project-first shell note: the product now organizes UI around Projects → Threads/Tasks/Team/Schedules. Any older sidebar references in this file should be treated as legacy until the matching sanity scripts are refreshed.

---

## Prerequisites

- **Bun** installed and on `$PATH`
- **Sidecar** source at `sidecar/`
- Claude subscription active (no API key needed — `ANTHROPIC_API_KEY` is set via subscription)
- `ODYSSEY_E2E_LIVE=1` to enable live Claude SDK tests (tests marked `[LIVE]` are skipped otherwise)

## Running All Tests

```bash
cd sidecar

# Full suite including live Claude SDK calls
ODYSSEY_E2E_LIVE=1 bun test

# Offline only (skips live tests)
bun test
```

### Run Individual Test Groups

```bash
# Unit tests (stores, registries, channels)
bun test test/unit/stores.test.ts

# Integration tests (PeerBus tool handlers)
bun test test/integration/peerbus-tools.test.ts

# HTTP API tests
bun test test/api/http-api.test.ts

# WebSocket protocol tests
bun test test/api/ws-protocol.test.ts

# E2E: full session lifecycle
bun test test/e2e/full-flow.test.ts

# E2E: all scenario groups
ODYSSEY_E2E_LIVE=1 bun test test/e2e/scenarios.test.ts

# E2E: focused live backend regressions
ODYSSEY_E2E_CLAUDE=1 bun test test/e2e/backend-live.test.ts
ODYSSEY_E2E_OLLAMA=1 bun test test/e2e/backend-live.test.ts

# E2E: specific scenario group
bun test test/e2e/scenarios.test.ts -t "BB: Blackboard"
```

All E2E test files boot their own sidecar subprocess on random ports — no manual sidecar start needed.

---

## Test File Inventory

### 1. `test/unit/stores.test.ts` — 46 tests

In-memory store unit tests. No network, no sidecar process.

| Group | Count | What It Covers |
|-------|-------|----------------|
| BlackboardStore | 9 | write/read, overwrite, glob query, keys, workspace scope, subscribe/unsubscribe |
| SessionRegistry | 11 | create/get, config, update, remove, list, listActive, findByAgentName (case-insensitive, filtering, empty) |
| MessageStore | 6 | push/drain, read tracking, since filter, empty inbox, peek count, pushToAll broadcast |
| ChatChannelStore | 14 | create, get, addParticipant (including closed), addMessage, waitForReply (resolve/closed/timeout), close, deadlock detection, list/listOpen, waitForIncoming |
| WorkspaceStore | 6 | create, get, missing, join (including idempotent and missing), list |

---

### 2. `test/integration/peerbus-tools.test.ts` — 30 tests

Integration tests for PeerBus tool handlers. Creates stores in-memory, no sidecar process.

| Group | Count | What It Covers |
|-------|-------|----------------|
| Blackboard Tools | 5 | write+broadcast, read, read-missing, query, subscribe |
| Messaging Tools | 15 | send (direct, by-name, unknown), broadcast, receive/drain, list agents, delegate (spawn, singleton, pool at cap, pool under cap, least-busy routing, context, unique IDs), list definitions |
| Chat Tools | 10 | start+block+resolve, start-unknown, reply+wait, reply-missing, close+resolve, listen, listen-timeout, invite, invite-unknown, listen-with-message |
| Workspace Tools | 4 | create, join, join-missing, list |

---

### 3. `test/api/http-api.test.ts` — 18 tests

HTTP server tests. Boots its own HTTP server on a random port.

| Group | Count | What It Covers |
|-------|-------|----------------|
| GET /health | 2 | `/health` and `/blackboard/health` both return 200 |
| POST /blackboard/write | 6 | create, JSON value, default writtenBy, missing key, missing value, overwrite |
| GET /blackboard/read | 3 | existing entry, 404 for missing, 400 for no key param |
| GET /blackboard/query | 2 | matching entries, wildcard default |
| GET /blackboard/keys | 2 | all keys, scope filter |
| CORS | 2 | OPTIONS returns headers, responses include allow-origin |
| Unknown routes | 1 | 404 for unknown path |

---

### 4. `test/api/ws-protocol.test.ts` — 13 tests

WebSocket protocol conformance. Boots its own WS server on a random port.

| Group | Count | What It Covers |
|-------|-------|----------------|
| Connection | 2 | connect+ready, multiple clients |
| Command Dispatch | 5 | session.create, session.message, agent.register (spawn/singleton/pool:N), delegate.task, delegate unknown |
| Delegation Policy | 4 | singleton reuse, pool least-busy routing, pause+resume dispatch, full config with skills+maxBudget |
| Broadcasting | 1 | event sent to all connected clients |

---

### 5. `test/e2e/full-flow.test.ts` — 8 tests

End-to-end with a real sidecar subprocess (random ports).

| Group | Count | What It Covers |
|-------|-------|----------------|
| Sidecar Boot | 2 | HTTP health, WS connect+ready |
| Blackboard (HTTP + WS) | 2 | write+read via HTTP, query returns entries |
| Agent Registration | 1 | agent.register stores definitions |
| Session Lifecycle | 3 | create establishes state, message-to-unknown errors, create+message streams tokens+result `[LIVE]` |
| Session Pause & Fork | 1 | fork returns confirmation |
| Concurrent Clients | 1 | both clients read same blackboard via HTTP |

---

### 6. `test/e2e/scenarios.test.ts` — 27 tests

Comprehensive E2E scenarios with a real sidecar subprocess. The main sanity suite.

#### GC: Group Chat — Swift app protocol (1 test)

| ID | Test | Live | Timeout | What It Verifies |
|----|------|------|---------|------------------|
| GC-1 | Two UUID session keys, Alpha then Beta with injected transcript block | LIVE | 180s | Matches per-`Session.id` routing: two `session.create` → message Alpha → build `GroupPromptBuilder`-shaped text including Alpha’s reply → message Beta → Beta’s answer reflects the thread |

#### S: Session Lifecycle (5 tests)

| ID | Test | Live | Timeout | What It Verifies |
|----|------|------|---------|------------------|
| S-1 | Create session, send message, receive tokens + result | LIVE | 90s | Full round-trip: `session.create` → `session.message` → `stream.token` → `session.result` |
| S-2 | Pause mid-stream sets paused status | LIVE | 120s | Long prompt streaming → `session.pause` → clean termination |
| S-3 | Resume restores session context | — | 30s | `session.resume` with fake Claude session ID → "context restored" token |
| S-4 | Fork creates new session with confirmation | — | 30s | `session.fork` → "Forked" confirmation token |
| S-5 | Two simultaneous sessions stream independently | LIVE | 120s | Two concurrent sessions (ALPHA/BETA) → both produce results |

#### UC: User-to-Chat (2 tests)

| ID | Test | Live | Timeout | What It Verifies |
|----|------|------|---------|------------------|
| UC-1 | User sends message, agent responds with full stream | LIVE | 90s | PING → PONG with streaming tokens and result |
| UC-2 | Message to unknown session returns error | — | 30s | `session.error` with "not found" |

#### CHAT: Agent Chat (2 tests)

| ID | Test | Live | Timeout | What It Verifies |
|----|------|------|---------|------------------|
| CHAT-1 | Agent-provisioned config with model alias and fresh sandbox dir | LIVE | 90s | Model alias `"sonnet"` resolved, non-existent sandbox `cwd` created, full stream.token + session.result round-trip |
| CHAT-2 | Non-existent working directory is created before query | — | 60s | Deeply nested `cwd` path auto-created by sidecar before SDK `query()` |

#### UA: User-to-Agent (3 tests)

| ID | Test | Live | Timeout | What It Verifies |
|----|------|------|---------|------------------|
| UA-1 | session.create with custom config stores in registry | — | 30s | Custom model/maxTurns/maxBudget accepted |
| UA-2 | delegate.task broadcasts peer.delegate and spawns session | — | 30s | Register agent → delegate → `peer.delegate` broadcast |
| UA-3 | delegate.task to unknown agent returns error | — | 30s | `session.error` with "not found" |

#### AA: Agent-to-Agent Messaging (2 tests)

| ID | Test | Live | Timeout | What It Verifies |
|----|------|------|---------|------------------|
| AA-1 | agent.register makes agents discoverable | — | 30s | Register Alice + Bob with different policies |
| AA-2 | Broadcast reaches all connected clients | — | 30s | Two WS clients both receive `peer.delegate` |

#### D: Delegation Policy Enforcement (5 tests)

| ID | Test | Live | Timeout | What It Verifies |
|----|------|------|---------|------------------|
| D-1 | Spawn policy creates new session per delegation | — | 30s | Two delegations → two `peer.delegate` events |
| D-2 | Singleton policy registered via agent.register | — | 30s | Singleton agent delegation works |
| D-3 | Pool:N policy registered correctly | — | 30s | pool:3 agent delegation works |
| D-4 | Delegation with context includes context in broadcast | — | 30s | Context string carried through to `peer.delegate` |
| D-5 | Multiple delegations to same agent all broadcast | — | 30s | 3 rapid delegations → 3 `peer.delegate` events |

#### BB: Blackboard Shared State (3 tests)

| ID | Test | Live | Timeout | What It Verifies |
|----|------|------|---------|------------------|
| BB-1 | Write via HTTP, read via HTTP | — | 30s | Round-trip value + writtenBy |
| BB-2 | Overwrite preserves key | — | 30s | Last-write-wins semantics |
| BB-3 | Query returns multiple entries | — | 30s | Pattern glob `prefix.*` returns ≥2 |

#### O: Multi-Agent Orchestration (3 tests)

| ID | Test | Live | Timeout | What It Verifies |
|----|------|------|---------|------------------|
| O-1 | Linear chain A → B | — | 30s | Sequential delegation with correct `from` field |
| O-2 | Fan-out to 3 agents | — | 30s | All 3 `peer.delegate` events arrive |
| O-3 | Delegation + blackboard pipeline | — | 30s | HTTP blackboard write → delegate → blackboard update → delegate → verify final state |

#### ACCEPT: Full Orchestration Pipeline (1 test)

| ID | Test | Live | Timeout | What It Verifies |
|----|------|------|---------|------------------|
| ACCEPT-1 | Orchestrator delegates to multiple specialists | LIVE | 11 min | 5 agents (Orchestrator, Researcher, Coder, Reviewer, Tester) with real prompts. Verifies ≥1 delegation, token streaming, and orchestrator produces final result. |

---

### 7. `test/e2e/backend-live.test.ts` — 2 tests

Focused backend regression tests. Boots its own sidecar subprocess on random ports.

| Group | Count | What It Covers |
|-------|-------|----------------|
| Native Claude backend | 1 | Real Claude Agent SDK round-trip with a native Claude model |
| Ollama-backed Claude backend | 1 | Real `/api/tags` discovery plus live round-trip using `model: ollama:<downloaded-tag>` |

---

## Quick Counts

| Test File | Tests | Offline | Live | Status |
|-----------|-------|---------|------|--------|
| `test/unit/stores.test.ts` | 46 | 46 | 0 | All pass |
| `test/integration/peerbus-tools.test.ts` | 30 | 30 | 0 | All pass |
| `test/api/http-api.test.ts` | 18 | 18 | 0 | All pass |
| `test/api/ws-protocol.test.ts` | 13 | 13 | 0 | All pass |
| `test/e2e/full-flow.test.ts` | 8 | 7 | 1 | All pass |
| `test/e2e/scenarios.test.ts` | 27 | 20 | 7 | All pass |
| `test/e2e/backend-live.test.ts` | 2 | 0 | 2 | New |
| **Total** | **144** | **134** | **10** | |

---

## Known Issue: `test/sidecar-api.script.ts` (legacy manual harness)

This file is a **legacy standalone runner** (9/11 passing, 2 failing). It has its own `main()` entry point, doesn't use the `bun:test` framework, and connects to hardcoded ports 9849/9850 expecting a pre-running sidecar. Renamed from `.test.ts` → `.script.ts` so `bun test` (no args) no longer auto-discovers it; run via `scripts/run-all-tests.sh` or directly with `bun run test/sidecar-api.script.ts`.

**Failing tests:**
1. `session.create + session.message round-trip` — expects a confirmation `stream.token` after `session.create`, but the sidecar no longer emits one on create.
2. `session.pause stops running session` — 21s timeout; stale expectation about post-pause messages.

These are **stale expectations** superseded by `scenarios.test.ts` which tests the same flows correctly (S-1 and S-2). This file should either be updated or removed.

---

## Test Infrastructure

The test harness (`test/helpers.ts`) provides:

- **`waitForHealth(port)`** — polls HTTP health endpoint until the sidecar is ready
- **`wsConnect(port)`** — opens a `BufferedWs` WebSocket client that buffers all messages
- **`BufferedWs.waitFor(predicate, timeout)`** — resolves when a matching message arrives
- **`BufferedWs.collectUntil(predicate, timeout)`** — accumulates messages until predicate matches
- **`makeAgentConfig(overrides)`** — builds a minimal `AgentConfig` with sensible defaults

Each E2E file boots its own sidecar subprocess on random ports (WS: 39849–40349, HTTP: 39850–40350) with a temp data directory, so tests are fully isolated.

---

## UI/E2E Testing with AppXray

AppXray provides inside-out testing of a running DEBUG build. It connects via WebSocket relay and gives deep access to the component tree, state, network, and UI automation.

### Architecture

```
Odyssey (DEBUG) ──WebSocket──> MCP Relay (127.0.0.1:19400) <──stdio── AppXray MCP Server <── AI Agent (Cursor)
```

### Prerequisites

- Odyssey built in **DEBUG** configuration (AppXray SDK is `#if DEBUG` only in `OdysseyApp.swift`)
- AppXray MCP server configured in Cursor (runs via `npx -y @wix/appxray-mcp-server` with `APPXRAY_AUTO_CONNECT=true`)
- The relay starts automatically on `127.0.0.1:19400` when the MCP server launches

### Connecting

```javascript
// 1. Discover running AppXray-enabled apps
session({ action: "discover" })

// 2. Connect to Odyssey
session({ action: "connect", appId: "com.odyssey.app" })

// 3. Full snapshot (tree + screenshot + state + network + logs)
inspect({ target: "tree" })
```

### Example Test Flows

All selectors reference accessibility identifiers documented in `TESTING.md` Section 5.

**Sidebar navigation:**
```javascript
interact({ action: "tap", selector: '@testId("sidebar.newSessionButton")' })
interact({ action: "wait", selector: '@testId("newSession.title")' })
interact({ action: "tap", selector: '@testId("newSession.agentCard.freeform")' })
interact({ action: "tap", selector: '@testId("newSession.startSessionButton")' })
```

**Send a message:**
```javascript
interact({ action: "type", selector: '@testId("chat.messageInput")', text: "Hello!" })
interact({ action: "tap", selector: '@testId("chat.sendButton")' })
interact({ action: "wait", selector: '@testId("chat.streamingBubble")' })
```

**Agent library:**
```javascript
interact({ action: "tap", selector: '@testId("sidebar.agentsButton")' })
interact({ action: "wait", selector: '@testId("agentLibrary.title")' })
interact({ action: "tap", selector: '@testId("agentLibrary.newAgentButton")' })
```

**Inspector panel:**
```javascript
interact({ action: "tap", selector: '@testId("mainWindow.inspectorToggle")' })
interact({ action: "wait", selector: '@testId("inspector.tabPicker")' })
```

**Settings tabs:**
```javascript
// Open Settings (Cmd+,), then:
interact({ action: "tap", selector: '@testId("settings.tab.connection")' })
interact({ action: "tap", selector: '@testId("settings.tab.developer")' })
```

### Available AppXray Tools

| Tool | Purpose |
|------|---------|
| `session` | Discover apps, connect/disconnect |
| `inspect` | Component tree, state, network, storage, accessibility, logs |
| `act` | Mutate state, trigger navigation |
| `interact` | UI automation: tap, type, swipe, wait, screenshot |
| `diagnose` | Health scans (quick/standard/deep) |
| `suggest` | Root-cause hypotheses |
| `trace` | Render/state/data-flow tracing |
| `diff` | Baseline snapshots and compare |
| `mock` | Network mocks and overrides |
| `config` | Feature flags and environment |
| `timetravel` | Checkpoints, restore, history |
| `chaos` | Inject failures (network errors, slow responses) |
| `batch` | Multiple operations in one call |
| `advanced` | eval, coverage, event subscribe |
| `report` | File bugs/features as GitHub issues |

---

## Parallel App Instances

Odyssey supports running multiple isolated instances simultaneously via the `--instance` flag. Each instance gets its own data, ports, and sidecar process.

### Launching Instances

```bash
# Launch three isolated instances for parallel testing
open -n /path/to/Odyssey.app --args --instance test-sidebar
open -n /path/to/Odyssey.app --args --instance test-chat
open -n /path/to/Odyssey.app --args --instance test-agents
```

### Isolation Per Instance

Each named instance (via `InstanceConfig.swift`) gets:

| Resource | Path / Value |
|----------|-------------|
| UserDefaults suite | `com.odyssey.app.<name>` |
| SwiftData store | `~/.odyssey/instances/<name>/data/Odyssey.store` |
| Blackboard data | `~/.odyssey/instances/<name>/blackboard/` |
| Log directory | `~/.odyssey/instances/<name>/logs/` |
| Sidecar log | `~/.odyssey/instances/<name>/logs/sidecar.log` |
| WS + HTTP ports | Auto-assigned free ports (non-default instances) |
| Sidecar process | Separate subprocess per instance |

### Connecting AppXray to a Specific Instance

Each instance registers independently with the AppXray relay:

```javascript
// Discover all running instances
session({ action: "discover" })
// Returns multiple entries — connect by session/process ID
session({ action: "connect", sessionId: "<id-from-discover>" })
```

### Parallel Testing Pattern

```
Instance "test-sidebar"  --> AppXray session 1 --> sidebar + navigation tests
Instance "test-chat"     --> AppXray session 2 --> chat + streaming tests
Instance "test-agents"   --> AppXray session 3 --> agent library + editor tests
```

### Warning

Do **not** run two instances both as "default" (no `--instance` flag). They would share:
- Ports 9849/9850 and the same sidecar process
- The same SwiftData store at `~/.odyssey/instances/default/data/`
- The same UserDefaults suite

This causes broadcast cross-talk between sessions and potential data corruption.

---

## Troubleshooting

### Sidecar Won't Connect

1. **Check the status pill** in the toolbar (`mainWindow.sidecarStatusPill`) — shows disconnected, connecting, connected, or error
2. **Check the sidecar log:** `~/.odyssey/instances/<instance>/logs/sidecar.log`
3. **Hit the health endpoint:** `curl -s http://127.0.0.1:9850/health | jq .`
4. **Verify Bun is installed** — the app searches these paths in order:
   - `/opt/homebrew/bin/bun`
   - `/usr/local/bin/bun`
   - `~/.bun/bin/bun`
   - `bun` on `$PATH`

### Common Issues

| Problem | Symptom | Fix |
|---------|---------|-----|
| Bun not found | `error` status on connect | Install Bun or set path in Settings > Developer > Bun Path |
| Sidecar path not found | `error` status | Set project path in Settings > Developer > Project Path (must contain `sidecar/src/index.ts`) |
| EADDRINUSE (port conflict) | Sidecar launch fails, log shows "address in use" | Kill orphan: `lsof -i :9849` then `kill <pid>`, or change ports in Settings > Connection |
| Two default instances | Broadcast cross-talk, data corruption | Always use `--instance <name>` for parallel runs |
| AppXray relay down | `Connection refused` on port 19400 | Ensure AppXray MCP server is running in Cursor (`APPXRAY_AUTO_CONNECT=true npx -y @wix/appxray-mcp-server`) |
| WS disconnect loop | Status flickers connecting/disconnected | Check `sidecar.log` for crash; auto-reconnect runs (2s delay, 5s on failure) |
| Release build, no AppXray | `session({ action: "discover" })` finds nothing | AppXray SDK is `#if DEBUG` only; rebuild in Debug configuration |

### Reconnect Behavior

- On WebSocket disconnect or sidecar process exit: auto-reconnect after **2 seconds**
- Reconnect tries connecting to an existing sidecar first, then relaunches
- On relaunch failure: retries every **5 seconds** indefinitely
- Manual: Settings > Connection > **Reconnect** button, or **Stop** then **Connect**

### Log Locations

| Log | Location |
|-----|----------|
| Sidecar output | `~/.odyssey/instances/<instance>/logs/sidecar.log` |
| Sidecar prefixes | `[odyssey-sidecar]`, `[ws]`, `[http]` |
| Swift app | `[SidecarManager]`, `[AppState]` in Xcode console or `Console.app` |

### Quick Health Check

```bash
# Sidecar HTTP health
curl -s http://127.0.0.1:9850/health | jq .

# Find processes on sidecar ports
lsof -i :9849 -i :9850

# Tail sidecar log (default instance)
tail -50 ~/.odyssey/instances/default/logs/sidecar.log

# Tail a named instance log
tail -50 ~/.odyssey/instances/test-chat/logs/sidecar.log
```

---

## Making Views Testable

AppXray and Argus rely on `.accessibilityIdentifier()` to target UI elements. Views missing identifiers cannot be automated. Follow the conventions below when adding or editing views.

Full reference: `TESTING.md` Section 5 (screen-by-screen inventory) and Section 9 (naming convention).

### Naming Convention

```
viewPrefix.elementName                              -- static
viewPrefix.elementName.\(item.id.uuidString)        -- dynamic row
settings.tabName.controlName                        -- settings scoped by tab
```

Prefixes are camelCase, matching the view struct name without the `View` suffix (e.g. `ChatView` → `chat`, `AgentEditorView` → `agentEditor`).

### Element Cheat Sheet

| Element Type | What to Add |
|---|---|
| Button (with text) | `.accessibilityIdentifier("prefix.name")` |
| Button (icon-only) | `.accessibilityIdentifier("prefix.name")` + `.accessibilityLabel("Action")` |
| TextField / TextEditor | `.accessibilityIdentifier("prefix.fieldName")` |
| Picker / Toggle / Stepper | `.accessibilityIdentifier("prefix.controlName")` |
| List / ScrollView | `.accessibilityIdentifier("prefix.listName")` on the container |
| Dynamic ForEach row | `.accessibilityIdentifier("prefix.rowName.\(id.uuidString)")` |
| Status indicator | `.accessibilityIdentifier("prefix.status")` + `.accessibilityLabel("state")` |
| Decorative / animation | `.accessibilityElement(children: .ignore)` |

### Known Gaps

These interactive elements currently lack explicit accessibility identifiers:

| Area | What's Missing | Workaround |
|------|---------------|------------|
| Alerts / Confirmation Dialogs | "Clear Messages" alert, delete confirmation, reset settings buttons | Use `@text("Delete")` or `@label(...)` selectors |
| Swipe Actions | Sidebar conversation row swipe-to-delete and swipe-to-pin | Use context menu or Argus `act({ action: "swipe" })` |
| Context Menus | Rename, Pin/Unpin, Close, Duplicate, Delete on sidebar rows | Use `@text("Rename")` etc. |
| DiffTextView | NSViewRepresentable with no SwiftUI identifier | Use Argus AI vision assertion |
| System Search Fields | `.searchable()` uses system controls | Use `@type("SearchField")` or `@placeholder(...)` |
| Markdown Links | Links rendered by MarkdownUI | Use `@text("link text")` |
| File Importer | System file picker dialog | Cannot automate; use path text field instead |

### Checklist: Adding Identifiers to a New View

1. Pick a unique camelCase prefix (e.g. `peerNetwork` for `PeerNetworkView`)
2. Add `.accessibilityIdentifier("prefix.elementName")` to every interactive element
3. Add `.accessibilityLabel("Human-readable action")` to icon-only buttons
4. For `ForEach` rows, append `.\(item.id.uuidString)`
5. Mark decorative elements with `.accessibilityElement(children: .ignore)`
6. Update the prefix map in `CLAUDE.md` under "Accessibility Identifiers > Prefix Map"
7. Add the control inventory table to `TESTING.md` Section 5

### Auditing Existing Views

Use AppXray to find gaps:

```javascript
// Connect to the running DEBUG app
session({ action: "connect", appId: "com.odyssey.app" })

// Inspect the full accessibility tree
inspect({ target: "accessibility" })
```

Compare the returned tree against the tables in `TESTING.md` Section 5. Any interactive element without an `accessibilityIdentifier` in the tree is a gap that needs fixing.

---

## Adding New Tests

1. Add a new `test()` or `liveTest()` in the appropriate test file
2. Follow the naming convention: `{GROUP}-{N}: {description}` for scenarios
3. Use `liveTest` for tests that call the Claude SDK
4. Update this document with the new test entry

## Last Full Run

**Date:** 2026-03-22
**Result:** 139/139 pass (excluding 2 legacy failures in `sidecar-api.script.ts`)
**Live tests:** All 6 live tests pass with `ODYSSEY_E2E_LIVE=1`
**ACCEPT-1 time:** ~135s (Orchestrator delegated to Researcher + Coder, produced meditation app)
