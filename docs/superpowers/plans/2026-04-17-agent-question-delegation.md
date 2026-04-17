# Agent Question Delegation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `ask_agent` tool and enhance `ask_user` so agents can delegate questions to other agents, controlled by a per-conversation delegation mode the user sets from the chat header.

**Architecture:** New `DelegationStore` (keyed by sessionId) holds per-conversation mode + target. `ask_user` routes to an agent on timeout when mode is active. New `ask_agent` tool spawns an ephemeral session of the nominated agent and returns its answer. Swift UI adds an Auto-Answer badge + popover to the chat header.

**Tech Stack:** TypeScript / Bun (sidecar), Swift / SwiftUI / SwiftData (macOS app), WebSocket wire protocol.

**Spec:** `docs/superpowers/specs/2026-04-17-agent-question-delegation-design.md`

---

## File Map

**Create:**
- `sidecar/src/stores/delegation-store.ts` — per-session delegation mode + target resolution
- `sidecar/src/tools/ask-agent-tool.ts` — `ask_agent` tool implementation

**Modify:**
- `sidecar/src/types.ts` — add `DelegationMode`, new `SidecarEvent` variants, new `SidecarCommand` variant
- `sidecar/src/tools/tool-context.ts` — add `delegation: DelegationStore`
- `sidecar/src/index.ts` — instantiate `DelegationStore`, wire into `toolContext`
- `sidecar/src/tools/ask-user-tool.ts` — add `timeout_seconds` param + delegation routing on timeout
- `sidecar/src/tools/peerbus-server.ts` — register `ask_agent` alongside `ask_user`
- `sidecar/src/ws-server.ts` — handle `conversation.setDelegationMode` command
- `Odyssey/Services/SidecarProtocol.swift` — mirror new command + event types
- `Odyssey/Models/Conversation.swift` — add `delegationMode` + `delegationTargetAgentName`
- `Odyssey/App/AppState.swift` — handle new events; send `setDelegationMode` command
- `Odyssey/Views/MainWindow/ChatView.swift` — Auto-Answer header badge + popover; routing pill + attribution tag in transcript

---

## Task 1: Sidecar — Types

**Files:**
- Modify: `sidecar/src/types.ts`

- [ ] **Step 1: Add `DelegationMode` type and new events after the `agent.confirmation` event line (~line 219)**

```typescript
// Add after the existing DelegationMode-related types, before SidecarCommand
export type DelegationMode = "off" | "by_agents" | "specific_agent" | "coordinator";
```

In `SidecarCommand` union, add a new variant:
```typescript
| { type: "conversation.setDelegationMode"; sessionId: string; mode: DelegationMode; targetAgentName?: string }
```

In `SidecarEvent` union, add two new variants:
```typescript
| { type: "agent.question.routing"; sessionId: string; questionId: string; targetAgentName: string }
| { type: "agent.question.resolved"; sessionId: string; questionId: string; answeredBy: string; isFallback: boolean }
```

- [ ] **Step 2: Verify TypeScript compiles**

```bash
cd /Users/shayco/Odyssey/sidecar && bun run build 2>&1 | head -30
```

Expected: no errors related to new types.

- [ ] **Step 3: Commit**

```bash
cd /Users/shayco/Odyssey/sidecar
git add src/types.ts
git commit -m "feat(delegation): add DelegationMode type and wire protocol events"
```

---

## Task 2: Sidecar — DelegationStore

**Files:**
- Create: `sidecar/src/stores/delegation-store.ts`

- [ ] **Step 1: Write the test**

Create `sidecar/test/delegation-store.test.ts`:

```typescript
import { describe, test, expect, beforeEach } from "bun:test";
import { DelegationStore } from "../src/stores/delegation-store.js";

describe("DelegationStore", () => {
  let store: DelegationStore;

  beforeEach(() => { store = new DelegationStore(); });

  test("defaults to off", () => {
    expect(store.get("session-1")).toEqual({ mode: "off" });
  });

  test("stores and retrieves mode", () => {
    store.set("session-1", { mode: "by_agents" });
    expect(store.get("session-1")).toEqual({ mode: "by_agents" });
  });

  test("resolveTarget: off mode returns nominated", () => {
    store.set("s1", { mode: "off" });
    expect(store.resolveTarget("s1", "Reviewer")).toBe("Reviewer");
  });

  test("resolveTarget: by_agents returns nominated", () => {
    store.set("s1", { mode: "by_agents" });
    expect(store.resolveTarget("s1", "Reviewer")).toBe("Reviewer");
  });

  test("resolveTarget: specific_agent overrides nominated", () => {
    store.set("s1", { mode: "specific_agent", targetAgentName: "PM" });
    expect(store.resolveTarget("s1", "Reviewer")).toBe("PM");
  });

  test("resolveTarget: coordinator uses stored targetAgentName", () => {
    store.set("s1", { mode: "coordinator", targetAgentName: "PM" });
    expect(store.resolveTarget("s1", "Reviewer")).toBe("PM");
  });

  test("resolveTarget: coordinator falls back to nominated if no targetAgentName", () => {
    store.set("s1", { mode: "coordinator" });
    expect(store.resolveTarget("s1", "Reviewer")).toBe("Reviewer");
  });
});
```

- [ ] **Step 2: Run test — verify it fails**

```bash
cd /Users/shayco/Odyssey/sidecar && bun test test/delegation-store.test.ts 2>&1
```

Expected: FAIL — `DelegationStore` not found.

- [ ] **Step 3: Implement `DelegationStore`**

Create `sidecar/src/stores/delegation-store.ts`:

```typescript
import type { DelegationMode } from "../types.js";

export interface DelegationConfig {
  mode: DelegationMode;
  targetAgentName?: string;
}

export class DelegationStore {
  private configs = new Map<string, DelegationConfig>();

  get(sessionId: string): DelegationConfig {
    return this.configs.get(sessionId) ?? { mode: "off" };
  }

  set(sessionId: string, config: DelegationConfig): void {
    this.configs.set(sessionId, config);
  }

  /**
   * Resolve the actual target agent name given delegation mode.
   * For coordinator mode, Swift stores the coordinator's name in targetAgentName
   * when it calls conversation.setDelegationMode.
   * @param sessionId - the calling session (= conversationId for primary sessions)
   * @param nominatedAgent - the agent name the asking agent suggested
   */
  resolveTarget(
    sessionId: string,
    nominatedAgent: string | undefined,
  ): string | undefined {
    const config = this.get(sessionId);
    switch (config.mode) {
      case "off":
      case "by_agents":
        return nominatedAgent;
      case "specific_agent":
      case "coordinator":
        return config.targetAgentName ?? nominatedAgent;
    }
  }
}
```

- [ ] **Step 4: Run test — verify it passes**

```bash
cd /Users/shayco/Odyssey/sidecar && bun test test/delegation-store.test.ts 2>&1
```

Expected: all 7 tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/shayco/Odyssey/sidecar
git add src/stores/delegation-store.ts test/delegation-store.test.ts
git commit -m "feat(delegation): add DelegationStore"
```

---

## Task 3: Sidecar — Wire DelegationStore into ToolContext

**Files:**
- Modify: `sidecar/src/tools/tool-context.ts`
- Modify: `sidecar/src/index.ts`

- [ ] **Step 1: Add `delegation` to `ToolContext` interface**

In `sidecar/src/tools/tool-context.ts`, add imports and the field:

```typescript
import type { DelegationStore } from "../stores/delegation-store.js";
```

Add to the `ToolContext` interface (after `connectors: ConnectorStore;`):

```typescript
delegation: DelegationStore;
```

- [ ] **Step 2: Instantiate and wire in `index.ts`**

In `sidecar/src/index.ts`, add import:

```typescript
import { DelegationStore } from "./stores/delegation-store.js";
```

After `const projectStore = new ProjectStore();`, add:

```typescript
const delegation = new DelegationStore();
```

Inside the `toolContext` object literal (after `projectStore,`), add:

```typescript
delegation,
```

- [ ] **Step 3: Verify TypeScript compiles**

```bash
cd /Users/shayco/Odyssey/sidecar && bun run build 2>&1 | head -30
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
cd /Users/shayco/Odyssey/sidecar
git add src/tools/tool-context.ts src/index.ts
git commit -m "feat(delegation): wire DelegationStore into ToolContext"
```

---

## Task 4: Sidecar — Enhance `ask_user` with delegation timeout routing

**Files:**
- Modify: `sidecar/src/tools/ask-user-tool.ts`

- [ ] **Step 1: Add `timeout_seconds` param and helper function**

In `ask-user-tool.ts`, replace `DEFAULT_TIMEOUT_MS` constant with a function and add the delegation routing helper:

```typescript
const DEFAULT_TIMEOUT_MS = {
  off: 5 * 60 * 1000,     // 5 min
  by_agents: 30 * 1000,   // 30s
  specific_agent: 30 * 1000,
  coordinator: 30 * 1000,
};

/** Resolve effective timeout: mode default, shortened by agent hint (cannot lengthen). */
function resolveTimeout(modeMs: number, hintSeconds?: number): number {
  if (!hintSeconds) return modeMs;
  return Math.min(hintSeconds * 1000, modeMs);
}

/** Find the least-busy active agent session ID, excluding the caller. */
function leastBusyAgent(ctx: ToolContext, excludeSessionId: string): string | undefined {
  return ctx.sessions
    .listActive()
    .filter((s) => s.id !== excludeSessionId)
    .sort((a, b) => {
      // Use whatever queue-depth method MessageStore exposes (getMessages, peek, etc.)
      const aLen = ctx.messages.getMessages?.(a.id)?.length ?? 0;
      const bLen = ctx.messages.getMessages?.(b.id)?.length ?? 0;
      return aLen - bLen;
    })
    [0]?.id;
}
```

Note: `ctx.messages.peek(sessionId)` returns the pending messages for that session — check `MessageStore` for the actual method name and use the equivalent that returns queue depth. If `peek` doesn't exist, use `ctx.messages.getMessages(sessionId)` or the equivalent method available on `MessageStore`.

- [ ] **Step 2: Add `timeout_seconds` to the tool's zod schema**

Inside `createAskUserTool`, in the schema object passed to `defineSharedTool`, add after `input_config`:

```typescript
timeout_seconds: z
  .number()
  .optional()
  .describe(
    "Hint to shorten the auto-routing timeout (seconds). Only effective when Auto-Answer mode is active. Cannot exceed the mode default (30s in auto modes). Ignored when mode is Off.",
  ),
```

- [ ] **Step 3: Replace the inline timer with delegation-aware routing**

Replace the current `async (args) => { ... }` handler body with:

```typescript
async (args) => {
  logger.info("tools", `ask_user invoked for session ${callingSessionId}: "${args.question.substring(0, 80)}"`);
  const questionId = randomUUID();

  const delegationConfig = ctx.delegation.get(callingSessionId);
  const isAutoMode = delegationConfig.mode !== "off";
  const modeTimeoutMs = DEFAULT_TIMEOUT_MS[delegationConfig.mode];
  const effectiveTimeoutMs = resolveTimeout(modeTimeoutMs, args.timeout_seconds);

  const result = await new Promise<{ answer: string; selectedOptions?: string[] }>(
    (resolve, reject) => {
      const timer = setTimeout(async () => {
        pendingQuestions.delete(questionId);
        const set = questionsBySession.get(callingSessionId);
        if (set) { set.delete(questionId); if (set.size === 0) questionsBySession.delete(callingSessionId); }

        if (!isAutoMode) {
          resolve({ answer: "[User did not respond within the timeout period. Proceed with your best judgment.]" });
          return;
        }

        // Resolve target agent via delegation store
        // For coordinator/specific_agent modes, targetAgentName is stored in the config.
        // For by_agents mode, fall back to least-busy active agent.
        const targetName = ctx.delegation.resolveTarget(callingSessionId, undefined)
          ?? ctx.sessions.get(leastBusyAgent(ctx, callingSessionId) ?? "")?.agentName;

        if (!targetName) {
          resolve({ answer: "[User did not respond and no delegate agent found. Proceed with your best judgment.]" });
          return;
        }

        const targetConfig = ctx.agentDefinitions.get(targetName);
        if (!targetConfig) {
          resolve({ answer: "[User did not respond and delegate agent config not found. Proceed with your best judgment.]" });
          return;
        }

        ctx.broadcast({ type: "agent.question.routing", sessionId: callingSessionId, questionId, targetAgentName: targetName });

        try {
          const delegateSessionId = randomUUID();
          const prompt = `Another agent has a question that the user did not answer in time. Please answer concisely.\n\nQuestion: ${args.question}`;
          const { result: agentAnswer } = await ctx.spawnSession(delegateSessionId, targetConfig, prompt, true);
          ctx.broadcast({ type: "agent.question.resolved", sessionId: callingSessionId, questionId, answeredBy: targetName, isFallback: true });
          resolve({ answer: agentAnswer ?? "[Agent did not provide an answer.]" });
        } catch {
          resolve({ answer: "[Delegate agent failed to answer. Proceed with your best judgment.]" });
        }
      }, effectiveTimeoutMs);

      pendingQuestions.set(questionId, { resolve, reject, timer });
      onQuestionCreated?.(questionId);

      const inputConfig = args.input_config ? {
        maxRating: args.input_config.max_rating,
        ratingLabels: args.input_config.rating_labels,
        min: args.input_config.min,
        max: args.input_config.max,
        step: args.input_config.step,
        unit: args.input_config.unit,
        fields: args.input_config.fields,
      } : undefined;

      ctx.broadcast({
        type: "agent.question",
        sessionId: callingSessionId,
        questionId,
        question: args.question,
        options: args.options,
        multiSelect: args.multi_select ?? false,
        private: args.private ?? true,
        inputType: args.input_type ?? "options",
        inputConfig,
        timeoutSeconds: Math.round(effectiveTimeoutMs / 1000),
        autoRouting: isAutoMode,
      });
    },
  );

  return createTextResult({ answer: result.answer, selectedOptions: result.selectedOptions });
},
```

Note: `agent.question` broadcast now includes `timeoutSeconds` and `autoRouting` — add these to the `SidecarEvent` `agent.question` variant in `types.ts`:
```typescript
| { type: "agent.question"; sessionId: string; questionId: string; question: string; options?: QuestionOption[]; multiSelect: boolean; private: boolean; inputType?: QuestionInputType; inputConfig?: QuestionInputConfig; timeoutSeconds?: number; autoRouting?: boolean }
```

- [ ] **Step 4: Verify build**

```bash
cd /Users/shayco/Odyssey/sidecar && bun run build 2>&1 | head -30
```

Expected: no errors.

- [ ] **Step 5: Commit**

```bash
cd /Users/shayco/Odyssey/sidecar
git add src/tools/ask-user-tool.ts src/types.ts
git commit -m "feat(delegation): ask_user delegation timeout routing + timeout_seconds param"
```

---

## Task 5: Sidecar — New `ask_agent` tool

**Files:**
- Create: `sidecar/src/tools/ask-agent-tool.ts`

- [ ] **Step 1: Create the tool file**

```typescript
import { z } from "zod";
import { randomUUID } from "crypto";
import type { ToolContext } from "./tool-context.js";
import { createTextResult, defineSharedTool } from "./shared-tool.js";
import { logger } from "../logger.js";

export function createAskAgentTool(ctx: ToolContext, callingSessionId: string) {
  return [
    defineSharedTool(
      "ask_agent",
      "Ask another agent a question and wait for its answer. Use this when a question can be answered by a specific agent rather than requiring human input. The calling agent's session blocks until the target agent responds.",
      {
        question: z.string().describe("The question to ask the target agent"),
        to_agent: z
          .string()
          .describe(
            "Name of the agent to ask (e.g. 'Reviewer', 'PM'). The conversation's Auto-Answer mode may override this to route to a different agent.",
          ),
      },
      async (args) => {
        logger.info("tools", `ask_agent invoked by ${callingSessionId}: asking "${args.to_agent}": "${args.question.substring(0, 80)}"`);

        // Resolve delegation override (specific_agent/coordinator modes override to_agent)
        const callerState = ctx.sessions.get(callingSessionId);
        const resolvedTargetName = ctx.delegation.resolveTarget(callingSessionId, args.to_agent) ?? args.to_agent;

        const targetConfig = ctx.agentDefinitions.get(resolvedTargetName);
        if (!targetConfig) {
          return createTextResult({
            error: "agent_not_found",
            agent: resolvedTargetName,
            message: `No agent definition found for "${resolvedTargetName}". Cannot delegate question.`,
          }, false);
        }

        const questionId = randomUUID();
        ctx.broadcast({
          type: "agent.question.routing",
          sessionId: callingSessionId,
          questionId,
          targetAgentName: resolvedTargetName,
        });

        try {
          const delegateSessionId = randomUUID();
          const callerName = callerState?.agentName ?? "another agent";
          const prompt = `${callerName} has a question for you. Please answer concisely.\n\nQuestion: ${args.question}`;

          const { result } = await ctx.spawnSession(delegateSessionId, targetConfig, prompt, true);

          ctx.broadcast({
            type: "agent.question.resolved",
            sessionId: callingSessionId,
            questionId,
            answeredBy: resolvedTargetName,
            isFallback: false,
          });

          return createTextResult({ answer: result ?? "[Agent provided no answer.]" });
        } catch (err: any) {
          return createTextResult({ error: "delegation_failed", message: err.message }, false);
        }
      },
    ),
  ];
}
```

- [ ] **Step 2: Verify build**

```bash
cd /Users/shayco/Odyssey/sidecar && bun run build 2>&1 | head -30
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
cd /Users/shayco/Odyssey/sidecar
git add src/tools/ask-agent-tool.ts
git commit -m "feat(delegation): add ask_agent tool"
```

---

## Task 6: Sidecar — Register `ask_agent` and handle `setDelegationMode` command

**Files:**
- Modify: `sidecar/src/tools/peerbus-server.ts`
- Modify: `sidecar/src/ws-server.ts`

- [ ] **Step 1: Register `ask_agent` in peerbus-server**

In `sidecar/src/tools/peerbus-server.ts`, add import:

```typescript
import { createAskAgentTool } from "./ask-agent-tool.js";
```

Inside `createPeerBusToolDefinitions`, in the `if (includeAskUser)` block, add `ask_agent` alongside `ask_user`:

```typescript
if (includeAskUser) {
  definitions.push(...createAskUserTool(ctx, callingSessionId, onQuestionCreated));
  definitions.push(...createAskAgentTool(ctx, callingSessionId));  // add this line
  definitions.push(...createRichDisplayTools(ctx, callingSessionId));
  logger.debug("peerbus", `ask_user + ask_agent + rich display tools INCLUDED for session ${callingSessionId}`);
} else {
  logger.debug("peerbus", `ask_user/ask_agent tools NOT included for session ${callingSessionId} (includeAskUser=${includeAskUser})`);
}
```

- [ ] **Step 2: Handle `conversation.setDelegationMode` in ws-server**

In `sidecar/src/ws-server.ts`, find the switch statement that handles `SidecarCommand` types. Add a case for the new command (follow the existing pattern — look for a `case "session.updateMode":` nearby):

```typescript
case "conversation.setDelegationMode": {
  this.ctx.delegation.set(cmd.sessionId, {
    mode: cmd.mode,
    targetAgentName: cmd.targetAgentName,
  });
  break;
}
```

- [ ] **Step 3: Verify build**

```bash
cd /Users/shayco/Odyssey/sidecar && bun run build 2>&1 | head -30
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
cd /Users/shayco/Odyssey/sidecar
git add src/tools/peerbus-server.ts src/ws-server.ts
git commit -m "feat(delegation): register ask_agent; handle setDelegationMode command"
```

---

## Task 7: Swift — Wire protocol types

**Files:**
- Modify: `Odyssey/Services/SidecarProtocol.swift`

- [ ] **Step 1: Add `DelegationMode` enum**

In `SidecarProtocol.swift`, add after the existing enums near the top:

```swift
enum DelegationMode: String, Codable, CaseIterable, Sendable {
    case off
    case byAgents = "by_agents"
    case specificAgent = "specific_agent"
    case coordinator
}
```

- [ ] **Step 2: Add `setDelegationMode` command case**

In the `SidecarCommand` enum, add:

```swift
case setDelegationMode(sessionId: String, mode: DelegationMode, targetAgentName: String?)
```

In `encodeToJSON()`, add a case (follow the pattern of other cases, creating a new `Codable` struct):

```swift
case .setDelegationMode(let sessionId, let mode, let targetAgentName):
    struct SetDelegationModeWire: Codable {
        let type: String
        let sessionId: String
        let mode: String
        let targetAgentName: String?
    }
    return try encoder.encode(SetDelegationModeWire(
        type: "conversation.setDelegationMode",
        sessionId: sessionId,
        mode: mode.rawValue,
        targetAgentName: targetAgentName
    ))
```

- [ ] **Step 3: Add new event types to `SidecarEvent`**

Find the `SidecarEvent` enum (or equivalent decoding logic — look for `agent.question` case handling). Add:

```swift
case agentQuestionRouting(sessionId: String, questionId: String, targetAgentName: String)
case agentQuestionResolved(sessionId: String, questionId: String, answeredBy: String, isFallback: Bool)
```

Also add `timeoutSeconds: Int?` and `autoRouting: Bool?` to the existing `agentQuestion` case.

Add decoding for the new cases following the existing pattern (each case is decoded from `type` field).

- [ ] **Step 4: Build Xcode project**

```bash
xcodebuild -project /Users/shayco/Odyssey/Odyssey.xcodeproj -scheme Odyssey -configuration Debug build 2>&1 | grep -E "error:|warning:|BUILD"
```

Expected: BUILD SUCCEEDED (or only pre-existing warnings).

- [ ] **Step 5: Commit**

```bash
cd /Users/shayco/Odyssey
git add Odyssey/Services/SidecarProtocol.swift
git commit -m "feat(delegation): Swift wire protocol — DelegationMode, setDelegationMode command, routing events"
```

---

## Task 8: Swift — Conversation model

**Files:**
- Modify: `Odyssey/Models/Conversation.swift`

- [ ] **Step 1: Add `delegationMode` and `delegationTargetAgentName` to `Conversation`**

In `Conversation.swift`, after `private var executionModeRaw: String?`, add:

```swift
private var delegationModeRaw: String?
var delegationTargetAgentName: String?
```

Add a computed property (after the `executionMode` computed property, following the same backing-raw-string pattern):

```swift
var delegationMode: DelegationMode {
    get { delegationModeRaw.flatMap(DelegationMode.init(rawValue:)) ?? .off }
    set { delegationModeRaw = newValue.rawValue }
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild -project /Users/shayco/Odyssey/Odyssey.xcodeproj -scheme Odyssey -configuration Debug build 2>&1 | grep -E "error:|BUILD"
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
cd /Users/shayco/Odyssey
git add Odyssey/Models/Conversation.swift
git commit -m "feat(delegation): add delegationMode + delegationTargetAgentName to Conversation model"
```

---

## Task 9: Swift — AppState event handling + send command

**Files:**
- Modify: `Odyssey/App/AppState.swift`

- [ ] **Step 1: Handle `agentQuestionRouting` event**

In `AppState.swift`, find where `SidecarEvent` cases are handled (look for `case .agentQuestion` or `agent.question`). Add handlers for the two new events:

```swift
case .agentQuestionRouting(let sessionId, let questionId, let targetAgentName):
    // Find the conversation message for this question and annotate it
    // Store routing info so ChatView can show the routing pill
    if let conversation = conversations.first(where: { $0.sessions.contains(where: { $0.id == sessionId }) }) {
        conversation.pendingQuestionRouting[questionId] = targetAgentName
    }

case .agentQuestionResolved(let sessionId, let questionId, let answeredBy, let isFallback):
    if let conversation = conversations.first(where: { $0.sessions.contains(where: { $0.id == sessionId }) }) {
        conversation.pendingQuestionRouting.removeValue(forKey: questionId)
        conversation.resolvedQuestions[questionId] = ResolvedQuestionInfo(answeredBy: answeredBy, isFallback: isFallback)
    }
```

Note: `pendingQuestionRouting` and `resolvedQuestions` are transient `@Transient` dictionaries on `Conversation` (not persisted). Add them to the `Conversation` model as `@Transient` properties:

```swift
// In Conversation.swift — NOT persisted, runtime-only
@Transient var pendingQuestionRouting: [String: String] = [:]   // questionId → targetAgentName
@Transient var resolvedQuestions: [String: ResolvedQuestionInfo] = [:]
```

Add `ResolvedQuestionInfo` struct in `Conversation.swift`:

```swift
struct ResolvedQuestionInfo {
    let answeredBy: String
    let isFallback: Bool
}
```

- [ ] **Step 2: Add `sendDelegationMode` method to AppState**

In `AppState.swift`, add a method (near other `send*` methods):

```swift
func setDelegationMode(for conversation: Conversation, mode: DelegationMode, targetAgentName: String? = nil) {
    guard let primarySession = conversation.sessions.first else { return }
    // For coordinator mode, resolve the coordinator's agent name from participants
    let resolvedTarget: String? = mode == .coordinator
        ? (targetAgentName ?? conversation.participants.first(where: { $0.role == .coordinator })?.agentName)
        : targetAgentName
    conversation.delegationMode = mode
    conversation.delegationTargetAgentName = resolvedTarget
    let command = SidecarCommand.setDelegationMode(
        sessionId: primarySession.id,
        mode: mode,
        targetAgentName: resolvedTarget
    )
    sidecarManager.send(command)
}
```

- [ ] **Step 3: Build**

```bash
xcodebuild -project /Users/shayco/Odyssey/Odyssey.xcodeproj -scheme Odyssey -configuration Debug build 2>&1 | grep -E "error:|BUILD"
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
cd /Users/shayco/Odyssey
git add Odyssey/App/AppState.swift Odyssey/Models/Conversation.swift
git commit -m "feat(delegation): AppState event handling + setDelegationMode command dispatch"
```

---

## Task 10: Swift — Chat header Auto-Answer badge + popover

**Files:**
- Modify: `Odyssey/Views/MainWindow/ChatView.swift`

- [ ] **Step 1: Add `DelegationModePickerView`**

In `ChatView.swift`, add a new SwiftUI view (before or after the existing `SimplifiedChatHeader` view):

```swift
struct DelegationModePickerView: View {
    @Binding var mode: DelegationMode
    @Binding var targetAgentName: String?
    let participants: [Participant]   // for the agent picker list
    let hasCoordinator: Bool
    let onSelect: (DelegationMode, String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            modeCard(.off, icon: "🚫", label: "Off", desc: "Questions always go to you", timeout: "5 min")
            modeCard(.byAgents, icon: "⚡", label: "By agents", desc: "Asking agent nominates who answers", timeout: "30s")
            modeCardWithPicker(.specificAgent, icon: "👤", label: "Specific agent", desc: "Always routes to chosen agent", timeout: "30s")
            if hasCoordinator {
                modeCard(.coordinator, icon: "🎯", label: "Coordinator", desc: "Coordinator handles all questions", timeout: "30s")
            }
        }
        .padding(8)
        .frame(width: 280)
    }

    @ViewBuilder
    private func modeCard(_ m: DelegationMode, icon: String, label: String, desc: String, timeout: String) -> some View {
        Button(action: { onSelect(m, nil) }) {
            HStack {
                Text(icon).font(.title3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(label).font(.system(size: 12, weight: .semibold))
                    Text(desc).font(.system(size: 10)).foregroundColor(.secondary)
                }
                Spacer()
                Text(timeout)
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(mode == m ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                    .cornerRadius(4)
                    .foregroundColor(mode == m ? .accentColor : .secondary)
            }
            .padding(8)
            .background(mode == m ? Color.accentColor.opacity(0.08) : Color.clear)
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(mode == m ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1.5))
            .cornerRadius(7)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func modeCardWithPicker(_ m: DelegationMode, icon: String, label: String, desc: String, timeout: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            modeCard(m, icon: icon, label: label, desc: desc, timeout: timeout)
            if mode == m {
                VStack(spacing: 0) {
                    ForEach(participants.filter { $0.isAgent }, id: \.id) { p in
                        Button(action: { onSelect(m, p.agentName) }) {
                            HStack {
                                Text(p.icon ?? "🤖").font(.system(size: 12))
                                Text(p.agentName ?? p.name).font(.system(size: 11))
                                Spacer()
                                if targetAgentName == p.agentName { Image(systemName: "checkmark").font(.system(size: 10)).foregroundColor(.accentColor) }
                            }
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(targetAgentName == p.agentName ? Color.accentColor.opacity(0.1) : Color.clear)
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))
            }
        }
    }
}
```

- [ ] **Step 2: Add badge to `simplifiedChatHeader`**

In `ChatView.swift`, find `simplifiedChatHeader` (around line 1005). In the top row HStack, after the existing Execution Mode badge and before the session menu button, add:

```swift
// Auto-Answer delegation badge
@State private var showDelegationPicker = false

// In the header HStack:
Button(action: { showDelegationPicker.toggle() }) {
    HStack(spacing: 4) {
        Image(systemName: conversation.delegationMode == .off ? "person.fill.questionmark" : "bolt.fill")
            .font(.system(size: 10))
        Text(conversation.delegationMode == .off ? "Auto-Answer" : "Auto · \(conversation.delegationMode.shortLabel)")
            .font(.system(size: 10, weight: .semibold))
        Image(systemName: "chevron.down").font(.system(size: 8))
    }
    .padding(.horizontal, 8).padding(.vertical, 3)
    .background(conversation.delegationMode == .off ? Color.secondary.opacity(0.15) : Color.accentColor.opacity(0.15))
    .foregroundColor(conversation.delegationMode == .off ? .secondary : .accentColor)
    .overlay(RoundedRectangle(cornerRadius: 5).stroke(conversation.delegationMode == .off ? Color.secondary.opacity(0.3) : Color.accentColor.opacity(0.4)))
    .cornerRadius(5)
}
.buttonStyle(.plain)
.popover(isPresented: $showDelegationPicker, arrowEdge: .bottom) {
    DelegationModePickerView(
        mode: Binding(get: { conversation.delegationMode }, set: { _ in }),
        targetAgentName: Binding(get: { conversation.delegationTargetAgentName }, set: { _ in }),
        participants: conversation.participants,
        hasCoordinator: conversation.participants.contains(where: { $0.role == .coordinator }),
        onSelect: { mode, target in
            appState.setDelegationMode(for: conversation, mode: mode, targetAgentName: target)
            showDelegationPicker = false
        }
    )
}
```

Add `shortLabel` to `DelegationMode` in `SidecarProtocol.swift`:

```swift
var shortLabel: String {
    switch self {
    case .off: return "Off"
    case .byAgents: return "agents"
    case .specificAgent: return "specific"
    case .coordinator: return "coordinator"
    }
}
```

- [ ] **Step 3: Build**

```bash
xcodebuild -project /Users/shayco/Odyssey/Odyssey.xcodeproj -scheme Odyssey -configuration Debug build 2>&1 | grep -E "error:|BUILD"
```

Fix any compile errors, then:

- [ ] **Step 4: Commit**

```bash
cd /Users/shayco/Odyssey
git add Odyssey/Views/MainWindow/ChatView.swift Odyssey/Services/SidecarProtocol.swift
git commit -m "feat(delegation): Auto-Answer badge and DelegationModePickerView in chat header"
```

---

## Task 11: Swift — Routing pill and attribution tag in transcript

**Files:**
- Modify: `Odyssey/Views/MainWindow/ChatView.swift`

- [ ] **Step 1: Add routing pill view**

In `ChatView.swift`, add a small view for the routing notice:

```swift
struct QuestionRoutingPillView: View {
    let targetAgentName: String
    let isFallback: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isFallback ? Color.orange : Color.green)
                .frame(width: 6, height: 6)
            Text(isFallback ? "⏱ No reply · routed to \(targetAgentName)" : "Routing to \(targetAgentName)…")
                .font(.system(size: 10))
                .foregroundColor(isFallback ? .orange : .green)
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(isFallback ? Color.orange.opacity(0.08) : Color.green.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isFallback ? Color.orange.opacity(0.25) : Color.green.opacity(0.25)))
        .cornerRadius(8)
    }
}
```

- [ ] **Step 2: Inject routing pill into message list**

In `ChatView.swift`, find where `agent.question` messages are rendered (the card that shows the user a question to answer). After the question card, check `conversation.pendingQuestionRouting` for the message's questionId and show the routing pill:

```swift
// After rendering the ask_user question card for a message:
if let routingTarget = conversation.pendingQuestionRouting[message.questionId ?? ""] {
    QuestionRoutingPillView(targetAgentName: routingTarget, isFallback: false)
        .padding(.leading, 32)
}
```

For resolved questions, when the follow-up agent message is rendered with `resolvedQuestions[questionId]`, show the fallback pill and attribution tag.

- [ ] **Step 3: Add attribution tag to agent message sender line**

In the agent message rendering code, when a message has `resolvedBy` metadata (add `resolvedBy: String?` and `isFallbackAnswer: Bool` to `ConversationMessage` as `@Transient` fields set when `agentQuestionResolved` fires), show the tag:

```swift
// In the message sender label HStack:
if let answeredBy = message.resolvedBy {
    Text(message.isFallbackAnswer ? "fallback answer" : "answered for you")
        .font(.system(size: 9, weight: .medium))
        .padding(.horizontal, 5).padding(.vertical, 1)
        .background(message.isFallbackAnswer ? Color.orange.opacity(0.12) : Color.accentColor.opacity(0.12))
        .foregroundColor(message.isFallbackAnswer ? .orange : .accentColor)
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(message.isFallbackAnswer ? Color.orange.opacity(0.3) : Color.accentColor.opacity(0.3)))
        .cornerRadius(3)
}
```

Set `message.resolvedBy` and `message.isFallbackAnswer` in AppState when handling `agentQuestionResolved` — find the most recent message from the answering agent in that conversation and annotate it.

- [ ] **Step 4: Build**

```bash
xcodebuild -project /Users/shayco/Odyssey/Odyssey.xcodeproj -scheme Odyssey -configuration Debug build 2>&1 | grep -E "error:|BUILD"
```

Fix any compile errors.

- [ ] **Step 5: Commit**

```bash
cd /Users/shayco/Odyssey
git add Odyssey/Views/MainWindow/ChatView.swift Odyssey/App/AppState.swift
git commit -m "feat(delegation): routing pill + attribution tag in chat transcript"
```

---

## Verification

Run through these scenarios end-to-end with the app running:

1. **Off mode (no regression):** Open a group conversation. Confirm Auto-Answer badge shows "Auto-Answer" in grey. Call `ask_user` from an agent. Confirm question surfaces to user as before. After 5 min (or shorten `DEFAULT_TIMEOUT_MS.off` to 10s for testing), confirm "proceed with best judgment" response.

2. **By agents — `ask_agent`:** Set mode to "By agents". Have an agent call `ask_agent(question, to_agent: "Reviewer")`. Confirm routing pill appears in chat. Confirm Reviewer's answer appears with "answered for you" tag. Confirm calling agent receives the answer and continues.

3. **By agents — `ask_user` timeout:** Set mode to "By agents". Have agent call `ask_user`. Don't answer. After 30s, confirm routing pill appears, fallback agent answers, attribution shows "fallback answer" tag.

4. **Specific agent override:** Set mode to "Specific agent → PM". Have agent call `ask_agent(question, to_agent: "Reviewer")`. Confirm PM answers (not Reviewer).

5. **Coordinator mode:** In a group with a coordinator (PM), set mode to "Coordinator". Have agent call `ask_user`. After 30s, confirm PM answers.

6. **Coordinator absent:** Set mode to "Coordinator" in a group with no coordinator. Have agent call `ask_user`. After 30s, confirm escalates to user (no routing pill).

7. **timeout_seconds shortening:** Set mode to "By agents". Have agent call `ask_user(question, timeout_seconds: 5)`. Confirm routing fires in ~5s, not 30s.
