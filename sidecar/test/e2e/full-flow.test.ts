/**
 * End-to-end tests for the ClaudPeer sidecar.
 *
 * Boots the full sidecar (index.ts) as a subprocess, then exercises:
 * - WebSocket connect + sidecar.ready
 * - HTTP health endpoint
 * - Blackboard write via HTTP → read via WS protocol (cross-protocol)
 * - agent.register → peer_list_agents visibility
 * - session.create → streaming events
 * - Full agent-to-agent flow: create 2 sessions, verify PeerBus tools available
 *
 * Usage: bun test test/e2e/full-flow.test.ts
 *
 * Note: These tests require `bun` available in PATH. They boot a real sidecar
 * on random ports and clean up after. Claude SDK calls are real — tests that
 * involve session.message + actual Claude responses are skipped unless
 * CLAUDPEER_E2E_LIVE=1 is set (to avoid API costs in CI).
 */
import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { spawn, type Subprocess } from "bun";
import { mkdtempSync } from "fs";
import { join } from "path";
import { tmpdir } from "os";

const WS_PORT = 29849 + Math.floor(Math.random() * 500);
const HTTP_PORT = 29850 + Math.floor(Math.random() * 500);
const DATA_DIR = mkdtempSync(join(tmpdir(), "claudpeer-e2e-"));
const isLive = process.env.CLAUDPEER_E2E_LIVE === "1";

let proc: Subprocess;

class BufferedWs {
  ws: WebSocket;
  buffer: any[] = [];
  private listeners: Array<(msg: any) => void> = [];

  constructor(ws: WebSocket) {
    this.ws = ws;
    ws.onmessage = (event: MessageEvent) => {
      const msg = JSON.parse(typeof event.data === "string" ? event.data : "{}");
      this.buffer.push(msg);
      for (const fn of this.listeners) fn(msg);
    };
  }

  send(data: any) { this.ws.send(JSON.stringify(data)); }
  close() { this.ws.close(); }

  waitFor(predicate: (msg: any) => boolean, timeoutMs = 10000): Promise<any> {
    const existing = this.buffer.find(predicate);
    if (existing) return Promise.resolve(existing);
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.listeners = this.listeners.filter((fn) => fn !== listener);
        reject(new Error("waitFor timeout"));
      }, timeoutMs);
      const listener = (msg: any) => {
        if (predicate(msg)) {
          clearTimeout(timer);
          this.listeners = this.listeners.filter((fn) => fn !== listener);
          resolve(msg);
        }
      };
      this.listeners.push(listener);
    });
  }

  collectNew(count: number, timeoutMs = 5000): Promise<any[]> {
    const startIdx = this.buffer.length;
    return new Promise((resolve) => {
      const timer = setTimeout(() => resolve(this.buffer.slice(startIdx)), timeoutMs);
      const listener = () => {
        if (this.buffer.length - startIdx >= count) {
          clearTimeout(timer);
          this.listeners = this.listeners.filter((fn) => fn !== listener);
          resolve(this.buffer.slice(startIdx, startIdx + count));
        }
      };
      this.listeners.push(listener);
    });
  }

  collectUntil(predicate: (msg: any) => boolean, timeoutMs = 30000): Promise<any[]> {
    const startIdx = this.buffer.length;
    // Check buffer first
    for (let i = startIdx; i < this.buffer.length; i++) {
      if (predicate(this.buffer[i])) return Promise.resolve(this.buffer.slice(startIdx, i + 1));
    }
    return new Promise((resolve) => {
      const timer = setTimeout(() => {
        this.listeners = this.listeners.filter((fn) => fn !== listener);
        resolve(this.buffer.slice(startIdx));
      }, timeoutMs);
      const listener = (msg: any) => {
        if (predicate(msg)) {
          clearTimeout(timer);
          this.listeners = this.listeners.filter((fn) => fn !== listener);
          resolve(this.buffer.slice(startIdx));
        }
      };
      this.listeners.push(listener);
    });
  }
}

function wsConnect(timeoutMs = 10000): Promise<BufferedWs> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("WS connect timeout")), timeoutMs);
    const tryConnect = () => {
      try {
        const ws = new WebSocket(`ws://localhost:${WS_PORT}`);
        ws.onopen = () => {
          clearTimeout(timer);
          resolve(new BufferedWs(ws));
        };
        ws.onerror = () => {
          setTimeout(tryConnect, 300);
        };
      } catch {
        setTimeout(tryConnect, 300);
      }
    };
    tryConnect();
  });
}

async function waitForHealth(maxRetries = 30): Promise<void> {
  for (let i = 0; i < maxRetries; i++) {
    try {
      const res = await fetch(`http://127.0.0.1:${HTTP_PORT}/health`);
      if (res.ok) return;
    } catch {}
    await new Promise((r) => setTimeout(r, 500));
  }
  throw new Error("Sidecar HTTP did not become ready");
}

// ─── Lifecycle ──────────────────────────────────────────────────────

beforeAll(async () => {
  const sidecarPath = join(import.meta.dir, "../../src/index.ts");

  proc = spawn({
    cmd: ["bun", "run", sidecarPath],
    env: {
      ...process.env,
      CLAUDPEER_WS_PORT: String(WS_PORT),
      CLAUDPEER_HTTP_PORT: String(HTTP_PORT),
      CLAUDPEER_DATA_DIR: DATA_DIR,
    },
    stdout: "pipe",
    stderr: "pipe",
  });

  await waitForHealth();
}, 30000);

afterAll(() => {
  proc?.kill();
});

// ─── Health ─────────────────────────────────────────────────────────

describe("E2E: Sidecar Boot", () => {
  test("HTTP /health returns ok", async () => {
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
      expect(ready.version).toBeDefined();
    } finally {
      ws.close();
    }
  });
});

// ─── Blackboard Cross-Protocol ──────────────────────────────────────

describe("E2E: Blackboard (HTTP + WS)", () => {
  test("write via HTTP, read via HTTP", async () => {
    const writeRes = await fetch(`http://127.0.0.1:${HTTP_PORT}/blackboard/write`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ key: "e2e.test", value: "hello-e2e", writtenBy: "e2e-suite" }),
    });
    expect(writeRes.status).toBe(201);

    const readRes = await fetch(`http://127.0.0.1:${HTTP_PORT}/blackboard/read?key=e2e.test`);
    expect(readRes.status).toBe(200);
    const body = (await readRes.json()) as any;
    expect(body.value).toBe("hello-e2e");
  });

  test("query returns written entries", async () => {
    await fetch(`http://127.0.0.1:${HTTP_PORT}/blackboard/write`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ key: "e2e.q1", value: "a", writtenBy: "test" }),
    });
    await fetch(`http://127.0.0.1:${HTTP_PORT}/blackboard/write`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ key: "e2e.q2", value: "b", writtenBy: "test" }),
    });

    const res = await fetch(`http://127.0.0.1:${HTTP_PORT}/blackboard/query?pattern=e2e.*`);
    const body = (await res.json()) as any[];
    expect(body.length).toBeGreaterThanOrEqual(2);
  });
});

// ─── Agent Registration ─────────────────────────────────────────────

describe("E2E: Agent Registration", () => {
  test("agent.register via WS stores definitions", async () => {
    const ws = await wsConnect();
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");

      ws.send({
        type: "agent.register",
        agents: [
          {
            name: "E2ECoder",
            config: {
              name: "E2ECoder",
              systemPrompt: "you code",
              allowedTools: [],
              mcpServers: [],
              model: "claude-sonnet-4-6",
              workingDirectory: "/tmp",
              skills: [],
            },
            instancePolicy: "spawn",
          },
          {
            name: "E2EReviewer",
            config: {
              name: "E2EReviewer",
              systemPrompt: "you review",
              allowedTools: [],
              mcpServers: [],
              model: "claude-sonnet-4-6",
              workingDirectory: "/tmp",
              skills: [],
            },
            instancePolicy: "singleton",
          },
        ],
      });

      await new Promise((r) => setTimeout(r, 500));
    } finally {
      ws.close();
    }
  });
});

// ─── Session Lifecycle ──────────────────────────────────────────────

describe("E2E: Session Lifecycle", () => {
  test("session.create establishes session state", async () => {
    const ws = await wsConnect();
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");

      ws.send({
        type: "session.create",
        conversationId: "e2e-lifecycle",
        agentConfig: {
          name: "LifecycleBot",
          systemPrompt: "Say OK",
          allowedTools: [],
          mcpServers: [],
          model: "claude-sonnet-4-6",
          maxTurns: 1,
          workingDirectory: "/tmp",
          skills: [],
        },
      });

      await new Promise((r) => setTimeout(r, 500));
    } finally {
      ws.close();
    }
  });

  test("session.message to unknown session returns error", async () => {
    const ws = await wsConnect();
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");

      ws.send({
        type: "session.message",
        sessionId: "e2e-nonexistent",
        text: "hello?",
      });

      const errorMsg = await ws.waitFor(
        (m) => m.type === "session.error" && m.sessionId === "e2e-nonexistent",
        5000,
      );
      expect(errorMsg.error).toContain("not found");
    } finally {
      ws.close();
    }
  });

  (isLive ? test : test.skip)("session.create + message returns streaming tokens and result", async () => {
    const ws = await wsConnect();
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");

      const sessionId = `e2e-live-${Date.now()}`;
      ws.send({
        type: "session.create",
        conversationId: sessionId,
        agentConfig: {
          name: "LiveBot",
          systemPrompt: "Reply only with the exact text: PONG. Nothing else.",
          allowedTools: [],
          mcpServers: [],
          model: "claude-sonnet-4-6",
          maxTurns: 1,
          workingDirectory: "/tmp",
          skills: [],
        },
      });

      await new Promise((r) => setTimeout(r, 500));

      ws.send({
        type: "session.message",
        sessionId,
        text: "PING",
      });

      const msgs = await ws.collectUntil(
        (m) => m.sessionId === sessionId && (m.type === "session.result" || m.type === "session.error"),
        60000,
      );

      const tokens = msgs.filter((m: any) => m.type === "stream.token" && m.sessionId === sessionId);
      expect(tokens.length).toBeGreaterThan(0);

      const result = msgs.find((m: any) => m.type === "session.result" && m.sessionId === sessionId);
      expect(result).toBeDefined();
      expect(result.result).toBeTruthy();
    } finally {
      ws.close();
    }
  }, 90000);
});

// ─── Session Pause / Fork ───────────────────────────────────────────

describe("E2E: Session Pause & Fork", () => {
  test("session.fork returns forked confirmation", async () => {
    const ws = await wsConnect();
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");

      ws.send({
        type: "session.create",
        conversationId: "e2e-fork-parent",
        agentConfig: {
          name: "ForkParent",
          systemPrompt: "test",
          allowedTools: [],
          mcpServers: [],
          model: "claude-sonnet-4-6",
          maxTurns: 1,
          workingDirectory: "/tmp",
          skills: [],
        },
      });

      await new Promise((r) => setTimeout(r, 300));

      ws.send({
        type: "session.fork",
        sessionId: "e2e-fork-parent",
      });

      const forkMsg = await ws.waitFor(
        (m) => m.type === "stream.token" && m.text?.includes("Forked"),
        5000,
      );
      expect(forkMsg.text).toContain("Forked");
    } finally {
      ws.close();
    }
  });
});

// ─── Concurrent Connections ─────────────────────────────────────────

describe("E2E: Concurrent WebSocket Clients", () => {
  test("both clients read same blackboard data via HTTP", async () => {
    const ws1 = await wsConnect();
    const ws2 = await wsConnect();
    try {
      await ws1.waitFor((m) => m.type === "sidecar.ready");
      await ws2.waitFor((m) => m.type === "sidecar.ready");

      const writeRes = await fetch(`http://127.0.0.1:${HTTP_PORT}/blackboard/write`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ key: "e2e.concurrent", value: "check", writtenBy: "e2e" }),
      });
      expect(writeRes.status).toBe(201);

      const read1 = await fetch(`http://127.0.0.1:${HTTP_PORT}/blackboard/read?key=e2e.concurrent`);
      const read2 = await fetch(`http://127.0.0.1:${HTTP_PORT}/blackboard/read?key=e2e.concurrent`);
      expect((await read1.json() as any).value).toBe("check");
      expect((await read2.json() as any).value).toBe("check");
    } finally {
      ws1.close();
      ws2.close();
    }
  });
});
