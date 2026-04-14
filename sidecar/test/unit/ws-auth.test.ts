/**
 * Unit tests for WsServer bearer token authentication.
 *
 * Tests verify that the WsServer correctly enforces or skips token auth
 * depending on whether the `token` option is configured.
 *
 * Usage: ODYSSEY_DATA_DIR=/tmp/odyssey-test-$(date +%s) bun test test/unit/ws-auth.test.ts
 */
import { describe, test, expect, afterEach, beforeAll, afterAll } from "bun:test";
import { WsServer, type WsServerOptions } from "../../src/ws-server.js";
import * as os from "node:os";
import * as path from "node:path";
import * as fs from "node:fs";
import { SessionManager } from "../../src/session-manager.js";
import { SessionRegistry } from "../../src/stores/session-registry.js";
import { BlackboardStore } from "../../src/stores/blackboard-store.js";
import { TaskBoardStore } from "../../src/stores/task-board-store.js";
import { MessageStore } from "../../src/stores/message-store.js";
import { ChatChannelStore } from "../../src/stores/chat-channel-store.js";
import { WorkspaceStore } from "../../src/stores/workspace-store.js";
import { PeerRegistry } from "../../src/stores/peer-registry.js";
import { ConnectorStore } from "../../src/stores/connector-store.js";
import type { SidecarEvent } from "../../src/types.js";
import type { ToolContext } from "../../src/tools/tool-context.js";

// Pick a high port range to avoid conflicts with the running app
// (ws-protocol.test.ts uses 19849–20849, so start above that)
let portCounter = 21000;
function nextPort(): number {
  return portCounter++;
}

function makeToolContext(): ToolContext {
  const tag = `ws-auth-${Date.now()}`;
  const sessions = new SessionRegistry();
  return {
    blackboard: new BlackboardStore(tag),
    taskBoard: new TaskBoardStore(tag),
    sessions,
    messages: new MessageStore(),
    channels: new ChatChannelStore(),
    workspaces: new WorkspaceStore(),
    peerRegistry: new PeerRegistry(),
    connectors: new ConnectorStore(),
    relayClient: {
      isConnected: () => false,
      connect: async () => {},
      sendCommand: async () => ({}),
    } as any,
    broadcast: (_event: SidecarEvent) => {},
    agentDefinitions: new Map(),
    spawnSession: async (_sessionId, _config, _prompt, _wait) => ({ sessionId: _sessionId }),
  };
}

/** Attempt an HTTP GET (not an upgrade) and return the status code. */
async function httpGet(port: number, authHeader?: string): Promise<number> {
  const headers: Record<string, string> = {};
  if (authHeader) headers["Authorization"] = authHeader;
  const res = await fetch(`http://localhost:${port}`, { headers });
  return res.status;
}

const servers: WsServer[] = [];

let tmpDataDir: string;

beforeAll(() => {
  tmpDataDir = fs.mkdtempSync(path.join(os.tmpdir(), "odyssey-ws-auth-"));
  process.env.ODYSSEY_DATA_DIR = tmpDataDir;
});

afterAll(() => {
  delete process.env.ODYSSEY_DATA_DIR;
  fs.rmSync(tmpDataDir, { recursive: true, force: true });
});

afterEach(() => {
  for (const s of servers) {
    try { s.close(); } catch { /* ignore */ }
  }
  servers.length = 0;
});

// ─── WA1: Reject HTTP upgrade without token ─────────────────────────────────

describe("WsServer bearer token auth", () => {
  test("WA1 rejectsConnectionWithoutToken", async () => {
    const port = nextPort();
    const ctx = makeToolContext();
    const sm = new SessionManager(ctx.broadcast, ctx.sessions, ctx);
    const srv = new WsServer(port, sm, ctx, { token: "secret-token" });
    servers.push(srv);

    // Plain HTTP GET without Authorization header must return 401
    const status = await httpGet(port);
    expect(status).toBe(401);
  });

  // ─── WA2: Reject with wrong token ─────────────────────────────────────────

  test("WA2 rejectsConnectionWithWrongToken", async () => {
    const port = nextPort();
    const ctx = makeToolContext();
    const sm = new SessionManager(ctx.broadcast, ctx.sessions, ctx);
    const srv = new WsServer(port, sm, ctx, { token: "correct-token" });
    servers.push(srv);

    const status = await httpGet(port, "Bearer wrong-token");
    expect(status).toBe(401);
  });

  // ─── WA3: Accept correct token (HTTP path, non-upgrade) returns 426 ───────

  test("WA3 acceptsConnectionWithCorrectToken", async () => {
    const port = nextPort();
    const ctx = makeToolContext();
    const sm = new SessionManager(ctx.broadcast, ctx.sessions, ctx);
    const srv = new WsServer(port, sm, ctx, { token: "correct-token" });
    servers.push(srv);

    // HTTP GET with correct token reaches the WS endpoint (which returns 426 for non-upgrade)
    const status = await httpGet(port, "Bearer correct-token");
    expect(status).toBe(426);
  });

  // ─── WA4: No token configured — all connections pass through ──────────────

  test("WA4 allowsAllConnectionsWhenTokenUnset", async () => {
    const port = nextPort();
    const ctx = makeToolContext();
    const sm = new SessionManager(ctx.broadcast, ctx.sessions, ctx);
    const srv = new WsServer(port, sm, ctx); // no options
    servers.push(srv);

    // No auth header, no token configured — must reach the WS endpoint (426)
    const status = await httpGet(port);
    expect(status).toBe(426);
  });
});
