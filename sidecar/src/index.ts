import { WsServer } from "./ws-server.js";
import { HttpServer } from "./http-server.js";
import { BlackboardStore } from "./stores/blackboard-store.js";
import { SessionRegistry } from "./stores/session-registry.js";
import { MessageStore } from "./stores/message-store.js";
import { ChatChannelStore } from "./stores/chat-channel-store.js";
import { WorkspaceStore } from "./stores/workspace-store.js";
import { PeerRegistry } from "./stores/peer-registry.js";
import { RelayClient } from "./relay-client.js";
import { SessionManager } from "./session-manager.js";
import { SseManager } from "./sse-manager.js";
import { WebhookManager } from "./webhook-manager.js";
import type { ToolContext } from "./tools/tool-context.js";
import type { AgentConfig, ApiContext, SidecarEvent } from "./types.js";

const WS_PORT = parseInt(process.env.CLAUDPEER_WS_PORT ?? "9849", 10);
const HTTP_PORT = parseInt(process.env.CLAUDPEER_HTTP_PORT ?? "9850", 10);
const DATA_DIR = process.env.CLAUDPEER_DATA_DIR ?? "~/.claudpeer";

import { appendFileSync } from "fs";
import { join as pathJoin } from "path";
import { homedir as osHomedir } from "os";
const _debugLogPath = pathJoin(osHomedir(), ".claudpeer", "debug-ask-user.log");
appendFileSync(_debugLogPath, `[${new Date().toISOString()}] SIDECAR STARTING (modified code loaded)\n`);
console.log("[claudpeer-sidecar] Starting...");

const blackboard = new BlackboardStore();
const sessions = new SessionRegistry();
const messages = new MessageStore();
const channels = new ChatChannelStore();
const workspaces = new WorkspaceStore();
const peerRegistry = new PeerRegistry();
const relayClient = new RelayClient((event) => broadcastFn(event));
const agentDefinitions = new Map<string, AgentConfig>();
const sseManager = new SseManager();
const webhookManager = new WebhookManager();

let broadcastFn: (event: SidecarEvent) => void = () => {};

const toolContext: ToolContext = {
  blackboard,
  sessions,
  messages,
  channels,
  workspaces,
  peerRegistry,
  relayClient,
  broadcast: (event) => broadcastFn(event),
  agentDefinitions,
  spawnSession: async (sessionId, config, initialPrompt, waitForResult) => {
    return sessionManager.spawnAutonomous(sessionId, config, initialPrompt, waitForResult);
  },
};

const sessionManager = new SessionManager(
  (event) => broadcastFn(event),
  sessions,
  toolContext,
);

const wsServer = new WsServer(WS_PORT, sessionManager, toolContext);

// Multi-target broadcast: WS clients + SSE subscribers + Webhooks
broadcastFn = (event) => {
  wsServer.broadcast(event);
  sseManager.broadcast(event);
  webhookManager.dispatch(event);
};

const apiContext: ApiContext = {
  sessionManager,
  toolCtx: toolContext,
  sseManager,
  webhookManager,
};

const httpServer = new HttpServer(HTTP_PORT, blackboard);
httpServer.setApiContext(apiContext);
httpServer.start();

console.log("[claudpeer-sidecar] Ready.");
console.log(`  WebSocket: ws://localhost:${WS_PORT}`);
console.log(`  HTTP API:  http://127.0.0.1:${HTTP_PORT}`);
console.log(`  REST API:  http://127.0.0.1:${HTTP_PORT}/api/v1/`);
console.log(`  Data dir:  ${DATA_DIR}`);

process.on("SIGINT", () => {
  console.log("\n[claudpeer-sidecar] Shutting down...");
  sseManager.close();
  wsServer.close();
  httpServer.close();
  process.exit(0);
});

process.on("SIGTERM", () => {
  sseManager.close();
  wsServer.close();
  httpServer.close();
  process.exit(0);
});

process.on("uncaughtException", (err) => {
  console.error("[sidecar] Uncaught exception (keeping alive):", err.message);
  console.error(err.stack?.substring(0, 500));
});

process.on("unhandledRejection", (reason) => {
  console.error("[sidecar] Unhandled rejection (keeping alive):", reason);
});
