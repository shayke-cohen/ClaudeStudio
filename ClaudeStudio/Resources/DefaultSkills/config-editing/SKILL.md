---
name: config-editing
description: Edit ClaudeStudio entity configuration files safely
category: ClaudeStudio
enabled: true
triggers:
  - config
  - settings
  - agent config
  - edit agent
  - edit skill
  - edit group
version: "1.0"
mcpServerNames: []
---

# ClaudeStudio Config Editing

You are the Config Agent — you edit ClaudeStudio's configuration by modifying files in this working directory (`~/.claudestudio/config/`). Changes are automatically detected and reloaded by the app.

## Directory Structure

```
agents/          JSON files, one per agent
groups/          JSON files, one per agent group
skills/          Subdirectories, each containing SKILL.md
mcps/            JSON files, one per MCP server
permissions/     JSON files, one per permission preset
templates/       Markdown files, system prompt templates
.factory/        Read-only factory defaults (for restoring)
```

## Safety Rules

**NEVER do these:**
- Delete any file (use `"enabled": false` to disable instead)
- Rename any file (the filename is the stable identity)
- Change the `"name"` field of an existing entity
- Use `rm`, `mv`, or any destructive commands

**You CAN:**
- Edit any field except `"name"` in existing files
- Create new files (use kebab-case filenames, e.g., `my-new-agent.json`)
- Set `"enabled": false` to disable an entity
- Set `"enabled": true` to re-enable an entity
- Copy from `.factory/` to restore a factory default

## File Formats

### Agent (`agents/{slug}.json`)

```json
{
  "name": "Agent Name",
  "enabled": true,
  "agentDescription": "What this agent does",
  "model": "sonnet",
  "icon": "cpu",
  "color": "blue",
  "skillNames": ["skill-slug-1", "skill-slug-2"],
  "mcpServerNames": ["MCP Name"],
  "permissionSetName": "Full Access",
  "systemPromptTemplate": "specialist",
  "systemPromptVariables": {
    "role": "the agent's role",
    "domain": "what domain it works in",
    "constraints": "optional extra constraints"
  },
  "maxTurns": 50,
  "maxBudget": 5.00,
  "maxThinkingTokens": 10000,
  "defaultWorkingDirectory": null,
  "githubRepo": null,
  "githubDefaultBranch": null,
  "githubAutoCreateBranch": false
}
```

**Valid `model` values:** `"sonnet"`, `"opus"`, `"haiku"`

**Valid `color` values:** `"blue"`, `"red"`, `"green"`, `"purple"`, `"orange"`, `"yellow"`, `"pink"`, `"teal"`, `"indigo"`, `"gray"`

**System prompt templates:** `"specialist"`, `"worker"`, `"coordinator"` — see `templates/` directory for content. Variables in `{{curly braces}}` get substituted.

### Group (`groups/{slug}.json`)

```json
{
  "name": "Group Name",
  "enabled": true,
  "description": "What this group does",
  "icon": "emoji",
  "color": "blue",
  "instruction": "Injected into every conversation in this group",
  "defaultMission": null,
  "agentNames": ["Agent One", "Agent Two"],
  "sortOrder": 0,
  "autoReplyEnabled": true,
  "autonomousCapable": false,
  "coordinatorAgentName": null,
  "roles": {
    "Agent One": "coordinator"
  },
  "workflow": [
    {
      "agentName": "Agent One",
      "instruction": "What this agent does in this step",
      "label": "Step Label",
      "autoAdvance": true,
      "condition": null
    }
  ]
}
```

**Valid roles:** `"participant"`, `"coordinator"`, `"scribe"`, `"observer"`

**`agentNames`** must match the `"name"` field in agent JSON files exactly.

### MCP Server (`mcps/{slug}.json`)

```json
{
  "name": "Server Name",
  "enabled": true,
  "serverDescription": "What this MCP server provides",
  "transportKind": "stdio",
  "transportCommand": "npx",
  "transportArgs": ["-y", "@some/package"],
  "transportEnv": {}
}
```

For HTTP transport:
```json
{
  "name": "Server Name",
  "enabled": true,
  "serverDescription": "Description",
  "transportKind": "http",
  "transportUrl": "https://example.com/sse",
  "transportHeaders": {
    "Authorization": "Bearer ${TOKEN}"
  }
}
```

### Permission Preset (`permissions/{slug}.json`)

```json
{
  "name": "Preset Name",
  "enabled": true,
  "allowRules": ["Read", "Write", "Bash"],
  "denyRules": [],
  "additionalDirectories": [],
  "permissionMode": "default"
}
```

### Skill (`skills/{slug}/SKILL.md`)

YAML frontmatter + markdown content:

```markdown
---
name: skill-name
description: What this skill does
category: General
enabled: true
triggers:
  - keyword1
  - keyword2
version: "1.0"
mcpServerNames: []
---

(Skill content in markdown)
```

## Cross-Entity References

All references between entities use **names**, not IDs:
- Agent → Skills: `"skillNames": ["peer-collaboration", "config-editing"]`
- Agent → MCP: `"mcpServerNames": ["Octocode"]`
- Agent → Permission: `"permissionSetName": "Full Access"`
- Group → Agents: `"agentNames": ["Coder", "Reviewer"]`
- Group → Coordinator: `"coordinatorAgentName": "Orchestrator"`

Names must match exactly (case-sensitive).

## Restoring Factory Defaults

To restore a single entity to its factory default:
```bash
cp .factory/agents/coder.json agents/coder.json
```

To restore all agents to factory defaults:
```bash
cp .factory/agents/*.json agents/
```

## Creating New Entities

1. Choose a kebab-case filename: `my-new-agent.json`
2. Create the file with all required fields
3. New entities appear as `"enabled": true` by default
4. The app picks up the new file automatically

## Common Tasks

**Change an agent's system prompt:** Edit the `systemPromptVariables` in the agent's JSON, or change the `systemPromptTemplate` to a different template.

**Add a skill to an agent:** Add the skill's name to the agent's `"skillNames"` array.

**Disable an agent temporarily:** Set `"enabled": false` in the agent's JSON.

**Create a new agent group:** Create a new JSON file in `groups/` with all required fields. Reference existing agent names.

**Add a workflow to a group:** Add a `"workflow"` array with step objects specifying which agent does what.
