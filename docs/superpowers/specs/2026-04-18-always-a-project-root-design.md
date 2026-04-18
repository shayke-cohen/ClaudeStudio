# Always-a-Project-Root: Session Working Directory Unification

**Date:** 2026-04-18
**Status:** Design approved

---

## Problem

Agent and group sessions have non-deterministic working directories. When a session is created without an explicit project, the working directory falls back to `windowState.projectDirectory` — whatever project happens to be open in the window at that moment. This means:

- Two identical agent clicks can produce sessions in different directories depending on window state
- Resident agents operating in a project's codebase are not actually linked to that project
- Schedules bake in the working directory at creation time, so they go stale if the agent or project root changes
- Agent-invite flows inherit the source session's WD, propagating any upstream mismatch

---

## Design

### The Unified Rule

Every session always has a deterministic project root. It is resolved from the **subject** of the session — never borrowed from window state, never baked in at creation time:

| Subject | Working Directory | Project |
|---|---|---|
| Agent in project context | `project.rootPath` | Project |
| Agent without project | `agent.defaultWorkingDirectory` | Agent default = project root (conceptual — no new SwiftData Project entity is created) |
| Group in project context | `project.rootPath` | Project |
| Group without project | `group.defaultWorkingDirectory` | Group default = project root |
| Schedule — agent target | `agent.defaultWorkingDirectory` (resolved at run time) | Agent's context |
| Schedule — group target | `group.defaultWorkingDirectory` (resolved at run time) | Group's context |
| Schedule — project target | `project.rootPath` (resolved at run time) | Project |

`windowState.projectDirectory` is **never** used as a fallback for session working directory.

---

## Session Initiation Changes

| # | Scenario | Current WD | Suggested WD | Current Project | Suggested Project |
|---|---|---|---|---|---|
| 1 | Click agent in sidebar (no explicit project) | Agent default | Agent default | None | Agent default = project root |
| 2 | Click agent → "New Chat in Project" | Agent default | Project root | Project | Project |
| 3 | Start agent from Agent Library (project selected) | Agent default | Project root | Project | Project |
| 4 | Start agent from main window panel (project selected) | Agent default | Project root | Project | Project |
| 5 | New Session sheet — single agent | Project root | Project root | Project | Project |
| 6 | New Session sheet — multiple agents | Project root | Project root | Project | Project |
| 7 | Start group from any group UI | Project root | Project root | Project | Project |
| 8 | Agent invites agent — project conversation | Source session WD | Project root | Inherited | Project |
| 9 | Agent invites agent — agent-home conversation | Source session WD | Agent default | None | Agent default = project root |
| 10 | Schedule fires — agent schedule | Baked-in at creation | Agent default (live) | Stored on schedule | Agent's context |
| 11 | Schedule fires — group schedule | Baked-in at creation | Group default (live) | Stored on schedule | Group's context |
| 12 | Schedule fires — project schedule | Baked-in at creation | Project root (live) | Stored on schedule | Project |
| 13 | CLI / URL scheme launch | Launch param / window state | Launch param / agent default | Selected project | Selected project / agent default |

Rows 2, 3, 4, 8, 9, 10, 11, 12 change.

---

## Implementation Approach

**Option A — Fix at call sites.** `AgentProvisioner.provision()` already honors `workingDirOverride` as highest priority. The fix is ensuring every call site with a project context passes `project.rootPath` as the override, and every call site without a project never falls back to window state.

### Call Site Fixes

**1. `SidebarView.startSession(with:in:)` (scenarios 2)**
When `project != nil`, pass `project.rootPath` as working dir — do not let agent default win.

**2. `AgentLibraryView.startSession(with:)` (scenario 3)**
When `windowState.selectedProjectId` is set, resolve the project and pass its `rootPath`. When no project, use `agent.defaultWorkingDirectory` — never `windowState.projectDirectory`.

**3. `MainWindowView.startSessionWithAgent(_:)` (scenario 4)**
Same as above.

**4. `AppState.handleInviteAgent()` (scenarios 8, 9)**
Look up `conversation.projectId` → project → `rootPath`. If project exists, pass `rootPath` as `workingDirOverride`. If no project (agent-home conversation), use the **invited agent's own** `defaultWorkingDirectory` — never inherit from the source (inviting) session.

### Schedule Model Change (scenarios 10–12)

`ScheduledMission` currently stores `projectDirectory: String` baked in at creation time from `windowState.projectDirectory`. This field becomes derived:

- Keep `projectDirectory` on `ScheduledMission` for migration safety but stop reading it at run time
- At run time, `ScheduleRunCoordinator` resolves WD from the schedule's target:
  - Agent schedule → `agent.defaultWorkingDirectory`
  - Group schedule → `group.defaultWorkingDirectory`
  - Project schedule → `project.rootPath`
- `ScheduleLibraryView` stops writing `windowState.projectDirectory` into the draft

---

## Files to Change

| File | Change |
|---|---|
| `Odyssey/Views/MainWindow/SidebarView.swift` | `startSession(with:in:)` — project root wins when project is set |
| `Odyssey/Views/AgentLibrary/AgentLibraryView.swift` | `startSession(with:)` — project root wins; no window state fallback |
| `Odyssey/Views/MainWindow/MainWindowView.swift` | `startSessionWithAgent(_:)` — same as above |
| `Odyssey/App/AppState.swift` | `handleInviteAgent()` — resolve WD from project or agent, not source session |
| `Odyssey/Services/ScheduleRunCoordinator.swift` | Resolve WD from subject at run time, not stored path |
| `Odyssey/Views/Schedules/ScheduleLibraryView.swift` | Stop baking `windowState.projectDirectory` into schedule draft |
| `Odyssey/Models/ScheduledMission.swift` | Deprecate / remove `projectDirectory` field |

---

## Verification

- Start a resident agent from the sidebar with no project open → WD is agent's home dir
- Start the same agent via "New Chat in Project" → WD is project root, not agent home
- Start a group from the group library with a project selected → WD is project root
- Invite an agent into a project conversation → invited agent WD is project root
- Invite an agent into an agent-home conversation → invited agent WD is its own default
- Create an agent schedule → run it → WD is agent's current `defaultWorkingDirectory`, not a stale baked-in path
- Change an agent's `defaultWorkingDirectory` → existing schedule picks up the new path on next run
