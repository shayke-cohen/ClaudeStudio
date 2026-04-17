/**
 * Live E2E tests for Resident Agent vault — real Claude sessions.
 *
 * Verifies that a resident agent actually uses its vault:
 *  1. Reads CLAUDE.md instructions (session start checklist is visible)
 *  2. Writes a session log entry to sessions/YYYY-MM-DD.md
 *  3. Appends a dated lesson to MEMORY.md
 *  4. SESSION.md is updated with the current task
 *
 * Requires a real Claude API key. Run with:
 *   ODYSSEY_E2E_LIVE=1 bun test test/e2e/resident-vault-live.test.ts
 *
 * Token cost: ~2–4 small turns. All prompts are tightly scoped.
 */
import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { spawn, type Subprocess } from "bun";
import { mkdtempSync, writeFileSync, readFileSync, existsSync, mkdirSync } from "fs";
import { join } from "path";
import { tmpdir } from "os";
import {
  wsConnect as wsConnectHelper,
  waitForHealth as waitForHealthHelper,
} from "../helpers.js";

const WS_PORT = 32000 + Math.floor(Math.random() * 500);
const HTTP_PORT = 32500 + Math.floor(Math.random() * 500);
const DATA_DIR = mkdtempSync(join(tmpdir(), "odyssey-vault-live-"));
const isLive = (process.env.ODYSSEY_E2E_LIVE ?? process.env.CLAUDESTUDIO_E2E_LIVE) === "1";

let proc: Subprocess;

function wsConnect(timeoutMs = 10_000) { return wsConnectHelper(WS_PORT, timeoutMs); }

// ─── Vault factory ───────────────────────────────────────────────────

function createVaultDir(slug: string): string {
  const dir = mkdtempSync(join(tmpdir(), `vault-live-${slug}-`));
  const date = new Date().toISOString().split("T")[0];

  writeFileSync(join(dir, "CLAUDE.md"), `---
agent: ${slug}
updated: ${date}
---

# ${slug}

## Role
Resident test agent for live vault E2E tests.

## Knowledge Graph

| File | Purpose | Cap |
|------|---------|-----|
| \`INDEX.md\` | Map-of-content | — |
| \`MEMORY.md\` | Routing index + recent lessons | 200 lines |
| \`GUIDELINES.md\` | Self-written rules | — |
| \`SESSION.md\` | Current active state (volatile) | Reset each session |
| \`sessions/YYYY-MM-DD.md\` | Append-only daily session log | — |
| \`knowledge/{topic}.md\` | Semantic topic notes | — |

## Session Start

1. Read \`INDEX.md\` — understand what exists in the graph
2. Read \`MEMORY.md\` — load routing index and recent lessons
3. Read \`GUIDELINES.md\` — apply self-written rules
4. Reset \`SESSION.md\` — write current task and what NOT to forget
5. Grep \`sessions/\` or \`knowledge/\` for topics relevant to today

## Session End (Reflection Loop)

Answer before closing:
1. What was the task? Did it succeed?
2. What was the earliest mistake or friction?
3. What one rule would prevent it next time?

Then:
- Write a one-liner to \`MEMORY.md\` (format: \`YYYY-MM-DD: <lesson>\`)
- Write a full reflection entry to today's session file
- If a pattern has recurred 2+ times across sessions → promote to \`knowledge/{topic}.md\`
- Update \`INDEX.md\` if any new file was created
`);

  writeFileSync(join(dir, "INDEX.md"), `---
updated: ${date}
---

# ${slug} — Knowledge Index

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

# ${slug} — Memory

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

// ─── Lifecycle ───────────────────────────────────────────────────────

beforeAll(async () => {
  const sidecarPath = join(import.meta.dir, "../../src/index.ts");
  proc = spawn({
    cmd: ["bun", "run", sidecarPath],
    env: {
      ...process.env,
      ODYSSEY_WS_PORT: String(WS_PORT),
      ODYSSEY_HTTP_PORT: String(HTTP_PORT),
      ODYSSEY_DATA_DIR: DATA_DIR,
      CLAUDESTUDIO_WS_PORT: String(WS_PORT),
      CLAUDESTUDIO_HTTP_PORT: String(HTTP_PORT),
      CLAUDESTUDIO_DATA_DIR: DATA_DIR,
    },
    stdout: "pipe",
    stderr: "pipe",
  });
  await waitForHealthHelper(HTTP_PORT);
}, 30_000);

afterAll(() => { proc?.kill(); });

// ─── Test 1: Agent reads CLAUDE.md and reports session start checklist ─

describe("E2E Live Vault: agent reads CLAUDE.md instructions", () => {
  (isLive ? test : test.skip)(
    "agent can read CLAUDE.md and report the session start checklist",
    async () => {
      const vaultDir = createVaultDir("vault-reader");
      const ws = await wsConnect();

      try {
        await ws.waitFor((m) => m.type === "sidecar.ready");
        const sessionId = `vault-read-${Date.now()}`;

        ws.send({
          type: "session.create",
          conversationId: sessionId,
          agentConfig: {
            name: "vault-reader",
            systemPrompt: "You are a resident agent with a knowledge vault in your working directory.",
            allowedTools: ["Read"],
            mcpServers: [],
            model: "claude-haiku-4-5-20251001",
            workingDirectory: vaultDir,
            skills: [],
            maxTurns: 3,
          },
        });

        await new Promise((r) => setTimeout(r, 300));

        ws.send({
          type: "session.message",
          sessionId,
          text: "Read CLAUDE.md in your working directory and tell me exactly what step 1 of the '## Session Start' section says. Reply with just that one line.",
        });

        const msgs = await ws.collectUntil(
          (m) => m.sessionId === sessionId && (m.type === "session.result" || m.type === "session.error"),
          120_000,
        );

        const errors = msgs.filter((m: any) => m.type === "session.error");
        expect(errors).toHaveLength(0);

        const result = msgs.find((m: any) => m.type === "session.result" && m.sessionId === sessionId);
        expect(result).toBeDefined();
        expect(result.result).toContain("INDEX.md");
      } finally {
        ws.close();
      }
    },
    150_000,
  );
});

// ─── Test 2: Agent writes a session log entry ────────────────────────

describe("E2E Live Vault: agent writes session log", () => {
  (isLive ? test : test.skip)(
    "agent writes sessions/YYYY-MM-DD.md with a log entry",
    async () => {
      const vaultDir = createVaultDir("vault-writer");
      const ws = await wsConnect();
      const today = new Date().toISOString().split("T")[0];

      try {
        await ws.waitFor((m) => m.type === "sidecar.ready");
        const sessionId = `vault-write-${Date.now()}`;

        ws.send({
          type: "session.create",
          conversationId: sessionId,
          agentConfig: {
            name: "vault-writer",
            systemPrompt: "You are a resident agent. Follow instructions exactly.",
            allowedTools: ["Read", "Write", "Bash"],
            mcpServers: [],
            model: "claude-haiku-4-5-20251001",
            workingDirectory: vaultDir,
            skills: [],
            maxTurns: 5,
          },
        });

        await new Promise((r) => setTimeout(r, 300));

        ws.send({
          type: "session.message",
          sessionId,
          text: `Do these steps in order:
1. Create the directory sessions/ inside your working directory (use Bash: mkdir -p sessions)
2. Write the file sessions/${today}.md with this exact content:
---
date: ${today}
---

## E2E Test Session
Task: live vault write test
Result: success
3. Reply with exactly: VAULT_WRITTEN`,
        });

        const msgs = await ws.collectUntil(
          (m) => m.sessionId === sessionId && (m.type === "session.result" || m.type === "session.error"),
          120_000,
        );

        const errors = msgs.filter((m: any) => m.type === "session.error");
        expect(errors).toHaveLength(0);

        const result = msgs.find((m: any) => m.type === "session.result" && m.sessionId === sessionId);
        expect(result).toBeDefined();

        // Verify the file was physically created
        const sessionFile = join(vaultDir, "sessions", `${today}.md`);
        expect(existsSync(sessionFile)).toBe(true);

        const content = readFileSync(sessionFile, "utf8");
        expect(content).toContain("E2E Test Session");
      } finally {
        ws.close();
      }
    },
    150_000,
  );
});

// ─── Test 3: Agent appends a lesson to MEMORY.md ─────────────────────

describe("E2E Live Vault: agent updates MEMORY.md", () => {
  (isLive ? test : test.skip)(
    "agent appends a dated lesson to MEMORY.md ## Recent Lessons",
    async () => {
      const vaultDir = createVaultDir("vault-memory");
      const ws = await wsConnect();
      const today = new Date().toISOString().split("T")[0];

      try {
        await ws.waitFor((m) => m.type === "sidecar.ready");
        const sessionId = `vault-mem-${Date.now()}`;

        ws.send({
          type: "session.create",
          conversationId: sessionId,
          agentConfig: {
            name: "vault-memory",
            systemPrompt: "You are a resident agent. Follow file-editing instructions exactly.",
            allowedTools: ["Read", "Write"],
            mcpServers: [],
            model: "claude-haiku-4-5-20251001",
            workingDirectory: vaultDir,
            skills: [],
            maxTurns: 5,
          },
        });

        await new Promise((r) => setTimeout(r, 300));

        ws.send({
          type: "session.message",
          sessionId,
          text: `Read MEMORY.md. Then rewrite it with this exact line appended under the "## Recent Lessons" section (after the blank line that follows the header):
${today}: E2E live vault test passed

Reply with exactly: MEMORY_UPDATED`,
        });

        const msgs = await ws.collectUntil(
          (m) => m.sessionId === sessionId && (m.type === "session.result" || m.type === "session.error"),
          120_000,
        );

        const errors = msgs.filter((m: any) => m.type === "session.error");
        expect(errors).toHaveLength(0);

        const result = msgs.find((m: any) => m.type === "session.result" && m.sessionId === sessionId);
        expect(result).toBeDefined();

        // Verify MEMORY.md was updated with the dated lesson
        const memContent = readFileSync(join(vaultDir, "MEMORY.md"), "utf8");
        expect(memContent).toContain(`${today}: E2E live vault test passed`);
      } finally {
        ws.close();
      }
    },
    150_000,
  );
});

// ─── Test 4: Full session lifecycle — start checklist + end reflection ─

describe("E2E Live Vault: full session lifecycle", () => {
  (isLive ? test : test.skip)(
    "agent follows start checklist and writes reflection at session end",
    async () => {
      const vaultDir = createVaultDir("vault-full");
      const ws = await wsConnect();
      const today = new Date().toISOString().split("T")[0];

      try {
        await ws.waitFor((m) => m.type === "sidecar.ready");
        const sessionId = `vault-full-${Date.now()}`;

        ws.send({
          type: "session.create",
          conversationId: sessionId,
          agentConfig: {
            name: "vault-full",
            systemPrompt: "You are a resident agent with a knowledge vault. Always follow your CLAUDE.md instructions exactly.",
            allowedTools: ["Read", "Write", "Bash"],
            mcpServers: [],
            model: "claude-haiku-4-5-20251001",
            workingDirectory: vaultDir,
            skills: [],
            maxTurns: 10,
          },
        });

        await new Promise((r) => setTimeout(r, 300));

        ws.send({
          type: "session.message",
          sessionId,
          text: `You are starting a new resident session. Follow these steps exactly:

SESSION START:
1. Read INDEX.md
2. Read MEMORY.md
3. Read GUIDELINES.md
4. Write SESSION.md with: Task: full lifecycle E2E test | Active Context: verifying vault read/write loop | Do Not Forget: write reflection at the end

SESSION WORK:
5. Create sessions/ directory (bash: mkdir -p sessions)
6. Write sessions/${today}.md with a brief log entry for this session

SESSION END REFLECTION:
7. Append this line to MEMORY.md under ## Recent Lessons: ${today}: vault lifecycle loop works end-to-end
8. Reply with exactly: LIFECYCLE_COMPLETE`,
        });

        const msgs = await ws.collectUntil(
          (m) => m.sessionId === sessionId && (m.type === "session.result" || m.type === "session.error"),
          180_000,
        );

        const errors = msgs.filter((m: any) => m.type === "session.error");
        expect(errors).toHaveLength(0);

        const result = msgs.find((m: any) => m.type === "session.result" && m.sessionId === sessionId);
        expect(result).toBeDefined();

        // SESSION.md must be updated with the current task
        const sessionMd = readFileSync(join(vaultDir, "SESSION.md"), "utf8");
        expect(sessionMd).toContain("full lifecycle E2E test");

        // sessions/YYYY-MM-DD.md must exist
        expect(existsSync(join(vaultDir, "sessions", `${today}.md`))).toBe(true);

        // MEMORY.md must contain the dated lesson
        const memMd = readFileSync(join(vaultDir, "MEMORY.md"), "utf8");
        expect(memMd).toContain(`${today}: vault lifecycle loop works end-to-end`);
      } finally {
        ws.close();
      }
    },
    240_000,
  );
});
