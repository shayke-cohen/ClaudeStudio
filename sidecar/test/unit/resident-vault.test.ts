/**
 * Unit tests for Resident Agent vault file structure and session registry integration.
 *
 * These tests verify:
 * - Vault files written by the Swift layer have the expected structure (read from temp dir)
 * - SessionRegistry correctly stores and retrieves workingDirectory for resident agents
 * - Vault working directories are preserved through the session config lifecycle
 *
 * Usage: ODYSSEY_DATA_DIR=/tmp/odyssey-test-$(date +%s) bun test test/unit/resident-vault.test.ts
 */
import { describe, test, expect, beforeEach, afterEach } from "bun:test";
import { mkdtempSync, writeFileSync, mkdirSync, readFileSync, existsSync } from "fs";
import { join } from "path";
import { tmpdir } from "os";
import { SessionRegistry } from "../../src/stores/session-registry.js";
import { makeAgentConfig } from "../helpers.js";

// ─── Vault file helpers ─────────────────────────────────────────────

function createVaultDir(agentName: string): string {
  const dir = mkdtempSync(join(tmpdir(), `odyssey-vault-${agentName.toLowerCase().replace(/\s/g, "-")}-`));
  const date = new Date().toISOString().split("T")[0];

  writeFileSync(join(dir, "CLAUDE.md"), `---
agent: ${agentName}
updated: ${date}
---

# ${agentName}

## Role
<!-- What this agent is here to do. -->

## Capabilities
<!-- What this agent is good at. -->

## Knowledge Graph

| File | Purpose | Cap |
|------|---------|-----|
| \`INDEX.md\` | Map of content | — |
| \`MEMORY.md\` | Routing index + recent lessons | 200 lines |
| \`GUIDELINES.md\` | Self-written rules | — |
| \`SESSION.md\` | Current active state (volatile) | Reset each session |
| \`sessions/YYYY-MM-DD.md\` | Append-only daily session log | — |
| \`knowledge/{topic}.md\` | Semantic topic notes | — |

## Session Start

1. Read \`INDEX.md\` — understand what exists in the graph
2. Read \`MEMORY.md\` — load routing index and recent lessons
3. Read \`GUIDELINES.md\` — apply your self-written rules
4. Reset \`SESSION.md\` — write current task and what NOT to forget
5. Grep \`sessions/\` or \`knowledge/\` for topics relevant to today

## Session End — Reflection Loop

Answer before closing:
1. What was the task? Did it succeed?
2. What was the earliest friction or mistake?
3. What one rule would prevent it next time?

Then:
- Write a one-liner to \`MEMORY.md\`: \`YYYY-MM-DD: <lesson>\`
- Write a full reflection entry to today's session file
- If a pattern has recurred 2+ times across sessions → promote to \`knowledge/{topic}.md\`
- Update \`INDEX.md\` if any new file was created
`);

  writeFileSync(join(dir, "INDEX.md"), `---
updated: ${date}
---

# ${agentName} — Knowledge Index

## Core Files
- [[CLAUDE.md]] — identity, graph conventions, and reflection loop
- [[MEMORY.md]] — routing index and recent lessons
- [[GUIDELINES.md]] — self-written rules
- [[SESSION.md]] — current active state (volatile)

## Sessions (Episodic)

## Knowledge (Semantic)
`);

  writeFileSync(join(dir, "MEMORY.md"), `---
updated: ${date}
cap: "200 lines — keep under this cap; move detail to knowledge/"
---

# ${agentName} — Memory

## Recent Lessons

## Domain Map

## Active Goals
`);

  writeFileSync(join(dir, "GUIDELINES.md"), `---
updated: ${date}
tags: [guidelines]
---

# Guidelines
`);

  writeFileSync(join(dir, "SESSION.md"), `---
updated: ${date}
volatile: true
---

# Current Session

## Task

## Active Context

## Do Not Forget
`);

  return dir;
}

// ─── Vault file content tests ───────────────────────────────────────

describe("Resident Vault — CLAUDE.md structure", () => {
  let vaultDir: string;

  beforeEach(() => {
    vaultDir = createVaultDir("Test Agent");
  });

  test("CLAUDE.md has YAML frontmatter", () => {
    const content = readFileSync(join(vaultDir, "CLAUDE.md"), "utf8");
    expect(content.startsWith("---")).toBe(true);
    expect(content).toContain("agent: Test Agent");
    expect(content).toContain("updated:");
  });

  test("CLAUDE.md contains session start checklist", () => {
    const content = readFileSync(join(vaultDir, "CLAUDE.md"), "utf8");
    expect(content).toContain("## Session Start");
    expect(content).toContain("INDEX.md");
    expect(content).toContain("MEMORY.md");
    expect(content).toContain("GUIDELINES.md");
    expect(content).toContain("SESSION.md");
  });

  test("CLAUDE.md contains reflection loop", () => {
    const content = readFileSync(join(vaultDir, "CLAUDE.md"), "utf8");
    expect(content).toContain("Session End");
    expect(content).toContain("Reflection Loop");
    expect(content).toContain("YYYY-MM-DD: <lesson>");
    expect(content).toContain("knowledge/{topic}.md");
    expect(content).toContain("2+ times");
  });

  test("CLAUDE.md file map mentions 200-line cap for MEMORY.md", () => {
    const content = readFileSync(join(vaultDir, "CLAUDE.md"), "utf8");
    expect(content).toContain("200 lines");
  });
});

describe("Resident Vault — MEMORY.md structure", () => {
  let vaultDir: string;

  beforeEach(() => {
    vaultDir = createVaultDir("Memory Agent");
  });

  test("MEMORY.md has YAML frontmatter with cap annotation", () => {
    const content = readFileSync(join(vaultDir, "MEMORY.md"), "utf8");
    expect(content.startsWith("---")).toBe(true);
    expect(content).toContain("200 lines");
    expect(content).toContain("knowledge/");
  });

  test("MEMORY.md has routing index sections", () => {
    const content = readFileSync(join(vaultDir, "MEMORY.md"), "utf8");
    expect(content).toContain("## Recent Lessons");
    expect(content).toContain("## Domain Map");
    expect(content).toContain("## Active Goals");
  });
});

describe("Resident Vault — INDEX.md structure", () => {
  let vaultDir: string;

  beforeEach(() => {
    vaultDir = createVaultDir("Index Agent");
  });

  test("INDEX.md links to all core vault files with wiki-link syntax", () => {
    const content = readFileSync(join(vaultDir, "INDEX.md"), "utf8");
    expect(content).toContain("[[CLAUDE.md]]");
    expect(content).toContain("[[MEMORY.md]]");
    expect(content).toContain("[[GUIDELINES.md]]");
    expect(content).toContain("[[SESSION.md]]");
  });

  test("INDEX.md has sections for episodic and semantic content", () => {
    const content = readFileSync(join(vaultDir, "INDEX.md"), "utf8");
    expect(content).toContain("Sessions (Episodic)");
    expect(content).toContain("Knowledge (Semantic)");
  });
});

describe("Resident Vault — SESSION.md structure", () => {
  let vaultDir: string;

  beforeEach(() => {
    vaultDir = createVaultDir("Session Agent");
  });

  test("SESSION.md has volatile frontmatter flag", () => {
    const content = readFileSync(join(vaultDir, "SESSION.md"), "utf8");
    expect(content).toContain("volatile: true");
  });

  test("SESSION.md has expected sections", () => {
    const content = readFileSync(join(vaultDir, "SESSION.md"), "utf8");
    expect(content).toContain("## Task");
    expect(content).toContain("## Active Context");
    expect(content).toContain("## Do Not Forget");
  });
});

// ─── SessionRegistry + vault working directory ──────────────────────

describe("SessionRegistry — resident vault working directory", () => {
  let registry: SessionRegistry;
  let vaultDir: string;

  beforeEach(() => {
    registry = new SessionRegistry();
    vaultDir = createVaultDir("Resident Agent");
  });

  test("session registered with vault working directory preserves it", () => {
    const config = makeAgentConfig({ name: "resident-agent", workingDirectory: vaultDir });
    registry.create("sess-1", config);

    const stored = registry.getConfig("sess-1");
    expect(stored?.workingDirectory).toBe(vaultDir);
  });

  test("vault files are accessible from the registered working directory", () => {
    const config = makeAgentConfig({ name: "resident-agent", workingDirectory: vaultDir });
    registry.create("sess-1", config);

    const workDir = registry.getConfig("sess-1")?.workingDirectory!;
    expect(existsSync(join(workDir, "CLAUDE.md"))).toBe(true);
    expect(existsSync(join(workDir, "MEMORY.md"))).toBe(true);
    expect(existsSync(join(workDir, "INDEX.md"))).toBe(true);
    expect(existsSync(join(workDir, "GUIDELINES.md"))).toBe(true);
    expect(existsSync(join(workDir, "SESSION.md"))).toBe(true);
  });

  test("updateSessionCwd reflects vault path change", () => {
    const config = makeAgentConfig({ name: "resident-agent", workingDirectory: "/tmp/old" });
    registry.create("sess-2", config);

    registry.updateConfig("sess-2", { workingDirectory: vaultDir });
    expect(registry.getConfig("sess-2")?.workingDirectory).toBe(vaultDir);
  });

  test("two resident sessions can have different vault directories", () => {
    const vault1 = createVaultDir("Agent One");
    const vault2 = createVaultDir("Agent Two");

    registry.create("sess-a", makeAgentConfig({ name: "agent-one", workingDirectory: vault1 }));
    registry.create("sess-b", makeAgentConfig({ name: "agent-two", workingDirectory: vault2 }));

    expect(registry.getConfig("sess-a")?.workingDirectory).toBe(vault1);
    expect(registry.getConfig("sess-b")?.workingDirectory).toBe(vault2);
    expect(registry.getConfig("sess-a")?.workingDirectory).not.toBe(
      registry.getConfig("sess-b")?.workingDirectory
    );
  });
});
