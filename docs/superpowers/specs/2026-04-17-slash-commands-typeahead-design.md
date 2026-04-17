# Slash Commands + Typeahead for Odyssey Chat

**Date:** 2026-04-17  
**Status:** Implemented

## Overview

Native macOS Claude Code CLI users miss their `/` slash commands when using the Odyssey GUI. This feature adds a typeahead slash command system to the chat input, giving CC parity for chat-scoped operations.

## Design

- `/` in chat → vertical typeahead dropdown, chat-scoped commands only
- `⌘K` → app-scoped command palette (separate, not in scope)
- Typeahead reuses the existing `@mention` autocomplete pattern in ChatView
- Keyboard navigation: ↑↓ to move, ↵ to select, Esc to dismiss
- Sub-picker for commands requiring a second step (model, effort, mode, export, branch, resume)
- Dropdown capped at 220pt height with scroll + auto-scroll to selected row (matches CC behavior)
- `//` prefix is excluded — treated as literal text, not a command

## Command List (24 commands across 7 groups)

| Group | Command | Backend |
|---|---|---|
| **Session** | `/clear` | `SidecarCommand.conversationClear` → sidecar broadcasts `conversation.cleared` |
| | `/compact` | `SidecarCommand.sessionCompact` |
| | `/export [format]` | `ChatTranscriptExport` (existing) — sub-picker for md/html/json |
| | `/resume` | `SidecarCommand.sessionResume` — sub-picker lists sessions |
| **Model** | `/model <model>` | `SidecarCommand.sessionUpdateModel` — sub-picker for 3 models |
| | `/effort <level>` | `SidecarCommand.sessionUpdateEffort` — sub-picker for low/medium/high/max |
| | `/fast` | Shorthand for `/effort low` |
| **Memory & Skills** | `/memory` | Opens `MemoryEditorSheet` editing `~/.odyssey/agents/{slug}/memory.md` |
| | `/skills` | Presents skills sheet from SwiftData `Skill` models |
| **Agents** | `/agents` | Opens existing agents sheet |
| | `/mode <mode>` | `SidecarCommand.sessionUpdateMode` — sub-picker: interactive/autonomous/worker |
| | `/plan` | Sets `planModeActive = true` — pill in input bar, next message gets `planMode: true` |
| **Tools** | `/mcp` | Opens MCP servers sheet from `AgentConfig.mcpServers` |
| | `/permissions` | Opens `PermissionSet` sheet |
| **Workflow** | `/loop <interval>` | Creates `ScheduledMissionDraft` via `ScheduleEngine` |
| | `/schedule` | Opens schedule editor sheet |
| **Git** | `/review` | Prompt injection → agent runs `git diff HEAD` + structured review |
| | `/diff` | Prompt injection → agent runs `git diff HEAD`, streams formatted output |
| | `/branch` | Sub-picker (create/switch/list) → agent executes git op |
| | `/init` | Prompt injection → agent creates `CLAUDE.md` + project summary |
| **Info** | `/context` | Inline info bubble: token count + % of context window used |
| | `/cost` | Inline info bubble: session cost in USD |
| | `/help` | Typeahead IS the help; Esc dismisses |
| | `/agents` | Existing agents sheet |

## New Files

| File | Purpose |
|---|---|
| `Odyssey/Services/SlashCommandRegistry.swift` | Command catalog with `SlashCommandInfo`, `SlashCommandGroup`, fuzzy filtering |
| `Odyssey/Views/Components/SlashCommandDropdown.swift` | Typeahead dropdown + `SlashSubPickerView` for two-step commands; capped at 220pt with scroll |
| `Odyssey/Views/Sheets/MemoryEditorSheet.swift` | `TextEditor` for `~/.odyssey/agents/{slug}/memory.md` |

## Modified Files

| File | Changes |
|---|---|
| `Odyssey/Services/ChatSendRouting.swift` | +20 `ChatSlashCommand` enum cases + `parseSlashCommand()` parser |
| `Odyssey/Views/MainWindow/ChatView.swift` | Typeahead state, keyboard nav, `sendMessage()` switch expansion for all 24 commands, `slashCommandSheets` extracted to fix type-checker timeout |
| `Odyssey/Services/SidecarProtocol.swift` | Added `conversationClear`, `sessionCompact`, `sessionUpdateModel`, `sessionUpdateEffort` commands; `conversationCleared` event |
| `sidecar/src/types.ts` | Added matching TypeScript command/event types |
| `sidecar/src/ws-server.ts` | Handlers for `conversation.clear`, `session.compact`, `session.updateModel`, `session.updateEffort`; fixed `broadcast()` call for `conversation.cleared` |

## Wire Protocol Additions

**Commands (Swift → Sidecar):**
- `conversation.clear` → `{ type, conversationId }` — clears messages, broadcasts `conversation.cleared`
- `session.compact` → `{ type, sessionId }` — triggers context summarization
- `session.updateModel` → `{ type, sessionId, model }` — overrides model for next turn
- `session.updateEffort` → `{ type, sessionId, effort }` — maps to `maxThinkingTokens` presets

**Events (Sidecar → Swift):**
- `conversation.cleared` → `{ type, conversationId }` — triggers local message clear in ChatView

## Test Coverage

- `OdysseyTests/ChatSendRoutingTests.swift` — 36 unit tests covering all 24 command parsers + edge cases
- `OdysseyTests/SidecarProtocolTests.swift` — 9 tests for new wire encoding/decoding
- `sidecar/test/unit/slash-commands.test.ts` — 14 unit tests for ConversationStore.clearMessages + SessionRegistry.updateConfig
- `sidecar/test/integration/slash-command-flow.test.ts` — 8 integration tests (real WsServer + stores)
- `sidecar/test/api/slash-command-api.test.ts` — 10 protocol correctness tests
- `sidecar/test/e2e/slash-command-e2e.test.ts` — 9 E2E tests (full sidecar subprocess, two-client broadcast)

## Key Implementation Notes

- **Type-checker timeout fix:** 9 slash command sheets extracted into `@ViewBuilder var slashCommandSheets` applied via `.background()` — Swift's type checker couldn't handle the chain inline
- **`exportTranscript`:** Uses `chatExportSnapshot()` → `ChatTranscriptExport.html/markdown(snap)`, pattern-matches `Row.kind` enum for JSON serialization
- **`createLoopMission`:** `ScheduledMissionDraft(name:promptTemplate:)` with `intervalHours: max(1, minutes/60)` — no `intervalMinutes`, minimum is 1 hour
- **Broadcast bug fix:** `conversation.clear` handler was calling `this.ctx.broadcast()` (no-op) instead of `this.broadcast()` — caught by integration tests
- **Duplicate property fix:** `conversationId` was added twice to `IncomingWireMessage` causing `Decodable` conformance failure; removed duplicate at line 784 and the redundant `CodingKeys` entry
