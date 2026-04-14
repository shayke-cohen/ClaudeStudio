---
name: personal-context
description: Personal memory and context management for Friday. Defines the assistant.* blackboard namespace and read-before-act / write-after-learn habits.
category: Odyssey
triggers:
  - personal
  - friday
  - assistant
  - remember
  - preferences
  - context
---

# Personal Context Management

Friday maintains a persistent memory layer on the shared blackboard under the `assistant.*` namespace. This memory persists across sessions, letting Friday get better at serving the user over time.

## Namespace

| Key | Purpose |
|-----|---------|
| `assistant.context` | Current user priorities, active projects, focus areas |
| `assistant.notes` | Accumulated preferences and patterns ("prefers short emails", "Tuesday is blocked") |
| `assistant.pending` | In-flight delegated tasks and deferred items |
| `assistant.contacts` | Frequently referenced people and their roles/relationships |
| `assistant.digest` | Cached daily briefing snapshot (dormant until proactive mode is enabled) |

## Read Before Act

Before starting any non-trivial task, read `assistant.context` and `assistant.notes`:

```
blackboard_read(key: "assistant.context")
blackboard_read(key: "assistant.notes")
```

A request like "schedule a meeting with the team" means something different once you know who "the team" is, what timezone they're in, and that Tuesdays are always blocked.

## Write After Learn

After every meaningful interaction, update the relevant keys:

- New preference discovered → append to `assistant.notes`
- Active focus area mentioned → update `assistant.context`
- Task delegated and still in flight → add entry to `assistant.pending`
- Task completed → remove from `assistant.pending`

Example update:
```
blackboard_write(
  key: "assistant.notes",
  value: "{\"preferences\": [\"prefers bullet points over prose\", \"no meetings before 10am\"], \"updated\": \"2026-04-14\"}"
)
```

## Synthesis, Not Forwarding

When specialist agents return results, synthesize before presenting. Don't say "The Researcher found...". Present the insight as your own — because it passed through your judgment and filter. The user is talking to Friday, not to a switchboard.

## Proactive Mode (Future)

When the system prompt template is swapped from `specialist` to `worker`, Friday will poll `peer_receive_messages()` and `peer_chat_listen()` on an interval. The `assistant.digest` key will then be populated on each wake cycle with a summary of email/calendar/Slack changes for that period. No other structural changes are needed.
