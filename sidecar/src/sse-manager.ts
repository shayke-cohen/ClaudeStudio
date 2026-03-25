import type { SidecarEvent } from "./types.js";

interface SseSubscriber {
  controller: ReadableStreamDefaultController;
  sessionId: string;
}

/**
 * Manages Server-Sent Events (SSE) subscribers for session streaming.
 * Each subscriber is associated with a session ID and receives events
 * filtered to that session.
 *
 * Note: SSE is fire-and-forget — no replay on reconnect.
 */
export class SseManager {
  private subscribers = new Map<string, Set<SseSubscriber>>();
  private heartbeatInterval: ReturnType<typeof setInterval> | null = null;

  constructor() {
    // Send keepalive to all subscribers every 30s
    this.heartbeatInterval = setInterval(() => {
      for (const [, subs] of this.subscribers) {
        for (const sub of subs) {
          try {
            sub.controller.enqueue(":keepalive\n\n");
          } catch {
            subs.delete(sub);
          }
        }
      }
    }, 30_000);
  }

  /**
   * Subscribe to events for a specific session.
   * Returns a ReadableStream suitable for an SSE Response.
   */
  subscribe(sessionId: string): ReadableStream {
    let subscriber: SseSubscriber;

    const stream = new ReadableStream({
      start: (controller) => {
        subscriber = { controller, sessionId };
        const set = this.subscribers.get(sessionId) ?? new Set();
        set.add(subscriber);
        this.subscribers.set(sessionId, set);

        // Send initial connection event
        controller.enqueue(`event: connected\ndata: {"sessionId":"${sessionId}"}\n\n`);
      },
      cancel: () => {
        const set = this.subscribers.get(sessionId);
        if (set) {
          set.delete(subscriber);
          if (set.size === 0) this.subscribers.delete(sessionId);
        }
      },
    });

    return stream;
  }

  /**
   * Broadcast a SidecarEvent to all matching SSE subscribers.
   * Events are matched by sessionId extracted from the event.
   */
  broadcast(event: SidecarEvent): void {
    const sessionId = this.extractSessionId(event);
    if (!sessionId) return;

    const subs = this.subscribers.get(sessionId);
    if (!subs || subs.size === 0) return;

    const data = `event: ${event.type}\ndata: ${JSON.stringify(event)}\n\n`;

    for (const sub of subs) {
      try {
        sub.controller.enqueue(data);
      } catch {
        subs.delete(sub);
      }
    }
  }

  /** Number of active SSE connections. */
  get connectionCount(): number {
    let count = 0;
    for (const subs of this.subscribers.values()) {
      count += subs.size;
    }
    return count;
  }

  close(): void {
    if (this.heartbeatInterval) clearInterval(this.heartbeatInterval);
    for (const [, subs] of this.subscribers) {
      for (const sub of subs) {
        try {
          sub.controller.close();
        } catch { /* already closed */ }
      }
    }
    this.subscribers.clear();
  }

  private extractSessionId(event: SidecarEvent): string | undefined {
    if ("sessionId" in event) return event.sessionId;
    if ("parentSessionId" in event) return event.parentSessionId;
    // Events without a sessionId (peer.chat, blackboard.update, etc.) are not
    // sent to SSE subscribers — they're system-wide, not session-scoped.
    return undefined;
  }
}
