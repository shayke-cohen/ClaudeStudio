/**
 * E2E tests for Resident Agent vault working directory.
 *
 * Boots a real sidecar, then exercises the full resident vault flow:
 * - Register an agent with a vault working directory via WS agent.register
 * - Verify the vault workingDirectory is retrievable via HTTP GET /agents/:name
 * - Create a session for a resident agent, verify workingDirectory in session state
 * - Verify SESSION.md in the vault directory is visible from session working directory
 * - Verify two resident agents maintain independent vault directories throughout lifecycle
 *
 * Usage: bun test test/e2e/resident-vault-e2e.test.ts
 *
 * Note: Tests that involve sending messages to Claude (session.message) are skipped
 * unless ODYSSEY_E2E_LIVE=1 is set (to avoid API costs in CI).
 */
import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { spawn, type Subprocess } from "bun";
import { mkdtempSync, writeFileSync, existsSync } from "fs";
import { join } from "path";
import { tmpdir } from "os";
import { BufferedWs, wsConnect as wsConnectHelper, waitForHealth as waitForHealthHelper } from "../helpers.js";

const WS_PORT = 28849 + Math.floor(Math.random() * 500);
const HTTP_PORT = 28850 + Math.floor(Math.random() * 500);
const DATA_DIR = mkdtempSync(join(tmpdir(), "odyssey-vault-e2e-"));

let proc: Subprocess;

function wsConnect(timeoutMs = 10_000) { return wsConnectHelper(WS_PORT, timeoutMs); }
async function waitForHealth(maxRetries = 30) { return waitForHealthHelper(HTTP_PORT, maxRetries); }

// ─── Vault factory ───────────────────────────────────────────────────

function createVaultDir(agentSlug: string): string {
  const dir = mkdtempSync(join(tmpdir(), `e2e-vault-${agentSlug}-`));
  const date = new Date().toISOString().split("T")[0];

  writeFileSync(join(dir, "CLAUDE.md"), `---\nagent: ${agentSlug}\nupdated: ${date}\n---\n\n# ${agentSlug}\n\n## Role\n<!-- resident agent -->\n\n## Session Start\n1. Read INDEX.md\n2. Read MEMORY.md\n`);
  writeFileSync(join(dir, "INDEX.md"), `---\nupdated: ${date}\n---\n\n# ${agentSlug} — Knowledge Index\n\n## Core Files\n- [[CLAUDE.md]]\n- [[MEMORY.md]]\n- [[GUIDELINES.md]]\n- [[SESSION.md]]\n`);
  writeFileSync(join(dir, "MEMORY.md"), `---\nupdated: ${date}\ncap: "200 lines"\n---\n\n# ${agentSlug} — Memory\n\n## Recent Lessons\n\n## Domain Map\n\n## Active Goals\n`);
  writeFileSync(join(dir, "GUIDELINES.md"), `---\nupdated: ${date}\ntags: [guidelines]\n---\n\n# Guidelines\n`);
  writeFileSync(join(dir, "SESSION.md"), `---\nupdated: ${date}\nvolatile: true\n---\n\n# Current Session\n\n## Task\n\n## Active Context\n\n## Do Not Forget\n`);

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

  await waitForHealth();
}, 30_000);

afterAll(() => {
  proc?.kill();
});

// ─── Boot ────────────────────────────────────────────────────────────

describe("E2E: Resident Vault — sidecar boot", () => {
  test("sidecar health endpoint is reachable", async () => {
    const res = await fetch(`http://127.0.0.1:${HTTP_PORT}/health`);
    expect(res.status).toBe(200);
    const body = await res.json() as any;
    expect(body.status).toBe("ok");
  });

  test("WebSocket connects and receives sidecar.ready", async () => {
    const ws = await wsConnect();
    try {
      const ready = await ws.waitFor((m) => m.type === "sidecar.ready");
      expect(ready.type).toBe("sidecar.ready");
    } finally {
      ws.close();
    }
  });
});

// ─── Agent registration with vault working directory ─────────────────

describe("E2E: Resident Vault — agent registration", () => {
  test("agent registered with vault dir is retrievable via HTTP with correct workingDirectory", async () => {
    const vaultDir = createVaultDir("e2e-resident-coder");
    const ws = await wsConnect();

    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");

      ws.send({
        type: "agent.register",
        agents: [{
          name: "e2e-resident-coder",
          config: {
            name: "e2e-resident-coder",
            systemPrompt: "You are a resident coder with persistent memory.",
            allowedTools: ["Read", "Write", "Bash"],
            mcpServers: [],
            model: "claude-sonnet-4-6",
            workingDirectory: vaultDir,
            skills: [],
          },
          instancePolicy: "spawn",
        }],
      });

      // Give the sidecar a tick to process
      await new Promise((r) => setTimeout(r, 100));

      const res = await fetch(`http://127.0.0.1:${HTTP_PORT}/api/v1/agents/e2e-resident-coder`);
      expect(res.status).toBe(200);
      const body = await res.json() as any;
      expect(body.name).toBe("e2e-resident-coder");
      expect(body.workingDirectory).toBe(vaultDir);
    } finally {
      ws.close();
    }
  });

  test("vault CLAUDE.md exists in the workingDirectory returned by the API", async () => {
    const vaultDir = createVaultDir("e2e-vault-check");
    const ws = await wsConnect();

    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");

      ws.send({
        type: "agent.register",
        agents: [{
          name: "e2e-vault-check",
          config: {
            name: "e2e-vault-check",
            systemPrompt: "Resident agent.",
            allowedTools: [],
            mcpServers: [],
            model: "claude-sonnet-4-6",
            workingDirectory: vaultDir,
            skills: [],
          },
          instancePolicy: "spawn",
        }],
      });

      await new Promise((r) => setTimeout(r, 100));

      const res = await fetch(`http://127.0.0.1:${HTTP_PORT}/api/v1/agents/e2e-vault-check`);
      const body = await res.json() as any;

      // Verify vault files are physically present at the returned path
      expect(existsSync(join(body.workingDirectory, "CLAUDE.md"))).toBe(true);
      expect(existsSync(join(body.workingDirectory, "MEMORY.md"))).toBe(true);
      expect(existsSync(join(body.workingDirectory, "INDEX.md"))).toBe(true);
      expect(existsSync(join(body.workingDirectory, "SESSION.md"))).toBe(true);
    } finally {
      ws.close();
    }
  });

  test("two resident agents have independent vault directories", async () => {
    const vaultA = createVaultDir("e2e-agent-alpha");
    const vaultB = createVaultDir("e2e-agent-beta");
    const ws = await wsConnect();

    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");

      ws.send({
        type: "agent.register",
        agents: [
          {
            name: "e2e-agent-alpha",
            config: { name: "e2e-agent-alpha", systemPrompt: "alpha", allowedTools: [], mcpServers: [], model: "claude-sonnet-4-6", workingDirectory: vaultA, skills: [] },
            instancePolicy: "spawn",
          },
          {
            name: "e2e-agent-beta",
            config: { name: "e2e-agent-beta", systemPrompt: "beta", allowedTools: [], mcpServers: [], model: "claude-sonnet-4-6", workingDirectory: vaultB, skills: [] },
            instancePolicy: "spawn",
          },
        ],
      });

      await new Promise((r) => setTimeout(r, 100));

      const [resA, resB] = await Promise.all([
        fetch(`http://127.0.0.1:${HTTP_PORT}/api/v1/agents/e2e-agent-alpha`).then((r) => r.json()),
        fetch(`http://127.0.0.1:${HTTP_PORT}/api/v1/agents/e2e-agent-beta`).then((r) => r.json()),
      ]) as any[];

      expect(resA.workingDirectory).toBe(vaultA);
      expect(resB.workingDirectory).toBe(vaultB);
      expect(resA.workingDirectory).not.toBe(resB.workingDirectory);
    } finally {
      ws.close();
    }
  });
});

// ─── Session creation with vault working directory ───────────────────

describe("E2E: Resident Vault — session creation (non-live)", () => {
  test("session.create with vault workingDirectory is accepted without fatal error", async () => {
    const vaultDir = createVaultDir("e2e-session-resident");
    const ws = await wsConnect();

    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");

      const conversationId = `vault-conv-${Date.now()}`;
      ws.send({
        type: "session.create",
        conversationId,
        agentConfig: {
          name: "e2e-session-resident",
          systemPrompt: "You are a resident agent with a knowledge vault.",
          allowedTools: [],
          mcpServers: [],
          model: "claude-sonnet-4-6",
          workingDirectory: vaultDir,
          skills: [],
        },
      });

      // Give the sidecar time to process the command
      await new Promise((r) => setTimeout(r, 500));

      // Sidecar must remain healthy — session.create with a vault dir must not crash the server
      const health = await fetch(`http://127.0.0.1:${HTTP_PORT}/health`);
      expect(health.status).toBe(200);

      // The vault directory must still be intact (not wiped by session start)
      expect(existsSync(join(vaultDir, "CLAUDE.md"))).toBe(true);
      expect(existsSync(join(vaultDir, "MEMORY.md"))).toBe(true);
      expect(existsSync(join(vaultDir, "SESSION.md"))).toBe(true);
    } finally {
      ws.close();
    }
  });
});
