import type { SidecarCommand, SidecarEvent } from "./types.js";

interface PendingRequest {
  resolve: (event: SidecarEvent) => void;
  reject: (err: Error) => void;
  timer: Timer;
}

/**
 * Outbound WebSocket relay to peer sidecars.
 * Opens connections on demand and correlates request/response by commandId.
 */
export class RelayClient {
  private connections = new Map<string, WebSocket>();
  private pending = new Map<string, PendingRequest>();
  private onEvent: (event: SidecarEvent) => void;

  constructor(onEvent: (event: SidecarEvent) => void) {
    this.onEvent = onEvent;
  }

  async connect(peerName: string, endpoint: string): Promise<void> {
    if (this.connections.has(peerName)) return;
    return new Promise((resolve, reject) => {
      const ws = new WebSocket(endpoint);
      ws.addEventListener("open", () => {
        ws.send(JSON.stringify({
          type: "relay.handshake",
          peerName: process.env.CLAUDPEER_INSTANCE ?? "default",
          version: "0.2.0",
        }));
        this.connections.set(peerName, ws);
        console.log(`[relay] Connected to peer "${peerName}" at ${endpoint}`);
        resolve();
      });
      ws.addEventListener("message", (event) => {
        try {
          const msg = JSON.parse(typeof event.data === "string" ? event.data : "{}");
          if (msg.commandId && this.pending.has(msg.commandId)) {
            const req = this.pending.get(msg.commandId)!;
            this.pending.delete(msg.commandId);
            clearTimeout(req.timer);
            req.resolve(msg.event);
          } else {
            // Streaming event from remote peer — forward to local broadcast
            this.onEvent(msg);
          }
        } catch { /* ignore parse errors */ }
      });
      ws.addEventListener("close", () => {
        this.connections.delete(peerName);
        console.log(`[relay] Disconnected from peer "${peerName}"`);
      });
      ws.addEventListener("error", (err) => {
        this.connections.delete(peerName);
        reject(new Error(`Relay connection to "${peerName}" failed`));
      });
    });
  }

  async sendCommand(peerName: string, command: SidecarCommand, timeoutMs = 30000): Promise<SidecarEvent> {
    const ws = this.connections.get(peerName);
    if (!ws || ws.readyState !== WebSocket.OPEN) {
      throw new Error(`No relay connection to peer "${peerName}"`);
    }
    const commandId = crypto.randomUUID();
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(commandId);
        reject(new Error(`Relay to "${peerName}" timed out after ${timeoutMs}ms`));
      }, timeoutMs);
      this.pending.set(commandId, { resolve, reject, timer });
      ws.send(JSON.stringify({ commandId, command }));
    });
  }

  disconnect(peerName: string): void {
    const ws = this.connections.get(peerName);
    if (ws) {
      ws.close();
      this.connections.delete(peerName);
    }
  }

  isConnected(peerName: string): boolean {
    const ws = this.connections.get(peerName);
    return ws !== undefined && ws.readyState === WebSocket.OPEN;
  }

  disconnectAll(): void {
    for (const [name, ws] of this.connections) {
      ws.close();
    }
    this.connections.clear();
  }
}
