import type { AgentConfig, SidecarEvent } from "./types.js";
import { SessionRegistry } from "./stores/session-registry.js";

type EventEmitter = (event: SidecarEvent) => void;

export class SessionManager {
  private registry = new SessionRegistry();
  private emit: EventEmitter;

  constructor(emit: EventEmitter) {
    this.emit = emit;
  }

  async createSession(conversationId: string, config: AgentConfig): Promise<void> {
    this.registry.create(conversationId, config);
    // TODO: Replace with actual Agent SDK ClaudeSDKClient creation
    this.emit({
      type: "stream.token",
      sessionId: conversationId,
      text: `[ClaudPeer] Session created for agent "${config.name}". Agent SDK integration pending.\n`,
    });
    this.emit({
      type: "session.result",
      sessionId: conversationId,
      result: "Session created (stub mode)",
      cost: 0,
    });
  }

  async sendMessage(sessionId: string, text: string): Promise<void> {
    const config = this.registry.getConfig(sessionId);
    if (!config) {
      this.emit({
        type: "session.error",
        sessionId,
        error: "Session not found",
      });
      return;
    }

    // TODO: Replace with client.query(text) when Agent SDK is integrated
    // For now, echo back with a stub response
    this.emit({
      type: "stream.token",
      sessionId,
      text: `[${config.name}] Received: "${text}"\n\n`,
    });
    this.emit({
      type: "stream.token",
      sessionId,
      text: `This is a stub response. The Agent SDK will be integrated to provide real Claude responses.\n`,
    });

    this.registry.update(sessionId, {
      tokenCount: (this.registry.get(sessionId)?.tokenCount ?? 0) + text.length,
    });

    this.emit({
      type: "session.result",
      sessionId,
      result: "Stub response complete",
      cost: 0,
    });
  }

  async resumeSession(sessionId: string, claudeSessionId: string): Promise<void> {
    // TODO: Use resume: claudeSessionId with Agent SDK
    this.emit({
      type: "stream.token",
      sessionId,
      text: `[ClaudPeer] Session resumed (stub). Claude session ID: ${claudeSessionId}\n`,
    });
  }

  async forkSession(sessionId: string): Promise<string> {
    const forkedId = `${sessionId}-fork-${Date.now()}`;
    const config = this.registry.getConfig(sessionId);
    if (config) {
      this.registry.create(forkedId, config);
    }
    return forkedId;
  }

  async pauseSession(sessionId: string): Promise<void> {
    this.registry.update(sessionId, { status: "paused" });
  }

  listSessions() {
    return this.registry.list();
  }
}
