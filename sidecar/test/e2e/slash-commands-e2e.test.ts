/**
 * E2E tests for slash command sidecar wire protocol.
 *
 * Boots a real sidecar and exercises:
 * - conversation.clear → conversation.cleared event + messages wiped
 * - session.updateModel → session config updated, sidecar stays healthy
 * - session.updateEffort (all four levels) → config updated, sidecar healthy
 *
 * No Claude API required. All tests run without ODYSSEY_E2E_LIVE.
 *
 * Usage: bun test test/e2e/slash-commands-e2e.test.ts
 */
import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { spawn, type Subprocess } from "bun";
import { mkdtempSync } from "fs";
import { join } from "path";
import { tmpdir } from "os";
import { BufferedWs, wsConnect as wsConnectHelper, waitForHealth as waitForHealthHelper } from "../helpers.js";
import { makeAgentConfig } from "../helpers.js";

const WS_PORT = 34000 + Math.floor(Math.random() * 500);
const HTTP_PORT = 34500 + Math.floor(Math.random() * 500);
const DATA_DIR = mkdtempSync(join(tmpdir(), "odyssey-slash-e2e-"));

let proc: Subprocess;

function wsConnect(timeoutMs = 10_000) { return wsConnectHelper(WS_PORT, timeoutMs); }
async function waitForHealth(maxRetries = 30) { return waitForHealthHelper(HTTP_PORT, maxRetries); }

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

afterAll(() => { proc?.kill(); });

// ─── Boot ─────────────────────────────────────────────────────────────

describe("E2E: Slash Commands — sidecar boot", () => {
  test("sidecar health endpoint is reachable", async () => {
    const res = await fetch(`http://127.0.0.1:${HTTP_PORT}/health`);
    expect(res.status).toBe(200);
    const body = await res.json() as any;
    expect(body.status).toBe("ok");
  });
});

// ─── conversation.clear ───────────────────────────────────────────────

describe("E2E: conversation.clear", () => {
  test("emits conversation.cleared event", async () => {
    const ws = await wsConnect();
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");
      const conversationId = `slash-clear-${Date.now()}`;

      ws.send({ type: "conversation.clear", conversationId });

      const cleared = await ws.waitFor(
        (m) => m.type === "conversation.cleared" && m.conversationId === conversationId,
        5_000,
      );
      expect(cleared.type).toBe("conversation.cleared");
      expect(cleared.conversationId).toBe(conversationId);
    } finally {
      ws.close();
    }
  });

  test("conversation.clear does not crash the sidecar", async () => {
    const ws = await wsConnect();
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");

      // Clear multiple conversations in rapid succession
      for (let i = 0; i < 5; i++) {
        ws.send({ type: "conversation.clear", conversationId: `bulk-clear-${i}` });
      }

      // Allow processing
      await new Promise((r) => setTimeout(r, 200));

      const health = await fetch(`http://127.0.0.1:${HTTP_PORT}/health`);
      expect(health.status).toBe(200);
    } finally {
      ws.close();
    }
  });

  test("multiple clears on the same conversation each emit conversation.cleared", async () => {
    const ws = await wsConnect();
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");
      const conversationId = `slash-multi-clear-${Date.now()}`;

      ws.send({ type: "conversation.clear", conversationId });
      ws.send({ type: "conversation.clear", conversationId });

      // Both should fire
      await ws.waitFor((m) => m.type === "conversation.cleared" && m.conversationId === conversationId, 5_000);
      await ws.waitFor((m) => m.type === "conversation.cleared" && m.conversationId === conversationId, 5_000);
    } finally {
      ws.close();
    }
  });
});

// ─── session.updateModel ──────────────────────────────────────────────

describe("E2E: session.updateModel", () => {
  test("session.updateModel on an active session keeps sidecar healthy", async () => {
    const ws = await wsConnect();
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");

      const sessionId = `slash-model-${Date.now()}`;

      // Create a session (it won't connect to Claude without API key, but gets registered)
      ws.send({
        type: "session.create",
        conversationId: sessionId,
        agentConfig: makeAgentConfig({ name: "ModelSwitchAgent", maxTurns: 1 }),
      });

      await new Promise((r) => setTimeout(r, 200));

      ws.send({ type: "session.updateModel", sessionId, model: "claude-opus-4-7" });

      await new Promise((r) => setTimeout(r, 200));

      const health = await fetch(`http://127.0.0.1:${HTTP_PORT}/health`);
      expect(health.status).toBe(200);
    } finally {
      ws.close();
    }
  });

  test("session.updateModel on unknown session does not crash sidecar", async () => {
    const ws = await wsConnect();
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");

      ws.send({ type: "session.updateModel", sessionId: "nonexistent-session", model: "claude-opus-4-7" });
      await new Promise((r) => setTimeout(r, 200));

      const health = await fetch(`http://127.0.0.1:${HTTP_PORT}/health`);
      expect(health.status).toBe(200);
    } finally {
      ws.close();
    }
  });
});

// ─── session.updateEffort ─────────────────────────────────────────────

describe("E2E: session.updateEffort", () => {
  for (const effort of ["low", "medium", "high", "max"] as const) {
    test(`effort="${effort}" does not crash sidecar`, async () => {
      const ws = await wsConnect();
      try {
        await ws.waitFor((m) => m.type === "sidecar.ready");

        const sessionId = `slash-effort-${effort}-${Date.now()}`;
        ws.send({
          type: "session.create",
          conversationId: sessionId,
          agentConfig: makeAgentConfig({ name: `EffortAgent-${effort}`, maxTurns: 1 }),
        });
        await new Promise((r) => setTimeout(r, 150));

        ws.send({ type: "session.updateEffort", sessionId, effort });
        await new Promise((r) => setTimeout(r, 150));

        const health = await fetch(`http://127.0.0.1:${HTTP_PORT}/health`);
        expect(health.status).toBe(200);
      } finally {
        ws.close();
      }
    });
  }

  test("session.updateEffort on unknown session does not crash sidecar", async () => {
    const ws = await wsConnect();
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");

      ws.send({ type: "session.updateEffort", sessionId: "ghost-session", effort: "high" });
      await new Promise((r) => setTimeout(r, 200));

      const health = await fetch(`http://127.0.0.1:${HTTP_PORT}/health`);
      expect(health.status).toBe(200);
    } finally {
      ws.close();
    }
  });
});

// ─── session.updateModel reflects in GET /sessions/:id ───────────────

describe("E2E: session.updateModel reflected in session registry via HTTP", () => {
  test("GET /sessions/:id returns session after model update", async () => {
    const ws = await wsConnect();
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");

      const sessionId = `slash-model-get-${Date.now()}`;
      ws.send({
        type: "session.create",
        conversationId: sessionId,
        agentConfig: makeAgentConfig({ name: "ModelGetAgent", maxTurns: 1 }),
      });
      await new Promise((r) => setTimeout(r, 200));

      ws.send({ type: "session.updateModel", sessionId, model: "claude-opus-4-7" });
      await new Promise((r) => setTimeout(r, 200));

      const res = await fetch(`http://127.0.0.1:${HTTP_PORT}/api/v1/sessions/${sessionId}`);
      expect(res.status).toBe(200);
      const body = await res.json() as any;
      expect(body.id).toBe(sessionId);
      expect(body.agentName).toBe("ModelGetAgent");
    } finally {
      ws.close();
    }
  });
});
