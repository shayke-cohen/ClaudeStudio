/**
 * Unit tests for SessionManager short-circuit paths.
 *
 * These avoid hitting real runtimes; they exercise the code paths that
 * short-circuit on missing sessions, missing configs, and mode updates.
 * Full lifecycle tests live in test/integration/local-agent-runtime.test.ts.
 */
import { describe, test, expect, beforeEach } from "bun:test";
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

function buildCtx(broadcast: (e: SidecarEvent) => void = () => {}): ToolContext {
  return {
    blackboard: new BlackboardStore(`sm-test-${Date.now()}-${Math.random()}`),
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
    broadcast,
    spawnSession: async (sid) => ({ sessionId: sid }),
    agentDefinitions: new Map<string, AgentConfig>(),
  };
}

describe("SessionManager short-circuit paths", () => {
  let events: SidecarEvent[];
  let registry: SessionRegistry;
  let ctx: ToolContext;
  let sm: SessionManager;

  beforeEach(() => {
    events = [];
    registry = new SessionRegistry();
    ctx = { ...buildCtx((e) => events.push(e)), sessions: registry };
    sm = new SessionManager((e) => events.push(e), registry, ctx);
  });

  test("sendMessage on unknown session emits session.error", async () => {
    await sm.sendMessage("ghost", "hi");
    expect(events).toHaveLength(1);
    expect(events[0]).toEqual({
      type: "session.error",
      sessionId: "ghost",
      error: "Session not found",
    });
  });

  test("updateSessionMode on missing session is a no-op", () => {
    sm.updateSessionMode("ghost", true);
    expect(registry.get("ghost")).toBeUndefined();
  });

  test("answerQuestion on missing session returns false", async () => {
    const result = await sm.answerQuestion("ghost", "q1", "yes");
    expect(result).toBe(false);
  });

  test("answerConfirmation on missing session returns false", async () => {
    const result = await sm.answerConfirmation("ghost", "c1", true);
    expect(result).toBe(false);
  });

  test("pauseSession on missing session does not throw", async () => {
    await sm.pauseSession("ghost");
  });

  test("buildQueryOptionsForTesting throws for unknown session", () => {
    expect(() => sm.buildQueryOptionsForTesting("ghost")).toThrow(
      /not found/,
    );
  });

  test("listSessions on empty registry returns []", () => {
    expect(sm.listSessions()).toEqual([]);
  });

  test("listSessions returns active sessions", () => {
    registry.create("s1", {
      name: "A",
      systemPrompt: "",
      allowedTools: [],
      mcpServers: [],
      model: "claude-sonnet-4-6",
      workingDirectory: "/tmp",
      skills: [],
    });
    expect(sm.listSessions()).toHaveLength(1);
  });

  test("updateSessionCwd mutates registered config", () => {
    registry.create("s1", {
      name: "A",
      systemPrompt: "",
      allowedTools: [],
      mcpServers: [],
      model: "claude-sonnet-4-6",
      workingDirectory: "/old",
      skills: [],
    });
    sm.updateSessionCwd("s1", "/new");
    expect(registry.getConfig("s1")?.workingDirectory).toBe("/new");
  });

  test("updateSessionMode updates interactive + policy on existing session", () => {
    registry.create("s1", {
      name: "A",
      systemPrompt: "",
      allowedTools: [],
      mcpServers: [],
      model: "claude-sonnet-4-6",
      workingDirectory: "/tmp",
      skills: [],
    });
    sm.updateSessionMode("s1", false, "singleton", 3);
    const config = registry.getConfig("s1");
    expect(config?.interactive).toBe(false);
    expect(config?.instancePolicy).toBe("singleton");
    expect(config?.instancePolicyPoolMax).toBe(3);
  });
});
