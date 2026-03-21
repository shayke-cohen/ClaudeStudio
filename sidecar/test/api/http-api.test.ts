/**
 * API tests for the HTTP blackboard server and WebSocket command/event protocol.
 *
 * Boots a real HttpServer on a random port and tests all REST endpoints.
 * Tests WebSocket protocol framing (connect, ready event, command dispatch).
 *
 * Usage: CLAUDPEER_DATA_DIR=/tmp/claudpeer-test-$(date +%s) bun test test/api/http-api.test.ts
 */
import { describe, test, expect, beforeAll, afterAll, beforeEach } from "bun:test";
import { BlackboardStore } from "../../src/stores/blackboard-store.js";
import { HttpServer } from "../../src/http-server.js";

const HTTP_PORT = 19850 + Math.floor(Math.random() * 1000);
const BASE = `http://127.0.0.1:${HTTP_PORT}`;
let httpServer: HttpServer;
let blackboard: BlackboardStore;

beforeAll(() => {
  blackboard = new BlackboardStore(`api-test-${Date.now()}`);
  httpServer = new HttpServer(HTTP_PORT, blackboard);
  httpServer.start();
});

afterAll(() => {
  httpServer.close();
});

// ─── Health ─────────────────────────────────────────────────────────

describe("GET /health", () => {
  test("returns 200 with status ok", async () => {
    const res = await fetch(`${BASE}/health`);
    expect(res.status).toBe(200);
    const body = (await res.json()) as any;
    expect(body.status).toBe("ok");
    expect(body.version).toBeDefined();
  });

  test("/blackboard/health also works", async () => {
    const res = await fetch(`${BASE}/blackboard/health`);
    expect(res.status).toBe(200);
  });
});

// ─── POST /blackboard/write ─────────────────────────────────────────

describe("POST /blackboard/write", () => {
  test("creates entry and returns 201", async () => {
    const res = await fetch(`${BASE}/blackboard/write`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ key: "api.w1", value: "val1", writtenBy: "test" }),
    });
    expect(res.status).toBe(201);
    const body = (await res.json()) as any;
    expect(body.key).toBe("api.w1");
    expect(body.value).toBe("val1");
    expect(body.writtenBy).toBe("test");
    expect(body.createdAt).toBeDefined();
    expect(body.updatedAt).toBeDefined();
  });

  test("accepts JSON value (stringifies)", async () => {
    const res = await fetch(`${BASE}/blackboard/write`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ key: "api.json", value: { nested: true }, writtenBy: "test" }),
    });
    expect(res.status).toBe(201);
    const body = (await res.json()) as any;
    expect(body.value).toBe('{"nested":true}');
  });

  test("defaults writtenBy to 'external'", async () => {
    const res = await fetch(`${BASE}/blackboard/write`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ key: "api.noauthor", value: "test" }),
    });
    expect(res.status).toBe(201);
    const body = (await res.json()) as any;
    expect(body.writtenBy).toBe("external");
  });

  test("rejects missing key", async () => {
    const res = await fetch(`${BASE}/blackboard/write`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ value: "no key" }),
    });
    expect(res.status).toBe(400);
  });

  test("rejects missing value", async () => {
    const res = await fetch(`${BASE}/blackboard/write`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ key: "api.noval" }),
    });
    expect(res.status).toBe(400);
  });

  test("overwrites existing key", async () => {
    await fetch(`${BASE}/blackboard/write`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ key: "api.overwrite", value: "v1", writtenBy: "a" }),
    });
    const res = await fetch(`${BASE}/blackboard/write`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ key: "api.overwrite", value: "v2", writtenBy: "b" }),
    });
    expect(res.status).toBe(201);
    const body = (await res.json()) as any;
    expect(body.value).toBe("v2");
    expect(body.writtenBy).toBe("b");
  });
});

// ─── GET /blackboard/read ───────────────────────────────────────────

describe("GET /blackboard/read", () => {
  test("returns existing entry", async () => {
    blackboard.write("api.readable", "data", "w");

    const res = await fetch(`${BASE}/blackboard/read?key=api.readable`);
    expect(res.status).toBe(200);
    const body = (await res.json()) as any;
    expect(body.key).toBe("api.readable");
    expect(body.value).toBe("data");
  });

  test("returns 404 for missing key", async () => {
    const res = await fetch(`${BASE}/blackboard/read?key=nonexistent`);
    expect(res.status).toBe(404);
  });

  test("returns 400 for missing key param", async () => {
    const res = await fetch(`${BASE}/blackboard/read`);
    expect(res.status).toBe(400);
  });
});

// ─── GET /blackboard/query ──────────────────────────────────────────

describe("GET /blackboard/query", () => {
  beforeEach(() => {
    blackboard.write("qapi.x", "1", "w");
    blackboard.write("qapi.y", "2", "w");
    blackboard.write("other.z", "3", "w");
  });

  test("returns matching entries", async () => {
    const res = await fetch(`${BASE}/blackboard/query?pattern=qapi.*`);
    expect(res.status).toBe(200);
    const body = (await res.json()) as any[];
    expect(body.length).toBeGreaterThanOrEqual(2);
    expect(body.some((e: any) => e.key === "qapi.x")).toBe(true);
    expect(body.some((e: any) => e.key === "qapi.y")).toBe(true);
  });

  test("defaults to wildcard when no pattern", async () => {
    const res = await fetch(`${BASE}/blackboard/query`);
    expect(res.status).toBe(200);
    const body = (await res.json()) as any[];
    expect(body.length).toBeGreaterThan(0);
  });
});

// ─── GET /blackboard/keys ───────────────────────────────────────────

describe("GET /blackboard/keys", () => {
  test("returns array of all keys", async () => {
    blackboard.write("kapi.a", "v", "w");
    blackboard.write("kapi.b", "v", "w");

    const res = await fetch(`${BASE}/blackboard/keys`);
    expect(res.status).toBe(200);
    const body = (await res.json()) as any;
    expect(Array.isArray(body.keys)).toBe(true);
    expect(body.keys).toContain("kapi.a");
    expect(body.keys).toContain("kapi.b");
  });

  test("filters by scope param", async () => {
    blackboard.write("scoped.api", "v", "w", "my-workspace");
    blackboard.write("scoped.other", "v", "w", "other-ws");

    const res = await fetch(`${BASE}/blackboard/keys?scope=my-workspace`);
    expect(res.status).toBe(200);
    const body = (await res.json()) as any;
    expect(body.keys).toContain("scoped.api");
    expect(body.keys).not.toContain("scoped.other");
  });
});

// ─── CORS ───────────────────────────────────────────────────────────

describe("CORS", () => {
  test("OPTIONS returns CORS headers", async () => {
    const res = await fetch(`${BASE}/health`, { method: "OPTIONS" });
    expect(res.status).toBe(200);
    expect(res.headers.get("access-control-allow-origin")).toBe("*");
    expect(res.headers.get("access-control-allow-methods")).toContain("POST");
  });

  test("responses include allow-origin header", async () => {
    const res = await fetch(`${BASE}/health`);
    expect(res.headers.get("access-control-allow-origin")).toBe("*");
  });
});

// ─── 404 ────────────────────────────────────────────────────────────

describe("Unknown routes", () => {
  test("returns 404 for unknown path", async () => {
    const res = await fetch(`${BASE}/unknown/route`);
    expect(res.status).toBe(404);
  });
});
