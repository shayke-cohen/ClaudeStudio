# Agent, Skill & Template Creation Design

**Date:** 2026-04-17
**Status:** Approved

## Context

The Odyssey app is being redesigned. The Library Hub is removed and replaced with a unified Configuration settings tab. The existing creation flows for agents, skills, and templates are being replaced with a consistent hybrid pattern: a modal sheet with two modes — AI-assisted (From Prompt) and Manual.

Today all three store primarily to SwiftData and only optionally write files. This means items created via the UI may not have a corresponding file on disk, breaking the file-backed design. This spec fixes that for all three entity types.

## Shared Principles (Agents, Skills, Templates)

- **Files are source of truth.** Creating or editing via the UI writes the file immediately.
- **SwiftData is a read cache.** The UI also inserts into SwiftData for instant list feedback; `ConfigSyncService`'s file watcher deduplicates on next sync.
- **Two creation modes in one modal:** From Prompt (default, AI-assisted) and Manual.
- **Entry point:** Configuration settings tab for each entity type.
- **Container:** Modal sheet floats over the Configuration tab.

---

## Agents

### Agent Storage

- File: `~/.odyssey/config/agents/{slug}.json`
- Write method: `ConfigFileManager.writeAgent()` (exists)
- Slug: kebab-case derived from name field in real time

### Creation Modal: `AgentCreationSheet`

Replaces `AgentEditorView` and `AgentFromPromptSheet` (audit call sites before removing).

**From Prompt mode:**

1. User types a free-form description
2. Starter chips: Code reviewer, PR summarizer, Tech writer, Data analyst
3. AI generates name, model, skills, system prompt via `generateAgent` sidecar command
4. All generated fields shown in editable form for review
5. File path preview shown before creation
6. "Create Agent" writes file then inserts into SwiftData

**Manual mode:** Same editable form, empty. Fields: name, icon, model, description, skills, MCPs, system prompt.

### Agent AI Generation

Input to `generateAgent`: `prompt`, `availableSkills`, `availableMCPs`

Output (`AgentConfigDTO`): name, model, skillNames, mcpServerNames, systemPrompt

---

## Skills

### Skill Storage

- File: `~/.odyssey/config/skills/{slug}.md` (YAML frontmatter + markdown body)
- Write method: `ConfigFileManager.writeBack(skillSlug:dto:content:)` (exists)
- Slug: kebab-case from name

### Creation Modal: `SkillCreationSheet`

Replaces `SkillEditorView` (audit call sites before removing).

**From Prompt mode:**

1. User describes what the skill should teach the agent
2. Starter chips: Security patterns, Code review style, Architecture principles, Testing strategy
3. AI generates name, description, category, triggers, and the full markdown content body
4. All fields editable before saving — content body is a monospaced TextEditor
5. File path preview shown
6. "Create Skill" writes file then inserts into SwiftData

**Manual mode:** Same form, empty. Fields: name, description, category, triggers, required MCPs, markdown content body.

### Skill AI Generation

Input: `prompt`, `availableCategories`, `availableMCPs`

Output: name, skillDescription, category, triggers (array), mcpServerNames, content (markdown body)

The content body is the highest-value output — it's the full skill text the agent will read at runtime.

---

## Templates (Prompt Templates)

### What Templates Are

Reusable prompts attached to a specific agent or group. Shown as quick-launch buttons when starting a session. Example: a "Coder" agent might have a "Review PR" template and a "Full Codebase Audit" template.

### Template Storage

- File: `~/.odyssey/config/prompt-templates/{agents|groups}/{ownerSlug}/{templateSlug}.md`
- Write method: `ConfigFileManager.writePromptTemplate(ownerKind:ownerSlug:templateSlug:dto:)` (exists)
- Slug: generated via `ConfigFileManager.uniquePromptTemplateSlug()` (exists)

### Creation Modal: `PromptTemplateCreationSheet`

Replaces `PromptTemplateEditorSheet`.

Templates are always owned by an agent or group. The modal always receives an owner (agent or group) as context — it is not a standalone entity.

**From Prompt mode:**

1. Header shows the owner: "New template for [Agent Name]"
2. User describes the task intent (e.g., "Review a pull request for naming and structure issues")
3. AI generates the prompt text, and optionally the template name
4. Both fields are editable before saving
5. "Create Template" writes file then inserts into SwiftData

**Manual mode:** Two fields — name and prompt text (large TextEditor). Same save action.

### Template AI Generation

Input: `intent` (user description), `agentName`, `agentSystemPrompt` (for context)

Output: name (optional), prompt (the full template text)

---

## Architecture Summary

### New views to create

| View                         | Replaces                                  | Location               |
|------------------------------|-------------------------------------------|------------------------|
| `AgentCreationSheet`         | `AgentEditorView` + `AgentFromPromptSheet`| `Views/Configuration/` |
| `SkillCreationSheet`         | `SkillEditorView`                         | `Views/Configuration/` |
| `PromptTemplateCreationSheet`| `PromptTemplateEditorSheet`               | `Views/Configuration/` |

### Views to modify

| View | Change |
|------|--------|
| `AgentsConfigTab` | Add "+ New Agent" button, wire to `AgentCreationSheet` (create if not exists) |
| `SkillsConfigTab` | Add "+ New Skill" button, wire to `SkillCreationSheet` (create if not exists) |
| `TemplatesConfigTab` | Add "+ New Template" button with owner context, wire to `PromptTemplateCreationSheet` |

### Save pattern (same for all three)

1. Write file via `ConfigFileManager` — source of truth
2. Insert/update SwiftData directly — for instant UI feedback
3. `ConfigSyncService` watcher deduplicates on next scan via `configSlug`

### Unchanged

- `ConfigFileManager` write methods (all exist)
- `ConfigSyncService` file watcher (already syncs files → SwiftData)
- File formats and directory structure

---

## Verification

### Agents

1. Configuration tab → Agents section → click "+ New Agent" → modal appears
2. From Prompt: type description → Generate → review editable fields → Create Agent
3. Check `~/.odyssey/config/agents/` in Terminal — `.json` file exists
4. Edit the file externally → app picks up the change within ~1s
5. Manual mode: fill form directly → Create → file written

### Skills

1. Configuration tab → Skills section → click "+ New Skill" → modal appears
2. From Prompt: describe skill → Generate → review name/category/triggers/content → Create Skill
3. Check `~/.odyssey/config/skills/` — `.md` file with frontmatter exists
4. Edit content externally → app syncs

### Templates

1. Configuration tab → select an agent → Templates section → click "+ New Template"
2. From Prompt: describe task intent → Generate → review name + prompt text → Create Template
3. Check `~/.odyssey/config/prompt-templates/agents/{slug}/` — `.md` file exists
4. Template appears in quick-launch buttons when starting a session with that agent
