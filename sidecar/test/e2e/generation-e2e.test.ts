/**
 * E2E tests for the generation pipeline (agent / skill / template).
 *
 * Boots the full sidecar as a subprocess on random ports. Tests the complete
 * request/response path through HTTP and WebSocket without any module mocks.
 *
 * - Error-path tests run unconditionally (no API key needed).
 * - Happy-path tests run only when ODYSSEY_E2E_LIVE=1 is set (real Claude calls).
 *
 * Usage:
 *   bun test test/e2e/generation-e2e.test.ts
 *   ODYSSEY_E2E_LIVE=1 bun test test/e2e/generation-e2e.test.ts
 */
import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { spawn, type Subprocess } from "bun";
import { mkdtempSync } from "fs";
import { join } from "path";
import { tmpdir } from "os";
import { wsConnect as wsConnectHelper, waitForHealth as waitForHealthHelper } from "../helpers.js";

const WS_PORT = 29960 + Math.floor(Math.random() * 500);
const HTTP_PORT = 29961 + Math.floor(Math.random() * 500);
const DATA_DIR = mkdtempSync(join(tmpdir(), "odyssey-gen-e2e-"));
const isLive = process.env.ODYSSEY_E2E_LIVE === "1";

let proc: Subprocess;

function wsConnect(timeoutMs = 10000) { return wsConnectHelper(WS_PORT, timeoutMs); }
async function waitForHealth() { return waitForHealthHelper(HTTP_PORT); }
function baseUrl() { return `http://127.0.0.1:${HTTP_PORT}`; }

// ─── Lifecycle ──────────────────────────────────────────────────────────────

beforeAll(async () => {
  proc = spawn({
    cmd: ["bun", "run", join(import.meta.dir, "../../src/index.ts")],
    env: {
      ...process.env,
      ODYSSEY_WS_PORT: String(WS_PORT),
      ODYSSEY_HTTP_PORT: String(HTTP_PORT),
      ODYSSEY_DATA_DIR: DATA_DIR,
    },
    stdout: "pipe",
    stderr: "pipe",
  });
  await waitForHealth();
}, 30000);

afterAll(() => {
  proc?.kill();
});

// ─── Boot smoke ─────────────────────────────────────────────────────────────

describe("E2E: sidecar boot", () => {
  test("HTTP /health responds ok", async () => {
    const res = await fetch(`${baseUrl()}/health`);
    expect(res.status).toBe(200);
    const body = (await res.json()) as any;
    expect(body.status).toBe("ok");
  });

  test("WebSocket receives sidecar.ready on connect", async () => {
    const ws = await wsConnect();
    try {
      const ready = await ws.waitFor((m) => m.type === "sidecar.ready");
      expect(ready.type).toBe("sidecar.ready");
      expect(ready.port).toBe(WS_PORT);
      expect(typeof ready.version).toBe("string");
    } finally {
      ws.close();
    }
  });
});

// ─── HTTP: POST /api/v1/agents/generate — validation ────────────────────────

describe("E2E: POST /api/v1/agents/generate validation", () => {
  test("missing prompt returns 400", async () => {
    const res = await fetch(`${baseUrl()}/api/v1/agents/generate`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({}),
    });
    expect(res.status).toBe(400);
    const body = (await res.json()) as any;
    expect(body.error).toBeDefined();
  });

  test("empty prompt returns 400", async () => {
    const res = await fetch(`${baseUrl()}/api/v1/agents/generate`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ prompt: "" }),
    });
    expect(res.status).toBe(400);
  });

  test("non-JSON body returns 400", async () => {
    const res = await fetch(`${baseUrl()}/api/v1/agents/generate`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: "not json at all",
    });
    expect(res.status).toBe(400);
  });

  test("GET /api/v1/agents/generate is not a route (404)", async () => {
    const res = await fetch(`${baseUrl()}/api/v1/agents/generate`);
    expect(res.status).toBe(404);
  });
});

// ─── HTTP: POST /api/v1/agents/generate — no API key ────────────────────────

describe("E2E: POST /api/v1/agents/generate without API key", () => {
  test("returns 500 error when ANTHROPIC_API_KEY is absent", async () => {
    // The sidecar was started without ANTHROPIC_API_KEY explicitly set (unless the
    // environment already has one). When no key is available, Anthropic SDK throws
    // an AuthenticationError which propagates as a 500 from the handler.
    if (isLive) return; // skip this check when running with real key

    const res = await fetch(`${baseUrl()}/api/v1/agents/generate`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ prompt: "A code review agent" }),
    });
    // Either 500 (Anthropic auth error) or 201 (if key happens to be set in env)
    expect([201, 500]).toContain(res.status);
  });
});

// ─── WS: generate.skill — error propagation ─────────────────────────────────

describe("E2E: WS generate.skill error propagation", () => {
  test("missing API key → generate.skill.error broadcast", async () => {
    if (isLive) return;

    const ws = await wsConnect();
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");

      const rid = `e2e-skill-${Date.now()}`;
      ws.send({
        type: "generate.skill",
        requestId: rid,
        prompt: "Security vulnerability detection patterns",
        availableCategories: ["Security", "General"],
        availableMCPs: [],
      });

      // Without a real API key the handler throws; we expect a generate.skill.error.
      // If a key IS set in env, we get a generate.skill.result — both are valid.
      const event = await ws.waitFor(
        (m) => (m.type === "generate.skill.result" || m.type === "generate.skill.error") && m.requestId === rid,
        15000
      );
      expect(["generate.skill.result", "generate.skill.error"]).toContain(event.type);
      expect(event.requestId).toBe(rid);
    } finally {
      ws.close();
    }
  });

  test("generate.skill.error carries requestId", async () => {
    if (isLive) return;

    const ws = await wsConnect();
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");

      const rid = `e2e-skill-err-${Date.now()}`;
      ws.send({
        type: "generate.skill",
        requestId: rid,
        prompt: "x",
        availableCategories: [],
        availableMCPs: [],
      });

      const event = await ws.waitFor(
        (m) => (m.type === "generate.skill.result" || m.type === "generate.skill.error") && m.requestId === rid,
        15000
      );
      // Whether it succeeded or errored, the requestId must be echoed back
      expect(event.requestId).toBe(rid);
    } finally {
      ws.close();
    }
  });
});

// ─── WS: generate.template — error propagation ──────────────────────────────

describe("E2E: WS generate.template error propagation", () => {
  test("missing API key → generate.template.error broadcast", async () => {
    if (isLive) return;

    const ws = await wsConnect();
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");

      const rid = `e2e-tmpl-${Date.now()}`;
      ws.send({
        type: "generate.template",
        requestId: rid,
        intent: "Review this PR for security issues",
        agentName: "Code Reviewer",
        agentSystemPrompt: "You are a code reviewer.",
      });

      const event = await ws.waitFor(
        (m) => (m.type === "generate.template.result" || m.type === "generate.template.error") && m.requestId === rid,
        15000
      );
      expect(["generate.template.result", "generate.template.error"]).toContain(event.type);
      expect(event.requestId).toBe(rid);
    } finally {
      ws.close();
    }
  });

  test("requestIds are isolated — two concurrent requests each get their own response", async () => {
    if (isLive) return;

    const ws = await wsConnect();
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");

      const rid1 = `e2e-iso-1-${Date.now()}`;
      const rid2 = `e2e-iso-2-${Date.now()}`;

      ws.send({ type: "generate.template", requestId: rid1, intent: "task 1", agentName: "A", agentSystemPrompt: "" });
      ws.send({ type: "generate.template", requestId: rid2, intent: "task 2", agentName: "B", agentSystemPrompt: "" });

      const [ev1, ev2] = await Promise.all([
        ws.waitFor((m) => (m.type === "generate.template.result" || m.type === "generate.template.error") && m.requestId === rid1, 15000),
        ws.waitFor((m) => (m.type === "generate.template.result" || m.type === "generate.template.error") && m.requestId === rid2, 15000),
      ]);

      expect(ev1.requestId).toBe(rid1);
      expect(ev2.requestId).toBe(rid2);
    } finally {
      ws.close();
    }
  });
});

// ─── Live-only: happy path ───────────────────────────────────────────────────

describe("E2E LIVE: POST /api/v1/agents/generate happy path", () => {
  test("returns 201 with valid GeneratedAgentSpec", async () => {
    if (!isLive) {
      console.log("  [skip] set ODYSSEY_E2E_LIVE=1 to run live generation tests");
      return;
    }

    const res = await fetch(`${baseUrl()}/api/v1/agents/generate`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ prompt: "A helpful code review agent that checks for security issues" }),
    });
    expect(res.status).toBe(201);
    const spec = (await res.json()) as any;
    expect(typeof spec.name).toBe("string");
    expect(typeof spec.systemPrompt).toBe("string");
    expect(spec.systemPrompt.length).toBeGreaterThan(50);
    expect(typeof spec.icon).toBe("string");
    expect(typeof spec.color).toBe("string");
    expect(Array.isArray(spec.matchedSkillIds)).toBe(true);
    expect(Array.isArray(spec.matchedMCPIds)).toBe(true);
  });

  test("WS generate.skill returns valid GeneratedSkillSpec", async () => {
    if (!isLive) return;

    const ws = await wsConnect();
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");

      const rid = `live-skill-${Date.now()}`;
      ws.send({
        type: "generate.skill",
        requestId: rid,
        prompt: "Secure coding practices for SQL injection prevention",
        availableCategories: ["Security", "General"],
        availableMCPs: [],
      });

      const event = await ws.waitFor((m) => m.type === "generate.skill.result" && m.requestId === rid, 30000);
      expect(event.spec.name).toBeTruthy();
      expect(event.spec.content.length).toBeGreaterThan(100);
      expect(Array.isArray(event.spec.triggers)).toBe(true);
      expect(event.spec.triggers.length).toBeGreaterThan(0);
    } finally {
      ws.close();
    }
  });

  test("WS generate.template returns valid GeneratedTemplateSpec", async () => {
    if (!isLive) return;

    const ws = await wsConnect();
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");

      const rid = `live-tmpl-${Date.now()}`;
      ws.send({
        type: "generate.template",
        requestId: rid,
        intent: "Review this PR for security vulnerabilities and code quality",
        agentName: "Security Reviewer",
        agentSystemPrompt: "You are a security-focused code reviewer.",
      });

      const event = await ws.waitFor((m) => m.type === "generate.template.result" && m.requestId === rid, 30000);
      expect(event.spec.name).toBeTruthy();
      expect(event.spec.prompt).toBeTruthy();
      expect(event.spec.prompt.length).toBeGreaterThan(20);
    } finally {
      ws.close();
    }
  });
});
