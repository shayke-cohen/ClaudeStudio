# Agent Question Delegation — Design Spec

**Date:** 2026-04-17  
**Status:** Design approved, pending implementation plan

---

## Context

Agents in Odyssey use `ask_user()` to block and wait for human input. In multi-agent group conversations this creates friction — the user must answer every clarifying question even when another agent in the group has the relevant knowledge. This spec introduces a delegation system so agents can route questions to other agents, with the user controlling how much autonomy to grant.

---

## Core Model

Two tools handle questions, one routing layer, one user-controlled mode.

```
ask_user(question, timeout_seconds?)
  → surfaces to human as a card in the transcript
  → countdown shown if mode is On
  → on timeout: routes based on delegation mode
  → Off mode: "proceed with best judgment" (current behaviour)

ask_agent(question, to_agent)
  → routes directly to nominated agent, no user interruption
  → mode may override to_agent (specific agent / coordinator modes)
  → user sees attribution in transcript: "answered for you"
```

The asking agent's only decisions:
1. Does this need a human, or can an agent answer it? → pick the tool
2. If agent — who? → `to_agent` on `ask_agent`

---

## Tool Specifications

### `ask_user`

Existing tool, two new fields added:

| Param | Type | Description |
|---|---|---|
| `question` | string | The question text (unchanged) |
| `options` | array | Structured choices (unchanged) |
| `input_type` | enum | UI input type (unchanged) |
| `private` | bool | Visibility (unchanged) |
| `timeout_seconds` | number? | Hint to shorten the mode's default timeout. Ignored in Off mode. Cannot exceed mode default. |

**Expiry behaviour:**

| Mode | Default timeout | On expiry |
|---|---|---|
| Off | 300s (5 min) | "Proceed with best judgment" — current behaviour unchanged |
| By agents | 30s | Route via fallback chain (see below) |
| Specific agent | 30s | Route to user's designated agent |
| Coordinator | 30s | Route to coordinator; if none present → escalate to user |

**Fallback chain** (By agents mode, when `ask_user` times out):
```
coordinator present? → route there (first coordinator session found)
else → least-busy available agent (measured by message queue depth, existing SessionRegistry logic)
else → "proceed with best judgment"
```

### `ask_agent` (new tool)

| Param | Type | Description |
|---|---|---|
| `question` | string | The question text |
| `to_agent` | string | Nominated agent name. Mode may override this. |

**Routing logic:**
- Mode Off or By agents → use `to_agent` as-is
- Mode Specific agent → override `to_agent` with user's designated agent
- Mode Coordinator → override `to_agent` with coordinator session

**No timeout.** The nominated agent always resolves the question. If the nominated agent session doesn't exist, fall back to user.

---

## Delegation Mode

Conversation-level setting. Three active states plus Off.

| Mode | ask_user timeout | ask_agent routing | When available |
|---|---|---|---|
| **Off** | 300s → best judgment | `to_agent` as nominated | Always |
| **By agents** | 30s → fallback chain | `to_agent` as nominated | Always |
| **Specific agent** | 30s → designated agent | Overridden to designated agent | Always (user picks agent) |
| **Coordinator** | 30s → coordinator | Overridden to coordinator | Only when coordinator exists in group |

---

## UX

### Control placement

Chat header, next to the existing **Interactive / Autonomous** execution mode toggle.

```
[👥 Dev Team]  [Interactive]  [⚡ Auto-Answer ▾]  [⋯]
```

Badge is blue-tinted when any auto mode is active, grey when Off.

### Mode picker popover

Card-style rows, each with a timeout badge on the right. Clicking **Specific agent** expands an inline agent picker showing all active participants.

```
┌─────────────────────────────────────────┐
│ 🚫  Off                          5 min  │
│ ⚡  By agents                     30s   │
│ 👤  Specific agent     ← selected  30s  │
│     ┌─────────────────────────┐         │
│     │ 🤖 Coder                │         │
│     │ 📋 Reviewer          ✓  │         │
│     │ 🎯 PM                   │         │
│     └─────────────────────────┘         │
│ 🎯  Coordinator                   30s   │
└─────────────────────────────────────────┘
```

Coordinator row only shown when a coordinator agent exists in the conversation.

### Chat transcript states

**ask_agent flow (direct delegation):**
```
🤖 Coder
   async/await or callbacks for the network layer?

   ● Routing to Reviewer…          ← green routing pill

📋 Reviewer  [answered for you]    ← small blue tag
   async/await — consistent with the rest of the codebase.
```

**ask_user timeout fallback:**
```
🎯 PM
   Should we prioritise speed or correctness for v1?

┌─ Question for you ──────────────────────┐
│ Should we prioritise speed or           │
│ correctness for v1?                     │
│ [Speed]  [Correctness]  [Type answer…] │
│ Auto-routing to Reviewer in 23s…        │
└─────────────────────────────────────────┘

   ⏱ No reply · routed to Reviewer       ← amber pill

📋 Reviewer  [fallback answer]           ← amber tag
   Correctness — we can optimise in v2.
```

---

## Implementation Touchpoints

| Layer | File | Change |
|---|---|---|
| Sidecar tool | `sidecar/src/tools/ask-user-tool.ts` | Add `timeout_seconds` param; wire mode-driven expiry routing |
| Sidecar tool | `sidecar/src/tools/ask-agent-tool.ts` | **New file** — `ask_agent` tool implementation |
| Tool context | `sidecar/src/tools/` index | Register `ask_agent` in tool registry |
| Session manager | `sidecar/src/session-manager.ts` | Expose delegation mode per conversation |
| Wire protocol | `sidecar/src/types.ts` | Add `agent.question.routing` and `agent.question.resolved` events |
| Swift protocol | `Odyssey/Services/SidecarProtocol.swift` | Mirror new event types |
| Swift model | `Odyssey/Models/Conversation.swift` | Add `delegationMode` + `delegationTargetAgentName` fields |
| Chat header | `Odyssey/Views/MainWindow/ChatView.swift` | Add Auto-Answer badge + popover |
| Chat transcript | `Odyssey/Views/MainWindow/ChatView.swift` | Routing pill + attribution tag rendering |

---

## Verification

1. **Off mode unchanged** — call `ask_user`, verify existing 5-min timeout and "best judgment" behaviour is intact
2. **By agents — ask_agent** — call `ask_agent(question, to_agent: "Reviewer")`, verify Reviewer session receives and answers, transcript shows routing pill + "answered for you" tag
3. **By agents — ask_user timeout** — call `ask_user`, don't answer, verify routing fires at 30s to fallback chain
4. **Specific agent override** — set mode to Specific: Reviewer, call `ask_agent(question, to_agent: "Coder")`, verify Reviewer answers (not Coder)
5. **Coordinator mode** — set mode to Coordinator, call `ask_user`, verify PM (coordinator) answers after 30s
6. **Coordinator absent** — set mode to Coordinator with no coordinator in group, verify `ask_user` escalates to user
7. **timeout_seconds shortening** — call `ask_user(question, timeout_seconds: 10)` in By agents mode, verify routing fires at 10s not 30s
8. **timeout_seconds ignored in Off** — call `ask_user(question, timeout_seconds: 5)` in Off mode, verify 5-min timeout still applies
