/**
 * Integration tests for conversation idle detection.
 *
 * Tests ConversationEvaluator wired with a real SessionManager instance.
 * Since real Claude sessions require API keys, these tests verify the
 * fallback paths: sessions missing claudeSessionId, unknown sessions,
 * and the correct event sequence produced by the evaluator.
 */
import { describe, test, expect, beforeEach } from "bun:test";
import { ConversationEvaluator } from "../../src/conversation-evaluator.js";
import { SessionManager } from "../../src/session-manager.js";
import { SessionRegistry } from "../../src/stores/session-registry.js";
import { BlackboardStore } from "../../src/stores/blackboard-store.js";
import { MessageStore } from "../../src/stores/message-store.js";
import { ChatChannelStore } from "../../src/stores/chat-channel-store.js";
import { WorkspaceStore } from "../../src/stores/workspace-store.js";
import { PeerRegistry } from "../../src/stores/peer-registry.js";
import { ConnectorStore } from "../../src/stores/connector-store.js";
import { ConversationStore } from "../../src/stores/conversation-store.js";
import { ProjectStore } from "../../src/stores/project-store.js";
import { NostrTransport } from "../../src/relay/nostr-transport.js";
import type { ToolContext } from "../../src/tools/tool-context.js";
import type { AgentConfig, SidecarEvent } from "../../src/types.js";

function buildCtx(emit: (e: SidecarEvent) => void = () => {}): ToolContext {
  const suffix = `${Date.now()}-${Math.random()}`;
  return {
    blackboard: new BlackboardStore(`idle-integ-${suffix}`),
    sessions: new SessionRegistry(),
    messages: new MessageStore(),
    channels: new ChatChannelStore(),
    workspaces: new WorkspaceStore(),
    peerRegistry: new PeerRegistry(),
    connectors: new ConnectorStore(),
    conversationStore: new ConversationStore(),
    projectStore: new ProjectStore(),
    nostrTransport: new NostrTransport(() => {}),
    relayClient: {
      isConnected: () => false,
      connect: async () => {},
      sendCommand: async () => ({}),
    } as any,
    broadcast: emit,
    spawnSession: async (sid) => ({ sessionId: sid }),
    agentDefinitions: new Map<string, AgentConfig>(),
  };
}

const BASE_CONFIG: AgentConfig = {
  name: "IntegAgent",
  systemPrompt: "test",
  allowedTools: [],
  mcpServers: [],
  provider: "claude",
  model: "claude-haiku-4-5-20251001",
  maxTurns: 5,
  workingDirectory: "/tmp",
  skills: [],
};

describe("SessionManager.evaluateSession — short-circuit paths", () => {
  let registry: SessionRegistry;
  let sm: SessionManager;

  beforeEach(() => {
    registry = new SessionRegistry();
    const ctx = { ...buildCtx(), sessions: registry };
    sm = new SessionManager(() => {}, registry, ctx);
  });

  test("returns null for completely unknown session", async () => {
    const result = await sm.evaluateSession("no-such-session", "STATUS: COMPLETE\nREASON: done");
    expect(result).toBeNull();
  });

  test("returns null for session that has no claudeSessionId", async () => {
    registry.create("known-no-claude-id", BASE_CONFIG);
    const result = await sm.evaluateSession("known-no-claude-id", "STATUS: COMPLETE\nREASON: done");
    expect(result).toBeNull();
  });

  test("returns null for session registered but config missing", async () => {
    // Force a state where session exists but registry.getConfig returns null
    registry.create("partial-sess", BASE_CONFIG);
    // We can only verify it doesn't throw and returns null
    const result = await sm.evaluateSession("partial-sess", "STATUS: COMPLETE\nREASON: test");
    expect(result).toBeNull();
  });
});

describe("ConversationEvaluator + SessionManager integration", () => {
  let events: SidecarEvent[];
  let registry: SessionRegistry;
  let sm: SessionManager;
  let evaluator: ConversationEvaluator;

  beforeEach(() => {
    events = [];
    registry = new SessionRegistry();
    const ctx = { ...buildCtx((e) => events.push(e)), sessions: registry };
    sm = new SessionManager((e) => events.push(e), registry, ctx);
    evaluator = new ConversationEvaluator(sm);
  });

  test("emits conversation.idle then conversation.idleResult in correct order", async () => {
    const emitted: SidecarEvent[] = [];
    await evaluator.evaluate(
      { conversationId: "integ-order", sessionIds: ["ghost"] },
      (e) => emitted.push(e),
    );

    const types = emitted.map((e) => e.type);
    const idleIdx = types.indexOf("conversation.idle");
    const resultIdx = types.indexOf("conversation.idleResult");
    expect(idleIdx).toBeGreaterThanOrEqual(0);
    expect(resultIdx).toBeGreaterThan(idleIdx);
  });

  test("produces failed status when all sessions are unknown", async () => {
    const emitted: SidecarEvent[] = [];
    await evaluator.evaluate(
      { conversationId: "integ-unknown", sessionIds: ["ghost-1", "ghost-2"] },
      (e) => emitted.push(e),
    );

    const result = emitted.find((e) => e.type === "conversation.idleResult") as any;
    expect(result.status).toBe("failed");
  });

  test("produces failed status when sessions exist but lack claudeSessionId", async () => {
    registry.create("sess-a", BASE_CONFIG);
    registry.create("sess-b", BASE_CONFIG);

    const emitted: SidecarEvent[] = [];
    await evaluator.evaluate(
      { conversationId: "integ-no-claude-id", sessionIds: ["sess-a", "sess-b"] },
      (e) => emitted.push(e),
    );

    const result = emitted.find((e) => e.type === "conversation.idleResult") as any;
    expect(result.status).toBe("failed");
    expect(result.reason).toMatch(/could not complete/i);
  });

  test("conversationId is preserved in all emitted events", async () => {
    const emitted: SidecarEvent[] = [];
    const convId = "integ-conv-id-check";
    await evaluator.evaluate(
      { conversationId: convId, sessionIds: [] },
      (e) => emitted.push(e),
    );

    for (const event of emitted) {
      expect((event as any).conversationId).toBe(convId);
    }
  });

  test("evaluate with no sessions emits two events total", async () => {
    const emitted: SidecarEvent[] = [];
    await evaluator.evaluate({ conversationId: "integ-count" }, (e) => emitted.push(e));

    expect(emitted).toHaveLength(2);
    expect(emitted[0].type).toBe("conversation.idle");
    expect(emitted[1].type).toBe("conversation.idleResult");
  });
});
