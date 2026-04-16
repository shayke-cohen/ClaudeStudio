# Odyssey Comprehensive Test Pass — Design

**Date:** 2026-04-16
**Branch:** p2p-ios
**Author:** Claude + Shay

## Goal

Raise test coverage across every layer (Swift XCTest unit, iOS XCTest, sidecar unit/integration/API, sidecar live-Claude E2E, AppXray macOS UI E2E, Argus iOS UI E2E), run the full suite, fix real bugs the suite uncovers, and produce a quality report.

This is one focused session — not a replacement for ongoing test work.

## Non-goals

- Exhaustive per-module unit tests for all 25 untested Models and 34 untested Services.
- Full Codex-runtime E2E (Claude only for this pass).
- Multi-machine P2P LAN E2E across two running instances.
- Cross-machine Nostr internet-relay E2E with real remote peer.
- Refactors beyond what is needed to fix a bug the tests surfaced.

## Baseline — Phase 0

Run each of these, record exact counts, investigate any failure before writing new tests:

1. `./scripts/run-all-tests.sh` — Swift XCTest + sidecar unit/integration/api/e2e + legacy API harness.
2. `cd sidecar && bun test test/nostr-crypto.test.ts test/nostr-transport.test.ts test/nostr-live-relay.test.ts` — root-level Nostr tests not in the runner.
3. `cd sidecar && bun run test/sidecar-api.script.ts` via the runner only (it wraps port allocation).
4. AppXray smoke: discover + connect to a running Odyssey debug build, inspect main window, screenshot.
5. Argus iOS smoke: allocate simulator, launch OdysseyiOS, inspect first screen.

A test that is red at baseline that we can't explain by design change is a bug — we fix it before moving on.

## Phase 1 — New tests, prioritized by risk

### Sidecar (bun test)

| Path | Purpose |
|---|---|
| `test/unit/session-manager.test.ts` | AbortController lifecycle, turn dispatch, unknown-session error, pause/resume, concurrent turn scheduling. |
| `test/unit/api-router.test.ts` | Route dispatch, 4xx shapes, unknown route → 404, malformed JSON → 400, blackboard + task-board REST round-trip at router level. |
| `test/unit/stores-expanded.test.ts` | Focused tests for `blackboard-store`, `message-store`, `peer-registry`, `session-registry`, `chat-channel-store`. |
| `test/unit/relay-client.test.ts` | Connection pool, command correlation, timeout behavior. |
| `test/integration/codex-runtime.test.ts` | Pending-turn/question/approval state map invariants (mocked Codex server). |
| `test/api/ws-server.test.ts` | Malformed frames, large payloads, multiple concurrent clients, TLS fallback path. |

### Swift XCTest (OdysseyTests)

| File | Purpose |
|---|---|
| `ConfigFileManagerTests` | Round-trip write/read, atomic replace, corrupt-file recovery. |
| `ConfigSyncServiceTests` | Sync semantics, conflict handling. |
| `NATTraversalManagerTests` | State transitions (mocked sockets). |
| `TURNAllocatorTests` | Allocation lifecycle (mocked). |
| `UPnPPortMapperTests` | Port-mapping state (mocked). |
| `P2PNetworkManagerTests` | Bonjour lifecycle, peer add/remove, reconnect backoff. |
| `AgentProvisionerTests` | Skill/MCP/permission composition, working-dir precedence. |
| Model unit tests | `Agent`, `Session`, `Conversation`, `TaskItem`, `Project` SwiftData round-trip. |

### iOS XCTest (OdysseyiOSTests)

| File | Purpose |
|---|---|
| `RemoteSidecarManagerTests` (expand) | Reconnect on drop, credential rotation. |
| `iOSAppStateTests` (expand) | Pairing state machine, launch paths. |

### Sidecar E2E (live Claude)

| File | Purpose |
|---|---|
| `test/e2e/chat-basic.test.ts` | Create session → send → assert `stream.token` + `session.result`. |
| `test/e2e/chat-resume.test.ts` | Resume via `claudeSessionId`, assert context continuity. |
| `test/e2e/chat-fork.test.ts` | Fork from earlier message, assert pivoted context. |
| `test/e2e/chat-pause.test.ts` | Pause mid-stream, assert abort in `session.result`. |
| `test/e2e/tools-task-board.test.ts` | Agent creates/updates task via tool; assert via REST `GET /api/v1/tasks`. |
| `test/e2e/tools-blackboard.test.ts` | Agent writes blackboard entry; assert via `GET /blackboard/read`. |
| `test/e2e/tools-rich-display.test.ts` | Agent calls `show_progress`; assert wire event. |
| `test/e2e/plan-mode.test.ts` | Request plan, assert `session.planComplete`. |
| `test/e2e/group-invite.test.ts` | Agent A invokes `group_invite_agent` to pull in B; assert B responds. |

### AppXray (macOS UI E2E)

Extend `tests/appxray/ui-tests.yaml` with:
- Create project → open thread → send "hi" → wait ≤60s for reply bubble → assert reply present.
- Open agent library, assert structure.
- Open settings nav; assert sections render.
- Trigger an error path (e.g., invalid WS port), assert alert UI.

### Argus (iOS UI E2E)

New `tests/argus/ios-smoke.ts`:
- Allocate iOS 26 simulator → launch OdysseyiOS → pairing screen → Settings → Conversations tab.
- Screenshot each; minimal assertions on key accessibility identifiers.
- No real pairing with a live mac (out of scope for one session).

## Phase 2 — Hunt & fix

Run the full suite. For each failure:
1. Decide: test bug vs code bug. Never weaken an assertion to paper over a real bug.
2. Fix the root cause at the smallest possible scope.
3. Re-run the specific test until green.
4. At the end of each batch, re-run the full suite.

Cap: ~3 cycles, or when fixes stop appearing. Every fix gets a line in the final report with file:line.

## Phase 3 — Report

Write `docs/superpowers/specs/2026-04-16-test-quality-report.md`:
- Baseline vs final pass/fail per layer.
- Every bug found + root cause + fix (file:line refs).
- Remaining coverage gaps queued for next session.
- Risk assessment: next priorities.

## Risks

- **Live Claude tests** cost tokens and can hang. Strict timeouts, skip with note on failure.
- **Bun socket tests** flaky on macOS ephemeral ports — retry once before marking red.
- **AppXray/Argus** need running apps; rebuild Debug first if stale.
- **Swift 6 strict concurrency** — new tests must be `@MainActor` where they touch UI-facing state.

## Success criteria

- Baseline captured: pass/fail counts for every layer.
- New tests added in every layer called out above.
- All existing + new tests run at least once.
- Bugs found by tests are fixed or documented with a reason for not fixing.
- Final report committed.
