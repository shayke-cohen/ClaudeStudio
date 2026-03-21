import type { ServerWebSocket } from "bun";
import type { SidecarCommand, SidecarEvent } from "./types.js";
import { SessionManager } from "./session-manager.js";

export class WsServer {
  private clients = new Set<ServerWebSocket<unknown>>();
  private sessionManager: SessionManager;
  private server: ReturnType<typeof Bun.serve> | null = null;

  constructor(port: number) {
    this.sessionManager = new SessionManager((event) => this.broadcast(event));

    this.server = Bun.serve({
      port,
      fetch(req, server) {
        if (server.upgrade(req)) return undefined;
        return new Response("WebSocket endpoint", { status: 426 });
      },
      websocket: {
        open: (ws) => {
          this.clients.add(ws);
          console.log(`[ws] Swift client connected (total: ${this.clients.size})`);
          const ready: SidecarEvent = {
            type: "sidecar.ready",
            port,
            version: "0.1.0",
          };
          ws.send(JSON.stringify(ready));
        },
        message: (ws, message) => {
          try {
            const data = typeof message === "string" ? message : new TextDecoder().decode(message);
            console.log("[ws] Received:", data.substring(0, 200));
            const command = JSON.parse(data) as SidecarCommand;
            this.handleCommand(command).catch((err) => {
              console.error("[ws] Command handler error:", err);
            });
          } catch (err) {
            console.error("[ws] Failed to parse command:", err);
          }
        },
        close: (ws) => {
          this.clients.delete(ws);
          console.log(`[ws] Swift client disconnected (total: ${this.clients.size})`);
        },
      },
    });

    console.log(`[ws] WebSocket server listening on ws://localhost:${port}`);
  }

  private async handleCommand(command: SidecarCommand): Promise<void> {
    switch (command.type) {
      case "session.create":
        await this.sessionManager.createSession(
          command.conversationId,
          command.agentConfig
        );
        break;
      case "session.message":
        await this.sessionManager.sendMessage(command.sessionId, command.text, command.attachments);
        break;
      case "session.resume":
        await this.sessionManager.resumeSession(
          command.sessionId,
          command.claudeSessionId
        );
        break;
      case "session.fork":
        await this.sessionManager.forkSession(command.sessionId);
        break;
      case "session.pause":
        await this.sessionManager.pauseSession(command.sessionId);
        break;
    }
  }

  broadcast(event: SidecarEvent): void {
    const data = JSON.stringify(event);
    for (const client of this.clients) {
      try {
        client.send(data);
      } catch {
        this.clients.delete(client);
      }
    }
  }

  close(): void {
    this.server?.stop();
  }
}
