import { WsServer } from "./ws-server.js";
import { HttpServer } from "./http-server.js";
import { BlackboardStore } from "./stores/blackboard-store.js";
import { TaskBoardStore } from "./stores/task-board-store.js";
import { SessionRegistry } from "./stores/session-registry.js";
import { MessageStore } from "./stores/message-store.js";
import { ChatChannelStore } from "./stores/chat-channel-store.js";
import { WorkspaceStore } from "./stores/workspace-store.js";
import { PeerRegistry } from "./stores/peer-registry.js";
import { ConnectorStore } from "./stores/connector-store.js";
import { RelayClient } from "./relay-client.js";
import { SessionManager } from "./session-manager.js";
import { SseManager } from "./sse-manager.js";
import { WebhookManager } from "./webhook-manager.js";
import { logger, setLogLevel } from "./logger.js";
import type { ToolContext } from "./tools/tool-context.js";
import type { AgentConfig, ApiContext, SidecarEvent } from "./types.js";

setLogLevel((process.env.ODYSSEY_LOG_LEVEL ?? process.env.CLAUDESTUDIO_LOG_LEVEL ?? "info") as any);

const WS_PORT = parseInt(process.env.ODYSSEY_WS_PORT ?? process.env.CLAUDESTUDIO_WS_PORT ?? "9849", 10);
const HTTP_PORT = parseInt(process.env.ODYSSEY_HTTP_PORT ?? process.env.CLAUDESTUDIO_HTTP_PORT ?? "9850", 10);
const DATA_DIR = process.env.ODYSSEY_DATA_DIR ?? process.env.CLAUDESTUDIO_DATA_DIR ?? "~/.odyssey";

logger.info("sidecar", "Starting...");

const blackboard = new BlackboardStore();
const taskBoard = new TaskBoardStore();
const sessions = new SessionRegistry();
const messages = new MessageStore();
const channels = new ChatChannelStore();
const workspaces = new WorkspaceStore();
const peerRegistry = new PeerRegistry();
const connectors = new ConnectorStore();
const relayClient = new RelayClient((event) => broadcastFn(event));
const agentDefinitions = new Map<string, AgentConfig>();
const sseManager = new SseManager();
const webhookManager = new WebhookManager();

let broadcastFn: (event: SidecarEvent) => void = () => {};

const toolContext: ToolContext = {
  blackboard,
  taskBoard,
  sessions,
  messages,
  channels,
  workspaces,
  peerRegistry,
  connectors,
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

const WS_TOKEN = process.env.ODYSSEY_WS_TOKEN ?? process.env.CLAUDESTUDIO_WS_TOKEN;
const TLS_CERT = process.env.ODYSSEY_TLS_CERT ?? process.env.CLAUDESTUDIO_TLS_CERT;
const TLS_KEY = process.env.ODYSSEY_TLS_KEY ?? process.env.CLAUDESTUDIO_TLS_KEY;

const wsServer = new WsServer(WS_PORT, sessionManager, toolContext, {
  ...(WS_TOKEN ? { token: WS_TOKEN } : {}),
  ...(TLS_CERT ? { tlsCert: TLS_CERT } : {}),
  ...(TLS_KEY ? { tlsKey: TLS_KEY } : {}),
});

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

logger.info("sidecar", "Ready", {
  wsPort: WS_PORT,
  httpPort: HTTP_PORT,
  dataDir: DATA_DIR,
});

process.on("SIGINT", () => {
  logger.info("sidecar", "Shutting down (SIGINT)");
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
  logger.error("sidecar", `Uncaught exception (keeping alive): ${err.message}`, {
    stack: err.stack?.substring(0, 500),
  });
});

process.on("unhandledRejection", (reason) => {
  logger.error("sidecar", `Unhandled rejection (keeping alive): ${reason}`);
});
