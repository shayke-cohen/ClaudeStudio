/**
 * Unit tests for SessionManager memory cleanup.
 * Verifies that turnHistory is freed after sendMessage completes or pauseSession is called.
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
import { DelegationStore } from "../../src/stores/delegation-store.js";
import { NostrTransport } from "../../src/relay/nostr-transport.js";
import type { ToolContext } from "../../src/tools/tool-context.js";
import type { AgentConfig, SidecarEvent } from "../../src/types.js";

const MOCK_CONFIG: AgentConfig = {
  name: "TestAgent",
  systemPrompt: "",
  allowedTools: [],
  mcpServers: [],
  model: "claude-sonnet-4-6",
  workingDirectory: "/tmp",
  skills: [],
  provider: "mock",
};

function buildCtx(broadcast: (e: SidecarEvent) => void = () => {}): ToolContext {
  const suffix = `${Date.now()}-${Math.random()}`;
  return {
    blackboard: new BlackboardStore(`cleanup-test-${suffix}`),
    sessions: new SessionRegistry(),
    messages: new MessageStore(),
    channels: new ChatChannelStore(),
    workspaces: new WorkspaceStore(),
    peerRegistry: new PeerRegistry(),
    connectors: new ConnectorStore(),
    conversationStore: new ConversationStore(),
    projectStore: new ProjectStore(),
    nostrTransport: new NostrTransport(() => {}),
    delegation: new DelegationStore(),
    relayClient: {
      isConnected: () => false,
      connect: async () => {},
      sendCommand: async () => ({}),
    } as any,
    broadcast,
    spawnSession: async (sid, config, prompt) => {
      return { sessionId: sid };
    },
    agentDefinitions: new Map<string, AgentConfig>(),
  };
}

describe("SessionManager turnHistory cleanup", () => {
  let registry: SessionRegistry;
  let sm: SessionManager;

  beforeEach(() => {
    registry = new SessionRegistry();
    const ctx = { ...buildCtx(), sessions: registry };
    sm = new SessionManager(() => {}, registry, ctx);
  });

  test("clears turnHistory after sendMessage completes", async () => {
    await sm.createSession("s1", MOCK_CONFIG);
    await sm.sendMessage("s1", "hello");
    expect(sm.getTurnHistory("s1")).toHaveLength(0);
  });

  test("clears turnHistory after second send on same session", async () => {
    await sm.createSession("s1", MOCK_CONFIG);
    await sm.sendMessage("s1", "first");
    await sm.sendMessage("s1", "second");
    expect(sm.getTurnHistory("s1")).toHaveLength(0);
  });

  test("clears turnHistory after pauseSession", async () => {
    await sm.createSession("s1", MOCK_CONFIG);
    await sm.sendMessage("s1", "working");
    await sm.pauseSession("s1");
    expect(sm.getTurnHistory("s1")).toHaveLength(0);
  });

  test("pauseSession on session with no sends leaves history empty", async () => {
    await sm.createSession("s1", MOCK_CONFIG);
    await sm.pauseSession("s1");
    expect(sm.getTurnHistory("s1")).toHaveLength(0);
  });

  test("does not leak memory across 50 sessions", async () => {
    const ids = Array.from({ length: 50 }, (_, i) => `session-${i}`);
    for (const id of ids) {
      await sm.createSession(id, { ...MOCK_CONFIG });
    }
    for (const id of ids) {
      await sm.sendMessage(id, "ping");
    }
    for (const id of ids) {
      expect(sm.getTurnHistory(id)).toHaveLength(0);
    }
  });
});
