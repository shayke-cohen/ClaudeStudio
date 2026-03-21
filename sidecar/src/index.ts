import { WsServer } from "./ws-server.js";
import { HttpServer } from "./http-server.js";
import { BlackboardStore } from "./stores/blackboard-store.js";

const WS_PORT = parseInt(process.env.CLAUDPEER_WS_PORT ?? "9849", 10);
const HTTP_PORT = parseInt(process.env.CLAUDPEER_HTTP_PORT ?? "9850", 10);

console.log("[claudpeer-sidecar] Starting...");

const blackboard = new BlackboardStore();
const wsServer = new WsServer(WS_PORT);
const httpServer = new HttpServer(HTTP_PORT, blackboard);

httpServer.start();

console.log("[claudpeer-sidecar] Ready.");
console.log(`  WebSocket: ws://localhost:${WS_PORT}`);
console.log(`  HTTP API:  http://127.0.0.1:${HTTP_PORT}`);

process.on("SIGINT", () => {
  console.log("\n[claudpeer-sidecar] Shutting down...");
  wsServer.close();
  httpServer.close();
  process.exit(0);
});

process.on("SIGTERM", () => {
  wsServer.close();
  httpServer.close();
  process.exit(0);
});
