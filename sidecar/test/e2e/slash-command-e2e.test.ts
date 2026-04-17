/**
 * E2E tests for slash command protocol — boots a real sidecar subprocess.
 *
 * Covers: conversation.clear, session.updateModel, session.updateEffort
 * commands sent over a real WebSocket to a fully running sidecar.
 *
 * Usage: ODYSSEY_DATA_DIR=/tmp/odyssey-test-$(date +%s) bun test test/e2e/slash-command-e2e.test.ts
 */
import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { spawn, type Subprocess } from "bun";
import { mkdtempSync } from "fs";
import { join } from "path";
import { tmpdir } from "os";
import { wsConnect as wsConnectHelper, waitForHealth as waitForHealthHelper } from "../helpers.js";

const WS_PORT = 29600 + Math.floor(Math.random() * 200);
const HTTP_PORT = 29800 + Math.floor(Math.random() * 200);
const DATA_DIR = mkdtempSync(join(tmpdir(), "odyssey-slash-e2e-"));

let proc: Subprocess;

function wsConnect(timeoutMs = 10000) { return wsConnectHelper(WS_PORT, timeoutMs); }
async function waitForHealth() { return waitForHealthHelper(HTTP_PORT, 30); }

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
}, 30000);

afterAll(() => proc?.kill());

// ─── Boot health ────────────────────────────────────────────────────

describe("E2E: Slash Command Sidecar Boot", () => {
  test("sidecar boots and HTTP health returns ok", async () => {
    const res = await fetch(`http://127.0.0.1:${HTTP_PORT}/health`);
    expect(res.status).toBe(200);
    const body = (await res.json()) as any;
    expect(body.status).toBe("ok");
  });

  test("WebSocket connects and receives sidecar.ready", async () => {
    const ws = await wsConnect();
    try {
      const ready = await ws.waitFor((m) => m.type === "sidecar.ready");
      expect(ready.type).toBe("sidecar.ready");
      expect(ready.port).toBe(WS_PORT);
    } finally {
      ws.close();
    }
  });
});

// ─── conversation.clear E2E ─────────────────────────────────────────

describe("E2E: conversation.clear", () => {
  test("sends conversation.clear and receives conversation.cleared", async () => {
    const ws = await wsConnect();
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");
      ws.send({ type: "conversation.clear", conversationId: "e2e-conv-1" });
      const evt = await ws.waitFor((m) => m.type === "conversation.cleared", 5000);
      expect(evt.type).toBe("conversation.cleared");
      expect(evt.conversationId).toBe("e2e-conv-1");
    } finally {
      ws.close();
    }
  });

  test("second client receives broadcast conversation.cleared", async () => {
    const ws1 = await wsConnect();
    const ws2 = await wsConnect();
    try {
      await ws1.waitFor((m) => m.type === "sidecar.ready");
      await ws2.waitFor((m) => m.type === "sidecar.ready");

      ws1.send({ type: "conversation.clear", conversationId: "e2e-conv-broadcast" });
      const [e1, e2] = await Promise.all([
        ws1.waitFor((m) => m.type === "conversation.cleared", 5000),
        ws2.waitFor((m) => m.type === "conversation.cleared", 5000),
      ]);
      expect(e1.conversationId).toBe("e2e-conv-broadcast");
      expect(e2.conversationId).toBe("e2e-conv-broadcast");
    } finally {
      ws1.close();
      ws2.close();
    }
  });
});

// ─── session.updateModel E2E ────────────────────────────────────────

describe("E2E: session.updateModel", () => {
  test("command is accepted without crashing the server", async () => {
    const ws = await wsConnect();
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");
      // Send without a pre-existing session — server should handle gracefully
      ws.send({ type: "session.updateModel", sessionId: "e2e-sess-model", model: "claude-opus-4-7" });
      // Verify server is still alive by sending another command
      await Bun.sleep(200);
      ws.send({ type: "conversation.clear", conversationId: "e2e-liveness-1" });
      const alive = await ws.waitFor((m) => m.type === "conversation.cleared", 5000);
      expect(alive.type).toBe("conversation.cleared");
    } finally {
      ws.close();
    }
  });
});

// ─── session.updateEffort E2E ────────────────────────────────────────

describe("E2E: session.updateEffort", () => {
  const efforts = ["low", "medium", "high", "max"];

  for (const effort of efforts) {
    test(`effort='${effort}' accepted without crashing server`, async () => {
      const ws = await wsConnect();
      try {
        await ws.waitFor((m) => m.type === "sidecar.ready");
        ws.send({ type: "session.updateEffort", sessionId: "e2e-sess-effort", effort });
        await Bun.sleep(200);
        // Liveness check — server still processes subsequent commands
        ws.send({ type: "conversation.clear", conversationId: `e2e-liveness-effort-${effort}` });
        const alive = await ws.waitFor((m) => m.type === "conversation.cleared", 5000);
        expect(alive.type).toBe("conversation.cleared");
      } finally {
        ws.close();
      }
    });
  }
});
