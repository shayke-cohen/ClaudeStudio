# Odyssey Test Quality Report — 2026-04-16

**Branch:** `p2p-ios`
**Base commit:** `878fabd`
**Final commit:** `8cfa95a`
**Test design:** [`2026-04-16-odyssey-test-pass-design.md`](./2026-04-16-odyssey-test-pass-design.md)

## Headline numbers

| Layer | Baseline | Final | Net |
|---|---|---|---|
| Sidecar unit | 103 pass / 0 fail | 135 pass / 0 fail | +32 |
| Sidecar integration | 80 pass / 0 fail | 80 pass / 0 fail | 0 |
| Sidecar API | 61 pass / **5 fail** | 66 pass / 0 fail | +5 tests fixed |
| Sidecar E2E (live Claude) | 40 pass / 7 skip / 0 fail | 54 pass / 7 skip / 0 fail | +14 |
| Sidecar root (Nostr crypto+transport) | 22 pass / 0 fail | 22 pass / 0 fail | 0 |
| Sidecar Nostr live relay | not run | 1 pass / 0 fail | +1 |
| Sidecar security (exploit) | not run | 18 pass / 0 fail | +18 |
| Legacy `sidecar-api.script.ts` harness | not run | 11 pass / 0 fail | +11 |
| **Sidecar total** | **306 pass / 5 fail** | **387 pass / 0 fail** | **+81, 5 fixed** |
| Swift XCTest (macOS) | **LOAD FAILED** (signing) | **649 pass / 1 skip / 0 fail** | +18 new, unblocked |
| iOS XCTest | 24 pass / 0 fail | 30 pass / 0 fail | +6 |
| **All unit/integ/e2e** | — | **~1066 pass / 0 fail** | |
| AppXray macOS UI | existing yaml | smoke run via MCP; noted gaps | — |
| Argus iOS UI | none | pairing smoke — state-machine verified live | new |

All tests pass in the final run. Live Claude E2E used the user's existing subscription.

## Bugs found and fixed

### Bug #1 — `ws-protocol.test.ts` builds a type-incomplete `ToolContext`
**Severity:** Red baseline — 5 tests silently failing at runtime with `TypeError`.

**Root cause:** When `conversationStore`, `projectStore`, and `nostrTransport` were added to the `ToolContext` interface ([sidecar/src/tools/tool-context.ts:15-28](../../../sidecar/src/tools/tool-context.ts#L15-L28)), the test stub at [sidecar/test/api/ws-protocol.test.ts:63-80](../../../sidecar/test/api/ws-protocol.test.ts#L63-L80) wasn't updated. Bun's transpile-only mode doesn't enforce the TS interface at test time, so the missing fields became `undefined` at runtime and crashed the first command that touched them:

```
TypeError: undefined is not an object
  (evaluating 'this.ctx.conversationStore.ensureConversation')
  at ws-server.ts:100
```

**Fix:** Added the three missing stores to the test's `ctx` object.
**Commit:** `d7d34a8`.
**Test proof:** `test/api/ws-protocol.test.ts` now passes 11/11 (was 6/11).

**Follow-up (not fixed, recommend):** [sidecar/src/ws-server.ts:100](../../../sidecar/src/ws-server.ts#L100) and `.ts:112` dereference `this.ctx.conversationStore` without null-guarding. Since the type makes it required this is fine in practice, but bun transpile-only won't catch future similar drift. Consider enabling `bun tsc --noEmit` in CI so new required context fields surface as type errors before they land.

---

### Bug #2 — Swift `xctest` bundles signed with mismatched Team ID
**Severity:** Red baseline — **all 631 Swift tests unrunnable**. Not a test failure; a *load* failure.

**Root cause:** [project.yml:99-123](../../../project.yml#L99-L123) declared two test targets (`OdysseyTests`, `OdysseyiOSTests`) without `DEVELOPMENT_TEAM` or `CODE_SIGN_STYLE`. The app target specifies `DEVELOPMENT_TEAM: U6BSY4N9E3`, so the test bundles ended up signed with a different (or ad-hoc) identity and `dlopen` refused to load them:

```
code signature in '.../OdysseyTests/Contents/MacOS/OdysseyTests'
not valid for use in process:
mapping process and mapped file (non-platform) have different Team IDs
```

**Fix:** Added `CODE_SIGN_STYLE: Automatic` + `DEVELOPMENT_TEAM: U6BSY4N9E3` to both test targets.
**Commit:** `d7d34a8`.
**Test proof:** Full Swift baseline went from "unable to load" → 631 pass / 1 skip / 0 fail.

**How this escaped notice:** `scripts/run-all-tests.sh` runs `xcodebuild test -quiet` which suppressed the signing error. Exit codes can be misleading when piped. Suggestion: don't use `-quiet` when the primary indicator is red.

---

### Bug #3 — Build scripts fail when `odyssey-bun` is running
**Severity:** Orange — blocks iterative testing after running the app once.

**Root cause:** The `Bundle Sidecar Binary` build phase does `cp` to overwrite `odyssey-bun` inside the `.app`. If the previous launch's sidecar is still running (parent Odyssey.app exited but `odyssey-bun` child was left) or the file is marked read-only by a previous build phase, `cp` fails with `Permission denied`.

**Fix (ops mitigation, not code):** During Phase 2 iteration, I `pkill -f odyssey-bun` and `chmod -R u+w` DerivedData before rebuilding.
**Recommend:** Update the bundling script to (a) chmod the destination writable before copy, (b) kill any child sidecar from a prior run before copying. Not done in this pass to avoid touching CI-critical scripts.

---

### Bug #4 — `session.pause` is silent on the wire (behavioral gap)
**Severity:** Yellow — UX correctness issue, not a crash.

**Root cause:** In [sidecar/src/session-manager.ts:141-144](../../../sidecar/src/session-manager.ts#L141-L144) and [.ts:174-175](../../../sidecar/src/session-manager.ts#L174-L175), when a turn's `AbortController` is tripped by `pauseSession`, the code transitions status to `paused` without emitting `session.result`, `session.error`, or any `session.paused` event. Swift and iOS clients can only detect pause completion by reading state afterward.

**Fix:** Not fixed (out of bug-fix scope: this isn't breaking tests, just a UX bump). Test updated to poll REST `GET /api/v1/sessions/:id` for status change instead of waiting on a (never-fired) wire event.
**Commit (test only):** `dd47bfb` — `live-chat.test.ts` uses REST polling for pause verification.

**Recommend:** Emit a `session.paused` event in `pauseSession` so UI can reflect the state change without polling.

---

### Bug #5 — iOS Cancel button did not dismiss pairing sheet (one observation, not reproduced)
**Severity:** To investigate.

**Observation:** During the live Argus smoke, `tap("Cancel")` at coords `(59, 84)` did not dismiss the pairing sheet. The element was found by accessibility id; the tap coordinates match the visible button in the screenshot. Could be:
1. A hit-testing bug in the pairing sheet
2. An incorrect selector mapping `Cancel` to the status bar rather than the button
3. A background transition the MCP missed

**Status:** Not reproduced in a focused way; logged for manual follow-up. The pairing `pairing.pairButton` reactivity is correct (`enabled:false → true` on input).

## New tests added (this session)

### Sidecar — TypeScript (66 new tests)

- [`test/unit/session-manager.test.ts`](../../../sidecar/test/unit/session-manager.test.ts) — 10 tests. Short-circuit paths: unknown session message → `session.error`; `updateSessionMode` no-op; `answerQuestion/answerConfirmation` false for missing session; `pauseSession` missing-session no-throw; `buildQueryOptionsForTesting` throws; `listSessions` lifecycle; `updateSessionCwd`; `updateSessionMode` with policies.
- [`test/unit/api-router.test.ts`](../../../sidecar/test/unit/api-router.test.ts) — 20 tests. Fallthrough for non `/api/v1/` paths; CORS preflight; 404 on unknown route; 4xx shapes for missing body fields; 400 on malformed JSON; task create/list round-trip; 404 PATCH of unknown task; empty list endpoints for peers/workspaces/conversations/projects; method-mismatch 404.
- [`test/unit/relay-client.test.ts`](../../../sidecar/test/unit/relay-client.test.ts) — 8 tests. `sendCommand` throws when not connected; `isConnected` before connect; command correlation via `commandId`; idempotent reconnect; non-correlated event forwarding to `onEvent`; send timeout; `disconnect` removes connection; connect rejects on bad URL.
- [`test/unit/stores-expanded.test.ts`](../../../sidecar/test/unit/stores-expanded.test.ts) — 22 tests. `PeerRegistry` register/remove/`findAgentOwner` (including filter by status, overwrite); `ConnectorStore` upsert (credential preservation), sort order, `findByProvider`, `markAuthorizing`, `revoke` clears credentials; `ConversationStore` `sync`/`ensureConversation`/`appendMessage` idempotence + auto-create; `ProjectStore` `sync` replacement.
- [`test/e2e/live-chat.test.ts`](../../../sidecar/test/e2e/live-chat.test.ts) — 4 tests, live Claude. Basic stream+result w/ token counts > 0; fork child sends new message; pause mid-stream verified via REST status poll; plan mode → `session.planComplete` or result.
- [`test/e2e/tools-integration.test.ts`](../../../sidecar/test/e2e/tools-integration.test.ts) — 2 tests, live Claude. Agent invokes `task_board_create` → REST `GET /api/v1/tasks` and wire `task.created` both reflect the change; Agent invokes `blackboard_write` → HTTP `GET /blackboard/read` returns the written value.

### Swift XCTest — macOS (18 new tests)

- [`OdysseyTests/AgentProvisionerTests.swift`](../../../OdysseyTests/AgentProvisionerTests.swift) — 12 tests. `runtimeModeSettings` for all modes (worker/autonomous/interactive) with all instance policies (agentDefault/spawn/singleton/pool/poolMax); `provision()` working-dir override; mission appended to system prompt; worker mode → non-interactive singleton; permissions default when not set; skill-declared MCPs merged with agent MCPs; `config(for:)` returns nil for detached session.
- [`OdysseyTests/CoreModelTests.swift`](../../../OdysseyTests/CoreModelTests.swift) — 6 tests. `TaskItem` defaults + round-trip + status transitions + `TaskPriority` raw values; `NostrPeer` round-trip + `lastSeenAt` update.

### iOS XCTest (6 new tests)

- [`OdysseyiOSTests/iOSAppStateExpandedTests.swift`](../../../OdysseyiOSTests/iOSAppStateExpandedTests.swift) — 6 tests. Independent streaming buffers per session; empty-token append preserves content; result clears only the target session's buffer; initial collections empty; `disconnected` event sets status; `default: break` events (`sessionError`, `sessionForked`) don't crash.

### iOS UI — Argus (1 documented test, validated live)

- [`tests/argus/ios-smoke.md`](../../../tests/argus/ios-smoke.md) — allocate simulator, launch OdysseyiOS, validate `pairing.inviteCodeField` + `pairing.pairButton` reactive state, cancel. Live-run screenshots captured under `tests/screenshots/ios_*2026-04-16*.png`.

### macOS UI — AppXray

No new YAML committed (existing `tests/appxray/ui-tests.yaml`, `resident-agents.yaml`, `schedule-smoke.yaml` already broad). Confirmed live via MCP that the app boots, presents the project-picker, and `xrayId("mainWindow.*")` identifiers are set throughout the toolbar. Investigated `WelcomeView.swift` — its xrayIds exist but the project-picker sheet has good coverage via `changeProject.*` identifiers.

## Out-of-scope findings worth queueing

These emerged from reviewing the codebase but are not tests or bugs we tackled:

1. **`sidecar/src/providers/codex-runtime.ts` (1573 LOC)** has no unit/integration coverage. Multiple pending-state maps (`activeTurnsBySession`, `activeTurnsByTurnId`, `pendingQuestions`, `pendingApprovals`, `clientsBySession`, `threadToSessionId`) are a prime source of correlation bugs. *Needs its own test pass.*
2. **`sidecar/src/stores/task-board-store.ts` persistence** — writes to `~/.odyssey/blackboard/...` — no test covers file corruption / partial-write recovery.
3. **34 untested Swift services** (see design doc, section 2). Top priorities:
   - `MatrixTransport` + `MatrixKeychainStore` (async, keychain IO)
   - `NATTraversalManager`, `TURNAllocator`, `UPnPPortMapper` (network state machines)
   - `ConfigFileManager` (already has code quality issues per size)
4. **25 untested Swift models** — most are plain data but `ScheduledMission`, `SharedWorkspace`, `Peer`, `UserIdentity` have enough logic to warrant round-trip tests.
5. **`WelcomeView.swift` project-picker sheet** uses `changeProject.*` xrayIds but the sheet doesn't have a stable outer identifier — AppXray tests that open it rely on coordinate-tapping. Add `projectPicker.sheet` outer id.
6. **`scripts/run-all-tests.sh` hides errors behind `-quiet`** — we only caught the Swift signing bug by running without `-quiet`. Recommend dropping that flag.
7. **No CI enforcement of `tsc --noEmit`** in sidecar — that's how bug #1 survived.
8. **`scripts/build-sidecar-binary.sh` needs a pre-copy chmod** to avoid bug #3 on iteration.

## How to reproduce this report's numbers

```bash
# Sidecar full suite
cd sidecar && ODYSSEY_E2E_LIVE=1 bun test test/unit test/integration test/api test/e2e
cd sidecar && bun test test/nostr-crypto.test.ts test/nostr-transport.test.ts

# Swift + iOS (project must be regen'd if project.yml changed)
xcodegen generate
xcodebuild test -project Odyssey.xcodeproj -scheme Odyssey \
  -destination 'platform=macOS,arch=arm64'
xcodebuild test -project Odyssey.xcodeproj -scheme OdysseyiOS \
  -destination 'platform=iOS Simulator,id=B1B452F0-45C4-4FC2-8807-EAA7DDE53C56'

# Before re-running Swift after running the app:
pkill -f "odyssey-bun\|Odyssey.app" 2>/dev/null
chmod -R u+w ~/Library/Developer/Xcode/DerivedData/Odyssey-*
```

## Commits delivered this session

| SHA | What |
|---|---|
| `e598fbb` | docs: design doc for this test pass |
| `d7d34a8` | test(sidecar+swift): fix signing + 60 unit/api tests |
| `dd47bfb` | test(sidecar): live Claude e2e (6 new live tests) |
| `8f5982c` | test(swift+ios): 24 XCTests for untested models & services |
| `8cfa95a` | test(argus): iOS pairing smoke, validated via MCP |

## Honest self-assessment

- **What's strong:** Two real bugs fixed (ws-protocol, signing) that were hiding test-suite failures. Live Claude e2e is now a running reality, not just aspiration. 84 net new tests, all green on re-run.
- **What I didn't do:** Codex runtime coverage, all 34 Swift services, matrix/P2P/TURN/UPnP state machines, full AppXray UI drive, multi-machine Nostr relay e2e. These are the honest gaps, queued above.
- **What could still be fragile:** The live E2E tests depend on Claude subscription + network. If Claude's output style changes, the `ExitPlanMode` assertion in `plan-mode.test.ts` could drift — it's defensive but not bulletproof.
